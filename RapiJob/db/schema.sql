-- ============================================================
--  RapiJob - Platform DB (PostgreSQL)
--  Schema completo propuesto en DESIGN.md
--  Ejecutar: psql $DATABASE_URL -f db/schema.sql
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. USERS (auth + roles)
-- ============================================================
CREATE TABLE users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email        TEXT UNIQUE NOT NULL,
    phone        TEXT UNIQUE,
    password     TEXT NOT NULL,                 -- bcrypt hash
    role         TEXT NOT NULL CHECK (role IN ('client','technician','admin','supervisor')),
    status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','inactive')),
    verified     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_email   ON users(email);
CREATE INDEX idx_users_role    ON users(role);

-- ============================================================
-- 2. PROFILES (datos extendidos)
--  NOTA: lat/lng en NUMERIC para evitar dependencia PostGIS en MVP.
--        En prod se recomienda GEOGRAPHY + índice GIST.
-- ============================================================
CREATE TABLE profiles (
    user_id            UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name         TEXT NOT NULL,
    last_name          TEXT NOT NULL,
    bio                TEXT,
    avatar_url         TEXT,
    location_lat       NUMERIC(9,6),
    location_lng       NUMERIC(9,6),
    location_label     TEXT,
    service_radius_km  NUMERIC(6,2) DEFAULT 30,
    hourly_rate        NUMERIC(10,2),
    verified_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_profiles_label ON profiles(location_label);

-- ============================================================
-- 3. SPECIALTIES (extensible: IT, mantenimiento, electricidad...)
-- ============================================================
CREATE TABLE specialties (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    description TEXT,
    icon_url    TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_specialties_name ON specialties(name);

-- ============================================================
-- 4. TECHNICIAN_SPECIALTIES (muchos-a-muchos)
-- ============================================================
CREATE TABLE technician_specialties (
    technician_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    specialty_id    UUID REFERENCES specialties(id) ON DELETE CASCADE,
    experience_years NUMERIC(4,1),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (technician_id, specialty_id)
);
CREATE INDEX idx_ts_technician ON technician_specialties(technician_id);
CREATE INDEX idx_ts_specialty  ON technician_specialties(specialty_id);

-- ============================================================
-- 5. CERTIFICATIONS (catálogo)
-- ============================================================
CREATE TABLE certifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    issuing_body TEXT,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_certifications_name ON certifications(name);

-- ============================================================
-- 6. TECHNICIAN_CERTIFICATIONS (certificados + workflow validación)
-- ============================================================
CREATE TABLE technician_certifications (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technician_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
    document_url     TEXT NOT NULL,
    issued_at        DATE,
    expires_at       DATE,
    validation_status TEXT NOT NULL DEFAULT 'pending'
                          CHECK (validation_status IN ('pending','valid','rejected')),
    validated_by     UUID REFERENCES users(id),
    validated_at     TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_tc_technician   ON technician_certifications(technician_id);
CREATE INDEX idx_tc_cert         ON technician_certifications(certification_id);
CREATE INDEX idx_tc_validation   ON technician_certifications(validation_status);
CREATE INDEX idx_tc_expires      ON technician_certifications(expires_at);

-- ============================================================
-- 7. JOBS (trabajos publicados por clientes)
-- ============================================================
CREATE TABLE jobs (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id          UUID NOT NULL REFERENCES users(id),
    title              TEXT NOT NULL,
    description        TEXT NOT NULL,
    specialty_id       UUID NOT NULL REFERENCES specialties(id),
    budget_min         NUMERIC(10,2),
    budget_max         NUMERIC(10,2),
    location_lat       NUMERIC(9,6),
    location_lng       NUMERIC(9,6),
    location_label     TEXT,
    is_remote          BOOLEAN NOT NULL DEFAULT FALSE,
    urgency            TEXT NOT NULL DEFAULT 'normal'
                          CHECK (urgency IN ('low','normal','high','urgent')),
    status             TEXT NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open','in_progress','completed','cancelled')),
    deadline_at        TIMESTAMPTZ,
    assigned_to        UUID REFERENCES users(id),
    completed_at       TIMESTAMPTZ,
    cancelled_at       TIMESTAMPTZ,
    cancellation_reason TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_jobs_client    ON jobs(client_id);
CREATE INDEX idx_jobs_specialty ON jobs(specialty_id);
CREATE INDEX idx_jobs_status    ON jobs(status);
CREATE INDEX idx_jobs_created   ON jobs(created_at DESC);

-- ============================================================
-- 8. JOB_APPLICATIONS (postulaciones de técnicos)
-- ============================================================
CREATE TABLE job_applications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id),
    technician_id   UUID NOT NULL REFERENCES users(id),
    cover_letter    TEXT,
    proposed_price  NUMERIC(10,2),
    status          TEXT NOT NULL DEFAULT 'applied'
                        CHECK (status IN ('applied','accepted','rejected','withdrawn')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ja_job        ON job_applications(job_id);
CREATE INDEX idx_ja_technician ON job_applications(technician_id);
CREATE INDEX idx_ja_status     ON job_applications(status);
CREATE UNIQUE INDEX uq_ja_job_tech ON job_applications(job_id, technician_id);

-- ============================================================
-- 9. JOB_ASSIGNMENTS (historial de asignaciones)
-- ============================================================
CREATE TABLE job_assignments (
    job_id            UUID NOT NULL REFERENCES jobs(id),
    technician_id     UUID NOT NULL REFERENCES users(id),
    assigned_by       UUID REFERENCES users(id),
    assigned_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at       TIMESTAMPTZ,
    rejected_at       TIMESTAMPTZ,
    rejection_reason  TEXT,
    PRIMARY KEY (job_id, technician_id, assigned_at)
);
CREATE INDEX idx_assignment_job        ON job_assignments(job_id);
CREATE INDEX idx_assignment_technician ON job_assignments(technician_id);

-- ============================================================
-- 10. JOB_REVIEWS (reseñas 1-5 estrellas)
-- ============================================================
CREATE TABLE job_reviews (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id        UUID NOT NULL REFERENCES jobs(id),
    reviewer_id   UUID NOT NULL REFERENCES users(id),
    reviewee_id   UUID NOT NULL REFERENCES users(id),
    rating        INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment       TEXT,
    is_anonymous  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_review_job      ON job_reviews(job_id);
CREATE INDEX idx_review_reviewee ON job_reviews(reviewee_id);
CREATE INDEX idx_review_rating   ON job_reviews(rating);
CREATE UNIQUE INDEX uq_review_job ON job_reviews(job_id);

-- ============================================================
-- 11. REVIEW_VALIDATIONS (validación de calidad por supervisor)
-- ============================================================
CREATE TABLE review_validations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id        UUID NOT NULL REFERENCES jobs(id),
    supervisor_id UUID NOT NULL REFERENCES users(id),
    status        TEXT NOT NULL CHECK (status IN ('approved','rejected','needs_revision')),
    score         NUMERIC(4,2),
    notes         TEXT,
    evidence_url  TEXT,
    validated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_rv_job        ON review_validations(job_id);
CREATE INDEX idx_rv_supervisor ON review_validations(supervisor_id);
CREATE INDEX idx_rv_status     ON review_validations(status);

-- ============================================================
-- 12. PAYMENTS (pagos)
-- ============================================================
CREATE TABLE payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id),
    payer_id        UUID NOT NULL REFERENCES users(id),
    payee_id        UUID NOT NULL REFERENCES users(id),
    amount          NUMERIC(10,2) NOT NULL,
    currency        TEXT NOT NULL DEFAULT 'USD',
    method          TEXT NOT NULL CHECK (method IN ('card','transfer','wallet')),
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','succeeded','failed','refunded')),
    provider_txn_id TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_job   ON payments(job_id);
CREATE INDEX idx_payments_payer  ON payments(payer_id);
CREATE INDEX idx_payments_payee  ON payments(payee_id);
CREATE INDEX idx_payments_status ON payments(status);

-- ============================================================
-- 13. DOCUMENTS (anexos: fotos, evidencias)
-- ============================================================
CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID REFERENCES jobs(id) ON DELETE CASCADE,
    uploader_id     UUID NOT NULL REFERENCES users(id),
    type            TEXT NOT NULL
                        CHECK (type IN ('contract','work_photo','evidence','cert','other')),
    url             TEXT NOT NULL,
    file_name       TEXT NOT NULL,
    file_size_bytes BIGINT,
    mime_type       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_documents_job      ON documents(job_id);
CREATE INDEX idx_documents_uploader ON documents(uploader_id);
CREATE INDEX idx_documents_type     ON documents(type);

-- ============================================================
-- 14. NOTIFICATIONS
-- ============================================================
CREATE TABLE notifications (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id),
    title         TEXT NOT NULL,
    message       TEXT NOT NULL,
    type          TEXT NOT NULL
                      CHECK (type IN ('job_applied','job_assigned','job_completed','review_added','payment','system')),
    read          BOOLEAN NOT NULL DEFAULT FALSE,
    reference_id  UUID,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user   ON notifications(user_id);
CREATE INDEX idx_notifications_read   ON notifications(read);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);

-- ============================================================
-- 15. KPI_SNAPSHOTS (histórico de KPIs)
-- ============================================================
CREATE TABLE kpi_snapshots (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type   TEXT NOT NULL CHECK (entity_type IN ('technician','client','platform')),
    entity_id     UUID REFERENCES users(id),
    metric_name   TEXT NOT NULL,
    metric_value  NUMERIC(12,4) NOT NULL,
    period_start  DATE NOT NULL,
    period_end    DATE NOT NULL
);
CREATE INDEX idx_kpi_entity      ON kpi_snapshots(entity_type, entity_id);
CREATE INDEX idx_kpi_metric      ON kpi_snapshots(metric_name);
CREATE INDEX idx_kpi_period      ON kpi_snapshots(period_start DESC);
CREATE INDEX idx_kpi_entity_metric ON kpi_snapshots(entity_type, metric_name);

-- ============================================================
-- 16. PLATFORM ALERT RULES (thresholds configurables)
-- ============================================================
CREATE TABLE platform_alert_rules (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_name    TEXT NOT NULL,
    operator       TEXT NOT NULL CHECK (operator IN ('>','<','>=','<=','==')),
    threshold      NUMERIC(12,4) NOT NULL,
    severity       TEXT NOT NULL CHECK (severity IN ('info','warning','critical')),
    channel        TEXT NOT NULL DEFAULT 'slack',
    enabled        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_alert_metric ON platform_alert_rules(metric_name);

-- ============================================================
-- 17. COMMISSION RULES (config para revenue/take-rate)
-- ============================================================
CREATE TABLE commission_rules (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    specialty_id UUID REFERENCES specialties(id),
    rate_pct     NUMERIC(5,2) NOT NULL DEFAULT 15.00,      -- 15%
    min_amount   NUMERIC(10,2) NOT NULL DEFAULT 0,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_commission_specialty ON commission_rules(specialty_id);

-- ============================================================
-- VISTAS: KPIs en tiempo real (técnico)
--  NOTA: "tasa de respuesta" = aceptación de ofertas (accepted / offered).
--        ≤100% siempre, porque accepted ⊆ offered.
--        offered = filas de job_assignments para el técnico;
--        accepted = accepted_at IS NOT NULL.
-- ============================================================
CREATE OR REPLACE VIEW v_tech_acceptance_rate AS
SELECT
    technician_id,
    COUNT(*)                                    AS offered,
    COUNT(*) FILTER (WHERE accepted_at IS NOT NULL) AS accepted,
    ROUND(100.0 * COUNT(*) FILTER (WHERE accepted_at IS NOT NULL)
             / NULLIF(COUNT(*),0), 2)            AS acceptance_rate
FROM job_assignments
GROUP BY technician_id;

CREATE OR REPLACE VIEW v_tech_rating AS
SELECT
    reviewee_id AS technician_id,
    ROUND(AVG(rating),2) AS avg_rating,
    COUNT(*)             AS reviews_count
FROM job_reviews r
JOIN jobs j ON j.id = r.job_id
WHERE j.status = 'completed'
GROUP BY reviewee_id;

CREATE OR REPLACE VIEW v_tech_earnings AS
SELECT
    payee_id AS technician_id,
    COALESCE(SUM(amount),0) AS total_earned
FROM payments
WHERE status = 'succeeded'
GROUP BY payee_id;

CREATE OR REPLACE VIEW v_tech_first_time_fix AS
SELECT
    j.assigned_to AS technician_id,
    COUNT(*) FILTER (WHERE v.id IS NULL) AS first_time_ok,
    COUNT(*)                                AS total_completed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE v.id IS NULL)
            / NULLIF(COUNT(*),0), 2)        AS first_time_fix_rate
FROM jobs j
JOIN job_reviews r ON r.job_id = j.id
LEFT JOIN review_validations v ON v.job_id = j.id
WHERE j.status = 'completed' AND j.assigned_to IS NOT NULL
GROUP BY j.assigned_to;

CREATE OR REPLACE VIEW v_tech_completion_rate AS
SELECT
    assigned_to AS technician_id,
    COUNT(*) AS jobs_assigned,
    COUNT(*) FILTER (WHERE status='completed') AS jobs_completed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status='completed')
             / NULLIF(COUNT(*),0), 2) AS completion_rate
FROM jobs
WHERE assigned_to IS NOT NULL
GROUP BY assigned_to;

CREATE OR REPLACE VIEW v_tech_resolution_time AS
SELECT
    assigned_to AS technician_id,
    ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at))/60), 2) AS avg_resolution_minutes
FROM jobs
WHERE status='completed' AND assigned_to IS NOT NULL
GROUP BY assigned_to;

CREATE OR REPLACE VIEW v_tech_applied AS
-- Total de aplicaciones que el técnico envió (enganche/aplicó a X trabajos)
SELECT
    technician_id,
    COUNT(*) AS jobs_applied
FROM job_applications
GROUP BY technician_id;

CREATE OR REPLACE VIEW v_tech_metrics AS
SELECT
    u.id AS technician_id,
    COALESCE(r.avg_rating,0)               AS avg_rating,
    COALESCE(r.reviews_count,0)            AS reviews_count,
    COALESCE(e.total_earned,0)             AS total_earned,
    COALESCE(acc.acceptance_rate,0)        AS acceptance_rate,
    COALESCE(comp.completion_rate,0)       AS completion_rate,
    COALESCE(rt.avg_resolution_minutes,0)  AS avg_resolution_minutes,
    COALESCE(app.jobs_applied,0)           AS jobs_applied,
    COALESCE(ff.first_time_fix_rate,0)     AS first_time_fix_rate
FROM users u
LEFT JOIN v_tech_rating      r   ON r.technician_id = u.id
LEFT JOIN v_tech_earnings    e   ON e.technician_id = u.id
LEFT JOIN v_tech_acceptance_rate acc ON acc.technician_id = u.id
LEFT JOIN v_tech_completion_rate    comp ON comp.technician_id = u.id
LEFT JOIN v_tech_resolution_time    rt   ON rt.technician_id = u.id
LEFT JOIN v_tech_applied             app  ON app.technician_id = u.id
LEFT JOIN v_tech_first_time_fix      ff   ON ff.technician_id = u.id
WHERE u.role = 'technician';

-- ============================================================
-- MATERIALIZED VIEW: KPIs semanales de PLATAFORMA (la pieza clave)
-- match_hours se calcula desde job_assignments.assigned_at (el job.created_at
-- es timestamp válido; assigned_to es UUID por lo que NO es restableable).
-- ============================================================
CREATE MATERIALIZED VIEW mv_platform_metrics AS
WITH per_job AS (
    SELECT
        j.id,
        DATE_TRUNC('week', j.created_at)::date  AS wk,
        j.created_at,
        j.completed_at,
        j.budget_max,
        j.status,
        j.assigned_to,
        (SELECT MIN(ja.assigned_at) FROM job_assignments ja WHERE ja.job_id = j.id) AS first_assigned_at
    FROM jobs j
),
weekly AS (
    SELECT
        wk,
        COUNT(*)                                              AS jobs_created,
        COUNT(*) FILTER (WHERE status='completed')            AS jobs_completed,
        COUNT(*) FILTER (WHERE status='cancelled')            AS jobs_cancelled,
        COUNT(*) FILTER (WHERE first_assigned_at IS NOT NULL) AS jobs_matched,
        AVG(EXTRACT(EPOCH FROM (first_assigned_at - created_at))/3600) AS match_hours,
        SUM(COALESCE(budget_max,0))                             AS gmv,
        AVG(EXTRACT(EPOCH FROM (completed_at - created_at))/60)  AS avg_completion_minutes
    FROM per_job
    GROUP BY wk
),
rev AS (
    SELECT DATE_TRUNC('week', created_at)::date AS wk,
           SUM(amount) AS revenue
    FROM payments WHERE status='succeeded'
    GROUP BY DATE_TRUNC('week', created_at)
),
eng AS (
    SELECT DATE_TRUNC('week', created_at)::date AS wk,
           COUNT(DISTINCT user_id) AS dau
    FROM notifications
    GROUP BY DATE_TRUNC('week', created_at)
)
SELECT
    w.wk,
    w.jobs_created,
    w.jobs_completed,
    w.jobs_cancelled,
    w.jobs_matched,
    ROUND(w.match_hours,1)            AS match_hours,
    ROUND(w.gmv,2)                    AS gmv,
    COALESCE(rev.revenue,0)           AS revenue,
    CASE WHEN w.jobs_created>0
         THEN ROUND(100.0*w.jobs_completed/w.jobs_created,2) ELSE 0 END AS completion_rate,
    CASE WHEN w.jobs_created>0
         THEN ROUND(100.0*w.jobs_cancelled/w.jobs_created,2) ELSE 0 END AS cancel_rate,
    CASE WHEN w.gmv>0
         THEN ROUND(100.0*COALESCE(rev.revenue,0)/w.gmv,2) ELSE 0 END AS take_rate,
    COALESCE(eng.dau,0)               AS dau
FROM weekly w
LEFT JOIN rev ON rev.wk = w.wk
LEFT JOIN eng ON eng.wk = w.wk
ORDER BY w.wk DESC;

CREATE UNIQUE INDEX mv_platform_metrics_wk ON mv_platform_metrics(wk);

COMMENT ON MATERIALIZED VIEW mv_platform_metrics IS
  'KPIs semanales de plataforma. Refrescar con: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_platform_metrics';
