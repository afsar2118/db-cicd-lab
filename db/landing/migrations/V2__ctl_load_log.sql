-- One row per source object per extract run.
-- status:
--   RUNNING            extract in progress (rows for this load_id may be incomplete)
--   SUCCESS            rows for this load_id are complete; rows_written = rows_read
--   SKIPPED_UNCHANGED  source content hash equal to the last SUCCESS load: nothing written
--   FAILED             error; the job deletes any rows it wrote for this load_id
-- Downstream layers read only load_ids with status SUCCESS.

CREATE TABLE ctl.load_log (
    load_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id         uuid        NOT NULL,           -- one extract job run covers several sources
    source_system  text        NOT NULL,           -- e.g. src_sf (local stand-in), snowflake
    source_object  text        NOT NULL,           -- e.g. fin_reporting.dp_title_actuals_rpt_vw
    target_table   text        NOT NULL,           -- e.g. raw.dp_title_actuals_rpt_vw
    status         text        NOT NULL,
    started_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz,
    rows_read      bigint,
    rows_written   bigint,
    content_hash   text,                           -- order-independent hash of the extracted rows
    error_message  text,
    CONSTRAINT ck_load_log_status CHECK (status IN ('RUNNING', 'SUCCESS', 'SKIPPED_UNCHANGED', 'FAILED')),
    CONSTRAINT ck_load_log_finished CHECK (status = 'RUNNING' OR finished_at IS NOT NULL),
    CONSTRAINT ck_load_log_success_counts CHECK (status <> 'SUCCESS' OR rows_written = rows_read)
);

CREATE INDEX ix_load_log_target_status ON ctl.load_log (target_table, status, load_id DESC);
CREATE INDEX ix_load_log_run ON ctl.load_log (run_id);
