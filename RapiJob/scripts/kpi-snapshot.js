# ============================================================
# Worker: snapshot de KPIs de plataforma a tabla kpi_snapshots
# Se ejecuta por cron (ej: cada lunes 03:00).
# Requiere: npm install  (instala pg)
# Uso:      npm run kpi:snapshot
# ============================================================
import pg from 'pg';
const { DATABASE_URL } = process.env;
const pool = new pg.Pool({ connectionString: DATABASE_URL });

const q = `
WITH per_job AS (
  SELECT
    j.status, j.created_at, j.budget_max,
    (SELECT MIN(ja.assigned_at) FROM job_assignments ja WHERE ja.job_id = j.id) AS first_assigned_at
  FROM jobs j
  WHERE j.created_at >= CURRENT_DATE - INTERVAL '7 days'
),
base AS (
  SELECT
    COUNT(*)                                                  AS jobs_created,
    COUNT(*) FILTER (WHERE status='completed')                AS jobs_completed,
    COUNT(*) FILTER (WHERE status='cancelled')                AS jobs_cancelled,
    AVG(EXTRACT(EPOCH FROM (first_assigned_at - created_at))) AS match_seconds,
    SUM(COALESCE(budget_max,0))                               AS gmv
  FROM per_job
)
INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'platform', NULL, metric, value, CURRENT_DATE-'7 days'::date, CURRENT_DATE
FROM (
  SELECT jobs_created::numeric                                   AS value, 'jobs_created_weekly' AS metric FROM base UNION ALL
  SELECT ROUND(100.0*jobs_completed/NULLIF(jobs_created,0),2)     AS value, 'completion_rate'   FROM base UNION ALL
  SELECT ROUND(100.0*jobs_cancelled/NULLIF(jobs_created,0),2)     AS value, 'cancel_rate'       FROM base UNION ALL
  SELECT ROUND(match_seconds/3600,2)                              AS value, 'match_hours'       FROM base UNION ALL
  SELECT gmv                                                      AS value, 'gmv_weekly'        FROM base
) s
ON CONFLICT DO NOTHING
RETURNING 1;`;

const res = await pool.query(q);
await pool.query(`REFRESH MATERIALIZED VIEW mv_platform_metrics`);
await pool.end();
console.log(`✅ Snapshot de KPIs de plataforma insertado (${res.rowCount} métricas). MV refrescada.`);
