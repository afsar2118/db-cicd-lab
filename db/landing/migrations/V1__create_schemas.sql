-- Landing database (landing_<env>): raw copies of the source views + extract control.
--   raw : one table per source view, rows stored as received, tagged with load_id
--   ctl : extract control (load log)

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS ctl;
