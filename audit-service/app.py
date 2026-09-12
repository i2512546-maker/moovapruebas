"""
Audit Service — Microservicio de Auditoría
Servicio independiente que captura logs asíncronos y expone API para consultas.

Ejecutar:
    python app.py

Configuración (.env):
    DB_HOST, DB_USER, DB_PASSWORD, DB_NAME, DB_PORT
    FLASK_SECRET_KEY, AUDIT_API_KEY, FLASK_ENV
"""

import os
import json
import threading
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.middleware.proxy_fix import ProxyFix
from dotenv import load_dotenv
from db import get_connection

load_dotenv()

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "audit-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)

limiter = Limiter(
    key_func=get_remote_address,
    app=app,
    default_limits=["500 per minute"],
    storage_uri="memory://",
)

AUDIT_API_KEY = os.environ.get("AUDIT_API_KEY", "")

# -----------------------------------------------------------------------
# Helper: validar API key
# -----------------------------------------------------------------------
def require_audit_key():
    key = request.headers.get("X-Audit-Key", "")
    if not AUDIT_API_KEY or key != AUDIT_API_KEY:
        return False
    return True


# -----------------------------------------------------------------------
# POST /api/logs  —  Recibe un log desde app.py principal (async)
# -----------------------------------------------------------------------
@app.route("/api/logs", methods=["POST"])
@limiter.limit("500/minute")
def create_log():
    if not require_audit_key():
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(force=True, silent=True) or {}

    campos_requeridos = ["usuario_tipo", "accion"]
    for campo in campos_requeridos:
        if not data.get(campo):
            return jsonify({"error": f"Campo requerido: {campo}"}), 400

    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO logs_auditoria
            (usuario_tipo, usuario_id, usuario_nombre, accion, detalles,
             ip_origen, user_agent, terapeuta_id, cita_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        data.get("usuario_tipo"),
        data.get("usuario_id"),
        data.get("usuario_nombre"),
        data.get("accion"),
        data.get("detalles"),
        data.get("ip_origen"),
        data.get("user_agent"),
        data.get("terapeuta_id"),
        data.get("cita_id"),
    ))
    conn.commit()
    log_id = cursor.lastrowid
    conn.close()

    return jsonify({"success": True, "log_id": log_id}), 201


# -----------------------------------------------------------------------
# POST /api/logs/batch  —  Recibe múltiples logs en un solo request
# -----------------------------------------------------------------------
@app.route("/api/logs/batch", methods=["POST"])
@limiter.limit("100/minute")
def create_log_batch():
    if not require_audit_key():
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(force=True, silent=True) or {}
    logs = data.get("logs", [])

    if not logs or not isinstance(logs, list):
        return jsonify({"error": "Se requiere lista 'logs'"}), 400

    conn   = get_connection()
    cursor = conn.cursor()
    insertados = 0
    for log in logs:
        if not log.get("usuario_tipo") or not log.get("accion"):
            continue
        cursor.execute("""
            INSERT INTO logs_auditoria
                (usuario_tipo, usuario_id, usuario_nombre, accion, detalles,
                 ip_origen, user_agent, terapeuta_id, cita_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            log.get("usuario_tipo"),
            log.get("usuario_id"),
            log.get("usuario_nombre"),
            log.get("accion"),
            log.get("detalles"),
            log.get("ip_origen"),
            log.get("user_agent"),
            log.get("terapeuta_id"),
            log.get("cita_id"),
        ))
        insertados += 1

    conn.commit()
    conn.close()

    return jsonify({"success": True, "insertados": insertados}), 201


# -----------------------------------------------------------------------
# GET /api/logs  —  Consulta de logs con filtros
# -----------------------------------------------------------------------
@app.route("/api/logs", methods=["GET"])
@limiter.limit("60/minute")
def list_logs():
    if not require_audit_key():
        return jsonify({"error": "API key invalida"}), 401

    usuario_tipo = request.args.get("usuario_tipo", "")
    accion       = request.args.get("accion", "")
    cita_id      = request.args.get("cita_id", "")
    fecha_desde  = request.args.get("fecha_desde", "")
    fecha_hasta  = request.args.get("fecha_hasta", "")
    limit        = min(int(request.args.get("limit", 50)), 500)
    offset       = int(request.args.get("offset", 0))

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)

    query  = "SELECT * FROM logs_auditoria WHERE 1=1"
    params = []

    if usuario_tipo:
        query += " AND usuario_tipo = %s"
        params.append(usuario_tipo)
    if accion:
        query += " AND accion LIKE %s"
        params.append(f"%{accion}%")
    if cita_id:
        query += " AND cita_id = %s"
        params.append(int(cita_id))
    if fecha_desde:
        query += " AND fecha_creacion >= %s"
        params.append(fecha_desde)
    if fecha_hasta:
        query += " AND fecha_creacion <= %s"
        params.append(f"{fecha_hasta} 23:59:59")

    query += " ORDER BY id DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    cursor.execute(query, params)
    logs = cursor.fetchall()

    cursor.execute("SELECT COUNT(*) as total FROM logs_auditoria "
                   + (" WHERE 1=1" if not params else ""))
    # Nota: el count simple sin filtros para total general
    conn.close()

    for log in logs:
        if log.get("fecha_creacion") and hasattr(log["fecha_creacion"], "strftime"):
            log["fecha_creacion"] = log["fecha_creacion"].strftime("%Y-%m-%d %H:%M:%S")

    return jsonify({"success": True, "total": len(logs), "logs": logs})


# -----------------------------------------------------------------------
# GET /api/logs/resumen  —  Resumen diario (usa la VIEW creada)
# -----------------------------------------------------------------------
@app.route("/api/logs/resumen", methods=["GET"])
@limiter.limit("30/minute")
def resumen_diario():
    if not require_audit_key():
        return jsonify({"error": "API key invalida"}), 401

    dias = request.args.get("dias", "7")
    try:
        dias = int(dias)
    except ValueError:
        dias = 7

    conn   = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("""
        SELECT dia, usuario_tipo, accion, total
        FROM logs_resumen_diario
        WHERE dia >= CURDATE() - INTERVAL %s DAY
        ORDER BY dia DESC
    """, (dias,))
    resumen = cursor.fetchall()
    conn.close()

    return jsonify({"success": True, "resumen": resumen})


# -----------------------------------------------------------------------
# POST /api/logs/limpiar  —  Elimina logs antiguos (mantenimiento)
# -----------------------------------------------------------------------
@app.route("/api/logs/limpiar", methods=["POST"])
@limiter.limit("1/hour")
def limpiar_logs():
    if not require_audit_key():
        return jsonify({"error": "API key invalida"}), 401

    data = request.get_json(silent=True) or {}
    dias = data.get("dias", 90)

    try:
        dias = int(dias)
    except (TypeError, ValueError):
        dias = 90

    if dias < 30:
        return jsonify({"error": "No se pueden borrar menos de 30 días de logs"}), 400

    conn   = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "DELETE FROM logs_auditoria WHERE fecha_creacion < CURDATE() - INTERVAL %s DAY",
        (dias,)
    )
    borrados = cursor.rowcount
    conn.commit()
    conn.close()

    return jsonify({"success": True, "borrados": borrados})


# -----------------------------------------------------------------------
# Inicio de la aplicación
# -----------------------------------------------------------------------
if __name__ == "__main__":
    if not AUDIT_API_KEY:
        print("ADVERTENCIA: AUDIT_API_KEY no esta configurada")
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5001)),
        debug=(os.environ.get("FLASK_ENV") == "development")
    )
