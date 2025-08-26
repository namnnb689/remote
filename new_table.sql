-- 1. Create schema
CREATE SCHEMA IF NOT EXISTS ddo;

-- 2. Create root partitioned table (hash by tenant_id)
CREATE TABLE IF NOT EXISTS ddo.entity_device_pairing (
    entity_device_link_id VARCHAR(100) PRIMARY KEY, -- unique identifier

    tenant_id             INTEGER      NOT NULL,
    entity_no             INTEGER      NOT NULL,
    device_aggregator_id  VARCHAR(100) NOT NULL,
    device_name           VARCHAR(50)  NOT NULL,

    pairing_status        VARCHAR(50)  NOT NULL, -- Active / Inactive / Rejected
    pairing_status_reason VARCHAR(50), -- nullable

    effective_from_date_time TIMESTAMP NOT NULL,
    effective_to_date_time   TIMESTAMP NOT NULL,

    insert_date_time TIMESTAMP NOT NULL DEFAULT now(),
    insert_by        VARCHAR(50) NOT NULL,
    update_date_time TIMESTAMP NOT NULL DEFAULT now(),
    update_by        VARCHAR(50) NOT NULL,

    -- Prevent duplicate pairings for the same entity/device
    CONSTRAINT uq_entity_device UNIQUE (entity_no, device_aggregator_id)
)
PARTITION BY HASH (tenant_id);

-- 3. Create 8 hash partitions (tenant_id modulus = 8)
DO $$
DECLARE
    i INT;
    tenant_partition TEXT;
BEGIN
    FOR i IN 0..7 LOOP
        tenant_partition := format('entity_device_pairing_tenant_%s', i);

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS ddo.%I
             PARTITION OF ddo.entity_device_pairing
             FOR VALUES WITH (MODULUS 8, REMAINDER %s)
             PARTITION BY RANGE (effective_from_date_time);',
            tenant_partition, i
        );
    END LOOP;
END$$;

-- 4. Create yearly range partitions (2020 → 2028) inside each tenant partition
DO $$
DECLARE
    i INT;
    yr INT;
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
    parent_name TEXT;
BEGIN
    FOR i IN 0..7 LOOP
        parent_name := format('entity_device_pairing_tenant_%s', i);

        FOR yr IN 2020..2028 LOOP
            start_date := make_date(yr, 1, 1);
            end_date   := make_date(yr + 1, 1, 1);
            partition_name := format('entity_device_pairing_t%s_%s', i, yr);

            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS ddo.%I
                 PARTITION OF ddo.%I
                 FOR VALUES FROM (%L) TO (%L);',
                partition_name, parent_name, start_date, end_date
            );

            -- 5. Create indexes on each final partition
            EXECUTE format(
                'CREATE INDEX IF NOT EXISTS idx_%I_tenant_entity
                 ON ddo.%I (tenant_id, entity_no);',
                partition_name, partition_name
            );

            EXECUTE format(
                'CREATE INDEX IF NOT EXISTS idx_%I_tenant_device
                 ON ddo.%I (tenant_id, device_aggregator_id);',
                partition_name, partition_name
            );

            EXECUTE format(
                'CREATE INDEX IF NOT EXISTS idx_%I_tenant_entity_device
                 ON ddo.%I (tenant_id, entity_no, device_aggregator_id);',
                partition_name, partition_name
            );
        END LOOP;
    END LOOP;
END$$;
