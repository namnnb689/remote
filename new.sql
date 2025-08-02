DO $$
DECLARE
    hash_count INT := 8;    -- số hash partitions
    start_year INT := 2023; -- năm bắt đầu
    end_year   INT := 2025; -- năm kết thúc
    h INT;  -- hash index
    y INT;  -- year index
    q INT;  -- quarter index
    hash_table TEXT;
    range_table TEXT;
    q_start DATE;
    q_end DATE;
BEGIN
    -- Tạo bảng cha (hash)
    EXECUTE $sql$
        CREATE TABLE IF NOT EXISTS vit_trans.wellness_attributes_partition (
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
        )
        PARTITION BY HASH (entity_no)
    $sql$;

    -- Level 1: Hash partitions
    FOR h IN 0..(hash_count-1) LOOP
        hash_table := format('vit_trans.wellness_attributes_partition_p%s', h);
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I
             PARTITION OF vit_trans.wellness_attributes_partition
             FOR VALUES WITH (MODULUS %s, REMAINDER %s)
             PARTITION BY RANGE (eff_from)',
            hash_table, hash_count, h
        );

        -- Level 2: Range partitions theo quý từ 2023 đến hết 2025
        FOR y IN start_year..end_year LOOP
            FOR q IN 1..4 LOOP
                q_start := make_date(y, (q-1)*3+1, 1);
                q_end   := (q_start + interval '3 month')::date;
                range_table := format('%s_y%s_q%s', hash_table, y, q);
                EXECUTE format(
                    'CREATE TABLE IF NOT EXISTS %I
                     PARTITION OF %I
                     FOR VALUES FROM (''%s'') TO (''%s'')',
                    range_table, hash_table, q_start, q_end
                );
            END LOOP;
        END LOOP;

        -- Partition lớn cho tất cả dữ liệu từ 2025 trở đi
        -- Partition lớn cho tất cả dữ liệu từ 2025 trở đi
        range_table := hash_table || '_r2025plus';
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I
            PARTITION OF %I
            FOR VALUES FROM (''2025-01-01'') TO (MAXVALUE)',
            range_table, hash_table
        );

    END LOOP;
END $$;
