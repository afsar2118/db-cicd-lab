-- =====================================================================
-- Self-checking test for the source stand-in database (src_sf):
-- the 7 Snowflake reporting views recreated in Postgres.
-- Safe on any environment: everything runs in one transaction and is
-- ROLLED BACK at the end, so no test rows are left behind.
-- Runs in CI (psql, after Flyway migrate) and in DBeaver (Alt+X).
-- Expected last line:  NOTICE: ALL 14 SRC_SF TESTS PASSED
-- Any failure stops the script with "TEST FAILED: <name>".
-- =====================================================================
BEGIN;

CREATE FUNCTION pg_temp.check(name text, ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'TEST FAILED: %', name; END IF;
  RAISE NOTICE 'pass: %', name;
END $$;

CREATE FUNCTION pg_temp.col_count(p_view text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM information_schema.columns
  WHERE table_schema = 'fin_reporting' AND table_name = p_view
$$;

-- ---------- 1-7: every view exists with the column count of its Snowflake definition ----------
SELECT pg_temp.check('1 dp_title_actuals_rpt_vw has 221 columns',       pg_temp.col_count('dp_title_actuals_rpt_vw') = 221);
SELECT pg_temp.check('2 dp_pnf_rpt_vw has 58 columns',                  pg_temp.col_count('dp_pnf_rpt_vw') = 58);
SELECT pg_temp.check('3 dp_cost_center_actuals_rpt_vw has 171 columns', pg_temp.col_count('dp_cost_center_actuals_rpt_vw') = 171);
SELECT pg_temp.check('4 dp_acct_hier_rpt_vw has 62 columns',            pg_temp.col_count('dp_acct_hier_rpt_vw') = 62);
SELECT pg_temp.check('5 dp_cost_ctr_hier_rpt_vw has 51 columns',        pg_temp.col_count('dp_cost_ctr_hier_rpt_vw') = 51);
SELECT pg_temp.check('6 dp_business_area_hier_rpt_vw has 36 columns',   pg_temp.col_count('dp_business_area_hier_rpt_vw') = 36);
SELECT pg_temp.check('7 dp_company_code_hier_rpt_vw has 36 columns',    pg_temp.col_count('dp_company_code_hier_rpt_vw') = 36);

-- ---------- test data: user may see company 1000, business area B1, version FC_OCT, one cost center ----------
INSERT INTO cnfmd.trs_fin_user_security_company_code_vw  VALUES ('TST1000');
INSERT INTO cnfmd.trs_fin_user_security_business_area_vw VALUES ('TSTB1');
INSERT INTO cnfmd.trs_fin_user_security_version_vw       VALUES ('TSTFC');
INSERT INTO cnfmd.trs_user_security_cost_center_hier     VALUES ('TSTCC1');
INSERT INTO edp_hana.stg_cv_dim_t001_compcode_01         VALUES ('TST1000', 'Test Company 1000');

INSERT INTO fin_cnfmd.trs_fact_title_actuals_vw (spl_doc_number, company_code, business_area, dw_update_dtm) VALUES
 ('TSTD1', 'TST1000', 'TSTB1', '2026-11-01'),   -- visible
 ('TSTD2', 'TST1000', NULL,    '2026-11-02'),   -- visible: NULL business area allowed
 ('TSTD3', 'TST1000', 'TSTB2', '2026-11-03'),   -- hidden: business area not granted
 ('TSTD4', 'TST2000', 'TSTB1', '2026-11-04');   -- hidden: company not granted

INSERT INTO fin_cnfmd.trs_fact_plan_forecast_vw (record_id, company_code, business_area, version, dw_update_dtm) VALUES
 ('TSTR1', 'TST1000', 'TSTB1', 'TSTFC',  '2026-11-01'),  -- visible
 ('TSTR2', 'TST1000', 'TSTB1', 'TSTAOP', '2026-11-02');  -- hidden: version not granted

INSERT INTO fin_cnfmd.trs_cv_costcenter_rep_cca_cc_vw (document_number, company_code, cost_center, business_area) VALUES
 ('TSTC1', 'TST1000', 'TSTCC1', NULL),   -- visible: this view has no business-area filter
 ('TSTC2', 'TST1000', 'TSTCC2', 'TSTB1'); -- hidden: cost center not granted

INSERT INTO edp_hana.stg_cv_dim_ba_hier_flat (ba_l00, ba_l01, ba_l02, ba_l03, business_area, src_delete_flg)
VALUES ('TSTTOP', '?', '', '  ? ', 'TSTB1', '?');
INSERT INTO edp_hana.stg_cv_dim_ccode_hier_flat (ccode_l00, ccode_l01, company_code)
VALUES ('TSTTOP', '?', 'TST1000');

-- ---------- 8-11: security filters ----------
SELECT pg_temp.check('8 title actuals: only granted company + business area (or NULL BA) rows show',
  (SELECT string_agg(spl_doc_number, ',' ORDER BY spl_doc_number)
     FROM fin_reporting.dp_title_actuals_rpt_vw WHERE spl_doc_number LIKE 'TST%') = 'TSTD1,TSTD2');

SELECT pg_temp.check('9 title actuals: company_code_desc comes from the T001 lookup',
  (SELECT company_code_desc FROM fin_reporting.dp_title_actuals_rpt_vw WHERE spl_doc_number = 'TSTD1')
   = 'Test Company 1000');

SELECT pg_temp.check('10 plan/forecast: version filter hides ungranted versions',
  (SELECT string_agg(record_id, ',') FROM fin_reporting.dp_pnf_rpt_vw WHERE record_id LIKE 'TST%') = 'TSTR1');

SELECT pg_temp.check('11 cost center actuals: cost center filter (KOSTL) applies',
  (SELECT string_agg(document_number, ',') FROM fin_reporting.dp_cost_center_actuals_rpt_vw
    WHERE document_number LIKE 'TST%') = 'TSTC1');

-- ---------- 12-14: hierarchy views rename and clean ('?' or blank -> NULL) ----------
SELECT pg_temp.check('12 business area hier: ''?'', blank and padded ''?'' become NULL; values kept',
  (SELECT business_area_hl00 = 'TSTTOP' AND business_area_hl01 IS NULL AND business_area_hl02 IS NULL
          AND business_area_hl03 IS NULL AND business_area_hierarchy = 'TSTB1'
     FROM fin_reporting.dp_business_area_hier_rpt_vw WHERE business_area_hl00 = 'TSTTOP'));

SELECT pg_temp.check('13 business area hier: audit columns are not cleaned',
  (SELECT src_delete_flg FROM fin_reporting.dp_business_area_hier_rpt_vw WHERE business_area_hl00 = 'TSTTOP') = '?');

SELECT pg_temp.check('14 company code hier: CCODE_* renamed to COMPANY_CODE_* and cleaned',
  (SELECT company_code_l00 = 'TSTTOP' AND company_code_l01 IS NULL AND company_code = 'TST1000'
     FROM fin_reporting.dp_company_code_hier_rpt_vw WHERE company_code_l00 = 'TSTTOP'));

DO $$ BEGIN RAISE NOTICE 'ALL 14 SRC_SF TESTS PASSED'; END $$;
ROLLBACK;
