DO $$
DECLARE
    hash_count INT := 8; -- số hash partitions
    start_year INT := 2023;
    end_year   INT := 2025;
    h INT; -- hash index
    y INT; -- year index
    q INT; -- quarter index
    hash_table TEXT;
    range_table TEXT;
    q_start DATE;
    q_end DATE;
BEGIN
    FOR h IN 0..(hash_count-1) LOOP
        hash_table := format('vit_trans.wellness_attributes_partition_p%s', h);

        -- Quý từ 2023 đến hết 2025
        FOR y IN start_year..end_year LOOP
            FOR q IN 1..4 LOOP
                q_start := make_date(y, (q-1)*3 + 1, 1);
                q_end := (q_start + interval '3 months');

                range_table := format('%s_y%s_q%s', hash_table, y, q);

                EXECUTE format(
                    'CREATE TABLE IF NOT EXISTS %I
                     PARTITION OF %I
                     FOR VALUES FROM (%L) TO (%L);',
                    range_table, hash_table, q_start, q_end
                );
            END LOOP;
        END LOOP;

        -- Partition từ 2026 trở đi
        range_table := format('%s_y2026_plus', hash_table);
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I
             PARTITION OF %I
             FOR VALUES FROM (%L) TO (MAXVALUE);',
            range_table, hash_table, make_date(2026, 1, 1)
        );
    END LOOP;
END $$;
