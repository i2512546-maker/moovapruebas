-- =====================================================================
--  Audit Service — Base de datos independiente
--  Microservicio: captura y consulta de logs de auditoría
--  Base de datos: audit_db
-- =====================================================================

SET time_zone = "+00:00";

CREATE DATABASE IF NOT EXISTS `moovacloud_auditoria`
    DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `moovacloud_auditoria`;

-- -------------------------------------------------------------------
--  TABLE: logs_auditoria
--  Registro completo de todas las acciones cruzadas del sistema.
--  NOTA: se usa BIGINT para soportar alto volumen de escrituras.
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS logs_auditoria (
    id              BIGINT(20)    NOT NULL AUTO_INCREMENT,
    usuario_tipo    VARCHAR(20)   NOT NULL COMMENT 'admin | terapeuta | paciente | sistema',
    usuario_id      INT(11)       DEFAULT NULL,
    usuario_nombre  VARCHAR(100)  DEFAULT NULL,
    accion          VARCHAR(255)  NOT NULL,
    detalles        TEXT          DEFAULT NULL,
    ip_origen       VARCHAR(45)   DEFAULT NULL,
    user_agent      VARCHAR(255)  DEFAULT NULL,
    terapeuta_id    INT(11)       DEFAULT NULL,
    cita_id         INT(11)       DEFAULT NULL,
    fecha_creacion  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_logs_fecha   (fecha_creacion),
    KEY idx_logs_usuario (usuario_tipo, usuario_id),
    KEY idx_logs_accion  (accion),
    KEY idx_logs_cita    (cita_id),
    KEY idx_logs_terapeuta (terapeuta_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Logs de auditoria - capturados de forma asincrona';

-- -------------------------------------------------------------------
--  TABLE: audit_queues
--  Cola interna para batch writes (opcional, si no se usa Redis)
--  Los logs en espera se procesan en background por un worker.
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_queues (
    id              BIGINT(20)    NOT NULL AUTO_INCREMENT,
    payload         JSON          NOT NULL,
    estado          ENUM('pendiente', 'procesado', 'error') NOT NULL DEFAULT 'pendiente',
    intentos        TINYINT       NOT NULL DEFAULT 0,
    creado_en       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    procesado_en    TIMESTAMP     NULL DEFAULT NULL,
    PRIMARY KEY (id),
    KEY idx_queue_estado (estado, creado_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Cola interna para procesamiento asincrono de logs';

-- -------------------------------------------------------------------
--  View: logs_resumen_diario
--  Resumen rápido de acciones por día (para dashboards)
-- -------------------------------------------------------------------
CREATE OR REPLACE VIEW logs_resumen_diario AS
    SELECT
        DATE(fecha_creacion)  AS dia,
        usuario_tipo,
        accion,
        COUNT(*)              AS total
    FROM logs_auditoria
    GROUP BY DATE(fecha_creacion), usuario_tipo, accion;
