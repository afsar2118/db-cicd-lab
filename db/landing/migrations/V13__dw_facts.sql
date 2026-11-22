-- dw facts, all LIST-partitioned by snapshot_key (a snapshot is dropped with DROP partition, never DELETE).
-- Each fact has a DEFAULT partition; dw.create_snapshot_partitions(snapshot_key) adds per-snapshot partitions.
-- Postgres requires the partition column in every PK/UK, so surrogate-key PKs become (snapshot_key, key).
-- Deviations:
--   fact_gl_line_item: source = DP_COST_CENTER_ACTUALS_RPT_VW (CO line items, KSB1 equivalent).
--     UK = (snapshot_key, company_code, fiscal_period_key, document_number, document_posting_row, assignment_number)
--     replaces (company_code, spl_doc_number, spl_doc_item_no): Snowflake analysis 2026-11-22 showed
--     assignment_number separates rows sharing a CO document row. New columns: document_posting_row,
--     assignment_number ('' when blank), value_type (04 actual / 11 statistical). spl_doc_* kept as the
--     nullable FI document reference.
--   amounts: numeric(18,4) everywhere (model: fact_gl_actual (18,2), plan facts (18,0)).

CREATE TABLE dw.fact_gl_line_item (
    gl_line_item_key         bigint         GENERATED ALWAYS AS IDENTITY,
    snapshot_key             bigint         NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key          int            NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    account_key              int            NOT NULL REFERENCES dw.dim_account (account_key),
    fiscal_period_key        int            NOT NULL REFERENCES dw.dim_fiscal_period (fiscal_period_key),
    company_code             text           NOT NULL,
    business_area_code       text,
    document_number          text           NOT NULL,
    document_posting_row     text           NOT NULL,
    assignment_number        text           NOT NULL DEFAULT '',
    value_type               text           NOT NULL,
    spl_doc_number           text,
    spl_doc_item_no          text,
    posting_date             date           NOT NULL,
    document_date            date,
    supplier_number          text,
    vendor_name              text,
    offsetting_account_name  text,
    aux_assignment_type      text,
    aux_assignment_object    text,
    line_text                text,
    header_text              text,
    document_type            text,
    ref_document_number      text,
    purchasing_document      text,
    trading_partner_company  text,
    trading_partner_ba       text,
    partner_object           text,
    dest_geo                 text,
    user_id                  text,
    amount_usd               numeric(18,4)  NOT NULL,
    transaction_currency     char(3)        NOT NULL,
    amount_transaction       numeric(18,4),
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, gl_line_item_key),
    CONSTRAINT uk_fact_gl_line_item UNIQUE (snapshot_key, company_code, fiscal_period_key, document_number, document_posting_row, assignment_number)
) PARTITION BY LIST (snapshot_key);
CREATE TABLE dw.fact_gl_line_item_default PARTITION OF dw.fact_gl_line_item DEFAULT;
COMMENT ON TABLE dw.fact_gl_line_item IS 'CO line items (DP_COST_CENTER_ACTUALS_RPT_VW), one set per snapshot';

CREATE TABLE dw.fact_gl_actual (
    snapshot_key        bigint         NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key     int            NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    account_key         int            NOT NULL REFERENCES dw.dim_account (account_key),
    fiscal_period_key   int            NOT NULL REFERENCES dw.dim_fiscal_period (fiscal_period_key),
    company_code        text           NOT NULL,
    business_area_code  text,
    amount_usd          numeric(18,4)  NOT NULL,
    amount_local        numeric(18,4),
    local_currency      char(3),
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, cost_center_key, account_key, fiscal_period_key)
) PARTITION BY LIST (snapshot_key);
CREATE TABLE dw.fact_gl_actual_default PARTITION OF dw.fact_gl_actual DEFAULT;
COMMENT ON TABLE dw.fact_gl_actual IS 'Derived: SUM of fact_gl_line_item';

CREATE TABLE dw.fact_plan_amount (
    snapshot_key        bigint         NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key     int            NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    account_key         int            NOT NULL REFERENCES dw.dim_account (account_key),
    fiscal_quarter_key  int            NOT NULL REFERENCES dw.dim_fiscal_quarter (fiscal_quarter_key),
    version_key         int            NOT NULL REFERENCES dw.dim_version (version_key),
    amount_usd          numeric(18,4)  NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, cost_center_key, account_key, fiscal_quarter_key, version_key)
) PARTITION BY LIST (snapshot_key);
CREATE TABLE dw.fact_plan_amount_default PARTITION OF dw.fact_plan_amount DEFAULT;

CREATE TABLE dw.fact_plan_amount_fy (
    snapshot_key     bigint         NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key  int            NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    account_key      int            NOT NULL REFERENCES dw.dim_account (account_key),
    fiscal_year      smallint       NOT NULL,
    version_key      int            NOT NULL REFERENCES dw.dim_version (version_key),
    amount_usd       numeric(18,4)  NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, cost_center_key, account_key, fiscal_year, version_key)
) PARTITION BY LIST (snapshot_key);
CREATE TABLE dw.fact_plan_amount_fy_default PARTITION OF dw.fact_plan_amount_fy DEFAULT;

CREATE TABLE dw.fact_intl_plan_amount (
    intl_plan_amount_key  bigint         GENERATED ALWAYS AS IDENTITY,
    snapshot_key          bigint         NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key       int            NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    account_key           int            NOT NULL REFERENCES dw.dim_account (account_key),
    fiscal_quarter_key    int            NOT NULL REFERENCES dw.dim_fiscal_quarter (fiscal_quarter_key),
    company_code          text,
    business_area_code    text,
    account_group         text,
    source_file           text           NOT NULL,
    company_label         text,
    dest_geo              text,
    function              text,
    function_rollup       text,
    territory             text,
    quarter_as_delivered  text,
    amount_usd            numeric(18,4),
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, intl_plan_amount_key)
) PARTITION BY LIST (snapshot_key);
CREATE TABLE dw.fact_intl_plan_amount_default PARTITION OF dw.fact_intl_plan_amount DEFAULT;
COMMENT ON TABLE dw.fact_intl_plan_amount IS 'Source: Excel (Intl consolidated). Empty until the Excel landing path exists';

CREATE TABLE dw.fact_headcount_position (
    headcount_position_key  bigint         GENERATED ALWAYS AS IDENTITY,
    snapshot_key            bigint         NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key         int            NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    org_key                 int            NOT NULL REFERENCES dw.dim_org (org_key),
    region_key              int            NOT NULL REFERENCES dw.dim_region (region_key),
    org_as_delivered        text,
    status                  text,
    role_type               text,
    approved_position_type  text,
    employee_flag           bool,
    region                  text,
    tower                   text,
    position_number         text,
    title                   text,
    job_level               text,
    planner                 text,
    salary_usd              numeric(18,4),
    prior_salary_usd        numeric(18,4),
    benefit_rate            numeric(9,6),
    merit_rate              numeric(9,6),
    sb_q1_usd               numeric(18,4)  NOT NULL,
    sb_q2_usd               numeric(18,4)  NOT NULL,
    sb_q3_usd               numeric(18,4)  NOT NULL,
    sb_q4_usd               numeric(18,4)  NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, headcount_position_key)
) PARTITION BY LIST (snapshot_key);
CREATE TABLE dw.fact_headcount_position_default PARTITION OF dw.fact_headcount_position DEFAULT;
COMMENT ON TABLE dw.fact_headcount_position IS 'Source: Excel (Headcount). Empty until the Excel landing path exists';

-- FK lookup indexes (created on the parent, inherited by every partition)
CREATE INDEX ix_fact_gl_line_item_cost_center_key ON dw.fact_gl_line_item (cost_center_key);
CREATE INDEX ix_fact_gl_line_item_account_key ON dw.fact_gl_line_item (account_key);
CREATE INDEX ix_fact_gl_line_item_fiscal_period_key ON dw.fact_gl_line_item (fiscal_period_key);
CREATE INDEX ix_fact_gl_actual_account_key ON dw.fact_gl_actual (account_key);
CREATE INDEX ix_fact_gl_actual_fiscal_period_key ON dw.fact_gl_actual (fiscal_period_key);
CREATE INDEX ix_fact_plan_amount_account_key ON dw.fact_plan_amount (account_key);
CREATE INDEX ix_fact_plan_amount_version_key ON dw.fact_plan_amount (version_key);
CREATE INDEX ix_fact_plan_amount_fy_account_key ON dw.fact_plan_amount_fy (account_key);
CREATE INDEX ix_fact_plan_amount_fy_version_key ON dw.fact_plan_amount_fy (version_key);
CREATE INDEX ix_fact_intl_plan_amount_cost_center_key ON dw.fact_intl_plan_amount (cost_center_key);
CREATE INDEX ix_fact_intl_plan_amount_account_key ON dw.fact_intl_plan_amount (account_key);
CREATE INDEX ix_fact_headcount_position_cost_center_key ON dw.fact_headcount_position (cost_center_key);
CREATE INDEX ix_fact_headcount_position_org_key ON dw.fact_headcount_position (org_key);
