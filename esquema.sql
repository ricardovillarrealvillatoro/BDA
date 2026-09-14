-- ============================================================================
-- Plataforma de apoyo a decisiones clinicas
-- Esquema relacional normalizado (3FN / BCNF) - PostgreSQL
-- Bases de Datos Avanzadas - SC3303 - Actividad de Avance del Proyecto Final
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- provee gen_random_uuid()

-- ============================================================================
-- 1. USUARIO  (para auditoria)
-- ============================================================================
CREATE TABLE usuario (
    usuario_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(150) NOT NULL,
    rol             VARCHAR(30)  NOT NULL
                        CHECK (rol IN ('medico', 'admin', 'auditor'))
);

-- ============================================================================
-- 2. MEDICO
-- ============================================================================
CREATE TABLE medico (
    medico_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(150) NOT NULL,
    especialidad    VARCHAR(100) NOT NULL,
    licencia        VARCHAR(30)  NOT NULL UNIQUE
);

-- ============================================================================
-- 3. PACIENTE
-- ============================================================================
CREATE TABLE paciente (
    paciente_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre            VARCHAR(150) NOT NULL,
    fecha_nacimiento  DATE NOT NULL,
    sexo              VARCHAR(20) NOT NULL
                          CHECK (sexo IN ('M', 'F', 'Otro')),
    identificacion    VARCHAR(30) NOT NULL UNIQUE,
    telefono          VARCHAR(20),
    direccion         VARCHAR(200)
);

-- ============================================================================
-- 4. ENCUENTRO
-- ============================================================================
CREATE TABLE encuentro (
    encuentro_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    paciente_id     UUID NOT NULL REFERENCES paciente(paciente_id),
    medico_id       UUID NOT NULL REFERENCES medico(medico_id),
    fecha_hora      TIMESTAMP NOT NULL DEFAULT now(),
    tipo            VARCHAR(30) NOT NULL
                        CHECK (tipo IN ('consulta', 'urgencia', 'hospitalizacion')),
    motivo          TEXT
);

CREATE INDEX idx_encuentro_paciente ON encuentro(paciente_id);
CREATE INDEX idx_encuentro_medico   ON encuentro(medico_id);
CREATE INDEX idx_encuentro_fecha    ON encuentro(fecha_hora);

-- ============================================================================
-- 5. CATALOGO_PRUEBA
-- ============================================================================
CREATE TABLE catalogo_prueba (
    prueba_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(150) NOT NULL,
    tipo            VARCHAR(50) NOT NULL
                        CHECK (tipo IN ('laboratorio', 'imagen', 'genomica', 'otro')),
    unidad_medida   VARCHAR(20)
);

-- ============================================================================
-- 6. ORDEN_MEDICA
-- ============================================================================
CREATE TABLE orden_medica (
    orden_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encuentro_id    UUID NOT NULL REFERENCES encuentro(encuentro_id),
    prueba_id       UUID NOT NULL REFERENCES catalogo_prueba(prueba_id),
    fecha_hora      TIMESTAMP NOT NULL DEFAULT now(),
    estado          VARCHAR(20) NOT NULL DEFAULT 'pendiente'
                        CHECK (estado IN ('pendiente', 'en_proceso', 'completada', 'cancelada'))
);

CREATE INDEX idx_orden_encuentro ON orden_medica(encuentro_id);
CREATE INDEX idx_orden_prueba    ON orden_medica(prueba_id);

-- ============================================================================
-- 7. RESULTADO
-- ============================================================================
CREATE TABLE resultado (
    resultado_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    orden_id        UUID NOT NULL REFERENCES orden_medica(orden_id),
    valor           NUMERIC(12,4) NOT NULL,
    unidad          VARCHAR(20),
    es_critico      BOOLEAN NOT NULL DEFAULT false,
    fecha_hora      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_resultado_orden    ON resultado(orden_id);
CREATE INDEX idx_resultado_critico  ON resultado(es_critico) WHERE es_critico = true;

-- ============================================================================
-- 8. DIAGNOSTICO
-- ============================================================================
CREATE TABLE diagnostico (
    diagnostico_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encuentro_id    UUID NOT NULL REFERENCES encuentro(encuentro_id),
    codigo_cie10    VARCHAR(10) NOT NULL,
    descripcion     VARCHAR(300) NOT NULL,
    fecha           DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX idx_diagnostico_encuentro ON diagnostico(encuentro_id);
CREATE INDEX idx_diagnostico_cie10     ON diagnostico(codigo_cie10);

-- ============================================================================
-- 9. REGLA_CLINICA
-- ============================================================================
CREATE TABLE regla_clinica (
    regla_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre              VARCHAR(150) NOT NULL UNIQUE,
    condicion_desc      TEXT NOT NULL,
    prioridad_default   VARCHAR(20) NOT NULL
                            CHECK (prioridad_default IN ('baja', 'media', 'alta', 'critica')),
    activa              BOOLEAN NOT NULL DEFAULT true
);

-- ============================================================================
-- 10. RECOMENDACION
-- ============================================================================
CREATE TABLE recomendacion (
    recomendacion_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encuentro_id           UUID NOT NULL REFERENCES encuentro(encuentro_id),
    regla_id               UUID NOT NULL REFERENCES regla_clinica(regla_id),
    fecha_hora             TIMESTAMP NOT NULL DEFAULT now(),
    prioridad              VARCHAR(20) NOT NULL
                                CHECK (prioridad IN ('baja', 'media', 'alta', 'critica')),
    ref_explicacion_mongo  VARCHAR(50)  -- referencia a coleccion explicaciones_recomendacion (MongoDB)
);

CREATE INDEX idx_recomendacion_encuentro ON recomendacion(encuentro_id);
CREATE INDEX idx_recomendacion_regla     ON recomendacion(regla_id);
CREATE INDEX idx_recomendacion_prioridad ON recomendacion(prioridad);

-- ============================================================================
-- 11. DECISION_MEDICA
--     Relacion 1 a 1 con RECOMENDACION: recomendacion_id es UNIQUE
-- ============================================================================
CREATE TABLE decision_medica (
    decision_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recomendacion_id    UUID NOT NULL UNIQUE REFERENCES recomendacion(recomendacion_id),
    medico_id           UUID NOT NULL REFERENCES medico(medico_id),
    tipo_decision        VARCHAR(20) NOT NULL
                             CHECK (tipo_decision IN ('aceptada', 'rechazada', 'modificada')),
    justificacion        TEXT,
    fecha_hora           TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_justificacion_requerida
        CHECK (tipo_decision = 'aceptada' OR justificacion IS NOT NULL)
);

CREATE INDEX idx_decision_medico ON decision_medica(medico_id);

-- ============================================================================
-- 12. REFERENCIA_IMAGEN
-- ============================================================================
CREATE TABLE referencia_imagen (
    imagen_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encuentro_id          UUID NOT NULL REFERENCES encuentro(encuentro_id),
    tipo_estudio          VARCHAR(50) NOT NULL,
    url_dicom             VARCHAR(300) NOT NULL,
    ref_metadata_mongo    VARCHAR(50)  -- referencia a coleccion metadatos_imagen (MongoDB)
);

CREATE INDEX idx_imagen_encuentro ON referencia_imagen(encuentro_id);

-- ============================================================================
-- 13. VARIANTE_GENOMICA_REF
-- ============================================================================
CREATE TABLE variante_genomica_ref (
    variante_ref_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    paciente_id          UUID NOT NULL REFERENCES paciente(paciente_id),
    ref_documento_mongo  VARCHAR(50) NOT NULL  -- referencia a coleccion variantes_genomicas (MongoDB)
);

CREATE INDEX idx_variante_paciente ON variante_genomica_ref(paciente_id);

-- ============================================================================
-- 14. SIGNOS_VITALES_REF
-- ============================================================================
CREATE TABLE signos_vitales_ref (
    signos_ref_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encuentro_id      UUID NOT NULL REFERENCES encuentro(encuentro_id),
    ref_serie_mongo   VARCHAR(50) NOT NULL  -- referencia a coleccion signos_vitales (MongoDB)
);

CREATE INDEX idx_signos_encuentro ON signos_vitales_ref(encuentro_id);

-- ============================================================================
-- 15. AUDITORIA
-- ============================================================================
CREATE TABLE auditoria (
    auditoria_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id       UUID NOT NULL REFERENCES usuario(usuario_id),
    tabla_afectada   VARCHAR(50) NOT NULL,
    accion           VARCHAR(20) NOT NULL
                          CHECK (accion IN ('insert', 'update', 'delete')),
    fecha_hora       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_auditoria_usuario ON auditoria(usuario_id);
CREATE INDEX idx_auditoria_tabla   ON auditoria(tabla_afectada);
CREATE INDEX idx_auditoria_fecha   ON auditoria(fecha_hora);

-- ============================================================================
-- Comentarios de documentacion (diccionario de datos embebido en el esquema)
-- ============================================================================
COMMENT ON TABLE paciente IS 'Datos demograficos del paciente';
COMMENT ON TABLE medico IS 'Datos del profesional medico';
COMMENT ON TABLE usuario IS 'Usuario del sistema, usado para trazabilidad en auditoria';
COMMENT ON TABLE encuentro IS 'Encuentro clinico entre un paciente y un medico';
COMMENT ON TABLE catalogo_prueba IS 'Catalogo maestro de pruebas disponibles';
COMMENT ON TABLE orden_medica IS 'Orden de una prueba del catalogo dentro de un encuentro';
COMMENT ON TABLE resultado IS 'Resultado atomico producido por una orden medica';
COMMENT ON TABLE diagnostico IS 'Diagnostico registrado durante un encuentro (CIE-10)';
COMMENT ON TABLE regla_clinica IS 'Regla configurable del motor de recomendaciones (simulado, no diagnostico real)';
COMMENT ON TABLE recomendacion IS 'Recomendacion generada por el sistema a partir de una regla clinica';
COMMENT ON TABLE decision_medica IS 'Decision del medico sobre una recomendacion: unica y siempre humana (1 a 1 con recomendacion)';
COMMENT ON TABLE referencia_imagen IS 'Referencia a un estudio de imagen; metadatos DICOM extendidos viven en MongoDB';
COMMENT ON TABLE variante_genomica_ref IS 'Referencia a variantes genomicas de esquema flexible almacenadas en MongoDB';
COMMENT ON TABLE signos_vitales_ref IS 'Referencia a la serie temporal de signos vitales almacenada en MongoDB';
COMMENT ON TABLE auditoria IS 'Registro de acciones (insert/update/delete) ejecutadas por usuarios del sistema';

COMMENT ON COLUMN recomendacion.ref_explicacion_mongo IS 'Apunta a la coleccion explicaciones_recomendacion en MongoDB (razonamiento/evidencia del copiloto)';
COMMENT ON COLUMN referencia_imagen.ref_metadata_mongo IS 'Apunta a la coleccion metadatos_imagen en MongoDB (tags DICOM, hallazgos preliminares)';
COMMENT ON COLUMN variante_genomica_ref.ref_documento_mongo IS 'Apunta a la coleccion variantes_genomicas en MongoDB';
COMMENT ON COLUMN signos_vitales_ref.ref_serie_mongo IS 'Apunta a la coleccion signos_vitales en MongoDB';
COMMENT ON CONSTRAINT chk_justificacion_requerida ON decision_medica IS 'Exige justificacion cuando la decision no es una aceptacion simple (rechazo o modificacion)';
