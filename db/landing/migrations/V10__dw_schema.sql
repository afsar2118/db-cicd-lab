-- Dimensional model (dw) lives in landing_<env> next to raw, so load procedures can read raw directly.
-- A bootstrap load_log row gives the built-in rows (unknown members) a created_load_id.
--
-- Deviations from 10_DFi_Data_Model_and_Bus_Matrix_V3 (decided 2026-11-22, review pending):
--   * audit created_load_id / updated_load_id reference ctl.load_log, not dim_snapshot
--   * all timestamps are timestamptz (model: timestamp in the audit block)
--   * every dimension has a -1 'Unknown' member; facts are partitioned by snapshot_key
--   Further deviations are listed at the top of each migration.

CREATE SCHEMA IF NOT EXISTS dw;

INSERT INTO ctl.load_log (run_id, source_system, source_object, target_table, status, finished_at, rows_read, rows_written)
VALUES ('00000000-0000-0000-0000-000000000000', 'dw_bootstrap', 'flyway', 'dw.*', 'SUCCESS', now(), 0, 0);
