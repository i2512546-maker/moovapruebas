# KPIs — Implementación Concreta

KPIs listos para lanzar. Funcionan para **cualquier tipo de técnico** (IT, mantenimiento,
instalaciones...) porque se basan en comportamientos universales del flujo (postulación,
asignación, completado, pago, reseña).

---

## 1. Qué son los KPIs (resumen rápido)

**Para técnico (reputación + productividad):**
1. **Tasa de aceptación** — % de ofertas que acepta el técnico (≤100%: accepted/offered).
2. **Tasa de finalización** — % de trabajos asignados que completa.
3. **Rating promedio** — puntuación media de reseñas (1-5 estrellas).
4. **Ingresos acumulados** — suma de pagos recibidos.
5. **Tiempo de resolución** — avg(completed_at − created_at).
6. **First-time-fix** — % de trabajos aprobados a la primera (sin `needs_revision`).
7. **Aplicaciones enviadas** — cuántos trabajos postuló (enganche).

**Para cliente:**
- Trabajos publicados, tiempo promedio de contratación, satisfacción, gasto total.

**Para plataforma:**
- Volumen de trabajos, tasa de finalización global, revenue, tasa de activación de técnicos.

> Todos usan timestamps genéricos (`created_at`, `completed_at`, etc.) presentes en el
> esquema → **no dependen del tipo de técnico**. Cambian de especialidad por filtro.

---

## 2. Queries SQL implementables (Views + Materialized Views)

Puedes crear estas `views` para lectura en tiempo real y una
**materialized view** para el snapshot histórico de plataforma.

### 2.1 Tasa de aceptación (técnico)  ← KPI de oferta
```sql
-- % de ofertas aceptadas (siempre ≤100% porque accepted ⊆ offered)
CREATE OR REPLACE VIEW v_tech_acceptance_rate AS
SELECT
    technician_id,
    COUNT(*) FILTER (WHERE accepted_at IS NOT NULL)  AS accepted,
    COUNT(*)                                          AS offered,
    ROUND(100.0 * COUNT(*) FILTER (WHERE accepted_at IS NOT NULL)
            / NULLIF(COUNT(*),0), 2)                  AS acceptance_rate
FROM job_assignments
GROUP BY technician_id;
```sql
CREATE OR REPLACE VIEW v_tech_acceptance_rate AS
SELECT
    technician_id,
    COUNT(*) FILTER (WHERE accepted_at IS NOT NULL)   AS accepted,
    COUNT(*)                                           AS offered,
    ROUND(100.0 * COUNT(*) FILTER (WHERE accepted_at IS NOT NULL)
            / NULLIF(COUNT(*),0), 2)                   AS acceptance_rate
FROM job_assignments
GROUP BY technician_id;
```

### 2.2 Rating + conteo de reseñas
```sql
CREATE OR REPLACE VIEW v_tech_rating AS
SELECT
    reviewee_id AS technician_id,
    ROUND(AVG(rating),2)      AS avg_rating,
    COUNT(*)                  AS reviews_count
FROM job_reviews r
JOIN jobs j ON j.id = r.job_id
WHERE j.status = 'completed'
GROUP BY reviewee_id;
```

### 2.3 Tiempo de resolución (minutos)
```sql
CREATE OR REPLACE VIEW v_tech_resolution_time AS
SELECT
    assigned_to AS technician_id,
    ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at))/60), 2) AS avg_resolution_min
FROM jobs
WHERE status = 'completed' AND assigned_to IS NOT NULL
GROUP BY assigned_to;
```

### 2.4 Ingresos acumulados (técnico)
```sql
CREATE OR REPLACE VIEW v_tech_earnings AS
SELECT
    payee_id AS technician_id,
    COALESCE(SUM(amount),0) AS total_earned
FROM payments
WHERE status = 'succeeded'
GROUP BY payee_id;
```

### 2.5 First-time-fix (IT)
```sql
-- Un job "dirty" si tuvo más de 1 revisión/validación
CREATE OR REPLACE VIEW v_tech_first_time_fix AS
SELECT
    j.assigned_to AS technician_id,
    COUNT(*) FILTER (WHERE v.id IS NULL)                          AS first_time_ok,
    COUNT(*)                                                       AS total_completed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE v.id IS NULL)
            / NULLIF(COUNT(*),0), 2)                              AS first_time_fix_rate
FROM jobs j
JOIN job_reviews r ON r.job_id = j.id
LEFT JOIN review_validations v ON v.job_id = j.id
WHERE j.status = 'completed' AND j.assigned_to IS NOT NULL
GROUP BY j.assigned_to;
```

### 2.6 Snapshot histórico (snapshot diario en `kpi_snapshots`)
```sql
-- Ejecutado por el worker una vez al día
INSERT INTO kpi_snapshots (entity_type, entity_id, metric_name, metric_value, period_start, period_end)
SELECT 'technician', t.id, 'rating', (SELECT avg_rating FROM v_tech_rating WHERE technician_id=t.id),
       CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE - INTERVAL '1 day'
FROM users t WHERE t.role='technician';

INSERT INTO kpi_snapshots (entity_type, entity_id, metric_name, metric_value, period_start, period_end)
SELECT 'platform', NULL, 'jobs_created_daily',
       COUNT(*), CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE - INTERVAL '1 day'
FROM jobs WHERE created_at::date = (CURRENT_DATE - INTERVAL '1 day')::date;
```

---

## 3. Worker de KPIs (TypeScript / NestJS cron)

```ts
// src/kpis/kpi.processor.ts
@Cron('0 2 * * *') // todos los días 02:00
async snapshotDaily() {
  const end = new Date(); end.setHours(0,0,0,0);
  const start = new Date(end); start.setDate(end.getDate()-1);

  const techs = await this.prisma.users.findMany({ where:{role:'technician'} });
  for (const t of techs) {
    const [rating, response, accept, earnings] = await Promise.all([
      this.prisma.jobReviews.aggregate({...}),
      this.prisma.jobApplications.count({...}),
      ...
    ]);
    await this.prisma.kpiSnapshot.create({ data: {
      entityType:'technician', entityId:t.id, metricName:'rating',
      metricValue: rating.avg ?? 0, periodStart:start, periodEnd:end
    }});
  }
}
```

---

## 4. Dashboard unificado (response genérica)

```http
GET /api/v1/dashboard/kpis?role=technician&period=30d
GET /api/v1/dashboard/kpis?role=platform&metric=jobs_created_daily
```
Respuesta: `{ metric, value, trend, unit }` → el frontend itera y pinta.
**Funciona para cualquier tipo de técnico** porque los filtros (`specialty`, `location`)
se pasan como query params y los queries base son especialidad-agnósticos.

---

## 5. Lanzamiento fácil (Quick-Start)

### Opción A — Monorepo con Docker (1 comando)
```
docker compose up -d --build
# levanta: db, redis, api, web, worker
```
`docker-compose.yml`:
```yaml
services:
  db:      { image: postgres:16, env_file: .env }
  redis:   { image: redis:7-alpine }
  api:     { build: ./backend, ports: ["4000:4000"], env_file: .env, depends_on: [db,redis] }
  web:     { build: ./frontend, ports: ["5173:5173"], env: { VITE_API_URL: http://localhost:4000/api } }
  worker:  { build: ./backend, command: npm run worker:start, depends_on: [db,redis] }
```

### Opción B — Serverless (más fácil de lanzar, cero infra)
- **Frontend** → Vite+React en Vercel (`vercel --prod`).
- **API + Workers** → funciones en `api/` desplegadas en Vercel/Netlify.
- **DB** → Neon.tech (Postgres serverless) — conecta con `DATABASE_URL`.
- **KPIs** → cron de Vercel (`vercel.json` + `@vercel/cron`) ejecuta el snapshot.
- **Storage** → S3 (o Cloudflare R2).

> Con esta opción `git push` dispara el deploy. Ideal para MVP rápido y "cualquier tipo de técnico".

### Variables de entorno mínimas (.env)
```
DATABASE_URL=postgresql://...
JWT_SECRET=***
REDIS_URL=redis://...
UPLOAD_PROVIDER=s3|cloudinary
```

### Seed de datos (para probar KPIs de inmediato)
```
npm run db:seed   # crea 1 admin, 3 técnicos (IT+mantenimiento), 1 cliente, jobs de prueba
npm run kpi:snapshot   # calcula KPIs iniciales
```

---

## 6. Qué aplicar para lanzar hoy

| Paso | Acción | Comando |
|---|---|---|
| 1 | Copia `DESIGN.md` → migrations | `npm run db:migrate` (usa schema de DESIGN.md) |
| 2 | Crea las 7 views de este archivo | `psql < docs/kpi-views.sql` |
| 3 | Ejecuta seed | `npm run db:seed` |
| 4 | Lanza worker de KPIs | `npm run kpi:run` (snapshot) |
| 5 | Abre `/dashboard/kpis` | verás todos los KPIs ya calculados |
