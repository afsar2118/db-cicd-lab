-- Stand-ins for Snowflake FIN_TRUSTED.CNFMD user security views.
-- In Snowflake these return the company codes / business areas the CURRENT user may see.
-- Here they are plain tables: whatever rows they hold are what DP_TITLE_ACTUALS_RPT_VW returns.
-- If trs_fin_user_security_company_code_vw is empty, the view returns NO rows.
-- Types ASSUMED (text) until confirmed.

CREATE TABLE cnfmd.trs_fin_user_security_company_code_vw (
    company_code  text   -- type ASSUMED
);

CREATE TABLE cnfmd.trs_fin_user_security_business_area_vw (
    business_area  text  -- type ASSUMED
);
