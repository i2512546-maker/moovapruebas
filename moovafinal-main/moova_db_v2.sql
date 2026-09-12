-- =====================================================================
--  Base de datos: moovacloud_db (v2 - Schema mejorado)
--  Compatible con MariaDB 11.4 / MySQL 8.0+
--  Este archivo es para nuevas instalaciones (ver migrar_db_v2.sql para migrar datos existentes)
-- =====================================================================

SET time_zone = "+00:00";

CREATE DATABASE IF NOT EXISTS `moovacloud_db`
    DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `moovacloud_db`;

-- -------------------------------------------------------------------
--  TABLE: admins
--  Credenciales de administradores del sistema
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admins (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(100) NOT NULL DEFAULT '',
    correo          VARCHAR(100) NOT NULL,
    clave           VARCHAR(255) NOT NULL,
    creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_admins_correo (correo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Administradores del sistema con acceso al panel de administracion';

-- -------------------------------------------------------------------
--  TABLE: terapeutas
--  Profesionales que atienden citas
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS terapeutas (
    ID              INT(11)     NOT NULL AUTO_INCREMENT,
    Nombre          VARCHAR(100) NOT NULL,
    Especialidad    VARCHAR(100) NOT NULL,
    Correo          VARCHAR(100) NOT NULL,
    Clave           VARCHAR(255) NOT NULL,
    Telefono        VARCHAR(20)  DEFAULT NULL,
    activo          TINYINT(1)  NOT NULL DEFAULT 1,
    creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ID),
    UNIQUE KEY uk_terapeutas_correo (Correo),
    KEY idx_terapeutas_activo (activo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Terapeutas o medicos que atienden citas';

-- -------------------------------------------------------------------
--  TABLE: personas
--  Pacientes que agenda citas
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS personas (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(100) NOT NULL,
    apellido        VARCHAR(100) NOT NULL,
    dni             VARCHAR(15)  NOT NULL,
    telefono        VARCHAR(20)  NOT NULL,
    creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_personas_dni (dni)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Personas/pacientes que agendan citas';

-- -------------------------------------------------------------------
--  TABLE: historial_citas
--  Citas agendadas entre personas y terapeutas
--  estado puede ser: programada | cancelada | completada
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS historial_citas (
    id                  INT(11)         NOT NULL AUTO_INCREMENT,
    persona_id          INT(11)         NOT NULL,
    terapeuta_id        INT(11)         NOT NULL,
    fecha_cita          DATE            NOT NULL,
    hora_cita           TIME            DEFAULT NULL,
    descripcion         TEXT            DEFAULT NULL,
    motivo_cancelacion  VARCHAR(255)    DEFAULT NULL,
    estado              VARCHAR(20)     NOT NULL DEFAULT 'programada',
    recordatorio_enviado TINYINT(1)     DEFAULT 0,
    creado_en           TIMESTAMP       NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en      TIMESTAMP       NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_historial_persona (persona_id, fecha_cita),
    KEY idx_historial_terapeuta_fecha (terapeuta_id, fecha_cita, estado),
    KEY idx_historial_estado_fecha (estado, fecha_cita),
    CONSTRAINT fk_historial_persona
        FOREIGN KEY (persona_id) REFERENCES personas(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_historial_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Historial de todas las citas agendadas';

-- -------------------------------------------------------------------
--  TABLE: horarios_medico
--  Horarios de disponibilidad de cada terapeuta
--  dia_semana: 0=lun, 1=mar, 2=mie, 3=jue, 4=vie, 5=sb, 6=dom
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS horarios_medico (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    terapeuta_id    INT(11)     NOT NULL,
    dia_semana      TINYINT(4)  NOT NULL COMMENT '0=lun, 1=mar, 2=mie, 3=jue, 4=vie, 5=sb, 6=dom',
    hora_inicio     TIME        NOT NULL,
    hora_fin        TIME        NOT NULL,
    duracion_min    INT(11)     NOT NULL DEFAULT 30,
    activo          TINYINT(1)  NOT NULL DEFAULT 1,
    creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_horarios_terapeuta (terapeuta_id, dia_semana, activo),
    CONSTRAINT fk_horarios_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Horarios de disponibilidad por terapeuta';

-- -------------------------------------------------------------------
--  TABLE: logs_auditoria
--  Registro de todas las acciones cruzadas en el sistema
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS logs_auditoria (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    usuario_tipo    VARCHAR(20) NOT NULL COMMENT 'admin | terapeuta | paciente',
    usuario_id      INT(11)     DEFAULT NULL,
    usuario_nombre  VARCHAR(100) DEFAULT NULL,
    accion          VARCHAR(255) NOT NULL,
    detalles        TEXT        DEFAULT NULL,
    ip_origen       VARCHAR(45) DEFAULT NULL,
    user_agent      VARCHAR(255) DEFAULT NULL,
    terapeuta_id    INT(11)     DEFAULT NULL,
    cita_id         INT(11)     DEFAULT NULL,
    fecha_creacion  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_logs_fecha (fecha_creacion),
    KEY idx_logs_usuario (usuario_tipo, usuario_id),
    CONSTRAINT fk_logs_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE SET NULL,
    CONSTRAINT fk_logs_cita
        FOREIGN KEY (cita_id) REFERENCES historial_citas(id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Log de auditoria de todas las acciones del sistema';

-- -------------------------------------------------------------------
--  TABLE: notas_clinicas
--  Notas y diagnosticos asociados a citas
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas_clinicas (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    cita_id         INT(11)     NOT NULL,
    paciente_id     INT(11)     NOT NULL,
    terapeuta_id    INT(11)     NOT NULL,
    nota            TEXT        NOT NULL,
    diagnostico     VARCHAR(255) DEFAULT NULL,
    creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_notas_cita (cita_id),
    KEY idx_notas_paciente (paciente_id),
    KEY idx_notas_terapeuta (terapeuta_id),
    CONSTRAINT fk_notas_cita
        FOREIGN KEY (cita_id) REFERENCES historial_citas(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_notas_paciente
        FOREIGN KEY (paciente_id) REFERENCES personas(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_notas_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Notas clinicas y diagnosticos por cita';

-- -------------------------------------------------------------------
--  TABLE: otp_verificaciones
--  Codigos OTP para verificar identidad al modificar/cancelar citas
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otp_verificaciones (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    dni             VARCHAR(15) NOT NULL,
    codigo          VARCHAR(6)  NOT NULL,
    accion          VARCHAR(20) NOT NULL COMMENT 'modificar | cancelar',
    intentos        INT(11)     NOT NULL DEFAULT 0,
    expira_en       DATETIME    NOT NULL,
    usado           TINYINT(1)  NOT NULL DEFAULT 0,
    creado_en       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_dni_accion_usado (dni, accion, usado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Codigos OTP de verificacion por SMS';

-- =====================================================================
--  Triggers: actualizacion automatica de updated_en
-- =====================================================================

DELIMITER $$

CREATE TRIGGER trg_admins_actualizar
    BEFORE UPDATE ON admins
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

CREATE TRIGGER trg_terapeutas_actualizar
    BEFORE UPDATE ON terapeutas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

CREATE TRIGGER trg_personas_actualizar
    BEFORE UPDATE ON personas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

CREATE TRIGGER trg_historial_actualizar
    BEFORE UPDATE ON historial_citas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

CREATE TRIGGER trg_horarios_actualizar
    BEFORE UPDATE ON horarios_medico
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

CREATE TRIGGER trg_notas_actualizar
    BEFORE UPDATE ON notas_clinicas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

CREATE TRIGGER trg_otp_actualizar
    BEFORE UPDATE ON otp_verificaciones
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

DELIMITER ;
