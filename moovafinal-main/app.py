import os
import secrets
import threading
from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
from flask_bcrypt import Bcrypt
from flask_wtf.csrf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.middleware.proxy_fix import ProxyFix
from functools import wraps
from datetime import datetime, timedelta
import requests as http_requests
from apscheduler.schedulers.background import BackgroundScheduler
from db import get_connection
from collections import defaultdict
from dotenv import load_dotenv

load_dotenv()

# -----------------------------------------------
# BLOQUEO / BANEO POR IP
# -----------------------------------------------
MAX_INTENTOS_IP = 3
TIEMPO_BLOQUEO  = 2   # minutos

ip_bloqueadas = defaultdict(lambda: {
    "intentos": 0,
    "bloqueado_hasta": None
})


def obtener_ip():
    """Obtiene la IP real del cliente usando ProxyFix (se confia en X-Forwarded-For
    solo cuando hay un proxy confiable configurado delante)."""
    return request.remote_addr


def ip_esta_bloqueada(ip):
    """Verifica si una IP está bloqueada. Desbloquea automáticamente si expiró."""
    datos = ip_bloqueadas[ip]
    if datos["bloqueado_hasta"]:
        if datetime.now() < datos["bloqueado_hasta"]:
            return True
        else:
            datos["intentos"] = 0
            datos["bloqueado_hasta"] = None
    return False


def registrar_intento_fallido(ip):
    """Registra un intento fallido y bloquea la IP si supera el límite."""
    datos = ip_bloqueadas[ip]
    datos["intentos"] += 1
    if datos["intentos"] >= MAX_INTENTOS_IP:
        datos["bloqueado_hasta"] = datetime.now() + timedelta(minutes=TIEMPO_BLOQUEO)
        app.logger.warning(f"IP BLOQUEADA: {ip}")


def limpiar_intentos(ip):
    """Limpia los intentos fallidos de una IP (login exitoso)."""
    ip_bloqueadas[ip]["intentos"] = 0
    ip_bloqueadas[ip]["bloqueado_hasta"] = None


def registrar_log(usuario_tipo, usuario_id, usuario_nombre, accion, detalles=None,
                  ip_origen=None, user_agent=None, terapeuta_id=None, cita_id=None):
    """Registra una accion en la tabla logs_auditoria para auditoria de seguridad.

    Envio principal: async via HTTP al audit-service (no bloquea el request).
    Fallback: si el service no responde, escribe localmente en la BD principal.
    """
    payload = {
        "usuario_tipo": usuario_tipo,
        "usuario_id": usuario_id,
        "usuario_nombre": usuario_nombre,
        "accion": accion,
        "detalles": detalles,
        "ip_origen": ip_origen,
        "user_agent": user_agent,
        "terapeuta_id": terapeuta_id,
        "cita_id": cita_id,
    }

    if AUDIT_SERVICE_URL and AUDIT_API_KEY:
        # Envio asincrono al microservicio de auditoria
        thread = threading.Thread(target=_enviar_log_async, args=(payload,), daemon=True)
        thread.start()
    else:
        # Fallback: escritura local (usar durante migracion o si el service esta caido)
        try:
            conn   = get_connection()
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO logs_auditoria
                    (usuario_tipo, usuario_id, usuario_nombre, accion, detalles,
                     ip_origen, user_agent, terapeuta_id, cita_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (usuario_tipo, usuario_id, usuario_nombre, accion, detalles,
                  ip_origen, user_agent, terapeuta_id, cita_id))
            conn.commit()
            conn.close()
        except Exception:
            pass  # No fallar si la tabla local no existe todavia


app = Flask(__name__)

# -----------------------------------------------
# CONFIGURACIÓN DE SEGURIDAD
# -----------------------------------------------
app.secret_key = os.environ.get("FLASK_SECRET_KEY")
if not app.secret_key:
    raise RuntimeError("FLASK_SECRET_KEY no esta configurada en las variables de entorno.")

bcrypt = Bcrypt(app)

# Proteccion CSRF global
csrf = CSRFProtect(app)

# ProxyFix: se confia en X-Forwarded-For solo cuando hay un proxy confiable delante.
# Nunca confiar en este header sin un proxy inverso configurado.
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)

# Rate limiter (memory backend — usar Redis en produccion)
limiter = Limiter(
    key_func=get_remote_address,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://",
)

# Cookies de sesion seguras
app.config.update(
    SESSION_COOKIE_SECURE=os.environ.get("FLASK_ENV") == "production",
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    WTF_CSRF_TIME_LIMIT=3600,
    PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
)

# -----------------------------------------------
# CONFIGURACIÓN DE APIS (credenciales desde env)
# -----------------------------------------------
APIPERU_TOKEN     = os.environ.get("APIPERU_TOKEN", "")
APIPERU_URL       = "https://dniruc.apisperu.com/api/v1/dni/{dni}?token={token}"

TEXTBEE_API_KEY   = os.environ.get("TEXTBEE_API_KEY", "")
TEXTBEE_DEVICE_ID = os.environ.get("TEXTBEE_DEVICE_ID", "")
TEXTBEE_URL       = "https://api.textbee.dev/api/v1/gateway/devices/{device_id}/send-sms"

API_KEY           = os.environ.get("API_KEY", "")
if not API_KEY:
    raise RuntimeError("API_KEY no esta configurada en las variables de entorno.")

OTP_EXPIRA_MIN    = 10
OTP_MAX_INTENTOS  = 3

# -------------------------------------------------------------------
# Configuracion del Audit Service (envio asincrono de logs)
# -------------------------------------------------------------------
AUDIT_SERVICE_URL = os.environ.get("AUDIT_SERVICE_URL", "")
AUDIT_API_KEY     = os.environ.get("AUDIT_API_KEY", "")


def _enviar_log_async(payload):
    """Envia un log al audit-service de forma asincrona (no bloqueante)."""
    if not AUDIT_SERVICE_URL or not AUDIT_API_KEY:
        return
    try:
        http_requests.post(
            AUDIT_SERVICE_URL + "/api/logs",
            json=payload,
            headers={"X-Audit-Key": AUDIT_API_KEY},
            timeout=3
        )
    except Exception:
        pass  # Fallar silenciosamente: la auditoria no debe interrumpir el flujo principal


# ===============================================
# Headers de seguridad
# ===============================================
@app.after_request
def set_security_headers(resp):
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["X-XSS-Protection"] = "1; mode=block"
    resp.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    resp.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    resp.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://fonts.googleapis.com https://t.contentsquare.com; "
        "style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://fonts.googleapis.com; "
        "img-src 'self' data: https:; "
        "font-src 'self' https://fonts.gstatic.com https://cdnjs.cloudflare.com; "
        "connect-src 'self'; "
        "frame-ancestors 'none';"
    )
    return resp


# ===============================================================
# AUTOMATIZACIÓN 1 — VERIFICACIÓN DE DISPONIBILIDAD DEL MÉDICO
# ===============================================================
def medico_disponible(medico_id, fecha_cita, excluir_cita_id=None):
    """
    Verifica si el médico tiene disponibilidad en la fecha indicada.
    Retorna True si NO tiene citas programadas ese día.
    El parámetro excluir_cita_id evita que al modificar una cita
    el sistema la cuente como conflicto consigo misma.
    """
    conn   = get_connection()
    cursor = conn.cursor()
    if excluir_cita_id:
        cursor.execute("""
            SELECT COUNT(*) FROM historial_citas
            WHERE terapeuta_id = %s
              AND fecha_cita   = %s
              AND estado       = 'programada'
              AND id          != %s
        """, (medico_id, fecha_cita, excluir_cita_id))
    else:
        cursor.execute("""
            SELECT COUNT(*) FROM historial_citas
            WHERE terapeuta_id = %s
              AND fecha_cita   = %s
              AND estado       = 'programada'
        """, (medico_id, fecha_cita))
    (count,) = cursor.fetchone()
    conn.close()
    return count == 0


# ===============================================================
# AUTOMATIZACIÓN 2 — SMS DE CONFIRMACIÓN AL PACIENTE
# ===============================================================
def _normalizar_telefono(telefono):
    """Normaliza un teléfono peruano al formato internacional +51XXXXXXXXX."""
    tel = telefono.strip().replace(" ", "").replace("-", "")
    if tel.startswith("0"):
        tel = tel[1:]
    if not tel.startswith("+"):
        tel = "+51" + tel
    return tel


def _enviar_sms(telefono, mensaje):
    """
    Función base para enviar SMS via TextBee (https://textbee.dev).
    Retorna True si el envío fue exitoso.
    """
    try:
        tel = _normalizar_telefono(telefono)
        url = TEXTBEE_URL.format(device_id=TEXTBEE_DEVICE_ID)
        resp = http_requests.post(
            url,
            json={"recipients": [tel], "message": mensaje},
            headers={"x-api-key": TEXTBEE_API_KEY},
            timeout=10
        )
        if resp.status_code in (200, 201):
            return True
        app.logger.error(f"TextBee error {resp.status_code}: {resp.text}")
        return False
    except Exception as e:
        app.logger.error(f"TextBee error: {e}")
        return False


def enviar_sms_confirmacion_paciente(telefono, nombre_paciente, nombre_medico,
                                      especialidad, fecha_cita):
    """
    Envía SMS al paciente confirmando que su cita fue agendada exitosamente.
    Se activa automáticamente al crear una cita nueva.
    """
    try:
        fecha_fmt = datetime.strptime(str(fecha_cita), "%Y-%m-%d").strftime("%d/%m/%Y")
    except Exception:
        fecha_fmt = str(fecha_cita)

    mensaje = (
        f"MOOVA Clinic: Hola {nombre_paciente}, tu cita fue confirmada. "
        f"Medico: {nombre_medico} ({especialidad}). "
        f"Fecha: {fecha_fmt}. "
        f"Para modificar o cancelar ingresa a nuestra web."
    )
    return _enviar_sms(telefono, mensaje)


# ===============================================================
# AUTOMATIZACIÓN 3 — NOTIFICACIÓN SMS AL MÉDICO
# ===============================================================
def enviar_sms_notificacion_medico(telefono_medico, nombre_medico,
                                    nombre_paciente, fecha_cita):
    """
    Notifica al médico por SMS cuando le asignan un nuevo paciente.
    Si el médico no tiene teléfono registrado, no hace nada.
    Se activa automáticamente al crear una cita nueva.
    """
    if not telefono_medico:
        return False

    try:
        fecha_fmt = datetime.strptime(str(fecha_cita), "%Y-%m-%d").strftime("%d/%m/%Y")
    except Exception:
        fecha_fmt = str(fecha_cita)

    mensaje = (
        f"MOOVA Clinic: Dr(a). {nombre_medico}, "
        f"se agendo una nueva cita. "
        f"Paciente: {nombre_paciente}. "
        f"Fecha: {fecha_fmt}."
    )
    return _enviar_sms(telefono_medico, mensaje)


# ===============================================================
# AUTOMATIZACIÓN 4 — RECORDATORIO AUTOMÁTICO 24H ANTES
# ===============================================================
def enviar_recordatorios_24h():
    """
    Tarea programada que se ejecuta cada hora via APScheduler.
    Busca todas las citas programadas para mañana que aún no
    recibieron recordatorio (recordatorio_enviado = 0) y envía
    SMS tanto al paciente como al médico.
    Marca cada cita con recordatorio_enviado = 1 para no duplicar.
    """
    manana = (datetime.today() + timedelta(days=1)).strftime("%Y-%m-%d")
    try:
        conn   = get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT h.id, h.fecha_cita,
                   p.nombre, p.apellido, p.telefono,
                   t.Nombre      AS medico,
                   t.Especialidad,
                   t.Telefono    AS telefono_medico
            FROM historial_citas h
            JOIN personas   p ON h.persona_id   = p.id
            JOIN terapeutas t ON h.terapeuta_id = t.ID
            WHERE h.fecha_cita = %s
              AND h.estado = 'programada'
              AND (h.recordatorio_enviado IS NULL OR h.recordatorio_enviado = 0)
        """, (manana,))
        citas = cursor.fetchall()

        for cita in citas:
            nombre_completo = f"{cita['nombre']} {cita['apellido']}"
            fecha_fmt = datetime.strptime(
                str(cita["fecha_cita"]), "%Y-%m-%d"
            ).strftime("%d/%m/%Y")

            # SMS al paciente
            msg_paciente = (
                f"MOOVA Clinic: Recordatorio - tienes una cita manana {fecha_fmt} "
                f"con {cita['medico']} ({cita['Especialidad']}). "
                f"Ante cualquier cambio ingresa a nuestra web."
            )
            _enviar_sms(cita["telefono"], msg_paciente)

            # SMS al médico (solo si tiene teléfono registrado)
            if cita.get("telefono_medico"):
                msg_medico = (
                    f"MOOVA Clinic: Recordatorio - manana {fecha_fmt} "
                    f"tienes cita con {nombre_completo}."
                )
                _enviar_sms(cita["telefono_medico"], msg_medico)

            # Marcar como enviado para no duplicar
            cursor.execute(
                "UPDATE historial_citas SET recordatorio_enviado = 1 WHERE id = %s",
                (cita["id"],)
            )

        conn.commit()
        conn.close()
        app.logger.info(
            f"[Recordatorios] {len(citas)} cita(s) notificadas para {manana}."
        )
    except Exception as e:
        app.logger.error(f"[Recordatorios] Error: {e}")


# -----------------------------------------------
# HELPERS OTP (para modificar/cancelar citas)
# -----------------------------------------------
def generar_otp():
    """Genera un codigoOTP de 6 digitos usando generador criptografico seguro."""
    return str(secrets.randbelow(900000) + 100000)


def enviar_sms_otp(telefono, codigo, accion):
    """Envía el SMS con código OTP para verificar identidad del paciente."""
    verbo   = "modificar" if accion == "modificar" else "cancelar"
    mensaje = (
        f"MOOVA Clinic: Tu codigo para {verbo} tu cita es {codigo}. "
        f"Valido por {OTP_EXPIRA_MIN} minutos. "
        f"No compartas este codigo."
    )
    return _enviar_sms(telefono, mensaje)


def guardar_otp(dni, codigo, accion):
    """Guarda el OTP en BD, invalidando códigos anteriores del mismo DNI+acción."""
    expira = datetime.now() + timedelta(minutes=OTP_EXPIRA_MIN)
    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE otp_verificaciones SET usado = 1 WHERE dni = %s AND accion = %s AND usado = 0",
        (dni, accion)
    )
    cursor.execute(
        "INSERT INTO otp_verificaciones (dni, codigo, accion, expira_en) VALUES (%s, %s, %s, %s)",
        (dni, codigo, accion, expira)
    )
    conn.commit()
    conn.close()


def verificar_otp(dni, codigo_ingresado, accion):
    """
    Verifica el OTP ingresado. Retorna:
      'ok'             — código correcto
      'incorrecto:N'   — código incorrecto, N intentos restantes
      'expirado'       — pasaron los 10 minutos
      'agotado'        — superó los intentos máximos
      'no_existe'      — no hay OTP activo para ese DNI
    """
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("""
        SELECT * FROM otp_verificaciones
        WHERE dni = %s AND accion = %s AND usado = 0
        ORDER BY creado_en DESC
        LIMIT 1
    """, (dni, accion))
    otp = cursor.fetchone()

    if not otp:
        conn.close()
        return "no_existe"

    if otp["intentos"] >= OTP_MAX_INTENTOS:
        conn.close()
        return "agotado"

    if datetime.now() > otp["expira_en"]:
        conn.close()
        return "expirado"

    if otp["codigo"] != codigo_ingresado.strip():
        cursor.execute(
            "UPDATE otp_verificaciones SET intentos = intentos + 1 WHERE id = %s",
            (otp["id"],)
        )
        conn.commit()
        conn.close()
        restantes = OTP_MAX_INTENTOS - otp["intentos"] - 1
        return f"incorrecto:{restantes}"

    cursor.execute(
        "UPDATE otp_verificaciones SET usado = 1 WHERE id = %s",
        (otp["id"],)
    )
    conn.commit()
    conn.close()
    return "ok"


# -----------------------------------------------
# HELPER APISperú — verificación de DNI
# -----------------------------------------------
def consultar_dni_apiperu(dni):
    """Consulta la API de APISperú para obtener datos del DNI."""
    try:
        url  = APIPERU_URL.format(dni=dni, token=APIPERU_TOKEN)
        resp = http_requests.get(url, headers={"Accept": "application/json"}, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            if data.get("success"):
                return data
    except Exception as e:
        app.logger.error(f"Error al consultar DNI {dni}: {e}")
    return None


# -----------------------------------------------
# DECORADORES
# -----------------------------------------------
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        ip = obtener_ip()
        if ip_esta_bloqueada(ip):
            flash(f"Tu IP está bloqueada temporalmente por {TIEMPO_BLOQUEO} minutos.")
            return redirect(url_for("login"))
        if "usuario" not in session and "admin" not in session:
            registrar_intento_fallido(ip)
            flash("Debes iniciar sesión.")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated_function


def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        ip = obtener_ip()
        if ip_esta_bloqueada(ip):
            flash(f"Tu IP está bloqueada temporalmente por {TIEMPO_BLOQUEO} minutos.")
            return redirect(url_for("login"))
        if "admin" not in session:
            registrar_intento_fallido(ip)
            flash("Acceso denegado.")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated_function


def api_key_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        ip = obtener_ip()
        if ip_esta_bloqueada(ip):
            return jsonify({"error": "IP bloqueada temporalmente"}), 403
        api_key = request.headers.get("X-API-Key", "")
        if api_key != API_KEY:
            registrar_intento_fallido(ip)
            return jsonify({"error": "API key invalida o ausente"}), 401
        limpiar_intentos(ip)
        return f(*args, **kwargs)
    return decorated


# -----------------------------------------------
# RUTAS
# -----------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    ip = obtener_ip()
    if ip_esta_bloqueada(ip):
        flash(f"Tu IP ha sido bloqueada temporalmente por {TIEMPO_BLOQUEO} minutos.")
        return render_template("login.html")

    if request.method == "POST":
        correo = request.form["correo"].strip()
        clave  = request.form["clave"].strip()

        if not correo or not clave:
            flash("Completa todos los campos.")
            return redirect(url_for("login"))

        conn   = get_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("SELECT * FROM admins WHERE correo = %s", (correo,))
        admin = cursor.fetchone()

        if admin:
            if bcrypt.check_password_hash(admin["clave"], clave):
                session["admin"]    = admin["nombre"]
                session["admin_id"] = admin["id"]
                limpiar_intentos(ip)
                conn.close()
                registrar_log("admin", admin["id"], admin["nombre"], "login",
                              detalles="Inicio de sesion exitoso",
                              ip_origen=ip,
                              user_agent=request.headers.get("User-Agent", ""))
                return redirect(url_for("panel_admin"))
            else:
                registrar_intento_fallido(ip)
                flash("Contrasena incorrecta.")
                conn.close()
                return redirect(url_for("login"))

        cursor.execute("SELECT * FROM terapeutas WHERE Correo = %s AND activo = 1", (correo,))
        medico = cursor.fetchone()
        conn.close()

        if medico:
            if bcrypt.check_password_hash(medico["Clave"], clave):
                session["usuario"]   = medico["Nombre"]
                session["medico_id"] = medico["ID"]
                limpiar_intentos(ip)
                registrar_log("terapeuta", medico["ID"], medico["Nombre"], "login",
                              detalles="Inicio de sesion exitoso",
                              ip_origen=ip,
                              user_agent=request.headers.get("User-Agent", ""))
                return redirect(url_for("interfaz"))
            else:
                registrar_intento_fallido(ip)
                flash("Contrasena incorrecta.")
        else:
            registrar_intento_fallido(ip)
            flash("El usuario no existe.")

        return redirect(url_for("login"))

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# -----------------------------------------------
# AGENDAR CITA
# Automatizaciones 1, 2 y 3 activas aquí
# -----------------------------------------------
@app.route("/citas", methods=["GET", "POST"])
def citas():
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT ID, Nombre, Especialidad FROM terapeutas WHERE activo = 1")
    terapeutas = cursor.fetchall()

    if request.method == "POST":
        nombre     = request.form.get("nombre", "").strip()
        apellido   = request.form.get("apellido", "").strip()
        dni        = request.form.get("dni", "").strip()
        telefono   = request.form.get("telefono", "").strip()
        medico_id  = request.form.get("medico_id", "").strip()
        fecha_cita = request.form.get("fecha_cita", "").strip()

        if not all([nombre, apellido, dni, telefono, medico_id, fecha_cita]):
            flash("campos_vacios")
            conn.close()
            return redirect(url_for("citas"))

        try:
            fecha_obj = datetime.strptime(fecha_cita, "%Y-%m-%d").date()
            if fecha_obj < datetime.today().date():
                flash("fecha_pasada")
                conn.close()
                return redirect(url_for("citas"))
        except ValueError:
            flash("campos_vacios")
            conn.close()
            return redirect(url_for("citas"))

        # AUTOMATIZACIÓN 1: bloquear si el médico ya tiene cita ese día
        if not medico_disponible(medico_id, fecha_cita):
            flash("Horario Ocupado, Elija otra fecha por favor.")
            conn.close()
            return redirect(url_for("citas"))

        cursor.execute("SELECT id FROM personas WHERE dni = %s", (dni,))
        persona = cursor.fetchone()

        if persona:
            persona_id = persona["id"]
        else:
            cursor.execute(
                "INSERT INTO personas (nombre, apellido, dni, telefono) VALUES (%s, %s, %s, %s)",
                (nombre, apellido, dni, telefono)
            )
            conn.commit()
            persona_id = cursor.lastrowid

        cursor.execute(
            "INSERT INTO historial_citas (persona_id, terapeuta_id, fecha_cita, estado) "
            "VALUES (%s, %s, %s, 'programada')",
            (persona_id, medico_id, fecha_cita)
        )
        conn.commit()
        cita_id = cursor.lastrowid

        cursor.execute(
            "SELECT Nombre, Especialidad, Telefono FROM terapeutas WHERE ID = %s",
            (medico_id,)
        )
        medico = cursor.fetchone()
        conn.close()

        # AUTOMATIZACIÓN 2: SMS de confirmación al paciente
        enviar_sms_confirmacion_paciente(
            telefono, nombre,
            medico["Nombre"], medico["Especialidad"], fecha_cita
        )

        # AUTOMATIZACIÓN 3: notificación SMS al médico
        enviar_sms_notificacion_medico(
            medico.get("Telefono"), medico["Nombre"],
            f"{nombre} {apellido}", fecha_cita
        )

        registrar_log("paciente", None, f"{nombre} {apellido}", "crear_cita",
                      detalles=f"Cita #{cita_id} - Dr(a). {medico['Nombre']} - {fecha_cita}",
                      ip_origen=obtener_ip(),
                      user_agent=request.headers.get("User-Agent", ""),
                      terapeuta_id=int(medico_id) if medico_id.isdigit() else None,
                      cita_id=cita_id)

        return redirect(url_for("retorno", cita_id=cita_id))

    conn.close()
    return render_template("citas.html", terapeutas=terapeutas)


@app.route("/api/verificar_dni", methods=["POST"])
@limiter.limit("10/minute")
def verificar_dni_ajax():
    dni = (request.json or {}).get("dni", "").strip()
    if len(dni) != 8 or not dni.isdigit():
        return jsonify({"success": False, "error": "DNI invalido"}), 400
    data = consultar_dni_apiperu(dni)
    if data:
        return jsonify({"success": True, "data": data})
    return jsonify({"success": False, "error": "DNI no encontrado"}), 404


@app.route("/api/disponibilidad", methods=["POST"])
@limiter.limit("30/minute")
def verificar_disponibilidad_ajax():
    """Endpoint AJAX para verificar disponibilidad del médico desde el frontend."""
    data         = request.get_json() or {}
    medico_id    = data.get("medico_id", "")
    fecha_cita   = data.get("fecha_cita", "")
    excluir_cita = data.get("excluir_cita_id")

    if not medico_id or not fecha_cita:
        return jsonify({"error": "Se requieren medico_id y fecha_cita"}), 400

    disponible = medico_disponible(medico_id, fecha_cita, excluir_cita)
    return jsonify({"disponible": disponible})


@app.route("/citas/modificar", methods=["GET", "POST"])
def modificar_cita():
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT ID, Nombre, Especialidad FROM terapeutas WHERE activo = 1")
    terapeutas = cursor.fetchall()

    if request.method == "POST":
        accion = request.form.get("accion")

        if accion == "solicitar":
            dni = request.form.get("dni", "").strip()
            if not dni or len(dni) != 8 or not dni.isdigit():
                conn.close()
                return render_template("modificar_cita.html",
                    error="Ingresa un DNI válido (8 dígitos).",
                    terapeutas=terapeutas)

            cursor.execute("""
                SELECT p.telefono FROM personas p
                JOIN historial_citas h ON h.persona_id = p.id
                WHERE p.dni = %s AND h.estado = 'programada'
                LIMIT 1
            """, (dni,))
            persona = cursor.fetchone()
            conn.close()

            if not persona:
                return render_template("modificar_cita.html",
                    error="No se encontraron citas programadas para ese DNI.",
                    terapeutas=terapeutas)

            codigo  = generar_otp()
            guardar_otp(dni, codigo, "modificar")
            enviado = enviar_sms_otp(persona["telefono"], codigo, "modificar")

            if not enviado:
                return render_template("modificar_cita.html",
                    error="No se pudo enviar el SMS. Intenta de nuevo.",
                    terapeutas=terapeutas)

            tel      = persona["telefono"].strip()
            tel_mask = tel[:3] + "***" + tel[-3:] if len(tel) >= 6 else "***"
            return render_template("modificar_cita.html",
                paso="verificar", dni=dni, tel_mask=tel_mask,
                terapeutas=terapeutas)

        elif accion == "verificar":
            dni       = request.form.get("dni", "").strip()
            codigo    = request.form.get("otp", "").strip()
            resultado = verificar_otp(dni, codigo, "modificar")

            if resultado == "ok":
                cursor.execute("""
                    SELECT h.id, h.fecha_cita, h.estado,
                           p.nombre, p.apellido, p.dni,
                           t.Nombre AS terapeuta, t.Especialidad, h.terapeuta_id
                    FROM historial_citas h
                    JOIN personas p ON h.persona_id = p.id
                    JOIN terapeutas t ON h.terapeuta_id = t.ID
                    WHERE p.dni = %s AND h.estado = 'programada'
                    ORDER BY h.fecha_cita ASC
                """, (dni,))
                citas_encontradas = cursor.fetchall()
                conn.close()
                return render_template("modificar_cita.html",
                    citas=citas_encontradas, terapeutas=terapeutas,
                    verificado=True)

            conn.close()
            mensajes = {
                "expirado":  "El código expiró. Solicita uno nuevo.",
                "agotado":   f"Superaste los {OTP_MAX_INTENTOS} intentos. Solicita un nuevo código.",
                "no_existe": "No hay un código activo. Solicita uno nuevo.",
            }
            if resultado.startswith("incorrecto:"):
                restantes = resultado.split(":")[1]
                error_msg = f"Código incorrecto. Te quedan {restantes} intento(s)."
            else:
                error_msg = mensajes.get(resultado, "Error de verificación.")

            return render_template("modificar_cita.html",
                paso="verificar", dni=dni, tel_mask="***",
                error=error_msg, terapeutas=terapeutas)

        elif accion == "guardar":
            cita_id      = request.form.get("cita_id")
            nueva_fecha  = request.form.get("fecha_cita", "").strip()
            nuevo_medico = request.form.get("medico_id", "").strip()

            if not cita_id or not nueva_fecha or not nuevo_medico:
                flash("Completa todos los campos para modificar.")
                conn.close()
                return redirect(url_for("modificar_cita"))

            try:
                fecha_obj = datetime.strptime(nueva_fecha, "%Y-%m-%d").date()
                if fecha_obj < datetime.today().date():
                    flash("La nueva fecha no puede ser en el pasado.")
                    conn.close()
                    return redirect(url_for("modificar_cita"))
            except ValueError:
                flash("Fecha invalida.")
                conn.close()
                return redirect(url_for("modificar_cita"))

            # AUTOMATIZACIÓN 1: verificar disponibilidad al modificar
            if not medico_disponible(nuevo_medico, nueva_fecha, excluir_cita_id=cita_id):
                flash("El médico ya tiene una cita programada ese día. Elige otra fecha.")
                conn.close()
                return redirect(url_for("modificar_cita"))

            cursor.execute(
                "UPDATE historial_citas SET fecha_cita = %s, terapeuta_id = %s WHERE id = %s",
                (nueva_fecha, nuevo_medico, cita_id)
            )
            conn.commit()
            conn.close()
            flash("exito:Cita modificada correctamente.")
            registrar_log("paciente", None, dni, "modificar_cita",
                          detalles=f"Cita #{cita_id} actualizada a {nueva_fecha} (doctor {nuevo_medico})",
                          ip_origen=obtener_ip(),
                          user_agent=request.headers.get("User-Agent", ""),
                          cita_id=int(cita_id) if str(cita_id).isdigit() else None)
            return redirect(url_for("modificar_cita"))

    conn.close()
    return render_template("modificar_cita.html", terapeutas=terapeutas)


@app.route("/citas/cancelar", methods=["GET", "POST"])
def cancelar_cita():
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)

    if request.method == "POST":
        accion = request.form.get("accion")

        if accion == "solicitar":
            dni = request.form.get("dni", "").strip()
            if not dni or len(dni) != 8 or not dni.isdigit():
                conn.close()
                return render_template("cancelar_cita.html",
                    error="Ingresa un DNI válido (8 dígitos).")

            cursor.execute("""
                SELECT p.telefono FROM personas p
                JOIN historial_citas h ON h.persona_id = p.id
                WHERE p.dni = %s AND h.estado = 'programada'
                LIMIT 1
            """, (dni,))
            persona = cursor.fetchone()
            conn.close()

            if not persona:
                return render_template("cancelar_cita.html",
                    error="No se encontraron citas programadas para ese DNI.")

            codigo  = generar_otp()
            guardar_otp(dni, codigo, "cancelar")
            enviado = enviar_sms_otp(persona["telefono"], codigo, "cancelar")

            if not enviado:
                return render_template("cancelar_cita.html",
                    error="No se pudo enviar el SMS. Intenta de nuevo.")

            tel      = persona["telefono"].strip()
            tel_mask = tel[:3] + "***" + tel[-3:] if len(tel) >= 6 else "***"
            return render_template("cancelar_cita.html",
                paso="verificar", dni=dni, tel_mask=tel_mask)

        elif accion == "verificar":
            dni       = request.form.get("dni", "").strip()
            codigo    = request.form.get("otp", "").strip()
            resultado = verificar_otp(dni, codigo, "cancelar")

            if resultado == "ok":
                cursor.execute("""
                    SELECT h.id, h.fecha_cita, h.estado,
                           p.nombre, p.apellido, p.dni,
                           t.Nombre AS terapeuta, t.Especialidad
                    FROM historial_citas h
                    JOIN personas p ON h.persona_id = p.id
                    JOIN terapeutas t ON h.terapeuta_id = t.ID
                    WHERE p.dni = %s AND h.estado = 'programada'
                    ORDER BY h.fecha_cita ASC
                """, (dni,))
                citas_encontradas = cursor.fetchall()
                conn.close()
                return render_template("cancelar_cita.html",
                    citas=citas_encontradas, verificado=True)

            conn.close()
            mensajes = {
                "expirado":  "El código expiró. Solicita uno nuevo.",
                "agotado":   f"Superaste los {OTP_MAX_INTENTOS} intentos. Solicita un nuevo código.",
                "no_existe": "No hay un código activo. Solicita uno nuevo.",
            }
            if resultado.startswith("incorrecto:"):
                restantes = resultado.split(":")[1]
                error_msg = f"Código incorrecto. Te quedan {restantes} intento(s)."
            else:
                error_msg = mensajes.get(resultado, "Error de verificación.")

            return render_template("cancelar_cita.html",
                paso="verificar", dni=dni, tel_mask="***",
                error=error_msg)

        elif accion == "confirmar":
            cita_id = request.form.get("cita_id")
            motivo  = request.form.get("motivo_cancelacion", "").strip()
            set_clause = "estado = 'cancelada'"
            params = [cita_id]
            if motivo:
                set_clause += ", motivo_cancelacion = %s"
                params = [motivo, cita_id]
            cursor.execute(
                f"UPDATE historial_citas SET {set_clause} WHERE id = %s",
                tuple(params)
            )
            conn.commit()
            conn.close()
            flash("exito:Tu cita ha sido cancelada correctamente.")
            registrar_log("paciente", None, dni, "cancelar_cita",
                          detalles=f"Cita #{cita_id} cancelada. Motivo: {motivo or 'No especificado'}",
                          ip_origen=obtener_ip(),
                          user_agent=request.headers.get("User-Agent", ""),
                          cita_id=int(cita_id) if str(cita_id).isdigit() else None)
            return redirect(url_for("cancelar_cita"))

    conn.close()
    return render_template("cancelar_cita.html")


@app.route("/retorno")
def retorno():
    cita_id = request.args.get("cita_id")
    return render_template("retorno.html", cita_id=cita_id)


@app.route("/interfaz")
@login_required
def interfaz():
    fecha_str = request.args.get("fecha", datetime.today().strftime("%Y-%m-%d"))
    try:
        fecha_obj = datetime.strptime(fecha_str, "%Y-%m-%d")
    except ValueError:
        fecha_obj = datetime.today()

    ayer          = (fecha_obj - timedelta(days=1)).strftime("%Y-%m-%d")
    manana        = (fecha_obj + timedelta(days=1)).strftime("%Y-%m-%d")
    dias          = ["Lunes", "Martes", "Miercoles", "Jueves", "Viernes", "Sabado", "Domingo"]
    dia_semana    = dias[fecha_obj.weekday()]
    fecha_display = fecha_obj.strftime("%d/%m/%Y")
    es_hoy        = fecha_str == datetime.today().strftime("%Y-%m-%d")
    es_admin      = "admin" in session

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)

    if es_admin:
        cursor.execute("""
            SELECT p.id, p.nombre, p.apellido, p.dni, p.telefono,
                   h.id AS historial_id, h.descripcion, h.estado,
                   t.Nombre AS terapeuta,
                   (SELECT COUNT(*) FROM historial_citas WHERE persona_id = p.id) AS total_visitas
            FROM personas p
            JOIN historial_citas h ON h.persona_id = p.id
            JOIN terapeutas t ON h.terapeuta_id = t.ID
            WHERE h.fecha_cita = %s AND h.estado = 'programada'
            ORDER BY p.apellido ASC
        """, (fecha_str,))
    else:
        cursor.execute("""
            SELECT p.id, p.nombre, p.apellido, p.dni, p.telefono,
                   h.id AS historial_id, h.descripcion, h.estado,
                   t.Nombre AS terapeuta,
                   (SELECT COUNT(*) FROM historial_citas WHERE persona_id = p.id) AS total_visitas
            FROM personas p
            JOIN historial_citas h ON h.persona_id = p.id
            JOIN terapeutas t ON h.terapeuta_id = t.ID
            WHERE h.fecha_cita = %s AND h.terapeuta_id = %s AND h.estado = 'programada'
            ORDER BY p.apellido ASC
        """, (fecha_str, session.get("medico_id")))

    pacientes = cursor.fetchall()
    conn.close()

    nombre_usuario = session.get("admin") or session.get("usuario")
    return render_template(
        "interfaz.html",
        pacientes=pacientes,
        fecha_actual=fecha_str,
        fecha_display=fecha_display,
        dia_semana=dia_semana,
        ayer=ayer,
        manana=manana,
        es_hoy=es_hoy,
        nombre_usuario=nombre_usuario,
        es_admin=es_admin
    )


@app.route("/guardar_descripcion", methods=["POST"])
@login_required
def guardar_descripcion():
    historial_id = request.form.get("historial_id")
    descripcion  = request.form.get("descripcion", "").strip()
    fecha        = request.form.get("fecha", datetime.today().strftime("%Y-%m-%d"))

    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE historial_citas SET descripcion = %s, estado = 'completada' WHERE id = %s",
        (descripcion, historial_id)
    )
    conn.commit()
    conn.close()
    return redirect(url_for("interfaz", fecha=fecha))


@app.route("/panel_admin", methods=["GET", "POST"])
@admin_required
def panel_admin():
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)

    if request.method == "POST":
        accion = request.form.get("accion")

        if accion == "registrar":
            nombre       = request.form.get("nombre", "").strip()
            especialidad = request.form.get("especialidad", "").strip()
            correo       = request.form.get("correo", "").strip()
            clave        = request.form.get("clave", "").strip()
            telefono     = request.form.get("telefono", "").strip()

            if nombre and especialidad and correo and clave:
                cursor.execute("SELECT ID FROM terapeutas WHERE Correo = %s", (correo,))
                if cursor.fetchone():
                    flash("Ya existe un medico con ese correo.")
                else:
                    clave_hash = bcrypt.generate_password_hash(clave).decode("utf-8")
                    cursor.execute(
                        "INSERT INTO terapeutas (Nombre, Especialidad, Correo, Clave, Telefono, activo) "
                        "VALUES (%s, %s, %s, %s, %s, 1)",
                        (nombre, especialidad, correo, clave_hash, telefono or None)
                    )
                    conn.commit()
                    medico_id_nuevo = cursor.lastrowid
                    flash("exito:Medico registrado correctamente.")
                    registrar_log("admin", session.get("admin_id"), session.get("admin"), "registrar_medico",
                                  detalles=f"Dr(a). {nombre} ({especialidad}) - ID {medico_id_nuevo}",
                                  ip_origen=obtener_ip(),
                                  user_agent=request.headers.get("User-Agent", ""),
                                  terapeuta_id=medico_id_nuevo)
            else:
                flash("Completa todos los campos.")

        elif accion == "cambiar_clave":
            medico_id   = request.form.get("medico_id")
            nueva_clave = request.form.get("nueva_clave", "").strip()
            if medico_id and nueva_clave:
                clave_hash = bcrypt.generate_password_hash(nueva_clave).decode("utf-8")
                cursor.execute(
                    "UPDATE terapeutas SET Clave = %s WHERE ID = %s",
                    (clave_hash, medico_id)
                )
                conn.commit()
                flash("exito:Contrasena actualizada correctamente.")
                registrar_log("admin", session.get("admin_id"), session.get("admin"), "cambiar_clave",
                              detalles=f"Clave actualizada para terapeuta ID {medico_id}",
                              ip_origen=obtener_ip(),
                              user_agent=request.headers.get("User-Agent", ""),
                              terapeuta_id=int(medico_id) if str(medico_id).isdigit() else None)
            else:
                flash("Datos incompletos.")

        elif accion == "eliminar":
            medico_id = request.form.get("medico_id")
            if medico_id:
                cursor.execute(
                    "UPDATE terapeutas SET activo = 0 WHERE ID = %s",
                    (medico_id,)
                )
                conn.commit()
                flash("exito:Medico desactivado correctamente.")
                registrar_log("admin", session.get("admin_id"), session.get("admin"), "eliminar_medico",
                              detalles=f"Terapeuta ID {medico_id} desactivado (soft delete)",
                              ip_origen=obtener_ip(),
                              user_agent=request.headers.get("User-Agent", ""),
                              terapeuta_id=int(medico_id) if str(medico_id).isdigit() else None)

        conn.close()
        return redirect(url_for("panel_admin"))

    cursor.execute(
        "SELECT ID, Nombre, Especialidad, Correo, Telefono, activo FROM terapeutas ORDER BY Nombre ASC"
    )
    medicos = cursor.fetchall()

    cursor.execute("""
        SELECT h.id, h.fecha_cita, h.estado,
               p.nombre, p.apellido, p.dni, p.telefono,
               t.Nombre AS terapeuta, t.Especialidad
        FROM historial_citas h
        JOIN personas p ON h.persona_id = p.id
        JOIN terapeutas t ON h.terapeuta_id = t.ID
        WHERE h.fecha_cita >= CURDATE()
        ORDER BY h.fecha_cita ASC
        LIMIT 20
    """)
    proximas_citas = cursor.fetchall()
    conn.close()

    return render_template("paneladmin.html", medicos=medicos, proximas_citas=proximas_citas)


@app.route("/panel_admin/cancelar_cita/<int:cita_id>", methods=["POST"])
@admin_required
def admin_cancelar_cita(cita_id):
    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE historial_citas SET estado = 'cancelada' WHERE id = %s", (cita_id,)
    )
    conn.commit()
    conn.close()
    flash("exito:Cita cancelada.")
    return redirect(url_for("panel_admin"))


# -----------------------------------------------
# API REST
# -----------------------------------------------
@app.route("/api/citas", methods=["GET"])
@csrf.exempt
@limiter.limit("20/minute")
@api_key_required
def api_listar_citas():
    dni    = request.args.get("dni", "")
    fecha  = request.args.get("fecha", "")
    estado = request.args.get("estado", "programada")

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    query  = """
        SELECT h.id, h.fecha_cita, h.estado,
               p.nombre, p.apellido, p.dni, p.telefono,
               t.Nombre AS terapeuta, t.Especialidad
        FROM historial_citas h
        JOIN personas p ON h.persona_id = p.id
        JOIN terapeutas t ON h.terapeuta_id = t.ID
        WHERE h.estado = %s
    """
    params = [estado]
    if dni:
        query += " AND p.dni = %s"
        params.append(dni)
    if fecha:
        query += " AND h.fecha_cita = %s"
        params.append(fecha)
    query += " ORDER BY h.fecha_cita ASC"
    cursor.execute(query, params)
    citas = cursor.fetchall()
    conn.close()

    for c in citas:
        if hasattr(c["fecha_cita"], "strftime"):
            c["fecha_cita"] = c["fecha_cita"].strftime("%Y-%m-%d")

    return jsonify({"success": True, "total": len(citas), "citas": citas})


@app.route("/api/citas/<int:cita_id>", methods=["GET"])
@csrf.exempt
@limiter.limit("20/minute")
@api_key_required
def api_detalle_cita(cita_id):
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("""
        SELECT h.id, h.fecha_cita, h.estado, h.descripcion,
               p.nombre, p.apellido, p.dni, p.telefono,
               t.Nombre AS terapeuta, t.Especialidad
        FROM historial_citas h
        JOIN personas p ON h.persona_id = p.id
        JOIN terapeutas t ON h.terapeuta_id = t.ID
        WHERE h.id = %s
    """, (cita_id,))
    cita = cursor.fetchone()
    conn.close()

    if not cita:
        return jsonify({"error": "Cita no encontrada"}), 404

    if hasattr(cita["fecha_cita"], "strftime"):
        cita["fecha_cita"] = cita["fecha_cita"].strftime("%Y-%m-%d")

    return jsonify({"success": True, "cita": cita})


@app.route("/api/citas", methods=["POST"])
@csrf.exempt
@limiter.limit("5/minute")
@api_key_required
def api_crear_cita():
    data = request.get_json() or {}

    for campo in ["nombre", "apellido", "dni", "telefono", "medico_id", "fecha_cita"]:
        if not data.get(campo):
            return jsonify({"error": f"Campo requerido: {campo}"}), 400

    try:
        fecha_obj = datetime.strptime(data["fecha_cita"], "%Y-%m-%d").date()
        if fecha_obj < datetime.today().date():
            return jsonify({"error": "La fecha no puede ser en el pasado"}), 400
    except ValueError:
        return jsonify({"error": "Formato de fecha invalido. Usa YYYY-MM-DD"}), 400

    # AUTOMATIZACIÓN 1 en la API
    if not medico_disponible(data["medico_id"], data["fecha_cita"]):
        return jsonify({"error": "El medico ya tiene una cita programada ese dia"}), 409

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT id FROM personas WHERE dni = %s", (data["dni"],))
    persona = cursor.fetchone()

    if persona:
        persona_id = persona["id"]
    else:
        cursor.execute(
            "INSERT INTO personas (nombre, apellido, dni, telefono) VALUES (%s, %s, %s, %s)",
            (data["nombre"], data["apellido"], data["dni"], data["telefono"])
        )
        conn.commit()
        persona_id = cursor.lastrowid

    cursor.execute(
        "INSERT INTO historial_citas (persona_id, terapeuta_id, fecha_cita, estado) "
        "VALUES (%s, %s, %s, 'programada')",
        (persona_id, data["medico_id"], data["fecha_cita"])
    )
    conn.commit()
    cita_id = cursor.lastrowid

    cursor.execute(
        "SELECT Nombre, Especialidad, Telefono FROM terapeutas WHERE ID = %s",
        (data["medico_id"],)
    )
    medico = cursor.fetchone()
    conn.close()

    if medico:
        # AUTOMATIZACIONES 2 y 3 en la API
        enviar_sms_confirmacion_paciente(
            data["telefono"], data["nombre"],
            medico["Nombre"], medico["Especialidad"], data["fecha_cita"]
        )
        enviar_sms_notificacion_medico(
            medico.get("Telefono"), medico["Nombre"],
            f"{data['nombre']} {data['apellido']}", data["fecha_cita"]
        )

    return jsonify({"success": True, "cita_id": cita_id, "mensaje": "Cita creada correctamente"}), 201


@app.route("/api/citas/<int:cita_id>", methods=["PUT"])
@csrf.exempt
@limiter.limit("5/minute")
@api_key_required
def api_modificar_cita(cita_id):
    data         = request.get_json() or {}
    nueva_fecha  = data.get("fecha_cita", "")
    nuevo_medico = data.get("medico_id", "")

    if not nueva_fecha or not nuevo_medico:
        return jsonify({"error": "Se requieren fecha_cita y medico_id"}), 400

    try:
        fecha_obj = datetime.strptime(nueva_fecha, "%Y-%m-%d").date()
        if fecha_obj < datetime.today().date():
            return jsonify({"error": "La fecha no puede ser en el pasado"}), 400
    except ValueError:
        return jsonify({"error": "Formato invalido. Usa YYYY-MM-DD"}), 400

    # AUTOMATIZACIÓN 1 en PUT
    if not medico_disponible(nuevo_medico, nueva_fecha, excluir_cita_id=cita_id):
        return jsonify({"error": "El medico ya tiene una cita programada ese dia"}), 409

    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE historial_citas SET fecha_cita = %s, terapeuta_id = %s "
        "WHERE id = %s AND estado = 'programada'",
        (nueva_fecha, nuevo_medico, cita_id)
    )
    conn.commit()
    afectadas = cursor.rowcount
    conn.close()

    if afectadas == 0:
        return jsonify({"error": "Cita no encontrada o ya no esta programada"}), 404

    return jsonify({"success": True, "mensaje": "Cita modificada correctamente"})


@app.route("/api/citas/<int:cita_id>", methods=["DELETE"])
@csrf.exempt
@limiter.limit("5/minute")
@api_key_required
def api_cancelar_cita(cita_id):
    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE historial_citas SET estado = 'cancelada' "
        "WHERE id = %s AND estado = 'programada'",
        (cita_id,)
    )
    conn.commit()
    afectadas = cursor.rowcount
    conn.close()

    if afectadas == 0:
        return jsonify({"error": "Cita no encontrada o ya no esta programada"}), 404

    return jsonify({"success": True, "mensaje": "Cita cancelada correctamente"})


@app.route("/api/terapeutas", methods=["GET"])
@csrf.exempt
@limiter.limit("20/minute")
@api_key_required
def api_terapeutas():
    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT ID, Nombre, Especialidad FROM terapeutas WHERE activo = 1 ORDER BY Nombre ASC")
    terapeutas = cursor.fetchall()
    conn.close()
    return jsonify({"success": True, "terapeutas": terapeutas})


# ===============================================================
# INICIO DE LA APLICACIÓN
# Automatización 4: APScheduler arranca junto con la app
# ===============================================================
if __name__ == "__main__":
    scheduler = BackgroundScheduler()
    scheduler.add_job(
        func=enviar_recordatorios_24h,
        trigger="interval",
        hours=1,
        id="recordatorios_24h",
        replace_existing=True
    )
    scheduler.start()
    app.logger.info("[Scheduler] Recordatorios 24h activados (revisa cada 1 hora).")

    try:
        app.run(debug=(os.environ.get("FLASK_ENV") == "development"))
    finally:
        scheduler.shutdown()
