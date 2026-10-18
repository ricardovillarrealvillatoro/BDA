-- =====================================================================
-- Bitácora de auditoría: cada INSERT, UPDATE o DELETE de las tablas clínicas y de usuarios
-- queda en la tabla auditoria con el usuario de la aplicación y la IP de la petición.
-- La app los envía al abrir la conexión (app/db.py) con set_config('app.id_usuario' / 'app.ip').
-- Cargar después de 01_schema.sql; 06_datos_prueba.sql desactiva estos triggers mientras carga.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_auditoria() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_anterior JSONB;
    v_nuevo    JSONB;
    v_id       TEXT;
BEGIN
    -- El hash de la contraseña nunca se copia a la bitácora; solo se indica que cambió
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_anterior := to_jsonb(OLD) - 'password_hash';
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_nuevo := to_jsonb(NEW) - 'password_hash';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        -- Un UPDATE que no cambia ningún valor no se registra
        IF to_jsonb(OLD) = to_jsonb(NEW) THEN
            RETURN NULL;
        END IF;
        IF (to_jsonb(OLD) ->> 'password_hash') IS DISTINCT FROM (to_jsonb(NEW) ->> 'password_hash') THEN
            v_nuevo := v_nuevo || '{"password_hash": "(cambiada)"}';
        END IF;
    END IF;

    -- TG_ARGV trae la(s) columna(s) de la llave primaria; las compuestas se guardan como "a-b"
    SELECT string_agg(COALESCE(v_nuevo, v_anterior) ->> col, '-') INTO v_id FROM unnest(TG_ARGV) AS col;

    INSERT INTO auditoria (id_usuario, tabla, id_registro, accion, valores_anteriores, valores_nuevos, ip)
    VALUES (
        NULLIF(current_setting('app.id_usuario', TRUE), '')::BIGINT,
        upper(TG_TABLE_NAME),
        v_id,
        TG_OP,
        v_anterior,
        v_nuevo,
        NULLIF(current_setting('app.ip', TRUE), '')::INET
    );
    RETURN NULL;
END;
$$;

-- Bitácora inmutable: no se permite modificar ni borrar registros de auditoría
CREATE OR REPLACE FUNCTION fn_auditoria_inmutable() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'La bitácora de auditoría es de solo lectura (% no permitido).', TG_OP;
END;
$$;

CREATE OR REPLACE TRIGGER tg_auditoria_inmutable
    BEFORE UPDATE OR DELETE ON auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_inmutable();
CREATE OR REPLACE TRIGGER tg_auditoria_sin_truncate
    BEFORE TRUNCATE ON auditoria
    FOR EACH STATEMENT EXECUTE FUNCTION fn_auditoria_inmutable();

-- Mismas tablas que ya aparecen en la bitácora de los datos de prueba
CREATE OR REPLACE TRIGGER tg_auditoria_usuario             AFTER INSERT OR UPDATE OR DELETE ON usuario             FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_usuario');
CREATE OR REPLACE TRIGGER tg_auditoria_usuario_rol         AFTER INSERT OR UPDATE OR DELETE ON usuario_rol         FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_usuario', 'id_rol');
CREATE OR REPLACE TRIGGER tg_auditoria_medico              AFTER INSERT OR UPDATE OR DELETE ON medico              FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_medico');
CREATE OR REPLACE TRIGGER tg_auditoria_medico_especialidad AFTER INSERT OR UPDATE OR DELETE ON medico_especialidad FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_medico', 'id_especialidad');
CREATE OR REPLACE TRIGGER tg_auditoria_paciente            AFTER INSERT OR UPDATE OR DELETE ON paciente            FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_paciente');
CREATE OR REPLACE TRIGGER tg_auditoria_alergia             AFTER INSERT OR UPDATE OR DELETE ON alergia             FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_alergia');
CREATE OR REPLACE TRIGGER tg_auditoria_antecedente         AFTER INSERT OR UPDATE OR DELETE ON antecedente         FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_antecedente');
CREATE OR REPLACE TRIGGER tg_auditoria_encuentro           AFTER INSERT OR UPDATE OR DELETE ON encuentro           FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_encuentro');
CREATE OR REPLACE TRIGGER tg_auditoria_diagnostico         AFTER INSERT OR UPDATE OR DELETE ON diagnostico         FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_diagnostico');
CREATE OR REPLACE TRIGGER tg_auditoria_prescripcion        AFTER INSERT OR UPDATE OR DELETE ON prescripcion        FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_prescripcion');
CREATE OR REPLACE TRIGGER tg_auditoria_orden_medica        AFTER INSERT OR UPDATE OR DELETE ON orden_medica        FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_orden');
CREATE OR REPLACE TRIGGER tg_auditoria_detalle_orden       AFTER INSERT OR UPDATE OR DELETE ON detalle_orden       FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_detalle');
CREATE OR REPLACE TRIGGER tg_auditoria_resultado           AFTER INSERT OR UPDATE OR DELETE ON resultado           FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_resultado');
CREATE OR REPLACE TRIGGER tg_auditoria_recomendacion       AFTER INSERT OR UPDATE OR DELETE ON recomendacion       FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_recomendacion');
CREATE OR REPLACE TRIGGER tg_auditoria_decision_medica     AFTER INSERT OR UPDATE OR DELETE ON decision_medica     FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_decision');
CREATE OR REPLACE TRIGGER tg_auditoria_version_regla       AFTER INSERT OR UPDATE OR DELETE ON version_regla       FOR EACH ROW EXECUTE FUNCTION fn_auditoria('id_version_regla');
