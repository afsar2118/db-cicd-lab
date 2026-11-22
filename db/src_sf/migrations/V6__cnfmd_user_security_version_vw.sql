-- Stand-in for Snowflake FIN_TRUSTED.CNFMD.TRS_FIN_USER_SECURITY_VERSION_VW
-- (used by DP_PNF_RPT_VW: only versions listed here are returned).
-- Plain table here; if it is empty, DP_PNF_RPT_VW returns NO rows.
-- Type ASSUMED (text) until confirmed.

CREATE TABLE cnfmd.trs_fin_user_security_version_vw (
    version  text  -- type ASSUMED
);
