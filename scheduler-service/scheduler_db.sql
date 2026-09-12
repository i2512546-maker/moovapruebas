-- =====================================================================
--  Scheduler Service — Base de datos independiente
--  Microservicio: gestión de horarios de disponibilidad de terapeutas
--  Base de datos: scheduler_db
-- =====================================================================

SET time_zone = "+00:00";

CREATE DATABASE IF NOT EXISTS `scheduler_db`
    DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `scheduler_db`;

-- -------------------------------------------------------------------
--  TABLE: terapeutas_cache
--  Copia local (cache) de los terapeutas registrados en auth-service.
--  Se sincroniza vía eventos (RabbitMQ/webhook) o polling periódico.
--  Evita acoplamiento directo entre bases de datos.
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS terapeutas_cache (
    id              INT(11)     NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    especialidad    VARCHAR(100) NOT NULL,
    activo          TINYINT(1)  NOT NULL DEFAULT 1,
    ultima_sync     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Cache local de terapeutas desde auth-service';

-- -------------------------------------------------------------------
--  TABLE: horarios_medico
--  Horarios de disponibilidad semanales por terapeuta
--  dia_semana: 0=lun .. 6=dom
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS horarios_medico (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    terapeuta_id    INT(11)     NOT NULL,
    dia_semana      TINYINT(4)  NOT NULL COMMENT '0=lun, 1=mar, 2=mie, 3=jue, 4=vie, 5=sb, 6=dom',
    hora_inicio     TIME        NOT NULL,
    hora_fin        TIME        NOT NULL,
    duracion_min    SMALLINT    NOT NULL DEFAULT 30,
    activo          TINYINT(1)  NOT NULL DEFAULT 1,
    creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_horario_terapeuta_dia (terapeuta_id, dia_semana),
    KEY idx_horario_terapeuta (terapeuta_id, activo),
    KEY idx_horario_dia (dia_semana, activo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Horarios semanales de disponibilidad de cada terapeuta';

-- -------------------------------------------------------------------
--  TABLE: excepciones_fecha
--  Días excepcionales (feriados, vacaciones, etc.)
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS excepciones_fecha (
    id              INT(11)     NOT NULL AUTO_INCREMENT,
    terapeuta_id    INT(11)     NOT NULL,
    fecha           DATE        NOT NULL,
    tipo            ENUM('bloqueo', 'disponible') NOT NULL DEFAULT 'bloqueo',
    motivo          VARCHAR(255) DEFAULT NULL,
    creado_en       TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_excepcion_terapeuta_fecha (terapeuta_id, fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
  COMMENT='Excepciones de horario por fecha (feriados, bloqueos, etc.)';

-- -------------------------------------------------------------------
--  Triggers
-- -------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_horarios_actualizar
    BEFORE UPDATE ON horarios_medico
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$

DELIMITER ;
