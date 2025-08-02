CREATE TABLE IF NOT EXISTS vit_trans.insert_status_log (
    log_id SERIAL PRIMARY KEY,
    batch_month DATE NOT NULL,
    status TEXT CHECK (status IN ('SUCCESS','FAILED')),
    error_message TEXT,
    inserted_at TIMESTAMP DEFAULT now()
);


DO $$
DECLARE
    start_date DATE := '2023-01-01';
    end_date   DATE := date_trunc('month', CURRENT_DATE); -- tháng hiện tại
    batch_start DATE;
    batch_end   DATE;
BEGIN
    batch_start := start_date;

    WHILE batch_start <= end_date LOOP
        batch_end := (batch_start + interval '1 month');

        BEGIN
            -- Chèn dữ liệu tháng này vào partition table
            EXECUTE format(
                'INSERT INTO vit_trans.wellness_attributes_partition
                 SELECT * FROM vit_trans.wellness_attributes
                 WHERE eff_from >= %L AND eff_from < %L;',
                batch_start, batch_end
            );

            -- Ghi log thành công
            INSERT INTO vit_trans.insert_status_log(batch_month, status)
            VALUES (batch_start, 'SUCCESS');

            RAISE NOTICE 'Inserted month % from % to %', batch_start, batch_start, batch_end;

        EXCEPTION WHEN OTHERS THEN
            -- Rollback tháng này nếu lỗi
            ROLLBACK;

            -- Ghi log thất bại
            INSERT INTO vit_trans.insert_status_log(batch_month, status, error_message)
            VALUES (batch_start, 'FAILED', SQLERRM);

            RAISE NOTICE 'Failed month %: %', batch_start, SQLERRM;
        END;

        -- Chuyển sang tháng tiếp theo
        batch_start := batch_end;
    END LOOP;
END $$;
