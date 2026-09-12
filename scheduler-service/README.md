# Scheduler Service — Microservicio de Horarios

Gestiona horarios de disponibilidad de terapeutas, verifica disponibilidad de citas y mantiene un cache local de terapeutas.

## 📁 Estructura

```
scheduler-service/
├── app.py              # API REST
├── db.py               # Conexión a MySQL
├── scheduler_db.sql    # Schema (horarios + cache de terapeutas)
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
├── .env / .env.example
└── README.md
```

## 🚀 Despliegue con Docker

```bash
cd scheduler-service
cp .env.example .env
docker-compose up --build -d
```

- **Service**: http://localhost:5002
- **MySQL**: localhost:3308

## 🚀 Despliegue en alwaysdata

1. Crear BD `scheduler_db` → importar `scheduler_db.sql`
2. Crear app Python → apuntar a `app.py`
3. Configurar env vars

## 🔌 API Endpoints

| Método | Ruta | Límite | Descripción |
|---|---|---|---|
| GET | `/api/horarios?terapeuta_id=1` | 60/min | Listar horarios activos de un terapeuta |
| POST | `/api/horarios` | 20/min | Crear o actualizar un horario (upsert) |
| PUT | `/api/horarios/{id}` | 20/min | Modificar horario existente |
| DELETE | `/api/horarios/{id}` | 10/min | Desactivar horario (soft delete) |
| POST | `/api/disponibilidad` | 30/min | Verificar disponibilidad por día/hora |
| PUT | `/api/terapeutas/cache` | 10/min | Sincronizar cache de terapeutas desde auth-service |

## 🔐 Autenticación

Header requerido:
```
X-Scheduler-Key: scheduler-api-key-2025-xK9mP3qL
```

## 🔗 Integración con appointment-service

El endpoint `/api/disponibilidad` consulta al appointment-service para verificar si ya existe una cita:
```
APPOINTMENT_SERVICE_URL=http://appointment-service:5003
APPOINTMENT_API_KEY=<key>
```

## 📊 Base de datos (scheduler_db)

| Tabla | Propósito |
|---|---|
| `horarios_medico` | Horarios semanales por terapeuta (0=lun ... 6=dom) |
| `terapeutas_cache` | Cache local de terapeutas (sync via API) |
| `excepciones_fecha` | Días bloqueados/desactivados (feriados) |
| `logs_resumen_diario` | View de resumen de disponibilidad |

## 🔄 Sincronización de terapeutas

El auth-service (o un job) debe sincronizar terapeutas al scheduler:
```bash
curl -X PUT http://scheduler:5002/api/terapeutas/cache \
  -H "X-Scheduler-Key: <key>" \
  -H "Content-Type: application/json" \
  -d '{"terapeutas": [{"id":1,"nombre":"Dr. X","especialidad":"Fisioterapia","activo":1}]}'
```
