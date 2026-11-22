-- =====================================================================
-- Self-checking test for the dimensional model (dw schema in landing_<env>).
-- Safe on any environment: everything runs in one transaction and is
-- ROLLED BACK at the end (including the test snapshot partitions).
-- Expected last line:  NOTICE: ALL 16 DW TESTS PASSED
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

-- ---------- 1-3: structure ----------
SELECT pg_temp.check('1 all 18 model tables exist',
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'dw' AND c.relkind IN ('r', 'p') AND NOT c.relispartition
      AND c.relname IN ('dim_snapshot','dim_fiscal_quarter','dim_fiscal_period','dim_version','dim_account',
                        'dim_cost_center','dim_org','dim_region','hier_account_path','bridge_account_hierarchy',
                        'hier_cost_center_path','map_cost_center_org','fact_gl_line_item','fact_gl_actual',
                        'fact_plan_amount','fact_plan_amount_fy','fact_intl_plan_amount','fact_headcount_position')) = 18);

SELECT pg_temp.check('2 every dimension except dim_snapshot has a -1 Unknown member',
  (SELECT count(*) FROM dw.dim_fiscal_quarter WHERE fiscal_quarter_key = -1) +
  (SELECT count(*) FROM dw.dim_fiscal_period  WHERE fiscal_period_key  = -1) +
  (SELECT count(*) FROM dw.dim_version        WHERE version_key        = -1) +
  (SELECT count(*) FROM dw.dim_account        WHERE account_key        = -1) +
  (SELECT count(*) FROM dw.dim_cost_center    WHERE cost_center_key    = -1) +
  (SELECT count(*) FROM dw.dim_org            WHERE org_key            = -1) +
  (SELECT count(*) FROM dw.dim_region         WHERE region_key         = -1) = 7);

SELECT pg_temp.check('3 all 6 facts are partitioned by snapshot_key and have a DEFAULT partition',
  (SELECT count(*) FROM pg_partitioned_table pt JOIN pg_class c ON c.oid = pt.partrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'dw' AND pt.partstrat = 'l' AND pt.partdefid <> 0) = 6);

-- ---------- test data ----------
INSERT INTO dw.dim_snapshot (entity, source, created_load_id, src_system)
SELECT 'TEST', 'test', load_id, 'TEST' FROM ctl.load_log WHERE source_system = 'dw_bootstrap';
INSERT INTO dw.dim_fiscal_quarter (fiscal_year, quarter_label, created_load_id, src_system)
SELECT 2099, 'Q1', load_id, 'TEST' FROM ctl.load_log WHERE source_system = 'dw_bootstrap';
INSERT INTO dw.dim_fiscal_period (fiscal_year, fiscal_period, fiscal_quarter_key, created_load_id, src_system)
SELECT 2099, 1, q.fiscal_quarter_key, l.load_id, 'TEST'
FROM dw.dim_fiscal_quarter q, ctl.load_log l WHERE q.fiscal_year = 2099 AND l.source_system = 'dw_bootstrap';
INSERT INTO dw.dim_account (account_code, pax_is_base, created_load_id, src_system)
SELECT 'TSTACC', false, load_id, 'TEST' FROM ctl.load_log WHERE source_system = 'dw_bootstrap';
INSERT INTO dw.dim_cost_center (cost_center_code, created_load_id, src_system)
SELECT 'TSTCC', load_id, 'TEST' FROM ctl.load_log WHERE source_system = 'dw_bootstrap';
INSERT INTO dw.dim_version (version_label, category, created_load_id, src_system)
SELECT 'TSTVER', 'Plan', load_id, 'TEST' FROM ctl.load_log WHERE source_system = 'dw_bootstrap';

CREATE TEMP VIEW t AS
SELECT (SELECT max(snapshot_key) FROM dw.dim_snapshot WHERE entity = 'TEST')               AS snap,
       (SELECT fiscal_period_key FROM dw.dim_fiscal_period WHERE fiscal_year = 2099)        AS per,
       (SELECT fiscal_quarter_key FROM dw.dim_fiscal_quarter WHERE fiscal_year = 2099)      AS qtr,
       (SELECT account_key FROM dw.dim_account WHERE account_code = 'TSTACC')               AS acc,
       (SELECT cost_center_key FROM dw.dim_cost_center WHERE cost_center_code = 'TSTCC')    AS cc,
       (SELECT version_key FROM dw.dim_version WHERE version_label = 'TSTVER')              AS ver,
       (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap')              AS lid;

-- ---------- 4-6: snapshot partitions ----------
SELECT pg_temp.check('4 create_snapshot_partitions creates one partition per fact',
  (SELECT dw.create_snapshot_partitions(snap) FROM t) = 6);
SELECT pg_temp.check('5 calling it again creates nothing (idempotent)',
  (SELECT dw.create_snapshot_partitions(snap) FROM t) = 0);

INSERT INTO dw.fact_gl_line_item (snapshot_key, cost_center_key, account_key, fiscal_period_key, company_code,
       document_number, document_posting_row, assignment_number, value_type, posting_date, amount_usd,
       transaction_currency, created_load_id, src_system)
SELECT snap, cc, acc, per, 'TST1', 'D1', '001', 'A1', '04', DATE '2099-01-15', 100.1234, 'USD', lid, 'TEST' FROM t;

SELECT pg_temp.check('6 a fact row lands in its snapshot partition, not the DEFAULT one',
  (SELECT tableoid::regclass::text FROM dw.fact_gl_line_item WHERE document_number = 'D1')
   = (SELECT 'dw.fact_gl_line_item_s' || snap FROM t));

-- ---------- 7-9: line-item key (CO document row + assignment number) ----------
SELECT pg_temp.must_fail('7 same CO document row and assignment twice in one snapshot',
 $q$INSERT INTO dw.fact_gl_line_item (snapshot_key, cost_center_key, account_key, fiscal_period_key, company_code,
       document_number, document_posting_row, assignment_number, value_type, posting_date, amount_usd,
       transaction_currency, created_load_id, src_system)
    SELECT snap, cc, acc, per, 'TST1', 'D1', '001', 'A1', '04', DATE '2099-01-15', 5, 'USD', lid, 'TEST' FROM t$q$);

INSERT INTO dw.fact_gl_line_item (snapshot_key, cost_center_key, account_key, fiscal_period_key, company_code,
       document_number, document_posting_row, assignment_number, value_type, posting_date, amount_usd,
       transaction_currency, created_load_id, src_system)
SELECT snap, cc, acc, per, 'TST1', 'D1', '001', 'A2', '11', DATE '2099-01-15', 7, 'USD', lid, 'TEST' FROM t;
SELECT pg_temp.check('8 same CO document row with another assignment number is a separate line',
  (SELECT count(*) FROM dw.fact_gl_line_item WHERE document_number = 'D1') = 2);

SELECT pg_temp.check('9 amounts keep 4 decimals',
  (SELECT amount_usd FROM dw.fact_gl_line_item WHERE assignment_number = 'A1') = 100.1234);

-- ---------- 10-12: dimension references ----------
SELECT pg_temp.must_fail('10 fact row pointing to a non-existent account',
 $q$INSERT INTO dw.fact_gl_actual (snapshot_key, cost_center_key, account_key, fiscal_period_key, company_code,
       amount_usd, created_load_id, src_system)
    SELECT snap, cc, -999, per, 'TST1', 1, lid, 'TEST' FROM t$q$);

INSERT INTO dw.fact_gl_actual (snapshot_key, cost_center_key, account_key, fiscal_period_key, company_code,
       amount_usd, created_load_id, src_system)
SELECT snap, -1, -1, per, 'TST1', 1, lid, 'TEST' FROM t;
SELECT pg_temp.check('11 unmatched cost center / account land on the -1 Unknown member',
  (SELECT count(*) FROM dw.fact_gl_actual WHERE cost_center_key = -1 AND account_key = -1) = 1);

INSERT INTO dw.fact_plan_amount (snapshot_key, cost_center_key, account_key, fiscal_quarter_key, version_key,
       amount_usd, created_load_id, src_system)
SELECT snap, cc, acc, qtr, ver, 1234.56, lid, 'TEST' FROM t;
SELECT pg_temp.check('12 plan amounts keep cents (no rounding to whole units)',
  (SELECT amount_usd FROM dw.fact_plan_amount WHERE version_key = (SELECT ver FROM t)) = 1234.56);

-- ---------- 13-14: hierarchies and mapping ----------
INSERT INTO dw.hier_cost_center_path (snapshot_key, cost_center_key, cost_center_name, cc_l4_code, cc_l4_name,
       cc_l5_code, cc_l5_name, created_load_id, src_system)
SELECT snap, cc, 'Test CC', 'L4', 'Level 4', 'L5', 'Level 5', lid, 'TEST' FROM t;
SELECT pg_temp.check('13 ragged cost center path (no L6/L7) is accepted',
  (SELECT cc_l6_code IS NULL AND cc_l7_code IS NULL FROM dw.hier_cost_center_path
    WHERE cost_center_key = (SELECT cc FROM t)));

INSERT INTO dw.map_cost_center_org (snapshot_key, cost_center_code, cost_center_key, org_key, region_key, tower,
       created_load_id, src_system)
SELECT snap, 'TSTCC', cc, -1, -1, 'T1', lid, 'TEST' FROM t;
SELECT pg_temp.must_fail('14 second org mapping for the same cost center in one snapshot',
 $q$INSERT INTO dw.map_cost_center_org (snapshot_key, cost_center_code, cost_center_key, org_key, region_key, tower,
       created_load_id, src_system)
    SELECT snap, 'TSTCC', cc, -1, -1, 'T2', lid, 'TEST' FROM t$q$);

-- ---------- 15-16: audit columns ----------
SELECT pg_temp.check('15 audit defaults filled: create time, created by, delete flag N',
  (SELECT bool_and(dw_create_dtm IS NOT NULL AND dw_created_by IS NOT NULL AND src_delete_flg = 'N')
     FROM dw.fact_gl_line_item WHERE document_number = 'D1'));

SELECT pg_temp.must_fail('16 delete flag other than Y/N',
 $q$UPDATE dw.dim_cost_center SET src_delete_flg = 'X' WHERE cost_center_code = 'TSTCC'$q$);

DO $$ BEGIN RAISE NOTICE 'ALL 16 DW TESTS PASSED'; END $$;
ROLLBACK;
