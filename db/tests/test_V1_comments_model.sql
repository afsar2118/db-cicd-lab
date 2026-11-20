-- =====================================================================
-- Self-checking test for V1 (comments data model).
-- Safe on any environment: everything runs in one transaction and is
-- ROLLED BACK at the end, so no test rows are left behind.
-- Runs in CI (psql, after Flyway migrate) and in DBeaver (Alt+X).
-- Expected last line:  NOTICE: ALL 16 TESTS PASSED
-- Any failure stops the script with "TEST FAILED: <name>".
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

-- ---------- test data: one department, tower and hub; OCT vs AOP ----------
INSERT INTO app.comment_thread (thread_id, thread_type, period, compare_period, department, tower, hub,
                                expense_category, line_item, source_tab, created_by) VALUES
 ('11111111-0000-0000-0000-000000000001','comment','FY27 OCT','FY27 AOP','DEPT_A','TOWER_1','hub_a',
  'Professional Services','Vendor_X','professional_services','bo@test'),
 ('11111111-0000-0000-0000-000000000002','comment','FY27 OCT','FY27 AOP','DEPT_A','TOWER_1','hub_a',
  'Professional Services',NULL,'full_year_comparison','bo@test'),
 ('11111111-0000-0000-0000-000000000003','comment','FY27 OCT','FY27 JUL','DEPT_A','TOWER_1','hub_a',
  'Professional Services',NULL,'professional_services','bo@test');

INSERT INTO app.comment_thread (thread_id, thread_type, period, compare_period, department, tower, hub, created_by)
VALUES ('22222222-0000-0000-0000-000000000001','variance_explanation','FY27 OCT','FY27 AOP',
        'DEPT_A','TOWER_1','hub_a','fin@test');

INSERT INTO app.comment_thread (thread_id, thread_type, period, department, tower, hub, expense_category, status, created_by)
VALUES ('33333333-0000-0000-0000-000000000001','question','FY27 OCT','DEPT_A','TOWER_1','hub_a',
        'Salary & Benefits','open','bo@test');

INSERT INTO app.comment_entry (thread_id, body, value_at_comment, explained_amount, author, author_role) VALUES
 ('11111111-0000-0000-0000-000000000001','Vendor_X savings',              -50000, NULL,    'bo@test','budget_owner'),
 ('11111111-0000-0000-0000-000000000002','Team moved to shared services',-200000, NULL,    'bo@test','budget_owner'),
 ('11111111-0000-0000-0000-000000000003','Prior forecast comment',           10000, NULL,    'bo@test','budget_owner'),
 ('22222222-0000-0000-0000-000000000001','Function moved to another tower',           -1000000, -600000, 'fin@test','finance'),
 ('22222222-0000-0000-0000-000000000001','Vendor_X contract ended',      -1000000, -300000, 'fin@test','finance'),
 ('33333333-0000-0000-0000-000000000001','Why is S&B up in Q3?',            450000, NULL,    'bo@test','budget_owner');

-- ---------- 1-5: display across tabs ----------
SELECT pg_temp.check('1 Full Year Comparison PS line shows its own + Vendor_X comment (roll-up)',
  (SELECT count(*) FROM app.comments_for('FY27 OCT','FY27 AOP', p_hub=>'hub_a',
                                         p_category=>'Professional Services')) = 2);

SELECT pg_temp.check('2 PS tab Vendor_X row shows Vendor_X + category + hub variance explanation (parents)',
  (SELECT count(*) FROM app.comments_for('FY27 OCT','FY27 AOP', p_hub=>'hub_a',
          p_category=>'Professional Services', p_line_item=>'Vendor_X', p_include_parents=>true)) = 3);

SELECT pg_temp.check('3 OCT vs JUL variance does not show OCT vs AOP comments',
  (SELECT count(*) FROM app.comments_for('FY27 OCT','FY27 JUL', p_hub=>'hub_a')) = 1);

SELECT pg_temp.check('4 Tower total rolls up all OCT vs AOP comments under it',
  (SELECT count(*) FROM app.comments_for('FY27 OCT','FY27 AOP', p_department=>'DEPT_A', p_tower=>'TOWER_1')) = 3);

SELECT pg_temp.check('5 Plain OCT value (no compare) shows only non-variance comments',
  (SELECT count(*) FROM app.comments_for('FY27 OCT', NULL, p_hub=>'hub_a')) = 1);

-- ---------- 6-8: workflow and views ----------
INSERT INTO app.comment_entry (thread_id, body, author, author_role)
VALUES ('33333333-0000-0000-0000-000000000001','Merit increase applied in Q3','fin@test','finance');
SELECT pg_temp.check('6 Finance reply marks question answered',
  (SELECT status FROM app.comment_thread WHERE thread_id='33333333-0000-0000-0000-000000000001') = 'answered');

SELECT pg_temp.check('7 Inbox lists the 5 test threads; question shows latest reply',
  (SELECT count(*) FROM app.v_comment_inbox WHERE created_by IN ('bo@test','fin@test')) = 5 AND
  (SELECT last_text FROM app.v_comment_inbox
    WHERE thread_id='33333333-0000-0000-0000-000000000001') = 'Merit increase applied in Q3');

SELECT pg_temp.check('8 Variance coverage sums the two drivers = -900,000',
  (SELECT explained_amount FROM app.v_variance_explained
    WHERE department='DEPT_A' AND hub='hub_a' AND compare_period='FY27 AOP') = -900000);

-- ---------- 9-16: rules the database must reject ----------
SELECT pg_temp.must_fail('9 Variance explanation at line_item level',
 $q$INSERT INTO app.comment_thread (thread_type,period,compare_period,department,tower,hub,expense_category,line_item,created_by)
    VALUES ('variance_explanation','FY27 OCT','FY27 AOP','DEPT_A','TOWER_1','h','Professional Services','Vendor_X','x')$q$);

SELECT pg_temp.must_fail('10 Variance explanation without compare_period',
 $q$INSERT INTO app.comment_thread (thread_type,period,department,tower,hub,created_by)
    VALUES ('variance_explanation','FY27 OCT','DEPT_A','TOWER_1','h','x')$q$);

SELECT pg_temp.must_fail('11 Hub without tower (org hierarchy)',
 $q$INSERT INTO app.comment_thread (thread_type,period,department,hub,created_by)
    VALUES ('comment','FY27 OCT','DEPT_A','h','x')$q$);

SELECT pg_temp.must_fail('12 Same period on both sides of a variance',
 $q$INSERT INTO app.comment_thread (thread_type,period,compare_period,department,created_by)
    VALUES ('comment','FY27 OCT','FY27 OCT','DEPT_A','x')$q$);

SELECT pg_temp.must_fail('13 explained_amount on a general comment',
 $q$INSERT INTO app.comment_entry (thread_id,body,explained_amount,author,author_role)
    VALUES ('11111111-0000-0000-0000-000000000001','x',100,'x','other')$q$);

SELECT pg_temp.must_fail('14 Changing the anchor of an existing thread',
 $q$UPDATE app.comment_thread SET hub='other_hub' WHERE thread_id='11111111-0000-0000-0000-000000000001'$q$);

SELECT pg_temp.must_fail('15 Closing a question without who/when',
 $q$UPDATE app.comment_thread SET status='closed' WHERE thread_id='33333333-0000-0000-0000-000000000001'$q$);

SELECT pg_temp.must_fail('16 Question without a status',
 $q$INSERT INTO app.comment_thread (thread_type,period,department,created_by)
    VALUES ('question','FY27 OCT','DEPT_A','x')$q$);

DO $$ BEGIN RAISE NOTICE 'ALL 16 TESTS PASSED'; END $$;
ROLLBACK;
