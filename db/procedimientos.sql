CREATE OR REPLACE PROCEDURE sp_registrar_paciente(
    IN p_curp CHAR(18),
    IN p_nombre VARCHAR(80),
    IN p_apellido_paterno VARCHAR(60),
    IN p_apellido_materno VARCHAR(60),
    IN p_fecha_nacimiento DATE,
    IN p_sexo CHAR(1),
    IN p_telefono VARCHAR(20),
    IN p_email VARCHAR(120),
    IN p_direccion VARCHAR(200),
    OUT p_id_paciente BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_fecha_nacimiento > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura.';
    END IF;

    INSERT INTO paciente (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, telefono, email, direccion)
    VALUES (p_curp, p_nombre, p_apellido_paterno, p_apellido_materno, p_fecha_nacimiento, p_sexo, p_telefono, p_email, p_direccion)
    RETURNING id_paciente INTO p_id_paciente;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_desactivar_paciente(
    IN p_id_paciente BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE paciente
    SET activo = FALSE,
        fecha_baja = NOW()
    WHERE id_paciente = p_id_paciente AND activo = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El paciente con ID % no existe o ya está desactivado.', p_id_paciente;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_abrir_encuentro(
    IN p_id_paciente BIGINT,
    IN p_id_medico BIGINT,
    IN p_tipo VARCHAR(20),
    IN p_motivo TEXT,
    OUT p_id_encuentro BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM encuentro WHERE id_paciente = p_id_paciente AND estado = 'abierto') THEN
        RAISE EXCEPTION 'El paciente ya tiene una consulta abierta en curso.';
    END IF;

    INSERT INTO encuentro (id_paciente, id_medico, tipo, estado, fecha_inicio, motivo)
    VALUES (p_id_paciente, p_id_medico, p_tipo, 'abierto', NOW(), p_motivo)
    RETURNING id_encuentro INTO p_id_encuentro;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_cerrar_encuentro(
    IN p_id_encuentro BIGINT,
    IN p_notas TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE encuentro
    SET estado = 'cerrado',
        fecha_fin = NOW(),
        notas = p_notas
    WHERE id_encuentro = p_id_encuentro AND estado = 'abierto';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La consulta % no existe o ya fue cerrada/cancelada.', p_id_encuentro;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_registrar_diagnostico(
    IN p_id_encuentro BIGINT,
    IN p_codigo_cie10 VARCHAR(10),
    IN p_tipo VARCHAR(12),
    IN p_estado VARCHAR(12)
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO diagnostico (id_encuentro, codigo_cie10, tipo, estado, fecha)
    VALUES (p_id_encuentro, p_codigo_cie10, p_tipo, p_estado, NOW());
END;
$$;

CREATE OR REPLACE PROCEDURE sp_prescribir_medicamento(
    IN p_id_encuentro BIGINT,
    IN p_id_medicamento BIGINT,
    IN p_id_medico BIGINT,
    IN p_dosis NUMERIC(10,3),
    IN p_id_unidad_dosis BIGINT,
    IN p_id_via BIGINT,
    IN p_frecuencia_horas SMALLINT,
    IN p_indicacion TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO prescripcion (id_encuentro, id_medicamento, id_medico, origen, dosis, id_unidad_dosis, id_via, frecuencia_horas, fecha_inicio, indicacion)
    VALUES (p_id_encuentro, p_id_medicamento, p_id_medico, 'interna', p_dosis, p_id_unidad_dosis, p_id_via, p_frecuencia_horas, CURRENT_DATE, p_indicacion);
END;
$$;

CREATE OR REPLACE PROCEDURE sp_generar_orden_medica(
    IN p_id_encuentro BIGINT,
    IN p_id_medico BIGINT,
    IN p_prioridad VARCHAR(8),
    OUT p_id_orden BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO orden_medica (id_encuentro, id_medico, prioridad, estado)
    VALUES (p_id_encuentro, p_id_medico, p_prioridad, 'pendiente')
    RETURNING id_orden INTO p_id_orden;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_registrar_resultado_laboratorio(
    IN p_id_detalle BIGINT,
    IN p_valor_numerico NUMERIC(12,4),
    IN p_valor_texto TEXT,
    IN p_id_validador BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO resultado (id_detalle, valor_numerico, valor_texto, id_validador, fecha_resultado)
    VALUES (p_id_detalle, p_valor_numerico, p_valor_texto, p_id_validador, NOW());

    UPDATE detalle_orden SET estado = 'reportada' WHERE id_detalle = p_id_detalle;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_registrar_decision_medica(
    IN p_id_recomendacion BIGINT,
    IN p_id_medico BIGINT,
    IN p_tipo VARCHAR(10),
    IN p_justificacion TEXT,
    IN p_accion_final TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO decision_medica (id_recomendacion, id_medico, tipo, justificacion, accion_final, fecha_hora)
    VALUES (p_id_recomendacion, p_id_medico, p_tipo, p_justificacion, p_accion_final, NOW());
END;
$$;

CREATE OR REPLACE PROCEDURE sp_asignar_especialidad_medico(
    IN p_id_medico BIGINT,
    IN p_id_especialidad BIGINT,
    IN p_cedula_especialidad VARCHAR(20),
    IN p_es_principal BOOLEAN
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_es_principal THEN
        UPDATE medico_especialidad SET es_principal = FALSE WHERE id_medico = p_id_medico;
    END IF;

    INSERT INTO medico_especialidad (id_medico, id_especialidad, cedula_especialidad, es_principal)
    VALUES (p_id_medico, p_id_especialidad, p_cedula_especialidad, p_es_principal);
END;
$$;
