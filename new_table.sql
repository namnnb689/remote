-- =========================
-- Setup
-- =========================
CREATE SCHEMA IF NOT EXISTS ddo;
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- for gen_random_uuid()

-- Drop if you want a clean re-create (optional)
-- DROP TABLE IF EXISTS ddo.entity_device_pairing CASCADE;

-- =========================
-- Parent (hash-partitioned) table
-- =========================
CREATE TABLE IF NOT EXISTS ddo.entity_device_pairing (
    -- Business/partitioning columns
    tenant_id                INTEGER      NOT NULL,
    effective_from_date_time TIMESTAMP    NOT NULL,
    entity_no                INTEGER      NOT NULL,
    device_aggregator_id     VARCHAR(100) NOT NULL,

    -- Additional columns from the spec
    entity_device_link_id    UUID         NOT NULL DEFAULT gen_random_uuid(),
    device_name              VARCHAR(50)  NOT NULL,
    pairing_status           VARCHAR(50)  NOT NULL,      -- Active | Inactive | Rejected
    pairing_status_reason    VARCHAR(50),                -- nullable
    effective_to_date_time   TIMESTAMP    NOT NULL,

    insert_date_time         TIMESTAMP    NOT NULL DEFAULT now(),
    insert_by                VARCHAR(50)  NOT NULL,
    update_date_time         TIMESTAMP    NOT NULL DEFAULT now(),
    update_by                VARCHAR(50)  NOT NULL,

    -- Constraints
    CONSTRAINT pk_entity_device_pairing
        PRIMARY KEY (tenant_id, effective_from_date_time, entity_no, device_aggregator_id),

    -- Keep a stable unique “row id” that also includes partition keys
    CONSTRAINT uq_entity_device_link
        UNIQUE (tenant_id, effective_from_date_time, entity_device_link_id),

    -- Basic value check for status
    CONSTRAINT ck_pairing_status
        CHECK (pairing_status IN ('Active','Inactive','Rejected'))
)
PARTITION BY HASH (tenant_id);

-- =========================
-- Level 1: 8 hash partitions (MODULUS = 8)
-- each of these will be sub-partitioned by yearly RANGE
-- =========================
DO $$
DECLARE
    i INT;
    p TEXT;
BEGIN
    FOR i IN 0..7 LOOP
        p := format('entity_device_pairing_tenant_%s', i);
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS ddo.%I
               PARTITION OF ddo.entity_device_pairing
               FOR VALUES WITH (MODULUS 8, REMAINDER %s)
               PARTITION BY RANGE (effective_from_date_time);',
            p, i
        );
    END LOOP;
END$$;

-- =========================
-- Level 2: Yearly RANGE partitions (2020 → 2028) under each hash partition
-- =========================
DO $$
DECLARE
    i  INT;
    yr INT;
    start_ts TIMESTAMP;
    end_ts   TIMESTAMP;
    parent_name TEXT;
    leaf_name   TEXT;
BEGIN
    FOR i IN 0..7 LOOP
        parent_name := format('entity_device_pairing_tenant_%s', i);

        FOR yr IN 2020..2028 LOOP
            start_ts := make_timestamp(yr, 1, 1, 0, 0, 0);
            end_ts   := make_timestamp(yr+1, 1, 1, 0, 0, 0);
            leaf_name := format('entity_device_pairing_t%s_%s', i, yr);

            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS ddo.%I
                   PARTITION OF ddo.%I
                   FOR VALUES FROM (%L) TO (%L);',
                leaf_name, parent_name, start_ts, end_ts
            );
        END LOOP;
    END LOOP;
END$$;

-- =========================
-- Indexes required ON EVERY LEAF PARTITION
-- (tenant_id, entity_no)
-- (tenant_id, device_aggregator_id)
-- (tenant_id, entity_no, device_aggregator_id)
-- =========================
DO $$
DECLARE
    leaf REGCLASS;
BEGIN
    -- find only leaf partitions (tables that are children and have no further children)
    FOR leaf IN
        SELECT c.oid::regclass
        FROM pg_class c
        JOIN pg_inherits i ON c.oid = i.inhrelid
        WHERE i.inhparent IN (
            -- second-level parents = hash partitions
            SELECT inhrelid
            FROM pg_inherits
            WHERE inhparent = 'ddo.entity_device_pairing'::regclass
        )
        AND NOT EXISTS (
            SELECT 1 FROM pg_inherits i2 WHERE i2.inhparent = c.oid
        )
    LOOP
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %s (tenant_id, entity_no);',
                       'idx_' || replace(leaf::text,'.','_') || '_tenant_entity', leaf);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %s (tenant_id, device_aggregator_id);',
                       'idx_' || replace(leaf::text,'.','_') || '_tenant_device', leaf);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %s (tenant_id, entity_no, device_aggregator_id);',
                       'idx_' || replace(leaf::text,'.','_') || '_tenant_entity_device', leaf);
    END LOOP;
END$$;

-- =========================
-- (Optional) Helpful test
-- =========================
-- INSERT INTO ddo.entity_device_pairing (
--     tenant_id, effective_from_date_time, entity_no, device_aggregator_id,
--     device_name, pairing_status, pairing_status_reason, effective_to_date_time,
--     insert_by, update_by
-- ) VALUES (
--     5, '2025-06-01 10:00:00', 12345, 'UUID-ABC',
--     'Apple Health', 'Active', NULL, '9999-12-31 23:59:59',
--     'system', 'system'
-- );
-- SELECT tableoid::regclass AS partition, *
-- FROM ddo.entity_device_pairing
-- WHERE tenant_id = 5 AND entity_no = 12345;





INSERT INTO entity_device_pairing (
    tenant_id,
    entity_no,
    device_aggregator_id,
    effective_from_date_time
)
SELECT
    (random() * 7)::int + 1 AS tenant_id,               -- tenant_id between 1–8
    (random() * 10000)::int AS entity_no,               -- random entity_no
    (random() * 5000)::int AS device_aggregator_id,     -- random device_aggregator_id
    timestamp '2020-01-01' 
        + (random() * (EXTRACT(EPOCH FROM timestamp '2028-12-31' - timestamp '2020-01-01'))) * interval '1 second'
        AS effective_from_date_time                     -- random datetime between 2020–2028
FROM generate_series(1, 100);                           -- exactly 100 rows

