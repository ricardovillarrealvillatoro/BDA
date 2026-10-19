-- =====================================================================
-- MedAssist AI · Procedimientos almacenados (15, se invocan con CALL desde Flask)
-- Documentación completa (parámetros, tablas, reglas, excepciones, ejemplos y
-- resultados obtenidos): docs/procedimientos.md
-- =====================================================================

-- Alta de un paciente; rechaza fecha de nacimiento futura y CURP repetida (USING COLUMN para el formulario).
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
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura.'
            USING ERRCODE = 'check_violation', COLUMN = 'fecha_nacimiento';
    END IF;
    IF EXISTS (SELECT 1 FROM paciente WHERE curp = p_curp) THEN
        RAISE EXCEPTION 'Ya existe un paciente con la CURP %.', p_curp
            USING ERRCODE = 'unique_violation', COLUMN = 'curp';
    END IF;

    INSERT INTO paciente (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, telefono, email, direccion)
    VALUES (p_curp, p_nombre, p_apellido_paterno, p_apellido_materno, p_fecha_nacimiento, p_sexo, p_telefono, p_email, p_direccion)
    RETURNING id_paciente INTO p_id_paciente;
END;
$$;

-- Baja lógica de un paciente: se conserva la fila y su historial clínico.
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

-- Abre una consulta: paciente activo, médico activo y una sola consulta abierta por paciente.
CREATE OR REPLACE PROCEDURE sp_abrir_encuentro(
    IN p_id_paciente BIGINT,
    IN p_id_medico BIGINT,
    IN p_tipo VARCHAR(20),
    IN p_motivo TEXT,
    OUT p_id_encuentro BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM paciente WHERE id_paciente = p_id_paciente AND activo) THEN
        RAISE EXCEPTION 'El paciente no existe o está dado de baja.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_medico AND activo)
       OR NOT EXISTS (SELECT 1 FROM medico WHERE id_medico = p_id_medico) THEN
        RAISE EXCEPTION 'El médico no existe o su cuenta está desactivada.';
    END IF;
    IF EXISTS (SELECT 1 FROM encuentro WHERE id_paciente = p_id_paciente AND estado = 'abierto') THEN
        RAISE EXCEPTION 'El paciente ya tiene una consulta abierta en curso.';
    END IF;

    INSERT INTO encuentro (id_paciente, id_medico, tipo, estado, fecha_inicio, motivo)
    VALUES (p_id_paciente, p_id_medico, p_tipo, 'abierto', NOW(), p_motivo)
    RETURNING id_encuentro INTO p_id_encuentro;
END;
$$;

-- Cierra una consulta abierta; con p_notas NULL se conservan las notas que ya tenía.
CREATE OR REPLACE PROCEDURE sp_cerrar_encuentro(
    IN p_id_encuentro BIGINT,
    IN p_notas TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE encuentro
    SET estado = 'cerrado',
        fecha_fin = NOW(),
        notas = COALESCE(p_notas, notas)
    WHERE id_encuentro = p_id_encuentro AND estado = 'abierto';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La consulta % no existe o ya fue cerrada/cancelada.', p_id_encuentro;
    END IF;
END;
$$;

-- Agrega un diagnóstico CIE-10; las restricciones de la tabla impiden un segundo principal o un código repetido.
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

-- Receta interna con fecha de inicio de hoy; la tabla valida dosis, frecuencia y que no se repita el mismo día.
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

-- Crea una orden de laboratorio pendiente; Flask agrega sus pruebas (detalle_orden) en la misma transacción.
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

-- Guarda el resultado de una prueba y la marca como reportada en la misma transacción.
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

-- Decisión del médico sobre una recomendación del copiloto (una por recomendación).
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

-- Asigna una especialidad; si es principal, la anterior deja de serlo (solo una principal por médico).
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

-- Alta de un médico: cuenta de usuario, rol "medico", cédula y (opcional) especialidad principal.
-- Los errores de duplicado indican la columna (USING COLUMN) para mostrarlos junto al campo del formulario.
CREATE OR REPLACE PROCEDURE sp_registrar_medico(
    IN p_username VARCHAR(50),
    IN p_password_hash VARCHAR(255),
    IN p_nombre VARCHAR(80),
    IN p_apellido_paterno VARCHAR(60),
    IN p_apellido_materno VARCHAR(60),
    IN p_email VARCHAR(120),
    IN p_cedula_profesional VARCHAR(20),
    IN p_id_especialidad BIGINT,
    IN p_cedula_especialidad VARCHAR(20),
    OUT p_id_medico BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM usuario WHERE username = p_username) THEN
        RAISE EXCEPTION 'El usuario % ya existe.', p_username
            USING ERRCODE = 'unique_violation', COLUMN = 'username';
    END IF;
    IF EXISTS (SELECT 1 FROM usuario WHERE lower(email) = lower(p_email)) THEN
        RAISE EXCEPTION 'El correo % ya está registrado.', p_email
            USING ERRCODE = 'unique_violation', COLUMN = 'email';
    END IF;
    IF EXISTS (SELECT 1 FROM medico WHERE cedula_profesional = p_cedula_profesional) THEN
        RAISE EXCEPTION 'La cédula profesional % ya está registrada.', p_cedula_profesional
            USING ERRCODE = 'unique_violation', COLUMN = 'cedula_profesional';
    END IF;
    IF p_id_especialidad IS NOT NULL AND
       EXISTS (SELECT 1 FROM medico_especialidad WHERE cedula_especialidad = p_cedula_especialidad) THEN
        RAISE EXCEPTION 'La cédula de especialidad % ya está registrada.', p_cedula_especialidad
            USING ERRCODE = 'unique_violation', COLUMN = 'cedula_especialidad';
    END IF;

    INSERT INTO usuario (username, password_hash, nombre, apellido_paterno, apellido_materno, email)
    VALUES (p_username, p_password_hash, p_nombre, p_apellido_paterno, p_apellido_materno, p_email)
    RETURNING id_usuario INTO p_id_medico;

    INSERT INTO usuario_rol (id_usuario, id_rol)
    SELECT p_id_medico, id_rol FROM rol WHERE nombre = 'medico';

    INSERT INTO medico (id_medico, cedula_profesional)
    VALUES (p_id_medico, p_cedula_profesional);

    IF p_id_especialidad IS NOT NULL THEN
        CALL sp_asignar_especialidad_medico(p_id_medico, p_id_especialidad, p_cedula_especialidad, TRUE);
    END IF;
END;
$$;

-- Cambia los datos de un médico; correo y cédula no pueden ser de otro usuario.
CREATE OR REPLACE PROCEDURE sp_actualizar_medico(
    IN p_id_medico BIGINT,
    IN p_nombre VARCHAR(80),
    IN p_apellido_paterno VARCHAR(60),
    IN p_apellido_materno VARCHAR(60),
    IN p_email VARCHAR(120),
    IN p_cedula_profesional VARCHAR(20)
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM medico WHERE id_medico = p_id_medico) THEN
        RAISE EXCEPTION 'El médico con ID % no existe.', p_id_medico;
    END IF;
    IF EXISTS (SELECT 1 FROM usuario WHERE lower(email) = lower(p_email) AND id_usuario <> p_id_medico) THEN
        RAISE EXCEPTION 'El correo % ya está registrado.', p_email
            USING ERRCODE = 'unique_violation', COLUMN = 'email';
    END IF;
    IF EXISTS (SELECT 1 FROM medico WHERE cedula_profesional = p_cedula_profesional AND id_medico <> p_id_medico) THEN
        RAISE EXCEPTION 'La cédula profesional % ya está registrada.', p_cedula_profesional
            USING ERRCODE = 'unique_violation', COLUMN = 'cedula_profesional';
    END IF;

    UPDATE usuario
    SET nombre = p_nombre,
        apellido_paterno = p_apellido_paterno,
        apellido_materno = p_apellido_materno,
        email = p_email
    WHERE id_usuario = p_id_medico;

    UPDATE medico SET cedula_profesional = p_cedula_profesional WHERE id_medico = p_id_medico;
END;
$$;

-- Baja lógica (o reactivación) de la cuenta de un médico; su historial clínico se conserva
CREATE OR REPLACE PROCEDURE sp_cambiar_estado_medico(
    IN p_id_medico BIGINT,
    IN p_activo BOOLEAN
)
LANGUAGE plpgsql AS $$
DECLARE
    v_abiertas INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM medico WHERE id_medico = p_id_medico) THEN
        RAISE EXCEPTION 'El médico con ID % no existe.', p_id_medico;
    END IF;

    IF NOT p_activo THEN
        SELECT COUNT(*) INTO v_abiertas FROM encuentro WHERE id_medico = p_id_medico AND estado = 'abierto';
        IF v_abiertas > 0 THEN
            RAISE EXCEPTION 'El médico tiene % consulta(s) abierta(s). Ciérrelas o cancélelas antes de desactivar la cuenta.', v_abiertas;
        END IF;
    END IF;

    UPDATE usuario SET activo = p_activo WHERE id_usuario = p_id_medico AND activo <> p_activo;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta del médico ya está %.', CASE WHEN p_activo THEN 'activa' ELSE 'desactivada' END;
    END IF;
END;
$$;

-- Corrige tipo, motivo o notas de una consulta que sigue abierta.
CREATE OR REPLACE PROCEDURE sp_actualizar_encuentro(
    IN p_id_encuentro BIGINT,
    IN p_tipo VARCHAR(20),
    IN p_motivo TEXT,
    IN p_notas TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE encuentro
    SET tipo = p_tipo,
        motivo = p_motivo,
        notas = p_notas
    WHERE id_encuentro = p_id_encuentro AND estado = 'abierto';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La consulta % no existe o ya fue cerrada/cancelada.', p_id_encuentro;
    END IF;
END;
$$;

-- Cancelación de una consulta abierta por error: solo si todavía no tiene información clínica
-- (resultados, diagnósticos confirmados o decisiones sobre recomendaciones). Sus órdenes pendientes se cancelan.
CREATE OR REPLACE PROCEDURE sp_cancelar_encuentro(
    IN p_id_encuentro BIGINT,
    IN p_motivo TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF length(trim(coalesce(p_motivo, ''))) < 10 THEN
        RAISE EXCEPTION 'Explique el motivo de la cancelación (mínimo 10 caracteres).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM encuentro WHERE id_encuentro = p_id_encuentro AND estado = 'abierto') THEN
        RAISE EXCEPTION 'La consulta % no existe o ya fue cerrada/cancelada.', p_id_encuentro;
    END IF;
    IF EXISTS (SELECT 1 FROM resultado r
               JOIN detalle_orden d ON r.id_detalle = d.id_detalle
               JOIN orden_medica o ON d.id_orden = o.id_orden
               WHERE o.id_encuentro = p_id_encuentro) THEN
        RAISE EXCEPTION 'No se puede cancelar: la consulta ya tiene resultados de laboratorio.';
    END IF;
    IF EXISTS (SELECT 1 FROM diagnostico WHERE id_encuentro = p_id_encuentro AND estado = 'confirmado') THEN
        RAISE EXCEPTION 'No se puede cancelar: la consulta ya tiene diagnósticos confirmados.';
    END IF;
    IF EXISTS (SELECT 1 FROM decision_medica dm
               JOIN recomendacion r ON dm.id_recomendacion = r.id_recomendacion
               WHERE r.id_encuentro = p_id_encuentro) THEN
        RAISE EXCEPTION 'No se puede cancelar: ya hay decisiones médicas sobre sus recomendaciones.';
    END IF;

    UPDATE detalle_orden SET estado = 'cancelada'
    WHERE estado IN ('pendiente', 'tomada')
      AND id_orden IN (SELECT id_orden FROM orden_medica WHERE id_encuentro = p_id_encuentro);

    UPDATE orden_medica SET estado = 'cancelada'
    WHERE id_encuentro = p_id_encuentro AND estado IN ('pendiente', 'en_proceso');

    UPDATE encuentro
    SET estado = 'cancelado',
        fecha_fin = NOW(),
        notas = concat_ws(E'\n', notas, 'Cancelada: ' || trim(p_motivo))
    WHERE id_encuentro = p_id_encuentro;
END;
$$;
