--Step 1: Create the new partitioned parent table 
CREATE TABLE
    vit_trans.wellness_attributes_partition (
        entity_no int8 NOT NULL,
        attribute_id int8 NOT NULL,
        eff_from timestamp NOT NULL,
        eff_to timestamp NULL,
        attribute_value varchar (200) NOT NULL,
        origin_type int8 NOT NULL,
        origin_id int8 NOT NULL,
        os_user_last_modified varchar (15) NULL,
        sess_user_last_modified varchar (15) NULL,
        date_time_last_modified timestamp NULL,
        archive_status int2 NULL,
        PRIMARY KEY (entity_no, attribute_id, eff_from)
    )
PARTITION BY
    RANGE (eff_from)
WITH
    (
        autovacuum_vacuum_cost_limit = 2000,
        autovacuum_vacuum_cost_delay = 0,
        autovacuum_vacuum_threshold = 10000,
        autovacuum_analyze_threshold = 10000,
        autovacuum_vacuum_scale_factor = 0.005,
        autovacuum_analyze_scale_factor = 0.005
    );


--Step 2: Create Partitions by Quarter (Dynamically)
-- Function hỗ trợ tạo bảng con (cho copy-paste nhanh)
-- Function hỗ trợ tạo bảng con (cho copy-paste nhanh)
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
                PARTITION OF vit_trans.wellness_attributes_partition
                FOR VALUES FROM (%L) TO (%L);
            $sql$, tbl_name, start_date, end_date);

            EXECUTE format($sql$
                ALTER TABLE %I
                ADD CONSTRAINT %I PRIMARY KEY (entity_no, attribute_id, eff_from);
            $sql$, tbl_name, constraint_name);
        END LOOP;
    END LOOP;
END$$;

CREATE TABLE IF NOT EXISTS vit_trans.wellness_attributes_2025_onward
PARTITION OF vit_trans.wellness_attributes_partition
FOR VALUES FROM ('2025-01-01') TO (MAXVALUE);

ALTER TABLE vit_trans.wellness_attributes_2025_onward
ADD CONSTRAINT wellness_attributes_2025_onward_pk PRIMARY KEY (entity_no, attribute_id, eff_from);


--Step 4: Copy data from old table to partitioned table
INSERT INTO vit_trans.wellness_attributes_partition (
    entity_no, attribute_id, eff_from, eff_to, attribute_value,
    origin_type, origin_id, os_user_last_modified, sess_user_last_modified,
    date_time_last_modified, archive_status
)
SELECT 
    entity_no, attribute_id, eff_from, eff_to, attribute_value,
    origin_type, origin_id, os_user_last_modified, sess_user_last_modified,
    date_time_last_modified, archive_status
FROM vit_trans.wellness_attributes
WHERE eff_from >= '2023-01-01';



--Step 5: Validate data integrity
-- Total rows in old table (from 2023)
SELECT COUNT(*) FROM vit_trans.wellness_attributes
WHERE eff_from >= '2023-01-01';

-- Total rows in partitioned table
SELECT COUNT(*) FROM vit_trans.wellness_attributes_partition;

-- Rows per partition
SELECT tableoid::regclass AS partition, COUNT(*)
FROM vit_trans.wellness_attributes_partition
GROUP BY tableoid
ORDER BY partition;


--Step 6: Redirect all applications to use the new partitioned table

ALTER TABLE vit_trans.wellness_attributes RENAME TO wellness_attributes_backup;
ALTER TABLE vit_trans.wellness_attributes_partition RENAME TO wellness_attributes;


--Step 7: Grant Permissions to Application/User
GRANT SELECT, INSERT, UPDATE, DELETE ON vit_trans.wellness_attributes TO your_app_user;

--Step 8: Run VACUUM ANALYZE to Update Query Planner Statistics
VACUUM ANALYZE vit_trans.wellness_attributes;

