-- =====================================================================
--  Migración v2: Mejora de estructura de base de datos MOOVA Clinic
--  Compatible con MariaDB 11.4 / MySQL 8.0+
--  Preserva todos los datos existentes (usa ALTER TABLE IF NOT EXISTS)
--
--  Cómo aplicar en alwaysdata:
--  1. Accede a phpMyAdmin o el cliente MySQL
--  2. Selecciona la base: moovacloud_db
--  3. Ejecuta este script
-- =====================================================================

SET time_zone = "+00:00";

-- -------------------------------------------------------------------
--  TABLE: admins
--  Mejoras: timestamps de creación/actualización
-- -------------------------------------------------------------------
ALTER TABLE admins
    ADD COLUMN IF NOT EXISTS creado_en  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

DROP TRIGGER IF EXISTS trg_admins_actualizar;
DELIMITER $$
CREATE TRIGGER trg_admins_actualizar
    BEFORE UPDATE ON admins
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- -------------------------------------------------------------------
--  TABLE: terapeutas
--  Mejoras: columna activo, timestamps
-- -------------------------------------------------------------------
ALTER TABLE terapeutas
    ADD COLUMN IF NOT EXISTS activo        TINYINT(1) NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS creado_en     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

DROP TRIGGER IF EXISTS trg_terapeutas_actualizar;
DELIMITER $$
CREATE TRIGGER trg_terapeutas_actualizar
    BEFORE UPDATE ON terapeutas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- Índice para búsquedas por estado activo
CREATE INDEX IF NOT EXISTS idx_terapeutas_activo ON terapeutas (activo);

-- -------------------------------------------------------------------
--  TABLE: personas
--  Mejoras: timestamps
-- -------------------------------------------------------------------
ALTER TABLE personas
    ADD COLUMN IF NOT EXISTS creado_en     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

DROP TRIGGER IF EXISTS trg_personas_actualizar;
DELIMITER $$
CREATE TRIGGER trg_personas_actualizar
    BEFORE UPDATE ON personas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- -------------------------------------------------------------------
--  TABLE: historial_citas
--  Mejoras: timestamps, motivo_cancelacion, FK con CASCADE
-- -------------------------------------------------------------------
ALTER TABLE historial_citas
    ADD COLUMN IF NOT EXISTS motivo_cancelacion VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS creado_en          TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS actualizado_en     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

-- Índice compuesto para consultas de horarios (terapeuta + fecha + estado)
CREATE INDEX IF NOT EXISTS idx_historial_terapeuta_fecha ON historial_citas (terapeuta_id, fecha_cita, estado);

-- Índice para citas por estado y fecha (para recordatorios)
CREATE INDEX IF NOT EXISTS idx_historial_estado_fecha ON historial_citas (estado, fecha_cita);

-- Índice para historial de un paciente
CREATE INDEX IF NOT EXISTS idx_historial_persona ON historial_citas (persona_id, fecha_cita);

-- FK: si se elimina una persona, se eliminan sus citas (CASCADE)
ALTER TABLE historial_citas
    ADD CONSTRAINT fk_historial_persona
        FOREIGN KEY (persona_id) REFERENCES personas(id)
        ON DELETE CASCADE;

DROP TRIGGER IF EXISTS trg_historial_actualizar;
DELIMITER $$
CREATE TRIGGER trg_historial_actualizar
    BEFORE UPDATE ON historial_citas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- -------------------------------------------------------------------
--  TABLE: horarios_medico
--  Mejoras: timestamps, ON UPDATE CASCADE en FK
-- -------------------------------------------------------------------
-- Primero eliminar la FK existente para poder re-crearla con ON UPDATE CASCADE
ALTER TABLE horarios_medico
    DROP FOREIGN KEY horarios_medico_ibfk_1;

ALTER TABLE horarios_medico
    ADD CONSTRAINT fk_horarios_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

ALTER TABLE horarios_medico
    ADD COLUMN IF NOT EXISTS creado_en     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

DROP TRIGGER IF EXISTS trg_horarios_actualizar;
DELIMITER $$
CREATE TRIGGER trg_horarios_actualizar
    BEFORE UPDATE ON horarios_medico
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- -------------------------------------------------------------------
--  TABLE: logs_auditoria
--  Mejoras: FK a terapeutas, index en fecha
-- -------------------------------------------------------------------
ALTER TABLE logs_auditoria
    ADD COLUMN IF NOT EXISTS terapeuta_id INT(11) NULL,
    ADD COLUMN IF NOT EXISTS cita_id      INT(11) NULL,
    ADD CONSTRAINT fk_logs_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE SET NULL,
    ADD CONSTRAINT fk_logs_cita
        FOREIGN KEY (cita_id) REFERENCES historial_citas(id)
        ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_logs_fecha ON logs_auditoria (fecha_creacion);
CREATE INDEX IF NOT EXISTS idx_logs_usuario ON logs_auditoria (usuario_tipo, usuario_id);

-- -------------------------------------------------------------------
--  TABLE: notas_clinicas
--  Mejoras: timestamps, ON UPDATE CASCADE en FKs
-- -------------------------------------------------------------------
ALTER TABLE notas_clinicas
    DROP FOREIGN KEY notas_clinicas_ibfk_1,
    DROP FOREIGN KEY notas_clinicas_ibfk_2,
    DROP FOREIGN KEY notas_clinicas_ibfk_3;

ALTER TABLE notas_clinicas
    ADD CONSTRAINT fk_notas_cita
        FOREIGN KEY (cita_id) REFERENCES historial_citas(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    ADD CONSTRAINT fk_notas_paciente
        FOREIGN KEY (paciente_id) REFERENCES personas(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    ADD CONSTRAINT fk_notas_terapeuta
        FOREIGN KEY (terapeuta_id) REFERENCES terapeutas(ID)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

ALTER TABLE notas_clinicas
    ADD COLUMN IF NOT EXISTS creado_en     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

DROP TRIGGER IF EXISTS trg_notas_actualizar;
DELIMITER $$
CREATE TRIGGER trg_notas_actualizar
    BEFORE UPDATE ON notas_clinicas
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- -------------------------------------------------------------------
--  TABLE: otp_verificaciones
--  Mejoras: índice compuesto optimizado, ON DELETE CASCADE en FK
-- -------------------------------------------------------------------
-- El índice idx_dni_accion ya existe, pero lo optimizamos agregando 'usado'
DROP INDEX IF EXISTS idx_dni_accion ON otp_verificaciones;
CREATE INDEX idx_dni_accion_usado ON otp_verificaciones (dni, accion, usado);

ALTER TABLE otp_verificaciones
    ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP;

DROP TRIGGER IF EXISTS trg_otp_actualizar;
DELIMITER $$
CREATE TRIGGER trg_otp_actualizar
    BEFORE UPDATE ON otp_verificaciones
    FOR EACH ROW
    SET NEW.actualizado_en = CURRENT_TIMESTAMP
$$
DELIMITER ;

-- -------------------------------------------------------------------
--  Verificación final: mostrar estructura actualizada
-- -------------------------------------------------------------------
SELECT
    TABLE_NAME AS tabla,
    COLUMN_NAME AS columna,
    COLUMN_TYPE AS tipo,
    IS_NULLABLE AS "puede_ser_nulo",
    COLUMN_DEFAULT AS "valor_por_defecto",
    EXTRA AS extra
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('admins', 'terapeutas', 'personas',
                      'historial_citas', 'horarios_medico',
                      'logs_auditoria', 'notas_clinicas', 'otp_verificaciones')
ORDER BY tabla, ordinal_position;
