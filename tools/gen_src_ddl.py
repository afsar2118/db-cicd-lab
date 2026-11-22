"""Generate the Postgres stand-in DDL for Snowflake source views from their column CSVs.

Each CSV (docs/src_sf/<view>.csv) is the single source of truth for column
order and types. When the real Snowflake types arrive (INFORMATION_SCHEMA.COLUMNS),
update pg_type/type_status in the CSV and re-run this script BEFORE the migration is
first applied anywhere (Flyway forbids editing an applied versioned migration).

Usage: python tools/gen_src_ddl.py
"""
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC_DIR = ROOT / "docs/src_sf"
SQL_DIR = ROOT / "db/src_sf/migrations"

SEC = "cnfmd.trs_fin_user_security"

VIEWS = [
    {
        "csv": "dp_title_actuals_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_TITLE_ACTUALS_RPT_VW",
        "view": "fin_reporting.dp_title_actuals_rpt_vw",
        "snowflake_base": "FIN_TRUSTED.FIN_CNFMD.TRS_FACT_TITLE_ACTUALS_VW",
        "base": "fin_cnfmd.trs_fact_title_actuals_vw",
        "base_file": "V2__fin_cnfmd_trs_fact_title_actuals_vw.sql",
        "view_file": "R__fin_reporting_dp_title_actuals_rpt_vw.sql",
        "from": (
            "FROM fin_cnfmd.trs_fact_title_actuals_vw f\n"
            "LEFT JOIN edp_hana.stg_cv_dim_t001_compcode_01 d   -- lookup on master data table\n"
            "    ON d.bukrs = f.company_code\n"
            f"WHERE f.company_code IN (SELECT DISTINCT company_code FROM {SEC}_company_code_vw)\n"
            f"  AND (f.business_area IN (SELECT DISTINCT business_area FROM {SEC}_business_area_vw)\n"
            "       OR f.business_area IS NULL);\n"
        ),
    },
    {
        "csv": "dp_pnf_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_PNF_RPT_VW",
        "view": "fin_reporting.dp_pnf_rpt_vw",
        "snowflake_base": "FIN_TRUSTED.FIN_CNFMD.TRS_FACT_PLAN_FORECAST_VW",
        "base": "fin_cnfmd.trs_fact_plan_forecast_vw",
        "base_file": "V5__fin_cnfmd_trs_fact_plan_forecast_vw.sql",
        "view_file": "R__fin_reporting_dp_pnf_rpt_vw.sql",
        "from": (
            "FROM fin_cnfmd.trs_fact_plan_forecast_vw\n"
            f"WHERE company_code IN (SELECT DISTINCT company_code FROM {SEC}_company_code_vw)\n"
            f"  AND (business_area IN (SELECT DISTINCT business_area FROM {SEC}_business_area_vw)\n"
            "       OR business_area IS NULL)\n"
            f"  AND version IN (SELECT DISTINCT version FROM {SEC}_version_vw);\n"
        ),
    },
    {
        "csv": "dp_cost_center_actuals_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_COST_CENTER_ACTUALS_RPT_VW",
        "view": "fin_reporting.dp_cost_center_actuals_rpt_vw",
        "snowflake_base": "FIN_TRUSTED.FIN_CNFMD.TRS_CV_COSTCENTER_REP_CCA_CC_VW",
        "base": "fin_cnfmd.trs_cv_costcenter_rep_cca_cc_vw",
        "base_file": "V7__fin_cnfmd_trs_cv_costcenter_rep_cca_cc_vw.sql",
        "view_file": "R__fin_reporting_dp_cost_center_actuals_rpt_vw.sql",
        "from": (
            "FROM fin_cnfmd.trs_cv_costcenter_rep_cca_cc_vw\n"
            f"WHERE company_code IN (SELECT DISTINCT company_code FROM {SEC}_company_code_vw)\n"
            "  AND cost_center IN (SELECT DISTINCT kostl FROM cnfmd.trs_user_security_cost_center_hier);\n"
        ),
    },
    {
        "csv": "dp_acct_hier_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_ACCT_HIER_RPT_VW",
        "view": "fin_reporting.dp_acct_hier_rpt_vw",
        "snowflake_base": "FIN_TRUSTED.FIN_CNFMD.TRS_DIM_ACCT_HIER",
        "base": "fin_cnfmd.trs_dim_acct_hier",
        "base_file": "V9__fin_cnfmd_trs_dim_acct_hier.sql",
        "base_note": "table or view in Snowflake - name has no _VW suffix, not confirmed",
        "view_file": "R__fin_reporting_dp_acct_hier_rpt_vw.sql",
        "from": "FROM fin_cnfmd.trs_dim_acct_hier;   -- no security filter in the Snowflake definition\n",
    },
    {
        "csv": "dp_cost_ctr_hier_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_COST_CTR_HIER_RPT_VW",
        "view": "fin_reporting.dp_cost_ctr_hier_rpt_vw",
        "snowflake_base": "FIN_TRUSTED.FIN_CNFMD.TRS_DIM_CC_HIER",
        "base": "fin_cnfmd.trs_dim_cc_hier",
        "base_file": "V10__fin_cnfmd_trs_dim_cc_hier.sql",
        "base_note": "table or view in Snowflake - name has no _VW suffix, not confirmed",
        "view_file": "R__fin_reporting_dp_cost_ctr_hier_rpt_vw.sql",
        "from": "FROM fin_cnfmd.trs_dim_cc_hier;   -- no security filter in the Snowflake definition\n",
    },
    {
        "csv": "dp_business_area_hier_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_BUSINESS_AREA_HIER_RPT_VW",
        "view": "fin_reporting.dp_business_area_hier_rpt_vw",
        "snowflake_base": "FIN_STAGING.EDP_HANA.STG_CV_DIM_BA_HIER_FLAT",
        "base": "edp_hana.stg_cv_dim_ba_hier_flat",
        "base_file": "V11__edp_hana_stg_cv_dim_ba_hier_flat.sql",
        "base_note": "staging object in Snowflake, table or view not confirmed; the view renames its BA_* columns",
        "view_file": "R__fin_reporting_dp_business_area_hier_rpt_vw.sql",
        "view_note": (
            "-- Snowflake IFF(TRIM(x) IN ('?',''), NULL, x) is written as\n"
            "-- CASE WHEN TRIM(x) IN ('?', '') THEN NULL ELSE x END (same result, including for NULL x).\n"
            "-- View columns are renamed by position, e.g. BA_L00 -> BUSINESS_AREA_HL00,\n"
            "-- BUSINESS_AREA -> BUSINESS_AREA_HIERARCHY.\n"
        ),
        "from": "FROM edp_hana.stg_cv_dim_ba_hier_flat;   -- no security filter in the Snowflake definition\n",
    },
    {
        "csv": "dp_company_code_hier_rpt_vw.csv",
        "snowflake_view": "FIN_CONSUMPTION.FIN_REPORTING.DP_COMPANY_CODE_HIER_RPT_VW",
        "view": "fin_reporting.dp_company_code_hier_rpt_vw",
        "snowflake_base": "FIN_STAGING.EDP_HANA.STG_CV_DIM_CCODE_HIER_FLAT",
        "base": "edp_hana.stg_cv_dim_ccode_hier_flat",
        "base_file": "V12__edp_hana_stg_cv_dim_ccode_hier_flat.sql",
        "base_note": "staging object in Snowflake, table or view not confirmed; the view renames its CCODE_* columns",
        "view_file": "R__fin_reporting_dp_company_code_hier_rpt_vw.sql",
        "view_note": (
            "-- Snowflake IFF(TRIM(x) IN ('?',''), NULL, x) is written as\n"
            "-- CASE WHEN TRIM(x) IN ('?', '') THEN NULL ELSE x END (same result, including for NULL x).\n"
            "-- View columns are renamed by position, e.g. CCODE_L00 -> COMPANY_CODE_L00.\n"
        ),
        "from": "FROM edp_hana.stg_cv_dim_ccode_hier_flat;   -- no security filter in the Snowflake definition\n",
    },
]

PLAIN_IDENT = re.compile(r"^[a-z_][a-z0-9_]*$")


def q(name):
    """Quote an identifier only when Postgres needs it (e.g. f&p_segment)."""
    return name if PLAIN_IDENT.match(name) else '"' + name.replace('"', '""') + '"'


def base_col(r):
    """Base-object column name; differs from the view column when the view renames it."""
    return r.get("base_column") or r["column_name"]


def load_columns(csv_name):
    with (DOC_DIR / csv_name).open(newline="") as f:
        rows = list(csv.DictReader(f))
    rows.sort(key=lambda r: int(r["ordinal"]))
    assert [int(r["ordinal"]) for r in rows] == list(range(1, len(rows) + 1)), "ordinal gap"
    names = [r["column_name"] for r in rows]
    assert len(names) == len(set(names)), "duplicate column name"
    assert all(len(n) <= 63 for n in names), "name longer than Postgres limit (63)"
    return rows


def base_table_sql(v, rows):
    base = [r for r in rows if r["in_base"] == "Y"]
    width = max(len(q(base_col(r))) for r in base)
    lines = []
    for i, r in enumerate(base):
        sep = "," if i < len(base) - 1 else ""
        flag = "" if r["type_status"] == "CONFIRMED" else "  -- type ASSUMED"
        lines.append(f"    {q(base_col(r)).ljust(width)}  {r['pg_type']}{sep}{flag}")
    return (
        f"-- Stand-in for Snowflake {v['snowflake_base']}\n"
        f"-- ({v.get('base_note', 'a view in Snowflake')}; a plain table here so dummy data can be loaded).\n"
        f"-- {len(base)} columns: every column {v['snowflake_view'].split('.')[-1]} reads from it.\n"
        f"-- Generated by tools/gen_src_ddl.py from docs/src_sf/{v['csv']}\n"
        "-- No keys or NOT NULL constraints: none are known for the source.\n\n"
        f"CREATE TABLE {v['base']} (\n" + "\n".join(lines) + "\n);\n"
    )


def view_sql(v, rows):
    col_list = ",\n".join(f"    {q(r['column_name'])}" for r in rows)
    sel = ",\n".join(f"    {r['view_expression']}" for r in rows)
    return (
        f"-- Stand-in for Snowflake {v['snowflake_view']}.\n"
        "-- Same column list, same joins and filters as the Snowflake definition.\n"
        f"-- Generated by tools/gen_src_ddl.py from docs/src_sf/{v['csv']}\n"
        "-- Repeatable migration: drop + create (CREATE OR REPLACE cannot change column types).\n"
        f"{v.get('view_note', '')}\n"
        f"DROP VIEW IF EXISTS {v['view']};\n\n"
        f"CREATE VIEW {v['view']} (\n{col_list}\n) AS\nSELECT\n{sel}\n{v['from']}"
    )


def main():
    for v in VIEWS:
        rows = load_columns(v["csv"])
        (SQL_DIR / v["base_file"]).write_text(base_table_sql(v, rows))
        (SQL_DIR / v["view_file"]).write_text(view_sql(v, rows))
        assumed = sum(r["type_status"] != "CONFIRMED" for r in rows)
        n_base = sum(r["in_base"] == "Y" for r in rows)
        print(f"{v['view']}: {len(rows)} view columns, {n_base} base columns, {assumed} types ASSUMED")


if __name__ == "__main__":
    main()
