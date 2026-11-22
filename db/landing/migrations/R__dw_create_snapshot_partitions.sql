-- Creates one partition per fact for a snapshot (idempotent). Call before loading the snapshot.
-- Partition names: dw.<fact>_s<snapshot_key>. Dropping a snapshot = DROP TABLE of its partitions.
CREATE OR REPLACE FUNCTION dw.create_snapshot_partitions(p_snapshot_key bigint)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  f       text;
  created int := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dw.dim_snapshot WHERE snapshot_key = p_snapshot_key) THEN
    RAISE EXCEPTION 'snapshot % not in dw.dim_snapshot', p_snapshot_key;
  END IF;
  FOREACH f IN ARRAY ARRAY['fact_gl_line_item', 'fact_gl_actual', 'fact_plan_amount', 'fact_plan_amount_fy', 'fact_intl_plan_amount', 'fact_headcount_position'] LOOP
    IF to_regclass(format('dw.%s_s%s', f, p_snapshot_key)) IS NULL THEN
      EXECUTE format('CREATE TABLE dw.%I PARTITION OF dw.%I FOR VALUES IN (%s)', f || '_s' || p_snapshot_key, f, p_snapshot_key);
      created := created + 1;
    END IF;
  END LOOP;
  RETURN created;
END $$;
