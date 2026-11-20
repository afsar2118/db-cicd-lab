-- Test for V2: due_date allowed on questions only. Rolls back.
BEGIN;

INSERT INTO app.comment_thread (thread_type, period, department, status, due_date, created_by)
VALUES ('question', 'FY27 OCT', 'DEPT_A', 'open', DATE '2026-12-15', 'bo@test');
DO $$ BEGIN RAISE NOTICE 'pass: 1 question with a due date is accepted'; END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO app.comment_thread (thread_type, period, department, due_date, created_by)
    VALUES ('comment', 'FY27 OCT', 'DEPT_A', DATE '2026-12-15', 'bo@test');
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'pass: 2 due date on a plain comment is rejected';
    RETURN;
  END;
  RAISE EXCEPTION 'TEST FAILED: 2 due date on a plain comment was accepted';
END $$;

DO $$ BEGIN RAISE NOTICE 'ALL 2 V2 TESTS PASSED'; END $$;
ROLLBACK;
