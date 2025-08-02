CREATE TABLE IF NOT EXISTS vit_trans.insert_status (
    id SERIAL PRIMARY KEY,
    year_month DATE NOT NULL UNIQUE,   -- tháng được insert
    status TEXT CHECK (status IN ('PENDING','SUCCESS','FAILED')) DEFAULT 'PENDING',
    started_at TIMESTAMP DEFAULT now(), -- thời điểm bắt đầu batch
    finished_at TIMESTAMP               -- thời điểm kết thúc batch
);
DO $$
DECLARE
    min_date DATE := '2023-01-01'; -- Ngày bắt đầu cố định
    max_date DATE;
    cur_date DATE;
BEGIN
    -- Lấy ngày max từ dữ liệu gốc
    SELECT date_trunc('month', max(eff_from))::date 
    INTO max_date
    FROM vit_trans.wellness_attributes
    WHERE eff_from >= min_date;

    cur_date := min_date;

    WHILE cur_date <= max_date LOOP
        BEGIN
            -- Thêm log trạng thái PENDING
            INSERT INTO vit_trans.insert_status (year_month, status, started_at)
            VALUES (cur_date, 'PENDING', now())
            ON CONFLICT (year_month) DO UPDATE 
                SET status = 'PENDING', started_at = now(), finished_at = NULL;

            -- Insert batch dữ liệu tháng
            INSERT INTO vit_trans.wellness_attributes_partition
            SELECT *
            FROM vit_trans.wellness_attributes
            WHERE eff_from >= cur_date
              AND eff_from < (cur_date + interval '1 month');

            -- Update SUCCESS nếu OK
            UPDATE vit_trans.insert_status
            SET status = 'SUCCESS', finished_at = now()
            WHERE year_month = cur_date;

            COMMIT; -- commit batch này
        EXCEPTION WHEN OTHERS THEN
            -- Rollback batch nếu lỗi
            ROLLBACK;

            UPDATE vit_trans.insert_status
            SET status = 'FAILED', finished_at = now()
            WHERE year_month = cur_date;
        END;

        -- Sang tháng tiếp
        cur_date := cur_date + interval '1 month';
    END LOOP;
END $$;
