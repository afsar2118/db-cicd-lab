-- Stand-in for Snowflake FIN_TRUSTED.CNFMD.TRS_USER_SECURITY_COST_CENTER_HIER
-- (used by DP_COST_CENTER_ACTUALS_RPT_VW: only cost centers listed here are returned).
-- Note the Snowflake name differs from the other security objects: no FIN_ prefix,
-- no _VW suffix, and the column is the SAP field name KOSTL (= cost center).
-- Only the column the view uses is modelled. Plain table here; if it is empty,
-- DP_COST_CENTER_ACTUALS_RPT_VW returns NO rows.
-- Type ASSUMED (text) until confirmed.

CREATE TABLE cnfmd.trs_user_security_cost_center_hier (
    kostl  text  -- type ASSUMED
);
