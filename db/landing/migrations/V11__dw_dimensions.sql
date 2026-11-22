-- dw dimensions. Surrogate keys: identity (int; dim_snapshot bigint). Unknown member = -1.
-- Deviation: dim_fiscal_period UK (fiscal_year, fiscal_period) and dim_fiscal_quarter UK (fiscal_year, quarter_label) added - the model has no natural key on either.

CREATE TABLE dw.dim_snapshot (
    snapshot_key      bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity            text        NOT NULL,
    component_loads   bigint[],
    source            text        NOT NULL,
    loaded_period     text,
    extracted_at      timestamptz,
    locked_for_cycle  text,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text
);
COMMENT ON TABLE dw.dim_snapshot IS 'One row per snapshot of an entity; component_loads = ctl.load_log ids it was built from';

CREATE TABLE dw.dim_fiscal_quarter (
    fiscal_quarter_key  int       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_year         smallint  NOT NULL,
    quarter_label       text      NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    CONSTRAINT uk_dim_fiscal_quarter UNIQUE (fiscal_year, quarter_label)
);

CREATE TABLE dw.dim_fiscal_period (
    fiscal_period_key   int       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_year         smallint  NOT NULL,
    fiscal_period       smallint  NOT NULL,
    fiscal_quarter_key  int       NOT NULL REFERENCES dw.dim_fiscal_quarter (fiscal_quarter_key),
    month_label         text,
    start_date          date,
    end_date            date,
    weeks               smallint,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    CONSTRAINT uk_dim_fiscal_period UNIQUE (fiscal_year, fiscal_period)
);

CREATE TABLE dw.dim_version (
    version_key    int   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    version_label  text  NOT NULL CONSTRAINT uk_dim_version UNIQUE,
    version_code   text,
    category       text  NOT NULL,
    cycle_month    text,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text
);

CREATE TABLE dw.dim_account (
    account_key     int   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_code    text  NOT NULL CONSTRAINT uk_dim_account UNIQUE,
    account_name    text,
    sap_short_name  text,
    pax_label       text,
    pax_is_base     bool  NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text
);
COMMENT ON TABLE dw.dim_account IS 'Accounts and account-hierarchy nodes (plan facts are at node level)';

CREATE TABLE dw.dim_cost_center (
    cost_center_key     int   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cost_center_code    text  NOT NULL CONSTRAINT uk_dim_cost_center UNIQUE,
    cost_center_name    text,
    sap_short_name      text,
    company_code        text,
    business_area_code  text,
    functional_area     text,
    profit_center       text,
    department          text,
    country             text,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text
);

CREATE TABLE dw.dim_org (
    org_key              int   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_name             text  NOT NULL CONSTRAINT uk_dim_org UNIQUE,
    tower                text,
    leader_top_level     text,
    leader_intermediate  text,
    leader_poc           text,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text
);
COMMENT ON TABLE dw.dim_org IS 'Source: Excel (CC mapping). Empty until the Excel landing path exists';

CREATE TABLE dw.dim_region (
    region_key            int       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    region_code           text      NOT NULL CONSTRAINT uk_dim_region UNIQUE,
    region_name           text,
    regional_sheet_order  smallint,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text
);
COMMENT ON TABLE dw.dim_region IS 'Source: Excel. Empty until the Excel landing path exists';

-- ---------------------------------------------------------------- unknown members (-1)
INSERT INTO dw.dim_fiscal_quarter (fiscal_quarter_key, fiscal_year, quarter_label, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, 0, 'Unknown', (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
INSERT INTO dw.dim_fiscal_period (fiscal_period_key, fiscal_year, fiscal_period, fiscal_quarter_key, month_label, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, 0, 0, -1, 'Unknown', (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
INSERT INTO dw.dim_version (version_key, version_label, category, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, 'Unknown', 'Unknown', (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
INSERT INTO dw.dim_account (account_key, account_code, account_name, pax_is_base, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, '#UNKNOWN', 'Unknown account', false, (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
INSERT INTO dw.dim_cost_center (cost_center_key, cost_center_code, cost_center_name, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, '#UNKNOWN', 'Unknown cost center', (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
INSERT INTO dw.dim_org (org_key, org_name, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, 'Unknown', (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
INSERT INTO dw.dim_region (region_key, region_code, region_name, created_load_id, src_system)
  OVERRIDING SYSTEM VALUE VALUES (-1, '#UNKNOWN', 'Unknown region', (SELECT load_id FROM ctl.load_log WHERE source_system = 'dw_bootstrap'), 'DW');
-- dim_snapshot has no unknown member: every fact row belongs to a real snapshot.
