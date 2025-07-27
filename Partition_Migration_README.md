# Partition Migration – Detailed Implementation Plan

## a. Create Partitioned Table

**Goal:** Prepare the parent table for partitioning.

```sql
CREATE SCHEMA IF NOT EXISTS vit_trans;

CREATE TABLE vit_trans.wellness_attributes_part (
    entity_no BIGINT NOT NULL,
    attribute_id BIGINT NOT NULL,
    eff_from TIMESTAMP NOT NULL,
    eff_to TIMESTAMP NULL,
    attribute_value VARCHAR(200) NOT NULL,
    origin_type BIGINT NOT NULL,
    origin_id BIGINT NOT NULL,
    os_user_last_modified VARCHAR(15),
    sess_user_last_modified VARCHAR(15),
    date_time_last_modified TIMESTAMP,
    archive_status SMALLINT
) PARTITION BY RANGE (eff_from);
```

## b. Load Initial Data (2023-01-01 → Now)

**Goal:** Move historical data from the old table to the new partitioned table.

```sql
INSERT INTO vit_trans.wellness_attributes_part
SELECT *
FROM vit_trans.wellness_attributes
WHERE eff_from >= '2023-01-01';
```

## c. Create Quarterly Partitions (DO $$)

**Goal:** Create partitions for 2023, 2024 by quarter, and one partition for 2025 onwards.

```sql
DO $$
DECLARE
    y INT;
    q INT;
    start_date DATE;
    end_date DATE;
    tbl_name TEXT;
    constraint_name TEXT;
BEGIN
    FOR y IN 2023..2024 LOOP
        FOR q IN 1..4 LOOP
            start_date := make_date(y, (q - 1) * 3 + 1, 1);
            end_date := start_date + interval '3 months';

            tbl_name := format('vit_trans.wellness_attributes_%s_q%s', y, q);
            constraint_name := format('wellness_attributes_%s_q%s_pk', y, q);

            EXECUTE format($sql$
                CREATE TABLE IF NOT EXISTS %I
                PARTITION OF vit_trans.wellness_attributes_part
                FOR VALUES FROM (%L) TO (%L);
            $sql$, tbl_name, start_date, end_date);

            BEGIN
                EXECUTE format($sql$
                    ALTER TABLE %I
                    ADD CONSTRAINT %I PRIMARY KEY (entity_no, attribute_id, eff_from);
                $sql$, tbl_name, constraint_name);
            EXCEPTION
                WHEN duplicate_object THEN
                    RAISE NOTICE 'Primary key already exists for %', tbl_name;
            END;
        END LOOP;
    END LOOP;

    tbl_name := 'vit_trans.wellness_attributes_2025_plus';
    constraint_name := 'wellness_attributes_2025_plus_pk';

    EXECUTE format($sql$
        CREATE TABLE IF NOT EXISTS %I
        PARTITION OF vit_trans.wellness_attributes_part
        FOR VALUES FROM ('2025-01-01') TO (MAXVALUE);
    $sql$, tbl_name);

    BEGIN
        EXECUTE format($sql$
            ALTER TABLE %I
            ADD CONSTRAINT %I PRIMARY KEY (entity_no, attribute_id, eff_from);
        $sql$, tbl_name, constraint_name);
    EXCEPTION
        WHEN duplicate_object THEN
            RAISE NOTICE 'Primary key already exists for %', tbl_name;
    END;
END$$;
```

## d. Create Trigger for Sync-Up

**Goal:** Keep old and new tables synchronized during migration.

```sql
CREATE OR REPLACE FUNCTION vit_trans.sync_to_partition()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO vit_trans.wellness_attributes_part VALUES (NEW.*);
    ELSIF (TG_OP = 'UPDATE') THEN
        UPDATE vit_trans.wellness_attributes_part
        SET attribute_value = NEW.attribute_value,
            eff_to = NEW.eff_to,
            date_time_last_modified = NEW.date_time_last_modified
        WHERE entity_no = NEW.entity_no
          AND attribute_id = NEW.attribute_id
          AND eff_from = NEW.eff_from;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM vit_trans.wellness_attributes_part
        WHERE entity_no = OLD.entity_no
          AND attribute_id = OLD.attribute_id
          AND eff_from = OLD.eff_from;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_partition_trigger
AFTER INSERT OR UPDATE OR DELETE ON vit_trans.wellness_attributes
FOR EACH ROW EXECUTE FUNCTION vit_trans.sync_to_partition();
```

## e. Monitoring – Data Quality Checks

**Goal:** Verify data consistency between old and partitioned tables.

```sql
SELECT COUNT(*) FROM vit_trans.wellness_attributes;
SELECT COUNT(*) FROM vit_trans.wellness_attributes_part;

SELECT tableoid::regclass AS partition, COUNT(*)
FROM vit_trans.wellness_attributes_part
GROUP BY tableoid
ORDER BY partition;
```

## f. Cut-over (Swap Tables)

**Goal:** Rename the new partitioned table to replace the old table.

```sql
LOCK TABLE vit_trans.wellness_attributes IN ACCESS EXCLUSIVE MODE;

ALTER TABLE vit_trans.wellness_attributes RENAME TO wellness_attributes_backup;
ALTER TABLE vit_trans.wellness_attributes_part RENAME TO wellness_attributes;

GRANT SELECT, INSERT, UPDATE, DELETE ON vit_trans.wellness_attributes TO your_app_user;
```

## g. Re-enable Trigger (if needed)

**Goal:** If synchronization is needed with other systems, re-create the trigger on the new table.
