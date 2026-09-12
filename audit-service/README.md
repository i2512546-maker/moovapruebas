# Audit Service — Microservicio de Auditoría

Servicio independiente que captura logs de auditoría de forma asíncrona y expone una API REST para consultas.

## 📁 Estructura

```
audit-service/
├── app.py              # API REST del servicio de auditoría
├── db.py               # Conexión a MySQL
├── audit_db.sql        # Schema de la base audit_db
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
├── .env                # Configuración (crear a partir de .env.example)
└── .env.example
```

## 🚀 Despliegue con Docker (desarrollo local)

```bash
cd audit-service
cp .env.example .env
docker-compose up --build -d
```

El servicio quedará disponible en: `http://localhost:5001`

La base `audit_db` escuchará en el puerto `3307` (host).

## 🚀 Despliegue en alwaysdata (producción)

### Paso 1: Crear la base de datos
1. Accede al panel de alwaysdata → Bases de datos
2. Crea una nueva base: `audit_db`
3. Importa `audit_db.sql` desde phpMyAdmin

### Paso 2: Crear la aplicación Python
1. Panel alwaysdata → Aplicaciones → Crear una aplicación
2. Tipo: Python 3.11
3. Ruta: `/home/user/audit-service/`
4. En "Ejecución", usa:
   ```bash
   pip install -r requirements.txt
   python app.py
   ```

### Paso 3: Configurar variables de entorno
En el panel de alwaysdata → Aplicación → Variables de entorno:
```
DB_HOST=mysql-moovacloud.alwaysdata.net
DB_USER=moovacloud
DB_PASSWORD=$Mo0vaCl1nic//
DB_NAME=audit_db
DB_PORT=3306
AUDIT_API_KEY=audit-api-key-2025-xK9mP3qL
FLASK_SECRET_KEY=audit-secret-key-change-me
```

## 🔌 Integración con app.py principal

El app principal (`moovafinal-main/app.py`) envía logs asíncronos al audit-service.

En el `.env` principal, configura:
```
AUDIT_SERVICE_URL=https://audit-tudominio.alwaysdata.net
AUDIT_API_KEY=audit-api-key-2025-xK9mP3qL
```

Cuando `AUDIT_SERVICE_URL` está configurada, los logs se envían vía HTTP async.
Si el service está caído, hay un fallback que escribe localmente en `logs_auditoria` (mientras migras).

## 📋 API Endpoints

| Método | Endpoint | Descripción |
|---|---|---|
| POST | `/api/logs` | Crear un log (usado por app principal) |
| POST | `/api/logs/batch` | Crear múltiples logs en un request |
| GET | `/api/logs` | Listar logs con filtros (tipo, acción, rango de fechas) |
| GET | `/api/logs/resumen` | Resumen diario de acciones |
| POST | `/api/logs/limpiar` | Borrar logs antiguos (máx. 30 días) |

## 🔐 Autenticación

Todas las requests llevan el header:
```
X-Audit-Key: audit-api-key-2025-xK9mP3qL
```

## 🗃️ Permisos recomendados

```sql
GRANT INSERT, SELECT ON audit_db.* TO 'moovacloud'@'%';
FLUSH PRIVILEGES;
```
