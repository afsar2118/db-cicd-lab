-- =====================================================================
-- Self-checking test for the landing database (raw + ctl schemas).
-- Safe on any environment: everything runs in one transaction and is
-- ROLLED BACK at the end, so no test rows are left behind.
-- Expected last line:  NOTICE: ALL 12 LANDING TESTS PASSED
-- =====================================================================
BEGIN;

CREATE FUNCTION pg_temp.check(name text, ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'TEST FAILED: %', name; END IF;
  RAISE NOTICE 'pass: %', name;
END $$;

CREATE FUNCTION pg_temp.must_fail(name text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pass: % (rejected: %)', name, SQLERRM;
    RETURN;
  END;
  RAISE EXCEPTION 'TEST FAILED: % (was accepted)', name;
END $$;

CREATE FUNCTION pg_temp.col_count(p_table text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM information_schema.columns WHERE table_schema = 'raw' AND table_name = p_table
$$;

-- ---------- 1-7: one raw table per source view: view columns + load_id + extracted_at ----------
SELECT pg_temp.check('1 raw.dp_title_actuals_rpt_vw has 221 + 2 columns',       pg_temp.col_count('dp_title_actuals_rpt_vw') = 223);
SELECT pg_temp.check('2 raw.dp_pnf_rpt_vw has 58 + 2 columns',                  pg_temp.col_count('dp_pnf_rpt_vw') = 60);
SELECT pg_temp.check('3 raw.dp_cost_center_actuals_rpt_vw has 171 + 2 columns', pg_temp.col_count('dp_cost_center_actuals_rpt_vw') = 173);
SELECT pg_temp.check('4 raw.dp_acct_hier_rpt_vw has 62 + 2 columns',            pg_temp.col_count('dp_acct_hier_rpt_vw') = 64);
SELECT pg_temp.check('5 raw.dp_cost_ctr_hier_rpt_vw has 51 + 2 columns',        pg_temp.col_count('dp_cost_ctr_hier_rpt_vw') = 53);
SELECT pg_temp.check('6 raw.dp_business_area_hier_rpt_vw has 36 + 2 columns',   pg_temp.col_count('dp_business_area_hier_rpt_vw') = 38);
SELECT pg_temp.check('7 raw.dp_company_code_hier_rpt_vw has 36 + 2 columns',    pg_temp.col_count('dp_company_code_hier_rpt_vw') = 38);

SELECT pg_temp.check('8 F&P_SEGMENT lands as fp_segment (no quoted name)',
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'raw' AND table_name = 'dp_pnf_rpt_vw' AND column_name = 'fp_segment')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'raw' AND column_name LIKE '%&%'));

-- ---------- 9-12: load log rules ----------
INSERT INTO ctl.load_log (run_id, source_system, source_object, target_table, status)
VALUES ('00000000-0000-0000-0000-000000000001', 'test', 'test.src', 'raw.dp_company_code_hier_rpt_vw', 'RUNNING');

INSERT INTO raw.dp_company_code_hier_rpt_vw (company_code, load_id, extracted_at)
SELECT 'TST', max(load_id), now() FROM ctl.load_log WHERE source_system = 'test';

SELECT pg_temp.check('9 a RUNNING load can tag raw rows',
  (SELECT count(*) FROM raw.dp_company_code_hier_rpt_vw r JOIN ctl.load_log l USING (load_id)
    WHERE l.source_system = 'test' AND r.company_code = 'TST') = 1);

SELECT pg_temp.must_fail('10 raw row with an unknown load_id',
 $q$INSERT INTO raw.dp_company_code_hier_rpt_vw (company_code, load_id, extracted_at) VALUES ('TST', -1, now())$q$);

SELECT pg_temp.must_fail('11 SUCCESS with rows_written <> rows_read',
 $q$INSERT INTO ctl.load_log (run_id, source_system, source_object, target_table, status, finished_at, rows_read, rows_written)
    VALUES ('00000000-0000-0000-0000-000000000001','test','test.src','raw.x','SUCCESS', now(), 10, 9)$q$);

SELECT pg_temp.must_fail('12 finished status without finished_at',
 $q$INSERT INTO ctl.load_log (run_id, source_system, source_object, target_table, status)
    VALUES ('00000000-0000-0000-0000-000000000001','test','test.src','raw.x','FAILED')$q$);

DO $$ BEGIN RAISE NOTICE 'ALL 12 LANDING TESTS PASSED'; END $$;
ROLLBACK;
