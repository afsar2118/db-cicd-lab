-- Source stand-in database (src_sf): one Postgres schema per Snowflake DATABASE.SCHEMA
-- that DP_TITLE_ACTUALS_RPT_VW touches. Postgres has no cross-database names, so the
-- Snowflake database prefix is dropped:
--   FIN_CONSUMPTION.FIN_REPORTING -> fin_reporting   (the view; location per architecture diagram)
--   FIN_TRUSTED.FIN_CNFMD         -> fin_cnfmd       (TRS_FACT_TITLE_ACTUALS_VW)
--   FIN_TRUSTED.CNFMD             -> cnfmd           (user security views)
--   FIN_STAGING.EDP_HANA          -> edp_hana        (company code master data, T001)
-- Identifiers are unquoted lowercase; Snowflake returns them uppercase. The extract job
-- lowercases column names, so the same job works against either source.

CREATE SCHEMA IF NOT EXISTS fin_reporting;
CREATE SCHEMA IF NOT EXISTS fin_cnfmd;
CREATE SCHEMA IF NOT EXISTS cnfmd;
CREATE SCHEMA IF NOT EXISTS edp_hana;
