"""Extract the source views into the landing database (raw schema) with Spark.

For each source in sources.yaml:
  1. log a RUNNING row in ctl.load_log (gets the load_id)
  2. read the whole view over JDBC (full extract), lowercase column names, apply renames
  3. check the columns match the raw table exactly (stops on schema drift)
  4. hash the content (order-independent); if equal to the last SUCCESS load -> SKIPPED_UNCHANGED
  5. otherwise append the rows with load_id + extracted_at, verify the row count, mark SUCCESS
  6. on any error: delete rows written for this load_id, mark FAILED, continue with the next source
Exit code 1 if any source failed.

Usage (from the repo root, venv active):
  python jobs/extract/extract_to_landing.py                       # all sources, .env in jobs/extract
  python jobs/extract/extract_to_landing.py --only raw.dp_pnf_rpt_vw --force
"""
import argparse
import hashlib
import logging
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import psycopg
import yaml
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

HERE = Path(__file__).resolve().parent
JDBC_DRIVER = "org.postgresql.Driver"
JDBC_PACKAGE = "org.postgresql:postgresql:42.7.4"
NULL_MARKER = "\u0000"   # distinguishes NULL from '' in the row hash
SEP = "\u001f"

log = logging.getLogger("extract")


# ------------------------------------------------------------------ configuration
def load_env_file(path: Path) -> None:
    """Minimal KEY=VALUE reader; real environment variables win."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def conn_settings(prefix: str) -> dict:
    missing = [k for k in ("HOST", "PORT", "DB", "USER") if not os.environ.get(f"{prefix}_{k}")]
    if missing:
        sys.exit(f"Missing settings: {', '.join(prefix + '_' + m for m in missing)} (see jobs/extract/.env.example)")
    s = {k.lower(): os.environ[f"{prefix}_{k}"] for k in ("HOST", "PORT", "DB", "USER")}
    s["password"] = os.environ.get(f"{prefix}_PASSWORD", "")
    return s


def jdbc_url(s: dict, extra: str = "") -> str:
    return f"jdbc:postgresql://{s['host']}:{s['port']}/{s['db']}{extra}"


def pg_conninfo(s: dict) -> str:
    return psycopg.conninfo.make_conninfo(host=s["host"], port=s["port"], dbname=s["db"],
                                          user=s["user"], password=s["password"] or None)


# ------------------------------------------------------------------ spark
def build_spark() -> SparkSession:
    b = (SparkSession.builder.appName("extract_to_landing").master("local[*]")
         # one fixed time zone end to end, so timestamp values round-trip unchanged
         .config("spark.sql.session.timeZone", "UTC")
         .config("spark.driver.extraJavaOptions", "-Duser.timezone=UTC")
         .config("spark.ui.showConsoleProgress", "false"))
    jar = os.environ.get("SPARK_JDBC_JAR")
    b = b.config("spark.jars", jar) if jar else b.config("spark.jars.packages", JDBC_PACKAGE)
    spark = b.getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    return spark


def read_source(spark, src: dict, obj: str) -> DataFrame:
    return (spark.read.format("jdbc")
            .option("url", jdbc_url(src)).option("driver", JDBC_DRIVER)
            .option("user", src["user"]).option("password", src["password"])
            .option("dbtable", obj).option("fetchsize", 10000)
            .load())


def content_hash(df: DataFrame, cols: list) -> tuple:
    """Order-independent: sum of a 60-bit slice of each row's SHA-256, plus count and column list."""
    row = F.sha2(F.concat_ws(SEP, *[F.coalesce(F.col(c).cast("string"), F.lit(NULL_MARKER)) for c in cols]), 256)
    part = F.conv(F.substring(row, 1, 15), 16, 10).cast("decimal(38,0)")
    agg = df.select(part.alias("h")).agg(F.count(F.lit(1)).alias("n"), F.sum("h").alias("s")).first()
    n, s = agg["n"], agg["s"] or 0
    return n, hashlib.sha256(f"{','.join(cols)}|{n}|{s}".encode()).hexdigest()


# ------------------------------------------------------------------ landing-side helpers (psycopg)
def target_columns(cur, table: str) -> dict:
    schema, name = table.split(".")
    cur.execute("""SELECT column_name, data_type FROM information_schema.columns
                   WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position""", (schema, name))
    cols = {r[0]: r[1] for r in cur.fetchall()}
    if not cols:
        raise RuntimeError(f"target table {table} not found - run the landing Flyway migrations first")
    return cols


def last_success_hash(cur, table: str):
    cur.execute("""SELECT content_hash FROM ctl.load_log WHERE target_table = %s AND status = 'SUCCESS'
                   ORDER BY load_id DESC LIMIT 1""", (table,))
    r = cur.fetchone()
    return r[0] if r else None


# ------------------------------------------------------------------ one source
def extract_one(spark, lnd_cur, src, lnd, cfg, item, run_id, run_started, force) -> dict:
    source, target, rename = item["source"], item["target"], item.get("rename") or {}
    lnd_cur.execute("""INSERT INTO ctl.load_log (run_id, source_system, source_object, target_table, status)
                       VALUES (%s, %s, %s, %s, 'RUNNING') RETURNING load_id""",
                    (run_id, cfg["source_system"], source, target))
    load_id = lnd_cur.fetchone()[0]
    result = {"target": target, "load_id": load_id, "status": "FAILED", "rows": None}
    df = None
    try:
        df = read_source(spark, src, source)
        df = df.toDF(*[c.lower() for c in df.columns])
        for old, new in rename.items():
            if old not in df.columns:
                raise RuntimeError(f"rename source column '{old}' not found in {source}")
            df = df.withColumnRenamed(old, new)

        tcols = target_columns(lnd_cur, target)
        data_cols = [c for c in tcols if c not in ("load_id", "extracted_at")]
        if set(df.columns) != set(data_cols):
            raise RuntimeError("column mismatch (schema drift): "
                               f"only in source {sorted(set(df.columns) - set(data_cols))}, "
                               f"only in raw {sorted(set(data_cols) - set(df.columns))}")
        df = df.select(*data_cols)
        # Spark reads Postgres TIME as a timestamp: send it back as 'HH:mm:ss' text
        for c in data_cols:
            if tcols[c].startswith("time without"):
                df = df.withColumn(c, F.date_format(F.col(c), "HH:mm:ss.SSSSSS"))
        df = df.persist()                       # read the source once: hash and write see the same rows

        rows, h = content_hash(df, data_cols)
        if not force and h == last_success_hash(lnd_cur, target):
            lnd_cur.execute("""UPDATE ctl.load_log SET status = 'SKIPPED_UNCHANGED', finished_at = now(),
                               rows_read = %s, rows_written = 0, content_hash = %s WHERE load_id = %s""",
                            (rows, h, load_id))
            result.update(status="SKIPPED_UNCHANGED", rows=rows)
            return result

        (df.withColumn("load_id", F.lit(load_id).cast("long"))
           .withColumn("extracted_at", F.lit(run_started).cast("timestamp"))
           .coalesce(4)
           .write.format("jdbc").mode("append")
           .option("url", jdbc_url(lnd, "?stringtype=unspecified&reWriteBatchedInserts=true"))
           .option("driver", JDBC_DRIVER)
           .option("user", lnd["user"]).option("password", lnd["password"])
           .option("dbtable", target).option("batchsize", 5000)
           .save())

        lnd_cur.execute(f"SELECT count(*) FROM {target} WHERE load_id = %s", (load_id,))
        written = lnd_cur.fetchone()[0]
        if written != rows:
            raise RuntimeError(f"row count check failed: read {rows}, landed {written}")
        lnd_cur.execute("""UPDATE ctl.load_log SET status = 'SUCCESS', finished_at = now(),
                           rows_read = %s, rows_written = %s, content_hash = %s WHERE load_id = %s""",
                        (rows, written, h, load_id))
        result.update(status="SUCCESS", rows=written)
        return result
    except Exception as e:                       # noqa: BLE001 - record any failure, then continue
        log.exception("extract failed for %s", source)
        if _table_exists(lnd_cur, target):
            lnd_cur.execute(f"DELETE FROM {target} WHERE load_id = %s", (load_id,))
        lnd_cur.execute("""UPDATE ctl.load_log SET status = 'FAILED', finished_at = now(), error_message = %s
                           WHERE load_id = %s""", (str(e)[:4000], load_id))
        result["error"] = root_cause(e)
        return result
    finally:
        if df is not None:
            df.unpersist()


def root_cause(e: Exception) -> str:
    """Spark wraps JDBC errors in a long Java trace: surface the database's own message."""
    lines = [l.strip() for l in str(e).splitlines() if l.strip()]
    for l in lines:
        if "ERROR:" in l:
            return l[l.index("ERROR:"):][:200]
    return (lines[0] if lines else repr(e))[:200]


def _table_exists(cur, table: str) -> bool:
    cur.execute("SELECT to_regclass(%s) IS NOT NULL", (table,))
    return cur.fetchone()[0]


# ------------------------------------------------------------------ main
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=str(HERE / "sources.yaml"))
    ap.add_argument("--env-file", default=str(HERE / ".env"))
    ap.add_argument("--only", nargs="*", help="target tables to extract (default: all)")
    ap.add_argument("--force", action="store_true", help="write even if the content is unchanged")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    load_env_file(Path(args.env_file))
    src, lnd = conn_settings("SRC"), conn_settings("LND")
    cfg = yaml.safe_load(Path(args.config).read_text())
    items = [i for i in cfg["sources"] if not args.only or i["target"] in args.only]
    if args.only and len(items) != len(args.only):
        sys.exit(f"unknown target(s): {sorted(set(args.only) - {i['target'] for i in cfg['sources']})}")

    run_id, run_started = uuid.uuid4(), datetime.now(timezone.utc)
    log.info("run %s: %s -> %s, %d source(s)", run_id, src["db"], lnd["db"], len(items))
    spark = build_spark()
    results = []
    try:
        with psycopg.connect(pg_conninfo(lnd), autocommit=True) as conn, conn.cursor() as cur:
            for item in items:
                r = extract_one(spark, cur, src, lnd, cfg, item, run_id, run_started, args.force)
                log.info("%-38s load_id=%-5s %-18s rows=%s", r["target"], r["load_id"], r["status"], r["rows"])
                results.append(r)
    finally:
        spark.stop()

    print(f"\nrun_id {run_id}")
    print(f"{'target':40} {'load_id':>8}  {'status':18} {'rows':>8}")
    for r in results:
        print(f"{r['target']:40} {r['load_id']:>8}  {r['status']:18} {str(r['rows']):>8}  {r.get('error', '')}")
    failed = [r for r in results if r["status"] == "FAILED"]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
