-- Stand-in for Snowflake FIN_STAGING.EDP_HANA.STG_CV_DIM_T001_COMPCODE_01
-- (SAP T001 company code master). Only the two columns the view uses are modelled:
--   bukrs = company code, butxt = company code description (-> COMPANY_CODE_DESC).
-- Types ASSUMED (text) until confirmed from Snowflake INFORMATION_SCHEMA.

CREATE TABLE edp_hana.stg_cv_dim_t001_compcode_01 (
    bukrs  text,   -- type ASSUMED
    butxt  text    -- type ASSUMED
);
