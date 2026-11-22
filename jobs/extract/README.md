# Extract job: source views -> landing (raw)

PySpark job that copies the 7 source views (`src_sf_<env>`, stand-in for Snowflake) into
`landing_<env>.raw`, one table per view, and logs every load in `landing_<env>.ctl.load_log`.
Versions match AWS Glue 5.1: Spark 3.5.6, Python 3.11, Java 17.

## How a run works

For each source in `sources.yaml`:
1. Log a `RUNNING` row in `ctl.load_log` (this gives the `load_id`).
2. Read the whole view over JDBC (full extract), lowercase column names, apply renames (`f&p_segment` -> `fp_segment`).
3. Check the columns match the raw table exactly. A mismatch stops that source (schema drift).
4. Hash the content. If it equals the last `SUCCESS` load of that table, mark `SKIPPED_UNCHANGED` and write nothing.
5. Otherwise append the rows tagged with `load_id` and `extracted_at`, check the landed row count, and mark `SUCCESS`.
6. On any error: delete that load's rows, mark `FAILED` with the database error, and continue with the next source.

Exit code 1 if any source failed. Downstream layers read only `SUCCESS` load_ids.

## One-time setup (Mac)

    brew install python@3.11 openjdk@17
    cd ~/db-cicd-lab
    python3.11 -m venv .venv
    source .venv/bin/activate
    pip install -r jobs/extract/requirements.txt
    cp jobs/extract/.env.example jobs/extract/.env     # then fill in the passwords

The first run downloads the Postgres JDBC driver from Maven Central (needs internet once).
`.env` is git-ignored.

## Run (from the repo root)

    source .venv/bin/activate
    export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
    python jobs/extract/extract_to_landing.py

Options: `--only raw.dp_pnf_rpt_vw ...` (some tables), `--force` (load even if unchanged),
`--env-file path` (e.g. a staging .env pointing at `src_sf_staging` / `landing_staging`).

## Check a run

    SELECT load_id, target_table, status, rows_read, rows_written, started_at, finished_at, error_message
    FROM ctl.load_log ORDER BY load_id DESC LIMIT 10;

With the seed data loaded, a first run lands: title actuals 1631, plan/forecast 2592,
cost center actuals 1800, account hierarchy 30, cost center hierarchy 24,
business area hierarchy 4, company code hierarchy 3. A second run with no source change
shows all 7 as `SKIPPED_UNCHANGED`.

## Moving to Snowflake / Glue later

Only the read side changes: Snowflake connector options instead of Postgres JDBC in
`read_source()`, and `source_system: snowflake` in `sources.yaml`. Column lowercasing,
the drift check, hashing and load logging stay the same.
