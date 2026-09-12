# Diseño de Plataforma: Búsqueda y Registro de Técnicos

Plataforma para buscar/registrar técnicos, generar trabajos, con KPIs integrados,
validaciones de negocio y una base de datos bien estructurada.

---

## 1. Visión General

| Dimensión | Decisión |
|---|---|
| Nombre | **RapiJob** (plataforma de técnicos) |
| Rol centrales | **Cliente** (publica trabajos), **Técnico** (ejecuta), **Admin** (gestiona), **Supervisor** (valida) |
| Flujo principal | Cliente publica trabajo → Técnicos postulan / son asignados → se ejecuta → Supervisor valida → se paga |
| Tipo de trabajo | Genérico: IT, mantenimiento, instalaciones (extensible por especialidad) |

---

## 2. Arquitectura y Tech Stack

### 2.1 Stack

| Capa | Tecnología | Justificación |
|---|---|---|
| Frontend | React + TypeScript + TailwindCSS | Componentes reutilizables, tipado, styling rápido |
| Backend | NestJS (Node + Express) + TypeScript | Arquitectura modular, validaciones con class-validator, OpenAPI integrado |
| Base de datos | PostgreSQL | ACID, JSONB flexible, full-text search, relacional sólido para KPIs |
| Auth | JWT + Passport (roles: client_tech/admin/supervisor) | Gestión de roles y permisos |
| Cache / Colas | Redis | Cacheo de KPIs, colas de notificaciones |
| Mensajería en vivo | WebSocket (Socket.io) | Notificaciones en tiempo real |
| Busqueda / Filtrado | Postgres full-text + Trigram indexes | Búsqueda de técnicos por especialidad, zona, rating |
| Storage | S3 / Cloudinary | Certificados, fotos, documentos |
| Contenerización | Docker + Docker Compose | Dev/prod consistente |
| Testing | Jest + Supertest (unitario) / Cypress (e2e) | Calidad asegurada |

### 2.2 Componentes

```
┌────────────┐   ┌─────────────┐   ┌──────────┐   ┌──────────┐
│  Frontend  │──▶│   API GW   │──▶│  Backend │──▶│  Redis   │
│  (React)   │   │  (Nginx)   │   │ (NestJS) │   │ (caché)  │
└────────────┘   └─────────────┘   └────┬─────┘   └──────────┘
                                           │
                                    ┌──────▼──────┐
                                    │ PostgreSQL  │
                                    │   (DB)      │
                                    └──────┬──────┘
                                           │
                              ┌────────────┼─────────────┐
                              │  S3/Cldr   │  Workers    │
                              │ (storage)  │ (queues)    │
                              └────────────┴─────────────┘
```

---

## 3. Esquema de Base de Datos (PostgreSQL)

> Todas las tablas incluyen `id (PK uuid)`, `created_at`, `updated_at`.
> Índices se indican junto a cada tabla.

### 3.1 Usuarios y perfiles

```sql
-- Tabla: users (auth + roles)
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       TEXT UNIQUE NOT NULL,
    phone       TEXT UNIQUE,
    password    TEXT NOT NULL,           -- bcrypt hash
    role        TEXT NOT NULL CHECK (role IN ('client','technician','admin','supervisor')),
    status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','inactive')),
    verified    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

-- Tabla: profiles (datos extendidos)
CREATE TABLE profiles (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name      TEXT NOT NULL,
    last_name       TEXT NOT NULL,
    bio             TEXT,
    avatar_url      TEXT,
    location        GEOGRAPHY(POINT,4326),     -- para búsqueda por proximidad
    location_label    TEXT,                    -- dirección legible
    service_radius_km NUMERIC(6,2) DEFAULT 30, -- radio de cobertura del técnico
    hourly_rate     NUMERIC(10,2),
    verified_at     TIMESTAMP,                 -- cuando fue verificado un técnico
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_profiles_location ON profiles USING GIST (location);
CREATE INDEX idx_profiles_radius ON profiles(service_radius_km);
```

### 3.2 Especialidades y certificaciones

```sql
-- Tabla: specialties (categorías de trabajo: redes, plomería, etc.)
CREATE TABLE specialties (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    description TEXT,
    icon_url    TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_specialties_name ON specialties(name);

-- Tabla: technician_specialties (muchos-a-muchos)
CREATE TABLE technician_specialties (
    technician_id UUID REFERENCES users(id) ON DELETE CASCADE,
    specialty_id  UUID REFERENCES specialties(id) ON DELETE CASCADE,
    experience_years NUMERIC(4,1),
    created_at    TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (technician_id, specialty_id)
);
CREATE INDEX idx_ts_technician ON technician_specialties(technician_id);
CREATE INDEX idx_ts_specialty ON technician_specialties(specialty_id);

-- Tabla: certifications (catálogo de certificaciones)
CREATE TABLE certifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    issuing_body TEXT,
    description TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_certifications_name ON certifications(name);

-- Tabla: technician_certifications (muchos-a-muchos + validación)
CREATE TABLE technician_certifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technician_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    certification_id UUID REFERENCES certifications(id) ON DELETE CASCADE,
    document_url    TEXT NOT NULL,         -- archivo del certificado
    issued_at       DATE,
    expires_at      DATE,
    validation_status TEXT NOT NULL DEFAULT 'pending'
                          CHECK (validation_status IN ('pending','valid','rejected')),
    validated_by    UUID REFERENCES users(id),     -- admin/supervisor
    validated_at    TIMESTAMP,
    rejection_reason TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_tc_technician ON technician_certifications(technician_id);
CREATE INDEX idx_tc_cert ON technician_certifications(certification_id);
CREATE INDEX idx_tc_validation ON technician_certifications(validation_status);
CREATE INDEX idx_tc_expires ON technician_certifications(expires_at);
```

### 3.3 Trabajos (jobs) y postulaciones

```sql
-- Tabla: jobs (trabajos publicados por clientes)
CREATE TABLE jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id       UUID NOT NULL REFERENCES users(id),
    title           TEXT NOT NULL,
    description     TEXT NOT NULL,
    specialty_id    UUID NOT NULL REFERENCES specialties(id),
    budget_min      NUMERIC(10,2),
    budget_max      NUMERIC(10,2),
    location        GEOGRAPHY(POINT,4326),
    location_label    TEXT,
    is_remote       BOOLEAN NOT NULL DEFAULT FALSE,
    urgency         TEXT NOT NULL DEFAULT 'normal'
                      CHECK (urgency IN ('low','normal','high','urgent')),
    status          TEXT NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open','in_progress','completed','cancelled')),
    deadline_at     TIMESTAMP,
    assigned_to     UUID REFERENCES users(id),     -- técnico asignado
    completed_at    TIMESTAMP,
    cancelled_at    TIMESTAMP,
    cancellation_reason TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_jobs_client ON jobs(client_id);
CREATE INDEX idx_jobs_specialty ON jobs(specialty_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_location ON jobs USING GIST (location);
CREATE INDEX idx_jobs_created ON jobs(created_at DESC);

-- Tabla: job_applications (postulaciones de técnicos)
CREATE TABLE job_applications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id),
    technician_id   UUID NOT NULL REFERENCES users(id),
    cover_letter    TEXT,
    proposed_price  NUMERIC(10,2),
    status          TEXT NOT NULL DEFAULT 'applied'
                      CHECK (status IN ('applied','accepted','rejected','withdrawn')),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_ja_job ON job_applications(job_id);
CREATE INDEX idx_ja_technician ON job_applications(technician_id);
CREATE INDEX idx_ja_status ON job_applications(status);
CREATE UNIQUE INDEX uq_ja_job_tech ON job_applications(job_id, technician_id);

-- Tabla: job_assignments (historial de asignación)
CREATE TABLE job_assignments (
    job_id          UUID NOT NULL REFERENCES jobs(id),
    technician_id   UUID NOT NULL REFERENCES users(id),
    assigned_by     UUID REFERENCES users(id),    -- cliente o admin
    assigned_at     TIMESTAMP NOT NULL DEFAULT now(),
    accepted_at     TIMESTAMP,
    rejected_at     TIMESTAMP,
    rejection_reason TEXT,
    PRIMARY KEY (job_id, technician_id, assigned_at)
);
CREATE INDEX idx_assignment_job ON job_assignments(job_id);
CREATE INDEX idx_assignment_technician ON job_assignments(technician_id);
```

### 3.4 Validación, pagos y reputación

```sql
-- Tabla: job_reviews (reseñas/calificaciones)
CREATE TABLE job_reviews (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id),
    reviewer_id     UUID NOT NULL REFERENCES users(id),
    reviewee_id     UUID NOT NULL REFERENCES users(id),
    rating          INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT,
    is_anonymous    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_review_job ON job_reviews(job_id);
CREATE INDEX idx_review_reviewee ON job_reviews(reviewee_id);
CREATE INDEX idx_review_rating ON job_reviews(rating);
CREATE UNIQUE INDEX uq_review_job ON job_reviews(job_id);

-- Tabla: review_validations (validaciones de calidad de trabajo)
CREATE TABLE review_validations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id),
    supervisor_id   UUID NOT NULL REFERENCES users(id),
    status          TEXT NOT NULL CHECK (status IN ('approved','rejected','needs_revision')),
    score           NUMERIC(4,2),      -- puntuación de calidad 0-10
    notes           TEXT,
    evidence_url    TEXT,              -- foto/documento de verificación
    validated_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_rv_job ON review_validations(job_id);
CREATE INDEX idx_rv_supervisor ON review_validations(supervisor_id);
CREATE INDEX idx_rv_status ON review_validations(status);

-- Tabla: payments (pagos)
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
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_job ON payments(job_id);
CREATE INDEX idx_payments_payer ON payments(payer_id);
CREATE INDEX idx_payments_payee ON payments(payee_id);
CREATE INDEX idx_payments_status ON payments(status);

-- Tabla: documents (documentos anexos: contratos, fotos)
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
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_documents_job ON documents(job_id);
CREATE INDEX idx_documents_uploader ON documents(uploader_id);
CREATE INDEX idx_documents_type ON documents(type);

-- Tabla: notifications (notificaciones)
CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    title           TEXT NOT NULL,
    message         TEXT NOT NULL,
    type            TEXT NOT NULL
                      CHECK (type IN ('job_applied','job_assigned','job_completed','review_added','payment','system')),
    read            BOOLEAN NOT NULL DEFAULT FALSE,
    reference_id    UUID,       -- id del job/app relevante
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_read ON notifications(read);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);
```

### 3.5 KPIs (historico de métricas)

```sql
-- Tabla: kpi_snapshots (snapshot histórico de KPIs)
-- Se calcula periódicamente (worker/cron) y se almacena para reporting rápido
CREATE TABLE kpi_snapshots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type     TEXT NOT NULL CHECK (entity_type IN ('technician','client','platform')),
    entity_id       UUID REFERENCES users(id),     -- nulo para 'platform'
    metric_name     TEXT NOT NULL,
    metric_value    NUMERIC(12,4) NOT NULL,
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_kpi_entity ON kpi_snapshots(entity_type, entity_id);
CREATE INDEX idx_kpi_metric ON kpi_snapshots(metric_name);
CREATE INDEX idx_kpi_period ON kpi_snapshots(period_start DESC);
CREATE INDEX idx_kpi_entity_metric ON kpi_snapshots(entity_type, metric_name);
```

---

## 4. KPIs Integrados

### 4.1 KPIs de Técnico (calculados en tiempo real / snapshot)

| KPI | Fórmula | Frecuencia | Origen SQL |
|---|---|---|---|
| **Tasa de respuesta** | postulaciones/envíos recibidos * 100 | Diario → snapshot | `job_applications` |
| **Tasa de aceptación** | jobs asignados a técnico / jobs ofertados * 100 | Diario | `job_assignments` |
| **Tasa de finalización** | jobs completados / jobs iniciados * 100 | Diario | `jobs` |
| **Rating promedio** | avg(rating) | En tiempo real | `job_reviews` |
| **Tiempo promedio de resolución** | avg(completed_at - created_at) | Diario | `jobs` |
| **Ingresos acumulados** | sum(amount) pagos recibidos | En tiempo real | `payments` |
| **Tasa de arreglo en primera visita** (IT) | jobs sin revisita / jobs completados * 100 | Semanal | `jobs`, `documents` |
| **Adherencia de disponibilidad** | horas disponibles efectivas / horas disponibles planificadas * 100 | Semanal | (config de agenda) |

### 4.2 KPIs de Cliente

| KPI | Fórmula |
|---|---|
| Trabajos publicados | count(jobs) |
| Tiempo promedio de contratación | avg(assigned_to - created_at) |
| Tasa de satisfacción | avg(rating recibida) |
| Gasto total | sum(amount pagado) |

### 4.3 KPIs de Plataforma

| KPI | Fórmula |
|---|---|
| Trabajos creados (mensual) | count(jobs) where period |
| Tasa de finalización global | jobs_completed / jobs_created * 100 |
| Revenue de plataforma | sum(comision) |
| Tasa de activación técnicos | verified_technicians / registered * 100 |

### 4.4 Dashboard de técnico (ejemplo endpoint)

```
GET /api/v1/technicians/{id}/dashboard
{
  "rating": 4.7,
  "jobsCompleted": 142,
  "responseRate": 92.5,
  "completionRate": 96.2,
  "avgResolutionMinutes": 128,
  "monthlyEarnings": 4320.00,
  "availableJobs": 5,
  "certificationsStatus": "valid",
  "rank": 3,
  "trendRating": 0.4
}
```

---

## 5. Validaciones (Business Rules)

### 5.1 Registro / Autenticación
- Email único y verificado (token de verificación).
- Password: mínimo 8 caracteres, 1 mayúscula, 1 número, 1 símbolo.
- Teléfono opcional pero único si se provee.

### 5.2 Técnico
- `role = 'technician'` requiere `profiles.service_radius_km > 0`.
- Al menos una `technician_specialties` activa.
- Al menos una certificación con `validation_status='valid'` (opcional según especialidad).
- Certificaciones vencidas (`expires_at < now`) → marcar inválidas, bloquear ofertas.

### 5.3 Publicación de trabajo
- `budget_min <= budget_max` (ambos > 0).
- `location` (point) + `location_label` requeridos si `is_remote=false`.
- `deadline_at >= created_at` si se provee.
- `specialty_id` válido.
- Si `assigned_to IS NOT NULL` → técnico debe tener esa especialidad.

### 5.4 Asignación / Postulación
- Técnico solo puede postular si tiene la `specialty_id` del job.
- Técnico dentro del `service_radius_km` del job (cálculo GIS).
- No postular al propio job del cliente.
- Un job solo puede tener un `status='in_progress'` activo por técnico.

### 5.5 Validación / Revisión
- `review_validations` requiere `supervisor_id` con role supervisor/admin.
- `score` (0-10) requerido al aprobar.
- `evidence_url` recomendado al aprobar (validación de trabajo real).
- Pago se libera solo si `review_validation.status='approved'`.

### 5.6 Pagos
- `amount <= budget_max` del job.
- No crear pago si job `status != 'completed'`.
- `payer_id` debe ser el cliente dueño del job.
- `payee_id` debe ser el técnico asignado.

### 5.7 Reputación
- `job_reviews` solo si job `status='completed'` y reviewer es cliente/técnico correspondiente.
- Una reseña por job (unique `job_id`).
- Rating 1-5 obligatorio.

---

## 6. Endpoints de API (REST + OpenAPI)

### 6.1 Auth
```
POST   /api/v1/auth/register
POST   /api/v1/auth/login          { email, password } → { access_token, refresh_token }
POST   /api/v1/auth/refresh
POST   /api/v1/auth/verify-email   { token }
POST   /api/v1/auth/forgot-password
POST   /api/v1/auth/reset-password { token, new_password }
```

### 6.2 Usuarios / Perfiles
```
GET    /api/v1/users/me
PUT    /api/v1/users/me/profile
GET    /api/v1/users/{id}          (solo público lo esencial)
GET    /api/v1/specialties
```

### 6.3 Técnicos
```
GET    /api/v1/technicians             ?filters (specialty, location, minRating, radius)
GET    /api/v1/technicians/{id}
GET    /api/v1/technicians/{id}/dashboard
GET    /api/v1/technicians/{id}/reviews
POST   /api/v1/technicians/{id}/certificates     (subir certificado)
GET    /api/v1/technicians/{id}/certificates
```

### 6.4 Trabajos
```
GET    /api/v1/jobs                    ?filters (specialty, status, client)
POST   /api/v1/jobs
GET    /api/v1/jobs/{id}
PUT    /api/v1/jobs/{id}
DELETE /api/v1/jobs/{id}               (cancelar, con motivo)
POST   /api/v1/jobs/{id}/assign         (asignar técnico / aceptar)
POST   /api/v1/jobs/{id}/apply          (postulación)
GET    /api/v1/jobs/{id}/applications
POST   /api/v1/jobs/{id}/complete
GET    /api/v1/jobs/{id}/reviews
POST   /api/v1/jobs/{id}/reviews
```

### 6.5 Validaciones / Supervisión
```
POST   /api/v1/jobs/{id}/validations
GET    /api/v1/jobs/{id}/validations
PUT    /api/v1/jobs/{id}/validations/{vId}
```

### 6.6 Pagos
```
POST   /api/v1/payments                (crear intención de pago)
GET    /api/v1/payments?user=...
GET    /api/v1/payments/{id}
```

### 6.7 Notificaciones
```
GET    /api/v1/notifications
POST   /api/v1/notifications/read       (marcar todas leídas)
WS     /ws/notifications               (tiempo real)
```

---

## 7. Worker / Cron (procesos en background)

| Worker | Responsabilidad | Periodicidad |
|---|---|---|
| KpiAggregator | Calcula `kpi_snapshots` desde tablas transaccionales | Cada hora |
| CertExpiryNotifier | Alertas de certificaciones próximas a vencer | Diario |
| StaleJobCleaner | Cancela jobs "open" vencidos (`deadline_at`) | Diario |
| PaymentReleaser | Libera pago al técnico si validation aprobada | Cada 5 min |
| LocationGeoCoder | Geocodifica `location_label` → point | On-demand |

---

## 8. Seguridad

- **Hashing**: bcrypt (salto 12) para passwords.
- **JWT**: access_token (15 min) + refresh_token (7 días), httpOnly.
- **Roles/Policies**: Guards en NestJS (`@Roles('technician')`).
- **Rate limit**: express-rate-limit (auth: 5 req/min; API: 100 req/min).
- **CORS**: whitelist de dominios.
- **Input validation**: `class-validator` + sanitización (sanitize-html).
- **PII**: encriptación en reposo de teléfonos; GDPR delete request → soft-delete.

---

## 9. Consideraciones de rendimiento

- Índices GIS (`GIST`) en `location` para búsquedas de proximidad.
- Índices compuestos en `jobs(status, specialty_id, created_at)` para listados.
- Trigrama index (`pg_trgm`) en `users.email`, `specialties.name` para LIKE rápido.
- Materialized views para KPIs de plataforma (refresco horario).
- Cacheo Redis de `/technicians/{id}/dashboard` (TTL 5 min).

---

## 10. Próximos pasos

1. Crear migrations SQL (basadas en este esquema).
2. Generar DTOs y entidades NestJS.
3. Scaffold de frontend con rutas protegidas por rol.
4. Tests: unit (Jest) de servicios + e2e (Cypress) de flujo completo.
