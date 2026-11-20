-- =====================================================================
-- Forecast app comments model (app schema) - v6 (after review 2026-11-05)
-- Replaces public.row_comments (UI repoints to these tables).
--
-- Principle: a comment belongs to the DATA, not to a tab. It is stored
-- against the data's coordinates (the "anchor"), so the same comment shows
-- on every tab that displays that data. The tab it was typed on is info only.
--
-- Anchor:
--   period / compare_period : the version(s) the value belongs to.
--                             Plain value  -> period = 'FY27 OCT', compare NULL
--                             Variance     -> period = 'FY27 OCT', compare = 'FY27 AOP'
--   department > tower > hub > cost_center : org hierarchy (cost center rolls
--                             up to hub, hub to tower, tower to department).
--                             A lower level requires all levels above it.
--   expense_category > line_item : expense hierarchy.
--   NULL at a level = "not at this level" (the comment is on the total).
--
-- No FKs to rpt/pipeline/UI data tables (rpt is rebuilt every run).
-- uuid keys to match existing UI tables. Requires PostgreSQL 13+.
--
-- Applied once per database by Flyway (tracked in flyway_schema_history).
-- Never edit this file after it has been deployed: add V2, V3 ... instead.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS app;

-- ---------------------------------------------------------------------
-- 1. Thread (PARENT): WHAT the comment is about + its type and status.
--    Anchor and type are fixed once created (see trigger below).
-- ---------------------------------------------------------------------
CREATE TABLE app.comment_thread (
  thread_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_type       varchar(30) NOT NULL
                    CHECK (thread_type IN ('comment','question','variance_explanation','override_reason')),

  -- ---- Anchor ----
  period            varchar(30)  NOT NULL,  -- e.g. 'FY27 OCT', 'FY27 AOP', 'FY27 Q2 ACT'
  compare_period    varchar(30),            -- set only for variances, e.g. 'FY27 AOP'
  department        varchar(100) NOT NULL,  -- top of the org hierarchy
  tower             varchar(100),
  hub               varchar(100),           -- as the UI names it today (hub leader user name)
  cost_center       varchar(20),
  expense_category  varchar(100),           -- Salary & Benefits, Professional Services, Other Expense,
                                            -- Contra, Allocation In, Travel ...  NULL = total row
  line_item         varchar(200),           -- line within the category, e.g. Vendor_X
  anchor_key        text GENERATED ALWAYS AS (
                      period || '|' || coalesce(compare_period,'-') || '|' ||
                      department || '|' || coalesce(tower,'*') || '|' ||
                      coalesce(hub,'*') || '|' || coalesce(cost_center,'*') || '|' ||
                      coalesce(expense_category,'*') || '|' || coalesce(line_item,'*')
                    ) STORED,               -- one string key for the UI; '*' = level not set

  -- ---- Context ----
  source_tab        varchar(50),            -- tab it was typed on (info only, never used to match)
  source            varchar(20) NOT NULL DEFAULT 'ui' CHECK (source IN ('ui','upload')),
  override_id       uuid,                   -- override_reason: row in public.value_overrides (no FK)

  -- ---- Workflow (questions only: budget owner asks, finance answers) ----
  status            varchar(20) CHECK (status IN ('open','answered','closed')),

  created_by        varchar(200) NOT NULL,
  created_at        timestamptz  NOT NULL DEFAULT now(),
  closed_by         varchar(200),
  closed_at         timestamptz,
  is_deleted        boolean      NOT NULL DEFAULT false,
  deleted_by        varchar(200),
  deleted_at        timestamptz,

  -- org hierarchy: a lower level needs every level above it
  CONSTRAINT ck_org_cc_needs_hub      CHECK (cost_center IS NULL OR hub   IS NOT NULL),
  CONSTRAINT ck_org_hub_needs_tower   CHECK (hub         IS NULL OR tower IS NOT NULL),
  CONSTRAINT ck_line_needs_category   CHECK (line_item   IS NULL OR expense_category IS NOT NULL),
  -- variance
  CONSTRAINT ck_compare_differs       CHECK (compare_period IS NULL OR compare_period <> period),
  CONSTRAINT ck_varexp_is_variance    CHECK (thread_type <> 'variance_explanation' OR compare_period IS NOT NULL),
  CONSTRAINT ck_varexp_hub_or_above   CHECK (thread_type <> 'variance_explanation'
                                             OR (cost_center IS NULL AND line_item IS NULL)),
  -- type-specific
  CONSTRAINT ck_override_link         CHECK (thread_type <> 'override_reason' OR override_id IS NOT NULL),
  CONSTRAINT ck_status_for_questions  CHECK ((thread_type = 'question') = (status IS NOT NULL)),
  CONSTRAINT ck_closed_has_who_when   CHECK (status IS DISTINCT FROM 'closed' OR (closed_by IS NOT NULL AND closed_at IS NOT NULL)),
  CONSTRAINT ck_deleted_has_who_when  CHECK (NOT is_deleted OR (deleted_by IS NOT NULL AND deleted_at IS NOT NULL))
);

CREATE INDEX ix_ct_anchor   ON app.comment_thread (period, compare_period, hub, expense_category) WHERE NOT is_deleted;
CREATE INDEX ix_ct_org      ON app.comment_thread (period, department, tower) WHERE NOT is_deleted;
CREATE INDEX ix_ct_open     ON app.comment_thread (status) WHERE thread_type = 'question' AND NOT is_deleted;
CREATE INDEX ix_ct_override ON app.comment_thread (override_id) WHERE override_id IS NOT NULL;

-- Anchor and type cannot change after creation (re-anchoring = new thread)
CREATE OR REPLACE FUNCTION app.trg_thread_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.thread_type, NEW.period, NEW.compare_period, NEW.department, NEW.tower, NEW.hub,
      NEW.cost_center, NEW.expense_category, NEW.line_item)
     IS DISTINCT FROM
     (OLD.thread_type, OLD.period, OLD.compare_period, OLD.department, OLD.tower, OLD.hub,
      OLD.cost_center, OLD.expense_category, OLD.line_item) THEN
    RAISE EXCEPTION 'thread_type and anchor columns cannot be changed (thread %)', OLD.thread_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_comment_thread_immutable
BEFORE UPDATE ON app.comment_thread
FOR EACH ROW EXECUTE FUNCTION app.trg_thread_immutable();

-- ---------------------------------------------------------------------
-- 2. Entry (CHILD): WHAT was said. First entry = original text, later
--    entries = replies or further drivers. Amounts live here:
--      value_at_comment : the figure shown on screen when this entry was
--                         written (context if a later rebuild changes it)
--      explained_amount : variance driver amount (variance_explanation only);
--                         a thread can hold several drivers, they are summed
-- ---------------------------------------------------------------------
CREATE TABLE app.comment_entry (
  entry_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id         uuid NOT NULL REFERENCES app.comment_thread(thread_id),
  body              text NOT NULL CHECK (length(btrim(body)) > 0),
  value_at_comment  numeric(18,2),
  explained_amount  numeric(18,2),
  author            varchar(200) NOT NULL,
  author_role       varchar(20)  NOT NULL CHECK (author_role IN ('budget_owner','finance','other')),
  created_at        timestamptz  NOT NULL DEFAULT now(),
  edited_by         varchar(200),
  edited_at         timestamptz,
  is_deleted        boolean NOT NULL DEFAULT false,
  CONSTRAINT ck_edit_has_who_when CHECK ((edited_by IS NULL) = (edited_at IS NULL))
);
CREATE INDEX ix_ce_thread ON app.comment_entry (thread_id, created_at);

-- explained_amount only on variance explanations; finance reply marks a question answered
CREATE OR REPLACE FUNCTION app.trg_entry_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_type varchar(30);
BEGIN
  SELECT thread_type INTO v_type FROM app.comment_thread WHERE thread_id = NEW.thread_id;
  IF NEW.explained_amount IS NOT NULL AND v_type <> 'variance_explanation' THEN
    RAISE EXCEPTION 'explained_amount is only allowed on variance_explanation threads';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.author_role = 'finance' AND v_type = 'question' THEN
    UPDATE app.comment_thread SET status = 'answered'
     WHERE thread_id = NEW.thread_id AND status = 'open';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_comment_entry_rules
BEFORE INSERT OR UPDATE ON app.comment_entry
FOR EACH ROW EXECUTE FUNCTION app.trg_entry_rules();

-- ---------------------------------------------------------------------
-- 3. Display rule: every tab calls this per value (cell) it shows.
--    period / compare_period match EXACTLY (no roll-up across versions:
--    an 'OCT vs AOP' comment never shows on 'OCT vs JUL').
--    Org and expense levels: pass NULL for a level the row totals over;
--    returns comments at that level AND below (roll-up).
--    p_include_parents = true also returns comments made HIGHER on the same
--    path (e.g. a hub-level variance explanation on that hub's line rows).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.comments_for(
  p_period text, p_compare_period text DEFAULT NULL,
  p_department text DEFAULT NULL, p_tower text DEFAULT NULL, p_hub text DEFAULT NULL,
  p_cost_center text DEFAULT NULL, p_category text DEFAULT NULL, p_line_item text DEFAULT NULL,
  p_include_parents boolean DEFAULT false)
RETURNS SETOF app.comment_thread
LANGUAGE sql STABLE AS $$
  SELECT t.*
  FROM app.comment_thread t
  WHERE NOT t.is_deleted
    AND t.period = p_period
    AND t.compare_period IS NOT DISTINCT FROM p_compare_period
    AND (p_department IS NULL OR t.department       = p_department)
    AND (p_tower      IS NULL OR t.tower            = p_tower       OR (p_include_parents AND t.tower IS NULL))
    AND (p_hub        IS NULL OR t.hub              = p_hub         OR (p_include_parents AND t.hub IS NULL))
    AND (p_cost_center IS NULL OR t.cost_center     = p_cost_center OR (p_include_parents AND t.cost_center IS NULL))
    AND (p_category   IS NULL OR t.expense_category = p_category    OR (p_include_parents AND t.expense_category IS NULL))
    AND (p_line_item  IS NULL OR t.line_item        = p_line_item   OR (p_include_parents AND t.line_item IS NULL))
  ORDER BY t.created_at;
$$;

-- ---------------------------------------------------------------------
-- 4. Finance central "Comments" tab: all live threads, status, last message
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW app.v_comment_inbox AS
SELECT t.thread_id, t.thread_type, t.anchor_key, t.period, t.compare_period,
       t.department, t.tower, t.hub, t.cost_center, t.expense_category, t.line_item,
       t.status, t.source_tab, t.created_by, t.created_at,
       first_e.body                       AS first_text,
       last_e.body                        AS last_text,
       last_e.author                      AS last_by,
       last_e.author_role                 AS last_by_role,
       last_e.created_at                  AS last_at,
       coalesce(agg.entries, 0)           AS entries,
       agg.explained_amount,
       (now()::date - t.created_at::date) AS age_days
FROM app.comment_thread t
LEFT JOIN LATERAL (SELECT body FROM app.comment_entry e
                   WHERE e.thread_id = t.thread_id AND NOT e.is_deleted
                   ORDER BY e.created_at LIMIT 1) first_e ON true
LEFT JOIN LATERAL (SELECT body, author, author_role, created_at FROM app.comment_entry e
                   WHERE e.thread_id = t.thread_id AND NOT e.is_deleted
                   ORDER BY e.created_at DESC LIMIT 1) last_e ON true
LEFT JOIN LATERAL (SELECT count(*) AS entries, sum(e.explained_amount) AS explained_amount
                   FROM app.comment_entry e
                   WHERE e.thread_id = t.thread_id AND NOT e.is_deleted) agg ON true
WHERE NOT t.is_deleted;

-- ---------------------------------------------------------------------
-- 5. Variance coverage: explained amount per variance and org level
--    (sum of live driver entries on live variance_explanation threads)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW app.v_variance_explained AS
SELECT t.period, t.compare_period, t.department, t.tower, t.hub, t.expense_category,
       count(DISTINCT t.thread_id) AS threads,
       count(e.explained_amount)   AS drivers,
       sum(e.explained_amount)     AS explained_amount
FROM app.comment_thread t
JOIN app.comment_entry e ON e.thread_id = t.thread_id AND NOT e.is_deleted
WHERE t.thread_type = 'variance_explanation' AND NOT t.is_deleted
GROUP BY t.period, t.compare_period, t.department, t.tower, t.hub, t.expense_category;
-- Coverage % = explained_amount / variance from the rpt table for the same
-- period, compare_period and org level (join once that rpt view exists).
