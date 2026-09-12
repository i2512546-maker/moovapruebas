"""
Scheduler Service — Microservicio de Horarios
Gestiona horarios de disponibilidad de terapeutas y verifica disponibilidad de citas.

Ejecutar:
    python app.py

Configuración (.env):
    DB_HOST, DB_USER, DB_PASSWORD, DB_NAME, DB_PORT
    FLASK_SECRET_KEY, SCHEDULER_API_KEY, FLASK_ENV
"""

import os
import json
import threading
from datetime import datetime, timedelta, time as time_util
from flask import Flask, request, jsonify
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.middleware.proxy_fix import ProxyFix
from dotenv import load_dotenv
from db import get_connection
import requests as http_requests

load_dotenv()

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "scheduler-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)

limiter = Limiter(
    key_func=get_remote_address,
    app=app,
    default_limits=["500 per minute"],
    storage_uri="memory://",
)

SCHEDULER_API_KEY = os.environ.get("SCHEDULER_API_KEY", "")

# -----------------------------------------------------------------------
# Configuracion del servicio de citas (para verificar disponibilidad)
# -----------------------------------------------------------------------
APPOINTMENT_SERVICE_URL = os.environ.get("APPOINTMENT_SERVICE_URL", "")
APPOINTMENT_API_KEY     = os.environ.get("APPOINTMENT_API_KEY", "")


def require_key():
    key = request.headers.get("X-Scheduler-Key", "")
    if not SCHEDULER_API_KEY or key != SCHEDULER_API_KEY:
        return False
    return True


# -----------------------------------------------------------------------
# GET /api/horarios?terapeuta_id={id}
#   Devuelve horarios activos de un terapeuta
# -----------------------------------------------------------------------
@app.route("/api/horarios", methods=["GET"])
@limiter.limit("60/minute")
def listar_horarios():
    if not require_key():
        return jsonify({"error": "API key invalida"}), 401

    terapeuta_id = request.args.get("terapeuta_id")
    if not terapeuta_id or not terapeuta_id.isdigit():
        return jsonify({"error": "terapeuta_id requerido (numerico)"}), 400

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("""
        SELECT h.id, h.terapeuta_id, h.dia_semana,
               TIME_FORMAT(h.hora_inicio, '%H:%i') AS hora_inicio,
               TIME_FORMAT(h.hora_fin,   '%H:%i') AS hora_fin,
               h.duracion_min, h.activo
        FROM horarios_medico h
        JOIN terapeutas_cache tc ON tc.id = h.terapeuta_id
        WHERE h.terapeuta_id = %s AND h.activo = 1 AND tc.activo = 1
        ORDER BY h.dia_semana
    """, (int(terapeuta_id),))
    horarios = cursor.fetchall()

    dia_nombres = ["Lunes", "Martes", "Miercoles", "Jueves", "Viernes", "Sabado", "Domingo"]
    for h in horarios:
        h["dia_nombre"] = dia_nombres[h["dia_semana"]] if 0 <= h["dia_semana"] <= 6 else "Desconocido"

    conn.close()
    return jsonify({"success": True, "terapeuta_id": terapeuta_id, "horarios": horarios})


# -----------------------------------------------------------------------
# POST /api/horarios  —  Crear / actualizar horario
# -----------------------------------------------------------------------
@app.route("/api/horarios", methods=["POST"])
@limiter.limit("20/minute")
def crear_horario():
    if not require_key():
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(force=True, silent=True) or {}
    terapeuta_id = data.get("terapeuta_id")
    dia_semana   = data.get("dia_semana")
    hora_inicio   = data.get("hora_inicio")
    hora_fin      = data.get("hora_fin")
    duracion_min  = data.get("duracion_min", 30)

    if None in (terapeuta_id, dia_semana, hora_inicio, hora_fin):
        return jsonify({"error": "terapeuta_id, dia_semana, hora_inicio y hora_fin son requeridos"}), 400

    if not (0 <= int(dia_semana) <= 6):
        return jsonify({"error": "dia_semana debe estar entre 0 (lun) y 6 (dom)"}), 400

    conn   = get_connection()
    cursor = conn.cursor()

    # Verificar que el terapeuta existe en cache y esta activo
    cursor.execute("SELECT id FROM terapeutas_cache WHERE id = %s AND activo = 1", (int(terapeuta_id),))
    if not cursor.fetchone():
        conn.close()
        return jsonify({"error": "Terapeuta no encontrado o inactivo"}), 404

    cursor.execute("""
        INSERT INTO horarios_medico
            (terapeuta_id, dia_semana, hora_inicio, hora_fin, duracion_min, activo)
        VALUES (%s, %s, %s, %s, %s, 1)
        ON DUPLICATE KEY UPDATE
            hora_inicio = VALUES(hora_inicio),
            hora_fin    = VALUES(hora_fin),
            duracion_min = VALUES(duracion_min),
            activo      = 1,
            actualizado_en = CURRENT_TIMESTAMP
    """, (int(terapeuta_id), int(dia_semana), hora_inicio, hora_fin, int(duracion_min)))
    conn.commit()
    horario_id = cursor.lastrowid
    conn.close()

    return jsonify({"success": True, "horario_id": horario_id}), 201


# -----------------------------------------------------------------------
# PUT /api/horarios/{id}  —  Modificar horario existente
# -----------------------------------------------------------------------
@app.route("/api/horarios/<int:horario_id>", methods=["PUT"])
@limiter.limit("20/minute")
def modificar_horario(horario_id):
    if not require_key():
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(force=True, silent=True) or {}
    campos = []
    params = []

    for campo in ["dia_semana", "hora_inicio", "hora_fin", "duracion_min", "activo"]:
        if campo in data and data[campo] is not None:
            campos.append(f"{campo} = %s")
            params.append(data[campo])

    if not campos:
        return jsonify({"error": "No hay campos para actualizar"}), 400

    params.append(horario_id)
    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(f"UPDATE horarios_medico SET {', '.join(campos)} WHERE id = %s", tuple(params))
    conn.commit()
    afectadas = cursor.rowcount
    conn.close()

    if afectadas == 0:
        return jsonify({"error": "Horario no encontrado"}), 404

    return jsonify({"success": True, "mensaje": "Horario actualizado"})


# -----------------------------------------------------------------------
# DELETE /api/horarios/{id}  —  Desactivar horario (soft delete)
# -----------------------------------------------------------------------
@app.route("/api/horarios/<int:horario_id>", methods=["DELETE"])
@limiter.limit("10/minute")
def eliminar_horario(horario_id):
    if not require_key():
        return jsonify({"error": "API key invalida"}), 401

    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE horarios_medico SET activo = 0 WHERE id = %s", (horario_id,))
    conn.commit()
    afectadas = cursor.rowcount
    conn.close()

    if afectadas == 0:
        return jsonify({"error": "Horario no encontrado"}), 404

    return jsonify({"success": True, "mensaje": "Horario desactivado"})


# -----------------------------------------------------------------------
# GET /api/disponibilidad
#   Verifica si un terapeuta tiene disponibilidad en dia_y_hora
#   { terapeuta_id, fecha_cita, hora_cita }
# -----------------------------------------------------------------------
@app.route("/api/disponibilidad", methods=["POST"])
@limiter.limit("30/minute")
def verificar_disponibilidad():
    key = request.headers.get("X-Scheduler-Key", "")
    if not SCHEDULER_API_KEY or key != SCHEDULER_API_KEY:
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(force=True, silent=True) or {}
    terapeuta_id = data.get("terapeuta_id")
    fecha_cita   = data.get("fecha_cita")
    hora_cita    = data.get("hora_cita", "09:00")

    if not terapeuta_id or not fecha_cita:
        return jsonify({"error": "terapeuta_id y fecha_cita son requeridos"}), 400

    try:
        fecha_obj = datetime.strptime(str(fecha_cita), "%Y-%m-%d")
    except ValueError:
        return jsonify({"error": "Formato de fecha invalido (YYYY-MM-DD)"}), 400

    dia_semana = fecha_obj.weekday()

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)

    # 1. Verificar horario del dia
    cursor.execute("""
        SELECT hora_inicio, hora_fin, duracion_min
        FROM horarios_medico
        WHERE terapeuta_id = %s AND dia_semana = %s AND activo = 1
    """, (int(terapeuta_id), dia_semana))
    horario = cursor.fetchone()

    if not horario:
        conn.close()
        return jsonify({
            "disponible": False,
            "motivo": f"Terapeuta sin horario programado para {['L','M','X','J','V','S','D'][dia_semana]}"
        })

    # 2. Verificar que la hora este dentro del horario
    try:
        hora = datetime.strptime(hora_cita, "%H:%M").time()
    except ValueError:
        conn.close()
        return jsonify({"error": "Formato de hora invalido (HH:MM)"}), 400

    hora_inicio = datetime.strptime(horario["hora_inicio"], "%H:%M:%S").time()
    hora_fin    = datetime.strptime(horario["hora_fin"], "%H:%M:%S").time()

    if hora < hora_inicio or hora > hora_fin:
        conn.close()
        return jsonify({
            "disponible": False,
            "motivo": f"Hora fuera del horario ({horario['hora_inicio']} - {horario['hora_fin']})"
        })

    # 3. Consultar appointment-service para verificar cita existente
    ocupado = False
    if APPOINTMENT_SERVICE_URL and APPOINTMENT_API_KEY:
        try:
            resp = http_requests.post(
                APPOINTMENT_SERVICE_URL + "/api/disponibilidad",
                json={
                    "terapeuta_id": terapeuta_id,
                    "fecha_cita": fecha_cita,
                    "hora_cita": hora_cita,
                },
                headers={"X-Appointment-Key": APPOINTMENT_API_KEY},
                timeout=3
            )
            if resp.status_code == 200:
                ocupado = not resp.json().get("disponible", True)
        except Exception:
            pass  # Si el appointment-service falla, asumimos disponible

    conn.close()

    if ocupado:
        return jsonify({"disponible": False, "motivo": "Ya tiene cita programada"})

    return jsonify({
        "disponible": True,
        "horario": {
            "hora_inicio": horario["hora_inicio"],
            "hora_fin": horario["hora_fin"],
            "duracion_min": horario["duracion_min"],
            "dia_semana": dia_semana
        }
    })


# -----------------------------------------------------------------------
# PUT /api/terapeutas/cache  —  Sincronizar cache de terapeutas
#   Recibe lista desde auth-service o scheduler interno
# -----------------------------------------------------------------------
@app.route("/api/terapeutas/cache", methods=["PUT"])
@limiter.limit("10/minute")
def sincronizar_cache():
    key = request.headers.get("X-Scheduler-Key", "")
    if not SCHEDULER_API_KEY or key != SCHEDULER_API_KEY:
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(force=True, silent=True) or {}
    terapeutas = data.get("terapeutas", [])

    if not isinstance(terapeutas, list):
        return jsonify({"error": "terapeutas debe ser una lista"}), 400

    conn   = get_connection()
    cursor = conn.cursor()
    insertados = 0
    actualizados = 0

    for t in terapeutas:
        cursor.execute("""
            INSERT INTO terapeutas_cache (id, nombre, especialidad, activo)
            VALUES (%s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
                nombre = VALUES(nombre),
                especialidad = VALUES(especialidad),
                activo = VALUES(activo)
        """, (t["id"], t["nombre"], t["especialidad"], t.get("activo", 1)))
        if cursor.rowcount == 1:
            insertados += 1
        else:
            actualizados += 1

    conn.commit()
    conn.close()

    return jsonify({
        "success": True,
        "insertados": insertados,
        "actualizados": actualizados,
        "total": len(terapeutas)
    })


# -----------------------------------------------------------------------
# Inicio
# -----------------------------------------------------------------------
if __name__ == "__main__":
    if not SCHEDULER_API_KEY:
        print("ADVERTENCIA: SCHEDULER_API_KEY no esta configurada")
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5002)),
        debug=(os.environ.get("FLASK_ENV") == "development")
    )
