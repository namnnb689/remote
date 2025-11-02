
DROP MATERIALIZED VIEW IF EXISTS public.mv_assessment_attr_7days;

CREATE MATERIALIZED VIEW public.mv_assessment_attr_7days AS
SELECT *
FROM vit_trans.assessment_attr
WHERE date_time_last_modified >= NOW() - INTERVAL '7 days';


CREATE INDEX idx_mv_assessment_attr_watermark
    ON public.mv_assessment_attr_7days (date_time_last_modified);


CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'refresh_mv_assessment_attr_7days',
    '0 16 * * *',  -- 16:00 UTC = 23:00 HKT
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_assessment_attr_7days;$$
);
