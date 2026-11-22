-- dw hierarchies, bridge and mapping (snapshot-versioned; snapshot_key in every key).
-- Deviations: hier_cost_center_path cc_l4..cc_l7 allow NULL (ragged paths; model: NOT NULL);
--             map_cost_center_org UK (snapshot_key, cost_center_key) added (one org per cost center per snapshot).

CREATE TABLE dw.hier_account_path (
    snapshot_key        bigint    NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    account_key         int       NOT NULL REFERENCES dw.dim_account (account_key),
    parent_account_key  int       REFERENCES dw.dim_account (account_key),
    node_level          smallint  NOT NULL,
    is_leaf             bool      NOT NULL,
    level_0_code  text  NOT NULL,
    level_0_name  text  NOT NULL,
    level_1_code  text,
    level_1_name  text,
    level_2_code  text,
    level_2_name  text,
    level_3_code  text,
    level_3_name  text,
    level_4_code  text,
    level_4_name  text,
    level_5_code  text,
    level_5_name  text,
    level_6_code  text,
    level_6_name  text,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, account_key)
);

CREATE TABLE dw.bridge_account_hierarchy (
    snapshot_key      bigint    NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    node_account_key  int       NOT NULL REFERENCES dw.dim_account (account_key),
    leaf_account_key  int       NOT NULL REFERENCES dw.dim_account (account_key),
    depth             smallint  NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, node_account_key, leaf_account_key)
);
COMMENT ON TABLE dw.bridge_account_hierarchy IS 'Derived from hier_account_path: every node x every leaf below it';

CREATE TABLE dw.hier_cost_center_path (
    snapshot_key      bigint  NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_key   int     NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    cost_center_name  text    NOT NULL,
    cc_l4_code  text,
    cc_l4_name  text,
    cc_l5_code  text,
    cc_l5_name  text,
    cc_l6_code  text,
    cc_l6_name  text,
    cc_l7_code  text,
    cc_l7_name  text,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    PRIMARY KEY (snapshot_key, cost_center_key)
);

CREATE TABLE dw.map_cost_center_org (
    map_cost_center_org_key  bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    snapshot_key             bigint  NOT NULL REFERENCES dw.dim_snapshot (snapshot_key),
    cost_center_code         text    NOT NULL,
    cost_center_key          int     NOT NULL REFERENCES dw.dim_cost_center (cost_center_key),
    org_key                  int     NOT NULL REFERENCES dw.dim_org (org_key),
    region_key               int     NOT NULL REFERENCES dw.dim_region (region_key),
    tower                    text    NOT NULL,
    created_load_id   bigint      NOT NULL REFERENCES ctl.load_log (load_id),
    updated_load_id   bigint      REFERENCES ctl.load_log (load_id),
    src_system        text        NOT NULL,
    src_delete_flg    char(1)     NOT NULL DEFAULT 'N' CHECK (src_delete_flg IN ('Y', 'N')),
    dw_create_dtm     timestamptz NOT NULL DEFAULT now(),
    dw_created_by     text        NOT NULL DEFAULT current_user,
    dw_update_dtm     timestamptz,
    dw_updated_by     text,
    CONSTRAINT uk_map_cost_center_org UNIQUE (snapshot_key, cost_center_key)
);
COMMENT ON TABLE dw.map_cost_center_org IS 'Source: Excel (CC mapping). Empty until the Excel landing path exists';

