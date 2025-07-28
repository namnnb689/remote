# Multi-Level Partitioning for `wellness_attributes_partition`

This document describes the implementation plan for creating a **two-level partitioned table** in PostgreSQL:
- **Level 1:** Hash partition by `entity_no`
- **Level 2:** Range partition by `eff_from` (quarters for 2023–2024 and one open-ended partition for 2025+)

---

## 1. Overview

The purpose of this partitioning strategy is to optimize queries that filter by `entity_no` and `eff_from`.
Hash partitioning distributes data evenly across partitions, and range sub-partitioning ensures efficient pruning
for time-based queries.

---

## 2. Implementation Steps

### Step 1: Create the Parent Table

```sql
CREATE SCHEMA IF NOT EXISTS vit_trans;

CREATE TABLE vit_trans.wellness_attributes_partition (
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
    archive_status SMALLINT,
    CONSTRAINT wellness_attributes_partition_pk PRIMARY KEY (entity_no, attribute_id, eff_from)
) PARTITION BY HASH (entity_no);
```

---

### Step 2: Create Hash Partitions (Level 1)

We will use 4 hash buckets for balanced distribution.

```sql
DO $$
DECLARE
    i INT;
    hash_table TEXT;
BEGIN
    FOR i IN 0..3 LOOP
        hash_table := format('vit_trans.wellness_attributes_partition_hash_%s', i);

        EXECUTE format($sql$
            CREATE TABLE IF NOT EXISTS %I
            PARTITION OF vit_trans.wellness_attributes_partition
            FOR VALUES WITH (MODULUS 4, REMAINDER %s)
            PARTITION BY RANGE (eff_from);
        $sql$, hash_table, i);
    END LOOP;
END$$;
```

---

### Step 3: Create Range Sub-Partitions (Level 2)

- Quarters for 2023 and 2024
- Single partition for 2025 and onward

```sql
DO $$
DECLARE
    i INT;
    y INT;
    q INT;
    start_date DATE;
    end_date DATE;
    range_table TEXT;
BEGIN
    FOR i IN 0..3 LOOP
        FOR y IN 2023..2024 LOOP
            FOR q IN 1..4 LOOP
                start_date := make_date(y, (q-1)*3 + 1, 1);
                end_date := start_date + interval '3 months';

                range_table := format('vit_trans.wellness_attributes_partition_hash_%s_%s_q%s', i, y, q);

                EXECUTE format($sql$
                    CREATE TABLE IF NOT EXISTS %I
                    PARTITION OF vit_trans.wellness_attributes_partition_hash_%s
                    FOR VALUES FROM (%L) TO (%L);
                $sql$, range_table, i, start_date, end_date);
            END LOOP;
        END LOOP;

        range_table := format('vit_trans.wellness_attributes_partition_hash_%s_2025_plus', i);
        EXECUTE format($sql$
            CREATE TABLE IF NOT EXISTS %I
            PARTITION OF vit_trans.wellness_attributes_partition_hash_%s
            FOR VALUES FROM ('2025-01-01') TO (MAXVALUE);
        $sql$, range_table, i);
    END LOOP;
END$$;
```

---

### Step 4: Load Data

```sql
INSERT INTO vit_trans.wellness_attributes_partition
SELECT *
FROM vit_trans.wellness_attributes
WHERE eff_from >= '2023-01-01';
```

---

### Step 5: Create Trigger to Sync During Migration

```sql
CREATE OR REPLACE FUNCTION vit_trans.sync_to_partition()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO vit_trans.wellness_attributes_partition VALUES (NEW.*);
    ELSIF (TG_OP = 'UPDATE') THEN
        UPDATE vit_trans.wellness_attributes_partition
        SET attribute_value = NEW.attribute_value,
            eff_to = NEW.eff_to,
            date_time_last_modified = NEW.date_time_last_modified
        WHERE entity_no = NEW.entity_no
          AND attribute_id = NEW.attribute_id
          AND eff_from = NEW.eff_from;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM vit_trans.wellness_attributes_partition
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

---

### Step 6: Monitoring and Validation

```sql
SELECT tableoid::regclass AS partition, COUNT(*)
FROM vit_trans.wellness_attributes_partition
GROUP BY tableoid
ORDER BY partition;
```

---

### Step 7: Cut-Over

```sql
LOCK TABLE vit_trans.wellness_attributes IN ACCESS EXCLUSIVE MODE;

ALTER TABLE vit_trans.wellness_attributes RENAME TO wellness_attributes_backup;
ALTER TABLE vit_trans.wellness_attributes_partition RENAME TO wellness_attributes;

GRANT SELECT, INSERT, UPDATE, DELETE ON vit_trans.wellness_attributes TO your_app_user;

VACUUM ANALYZE vit_trans.wellness_attributes;
```

---

## 3. Notes

- Adjust number of hash partitions (`MODULUS`) based on data size and query pattern.
- Future partitions (beyond 2025) can be added easily by extending the DO block logic.
- Ensure application downtime or use sync triggers before cut-over.
