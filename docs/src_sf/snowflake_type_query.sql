-- Run in Snowflake and export the result as CSV (attach the file, not a photo).
-- It gives the real data types for every column the local stand-in models.

SELECT 'FIN_CONSUMPTION' AS table_catalog, table_schema, table_name, ordinal_position, column_name,
       data_type, character_maximum_length, numeric_precision, numeric_scale, is_nullable
FROM FIN_CONSUMPTION.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'FIN_REPORTING' AND table_name IN ('DP_TITLE_ACTUALS_RPT_VW', 'DP_PNF_RPT_VW', 'DP_COST_CENTER_ACTUALS_RPT_VW',
                                                          'DP_ACCT_HIER_RPT_VW', 'DP_COST_CTR_HIER_RPT_VW',
                                                          'DP_BUSINESS_AREA_HIER_RPT_VW', 'DP_COMPANY_CODE_HIER_RPT_VW')
UNION ALL
SELECT 'FIN_STAGING', table_schema, table_name, ordinal_position, column_name,
       data_type, character_maximum_length, numeric_precision, numeric_scale, is_nullable
FROM FIN_STAGING.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'EDP_HANA'
  AND (   (table_name = 'STG_CV_DIM_T001_COMPCODE_01' AND column_name IN ('BUKRS', 'BUTXT'))
       OR  table_name IN ('STG_CV_DIM_BA_HIER_FLAT', 'STG_CV_DIM_CCODE_HIER_FLAT'))
UNION ALL
SELECT 'FIN_TRUSTED', table_schema, table_name, ordinal_position, column_name,
       data_type, character_maximum_length, numeric_precision, numeric_scale, is_nullable
FROM FIN_TRUSTED.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'CNFMD'
  AND table_name IN ('TRS_FIN_USER_SECURITY_COMPANY_CODE_VW', 'TRS_FIN_USER_SECURITY_BUSINESS_AREA_VW',
                     'TRS_FIN_USER_SECURITY_VERSION_VW', 'TRS_USER_SECURITY_COST_CENTER_HIER')
ORDER BY 1, 2, 3, 4;
