# Source stand-in database (`src_sf`) — Snowflake views modelled so far

Each view is recreated in local Postgres with the same column list, joins and filters as
its Snowflake definition. Its base object becomes a plain table so dummy data can be loaded.
Column order/types live in the CSV next to this file; `tools/gen_src_ddl.py` regenerates
the base-table (V) and view (R__) scripts from it. All types are ASSUMED until the
Snowflake export from `snowflake_type_query.sql` is applied.

| Snowflake view (FIN_CONSUMPTION.FIN_REPORTING) | Cols | Base object (FIN_TRUSTED.FIN_CNFMD unless stated) | Filters | Scripts |
|---|---|---|---|---|
| DP_TITLE_ACTUALS_RPT_VW | 221 | TRS_FACT_TITLE_ACTUALS_VW (+ T001 lookup) | company code, business area | V2, V3, V4, R__ |
| DP_PNF_RPT_VW | 58 | TRS_FACT_PLAN_FORECAST_VW | company code, business area, version | V5, V6, R__ |
| DP_COST_CENTER_ACTUALS_RPT_VW | 171 | TRS_CV_COSTCENTER_REP_CCA_CC_VW | company code, cost center (KOSTL) | V7, V8, R__ |
| DP_ACCT_HIER_RPT_VW | 62 | TRS_DIM_ACCT_HIER | none | V9, R__ |
| DP_COST_CTR_HIER_RPT_VW | 51 | TRS_DIM_CC_HIER | none | V10, R__ |
| DP_BUSINESS_AREA_HIER_RPT_VW | 36 | FIN_STAGING.EDP_HANA.STG_CV_DIM_BA_HIER_FLAT (columns renamed; '?'/blank -> NULL) | none | V11, R__ |
| DP_COMPANY_CODE_HIER_RPT_VW | 36 | FIN_STAGING.EDP_HANA.STG_CV_DIM_CCODE_HIER_FLAT (columns renamed; '?'/blank -> NULL) | none | V12, R__ |

V1 creates the schemas. Security objects (FIN_TRUSTED.CNFMD) are plain tables locally:
an empty security table makes the views that use it return no rows.

All seven Snowflake views from the architecture source list are now modelled (the diagram lists the account hierarchy as DP_COST_ELEMENT_HIER_RPT_VW; DP_ACCT_HIER_RPT_VW is assumed to be it - to confirm).
