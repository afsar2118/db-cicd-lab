-- V2: questions can carry a due date (date finance should answer by)
ALTER TABLE app.comment_thread ADD COLUMN due_date date;

ALTER TABLE app.comment_thread ADD CONSTRAINT ck_due_date_for_questions
  CHECK (due_date IS NULL OR thread_type = 'question');

COMMENT ON COLUMN app.comment_thread.due_date IS
  'Questions only: date finance should answer by';
