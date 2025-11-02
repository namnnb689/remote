
DROP MATERIALIZED VIEW IF EXISTS public.mv_assessment_attr_7days;

CREATE MATERIALIZED VIEW public.mv_assessment_attr_7days AS
SELECT *
FROM public.assessment_attr
WHERE watermark >= NOW() - INTERVAL '7 days';

CREATE INDEX idx_mv_assessment_attr_watermark
    ON public.mv_assessment_attr_7days (watermark);



CREATE EXTENSION IF NOT EXISTS pg_cron;
-- Schedule daily refresh at 23:00 HKT (16:00 UTC)
SELECT cron.schedule(
    'refresh_mv_assessment_attr_7days',
    '0 16 * * *',  
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_assessment_attr_7days;$$
);


SELECT * FROM cron.job;
SELECT * FROM cron.job_run_details ORDER BY runid DESC LIMIT 10;