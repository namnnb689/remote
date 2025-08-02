DO $$
DECLARE
    min_date DATE := '2023-01-01';
    max_date DATE;
    cur_date DATE;
BEGIN
    SELECT date_trunc('month', max(eff_from))::date 
    INTO max_date
    FROM vit_trans.wellness_attributes
    WHERE eff_from >= min_date;

    cur_date := min_date;

    WHILE cur_date <= max_date LOOP
        BEGIN
            INSERT INTO vit_trans.insert_status (year_month, status, started_at)
            VALUES (cur_date, 'PENDING', now())
            ON CONFLICT (year_month) DO UPDATE 
                SET status = 'PENDING', started_at = now(), finished_at = NULL;

            INSERT INTO vit_trans.wellness_attributes_partition
            SELECT *
            FROM vit_trans.wellness_attributes
            WHERE eff_from >= cur_date
              AND eff_from < (cur_date + interval '1 month');

            UPDATE vit_trans.insert_status
            SET status = 'SUCCESS', finished_at = now()
            WHERE year_month = cur_date;

            COMMIT;
        EXCEPTION WHEN OTHERS THEN
            ROLLBACK;
            UPDATE vit_trans.insert_status
            SET status = 'FAILED', finished_at = now()
            WHERE year_month = cur_date;
        END;

        cur_date := cur_date + interval '1 month';
    END LOOP;
END $$;
