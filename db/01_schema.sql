SET client_min_messages = warning;
-- MedAssist AI · Tablas, restricciones e índices (PostgreSQL 14+)
-- Las columnas mongo_* guardan el id del documento en MongoDB (se integra en una fase posterior).

-- Borra lo anterior del esquema public; sin DROP SCHEMA porque en Cloud SQL public no es del usuario de la app
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'public' LOOP
    EXECUTE format('DROP VIEW IF EXISTS public.%I CASCADE', r.viewname);
  END LOOP;
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', r.tablename);
  END LOOP;
  FOR r IN SELECT p.oid::regprocedure AS firma, p.prokind
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.prokind IN ('f','p') LOOP
    EXECUTE format('DROP %s IF EXISTS %s CASCADE',
                   CASE r.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, r.firma);
  END LOOP;
END $$;

-- A. Usuarios, médicos y auditoría
CREATE TABLE usuario (
  id_usuario        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  username          VARCHAR(50)  NOT NULL UNIQUE,
  password_hash     VARCHAR(255) NOT NULL,
  nombre            VARCHAR(80)  NOT NULL,
  apellido_paterno  VARCHAR(60)  NOT NULL,
  apellido_materno  VARCHAR(60),
  email             VARCHAR(120) NOT NULL UNIQUE,
  activo            BOOLEAN      NOT NULL DEFAULT true,
  fecha_alta        TIMESTAMP    NOT NULL DEFAULT now(),
  CONSTRAINT ck_usuario_username CHECK (username ~ '^[a-z0-9._]{3,50}$'),
  CONSTRAINT ck_usuario_email    CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

CREATE TABLE rol (
  id_rol  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre  VARCHAR(30) NOT NULL UNIQUE
          CHECK (nombre IN ('medico','admin_clinico','auditor','sistema'))
);

CREATE TABLE usuario_rol (
  id_usuario BIGINT NOT NULL REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  id_rol     BIGINT NOT NULL REFERENCES rol(id_rol),
  PRIMARY KEY (id_usuario, id_rol)
);

-- Subtipo de USUARIO: PK compartida (no lleva IDENTITY)
CREATE TABLE medico (
  id_medico           BIGINT PRIMARY KEY REFERENCES usuario(id_usuario),
  cedula_profesional  VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE especialidad (
  id_especialidad BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre          VARCHAR(100) NOT NULL UNIQUE,
  descripcion     TEXT
);

CREATE TABLE medico_especialidad (
  id_medico            BIGINT NOT NULL REFERENCES medico(id_medico),
  id_especialidad      BIGINT NOT NULL REFERENCES especialidad(id_especialidad),
  cedula_especialidad  VARCHAR(20) NOT NULL UNIQUE,
  es_principal         BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (id_medico, id_especialidad)
);
CREATE UNIQUE INDEX ux_medico_especialidad_principal
  ON medico_especialidad(id_medico) WHERE es_principal;

CREATE TABLE auditoria (
  id_auditoria       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario         BIGINT REFERENCES usuario(id_usuario),
  tabla              VARCHAR(50) NOT NULL,
  id_registro        VARCHAR(64) NOT NULL,
  accion             VARCHAR(10) NOT NULL CHECK (accion IN ('INSERT','UPDATE','DELETE')),
  valores_anteriores JSONB,
  valores_nuevos     JSONB,
  ip                 INET,
  fecha_hora         TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_fecha   ON auditoria(fecha_hora DESC);
CREATE INDEX ix_auditoria_usuario ON auditoria(id_usuario);
CREATE INDEX ix_auditoria_tabla   ON auditoria(tabla);

-- B. Paciente, antecedentes, encuentros y diagnósticos
CREATE TABLE paciente (
  id_paciente       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  curp              CHAR(18)     NOT NULL UNIQUE,
  nombre            VARCHAR(80)  NOT NULL,
  apellido_paterno  VARCHAR(60)  NOT NULL,
  apellido_materno  VARCHAR(60),
  fecha_nacimiento  DATE         NOT NULL,
  sexo              CHAR(1)      NOT NULL CHECK (sexo IN ('F','M','I')),
  telefono          VARCHAR(20),
  email             VARCHAR(120),
  direccion         VARCHAR(200),
  activo            BOOLEAN      NOT NULL DEFAULT true,
  fecha_baja        TIMESTAMP,
  CONSTRAINT ck_paciente_curp  CHECK (curp ~ '^[A-Z]{4}[0-9]{6}[HMX][A-Z]{5}[A-Z0-9][0-9]$'),
  CONSTRAINT ck_paciente_nac   CHECK (fecha_nacimiento <= current_date),
  CONSTRAINT ck_paciente_baja  CHECK (activo OR fecha_baja IS NOT NULL)
);
CREATE INDEX ix_paciente_apellidos ON paciente(apellido_paterno, apellido_materno, nombre);

CREATE TABLE tipo_antecedente (
  id_tipo_antecedente BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre              VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE catalogo_cie10 (
  codigo_cie10 VARCHAR(10)  PRIMARY KEY,
  descripcion  VARCHAR(300) NOT NULL,
  capitulo     VARCHAR(10)  NOT NULL
);

CREATE TABLE antecedente (
  id_antecedente      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_paciente         BIGINT NOT NULL REFERENCES paciente(id_paciente),
  id_tipo_antecedente BIGINT NOT NULL REFERENCES tipo_antecedente(id_tipo_antecedente),
  codigo_cie10        VARCHAR(10) REFERENCES catalogo_cie10(codigo_cie10),
  descripcion         TEXT,
  parentesco          VARCHAR(30),
  fecha_inicio        DATE,
  estado              VARCHAR(10) NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','resuelto')),
  CONSTRAINT ck_antecedente_contenido CHECK (codigo_cie10 IS NOT NULL OR descripcion IS NOT NULL)
);
CREATE INDEX ix_antecedente_paciente ON antecedente(id_paciente);

CREATE TABLE encuentro (
  id_encuentro  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_paciente   BIGINT      NOT NULL REFERENCES paciente(id_paciente),
  id_medico     BIGINT      NOT NULL REFERENCES medico(id_medico),
  tipo          VARCHAR(20) NOT NULL CHECK (tipo IN ('consulta','urgencia','hospitalizacion')),
  estado        VARCHAR(10) NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto','cerrado','cancelado')),
  fecha_inicio  TIMESTAMP   NOT NULL DEFAULT now(),
  fecha_fin     TIMESTAMP,
  motivo        TEXT        NOT NULL CHECK (length(trim(motivo)) >= 5),
  notas         TEXT,
  CONSTRAINT uq_encuentro_paciente_fecha UNIQUE (id_paciente, fecha_inicio),
  CONSTRAINT ck_encuentro_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
  CONSTRAINT ck_encuentro_cierre CHECK (estado = 'abierto' OR fecha_fin IS NOT NULL)
);
CREATE INDEX ix_encuentro_paciente ON encuentro(id_paciente, fecha_inicio DESC);
CREATE INDEX ix_encuentro_medico   ON encuentro(id_medico, fecha_inicio DESC);
CREATE INDEX ix_encuentro_estado   ON encuentro(estado);
-- A lo más una consulta abierta por paciente (respaldo de la validación de sp_abrir_encuentro ante concurrencia)
CREATE UNIQUE INDEX ux_encuentro_abierto_paciente ON encuentro(id_paciente) WHERE estado = 'abierto';

CREATE TABLE diagnostico (
  id_diagnostico BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_encuentro   BIGINT      NOT NULL REFERENCES encuentro(id_encuentro),
  codigo_cie10   VARCHAR(10) NOT NULL REFERENCES catalogo_cie10(codigo_cie10),
  tipo           VARCHAR(12) NOT NULL CHECK (tipo IN ('principal','secundario')),
  estado         VARCHAR(12) NOT NULL CHECK (estado IN ('presuntivo','confirmado','descartado')),
  fecha          TIMESTAMP   NOT NULL DEFAULT now(),
  CONSTRAINT uq_diagnostico UNIQUE (id_encuentro, codigo_cie10)
);
CREATE UNIQUE INDEX ux_diagnostico_principal ON diagnostico(id_encuentro) WHERE tipo = 'principal';

-- C. Medicamentos y tratamientos
CREATE TABLE unidad (
  id_unidad     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_ucum   VARCHAR(20)   NOT NULL UNIQUE,
  nombre        VARCHAR(50)   NOT NULL,
  magnitud      VARCHAR(30)   NOT NULL,
  factor_a_base NUMERIC(18,9) NOT NULL CHECK (factor_a_base > 0)
);

CREATE TABLE principio_activo (
  id_principio_activo BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_atc          VARCHAR(7)   NOT NULL UNIQUE,
  nombre              VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE alergia (
  id_alergia          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_paciente         BIGINT NOT NULL REFERENCES paciente(id_paciente),
  id_principio_activo BIGINT REFERENCES principio_activo(id_principio_activo),
  sustancia_otra      VARCHAR(100),
  reaccion            VARCHAR(150),
  severidad           VARCHAR(10) NOT NULL CHECK (severidad IN ('leve','moderada','grave')),
  fecha_registro      DATE NOT NULL DEFAULT current_date,
  CONSTRAINT ck_alergia_origen CHECK (num_nonnulls(id_principio_activo, sustancia_otra) = 1)
);
CREATE INDEX ix_alergia_paciente ON alergia(id_paciente);

CREATE TABLE medicamento (
  id_medicamento     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre_comercial   VARCHAR(100) NOT NULL,
  forma_farmaceutica VARCHAR(50)  NOT NULL,
  presentacion       VARCHAR(100) NOT NULL,
  CONSTRAINT uq_medicamento UNIQUE (nombre_comercial, forma_farmaceutica, presentacion)
);

CREATE TABLE medicamento_componente (
  id_medicamento      BIGINT NOT NULL REFERENCES medicamento(id_medicamento),
  id_principio_activo BIGINT NOT NULL REFERENCES principio_activo(id_principio_activo),
  concentracion       NUMERIC(10,3) NOT NULL CHECK (concentracion > 0),
  id_unidad           BIGINT NOT NULL REFERENCES unidad(id_unidad),
  PRIMARY KEY (id_medicamento, id_principio_activo)
);

CREATE TABLE interaccion (
  id_pa_a     BIGINT NOT NULL REFERENCES principio_activo(id_principio_activo),
  id_pa_b     BIGINT NOT NULL REFERENCES principio_activo(id_principio_activo),
  severidad   VARCHAR(10) NOT NULL CHECK (severidad IN ('menor','moderada','mayor')),
  descripcion TEXT NOT NULL,
  PRIMARY KEY (id_pa_a, id_pa_b),
  CONSTRAINT ck_interaccion_orden CHECK (id_pa_a < id_pa_b)
);

CREATE TABLE via_administracion (
  id_via BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE prescripcion (
  id_prescripcion   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_encuentro      BIGINT NOT NULL REFERENCES encuentro(id_encuentro),
  id_medicamento    BIGINT NOT NULL REFERENCES medicamento(id_medicamento),
  id_medico         BIGINT REFERENCES medico(id_medico),
  origen            VARCHAR(10) NOT NULL CHECK (origen IN ('interna','referida')),
  dosis             NUMERIC(10,3) NOT NULL CHECK (dosis > 0),
  id_unidad_dosis   BIGINT NOT NULL REFERENCES unidad(id_unidad),
  id_via            BIGINT NOT NULL REFERENCES via_administracion(id_via),
  frecuencia_horas  SMALLINT NOT NULL CHECK (frecuencia_horas > 0),
  fecha_inicio      DATE NOT NULL,
  fecha_fin         DATE,
  indicacion        TEXT,
  motivo_suspension TEXT,
  CONSTRAINT uq_prescripcion UNIQUE (id_encuentro, id_medicamento, fecha_inicio),
  CONSTRAINT ck_prescripcion_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
  CONSTRAINT ck_prescripcion_medico CHECK (origen <> 'interna' OR id_medico IS NOT NULL)
);
CREATE INDEX ix_prescripcion_encuentro ON prescripcion(id_encuentro);

-- D. Órdenes, laboratorio, imagen, signos vitales y genómica
CREATE TABLE prueba (
  id_prueba    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_loinc VARCHAR(10)  NOT NULL UNIQUE,
  nombre       VARCHAR(150) NOT NULL,
  tipo         VARCHAR(12)  NOT NULL CHECK (tipo IN ('laboratorio','imagen','genomica')),
  modalidad    VARCHAR(4)   CHECK (modalidad IN ('RX','TC','RM','US')),
  id_unidad    BIGINT REFERENCES unidad(id_unidad),
  CONSTRAINT ck_prueba_modalidad CHECK ((tipo = 'imagen') = (modalidad IS NOT NULL))
);

CREATE TABLE rango_referencia (
  id_rango       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_prueba      BIGINT NOT NULL REFERENCES prueba(id_prueba),
  sexo           CHAR(1) NOT NULL CHECK (sexo IN ('F','M','X')),
  edad_min_anios SMALLINT NOT NULL CHECK (edad_min_anios >= 0),
  edad_max_anios SMALLINT NOT NULL,
  ref_min        NUMERIC(12,4) NOT NULL,
  ref_max        NUMERIC(12,4) NOT NULL,
  critico_min    NUMERIC(12,4),
  critico_max    NUMERIC(12,4),
  CONSTRAINT uq_rango UNIQUE (id_prueba, sexo, edad_min_anios),
  CONSTRAINT ck_rango_edad CHECK (edad_max_anios > edad_min_anios),
  CONSTRAINT ck_rango_ref  CHECK (ref_min <= ref_max),
  CONSTRAINT ck_rango_crit CHECK ((critico_min IS NULL OR critico_min <= ref_min)
                              AND (critico_max IS NULL OR critico_max >= ref_max))
);

CREATE TABLE orden_medica (
  id_orden     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_encuentro BIGINT NOT NULL REFERENCES encuentro(id_encuentro),
  id_medico    BIGINT NOT NULL REFERENCES medico(id_medico),
  fecha_orden  TIMESTAMP NOT NULL DEFAULT now(),
  prioridad    VARCHAR(8)  NOT NULL CHECK (prioridad IN ('rutina','urgente')),
  estado       VARCHAR(12) NOT NULL DEFAULT 'pendiente'
               CHECK (estado IN ('pendiente','en_proceso','completada','cancelada'))
);
CREATE INDEX ix_orden_encuentro ON orden_medica(id_encuentro);

CREATE TABLE detalle_orden (
  id_detalle   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_orden     BIGINT NOT NULL REFERENCES orden_medica(id_orden),
  id_prueba    BIGINT NOT NULL REFERENCES prueba(id_prueba),
  indicaciones TEXT,
  estado       VARCHAR(10) NOT NULL DEFAULT 'pendiente'
               CHECK (estado IN ('pendiente','tomada','reportada','cancelada')),
  CONSTRAINT uq_detalle_orden UNIQUE (id_orden, id_prueba)
);

CREATE TABLE resultado (
  id_resultado    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_detalle      BIGINT NOT NULL REFERENCES detalle_orden(id_detalle),
  valor_numerico  NUMERIC(12,4),
  valor_texto     TEXT,
  fecha_resultado TIMESTAMP NOT NULL DEFAULT now(),
  id_validador    BIGINT REFERENCES usuario(id_usuario),
  CONSTRAINT uq_resultado UNIQUE (id_detalle, fecha_resultado),
  CONSTRAINT ck_resultado_valor CHECK (num_nonnulls(valor_numerico, valor_texto) >= 1)
);

CREATE TABLE estudio_imagen (
  id_estudio         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_detalle         BIGINT NOT NULL UNIQUE REFERENCES detalle_orden(id_detalle),
  uri_pacs           VARCHAR(300) NOT NULL,
  conclusion         TEXT,
  mongo_metadatos_id CHAR(24),
  fecha_estudio      TIMESTAMP NOT NULL
);

CREATE TABLE tipo_signo_vital (
  id_tipo_signo BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo        VARCHAR(10) NOT NULL UNIQUE,
  nombre        VARCHAR(60) NOT NULL,
  id_unidad     BIGINT NOT NULL REFERENCES unidad(id_unidad),
  ref_min       NUMERIC(8,2) NOT NULL,
  ref_max       NUMERIC(8,2) NOT NULL,
  critico_min   NUMERIC(8,2),
  critico_max   NUMERIC(8,2),
  CONSTRAINT ck_signo_ref CHECK (ref_min <= ref_max)
);

CREATE TABLE serie_signos_ref (
  id_serie       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_encuentro   BIGINT NOT NULL REFERENCES encuentro(id_encuentro),
  id_tipo_signo  BIGINT NOT NULL REFERENCES tipo_signo_vital(id_tipo_signo),
  mongo_serie_id CHAR(24) NOT NULL,
  fecha_inicio   TIMESTAMP NOT NULL,
  fecha_fin      TIMESTAMP,
  dispositivo    VARCHAR(80),
  CONSTRAINT uq_serie UNIQUE (id_encuentro, id_tipo_signo, fecha_inicio),
  CONSTRAINT ck_serie_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

CREATE TABLE estudio_genomico (
  id_estudio_genomico BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_paciente         BIGINT NOT NULL REFERENCES paciente(id_paciente),
  id_detalle          BIGINT UNIQUE REFERENCES detalle_orden(id_detalle),
  laboratorio         VARCHAR(100) NOT NULL,
  tipo_estudio        VARCHAR(16) NOT NULL CHECK (tipo_estudio IN ('panel','exoma','genoma','farmacogenomica')),
  fecha_estudio       DATE NOT NULL,
  mongo_variantes_id  CHAR(24) NOT NULL
);

-- E. Protocolos y reglas configurables
CREATE TABLE protocolo (
  id_protocolo       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo             VARCHAR(10)  NOT NULL UNIQUE,
  nombre             VARCHAR(150) NOT NULL,
  institucion_fuente VARCHAR(150) NOT NULL,
  area_clinica       VARCHAR(80)
);

CREATE TABLE version_protocolo (
  id_version_protocolo BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_protocolo         BIGINT NOT NULL REFERENCES protocolo(id_protocolo),
  version              VARCHAR(10) NOT NULL,
  fecha_publicacion    DATE NOT NULL,
  vigente_desde        DATE NOT NULL,
  vigente_hasta        DATE,
  uri_documento        VARCHAR(300),
  CONSTRAINT uq_version_protocolo UNIQUE (id_protocolo, version),
  CONSTRAINT ck_version_protocolo_vig CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);

CREATE TABLE regla_clinica (
  id_regla    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      VARCHAR(10)  NOT NULL UNIQUE,
  nombre      VARCHAR(150) NOT NULL UNIQUE,
  descripcion TEXT
);

CREATE TABLE version_regla (
  id_version_regla     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_regla             BIGINT NOT NULL REFERENCES regla_clinica(id_regla),
  numero_version       SMALLINT NOT NULL CHECK (numero_version >= 1),
  id_version_protocolo BIGINT NOT NULL REFERENCES version_protocolo(id_version_protocolo),
  tipo_accion          VARCHAR(10) NOT NULL CHECK (tipo_accion IN ('alerta','revision','sugerir','evitar')),
  id_pa_objetivo       BIGINT REFERENCES principio_activo(id_principio_activo),
  prioridad_base       VARCHAR(8) NOT NULL CHECK (prioridad_base IN ('baja','media','alta','critica')),
  plantilla_texto      TEXT NOT NULL,
  vigente_desde        DATE NOT NULL,
  vigente_hasta        DATE,
  estado               VARCHAR(12) NOT NULL DEFAULT 'borrador'
                       CHECK (estado IN ('borrador','activa','en_revision','retirada')),
  id_autor             BIGINT NOT NULL REFERENCES usuario(id_usuario),
  fecha_creacion       TIMESTAMP NOT NULL DEFAULT now(),
  CONSTRAINT uq_version_regla UNIQUE (id_regla, numero_version),
  CONSTRAINT ck_version_regla_obj CHECK ((tipo_accion IN ('sugerir','evitar')) = (id_pa_objetivo IS NOT NULL)),
  CONSTRAINT ck_version_regla_vig CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);
CREATE UNIQUE INDEX ux_version_regla_activa ON version_regla(id_regla) WHERE estado = 'activa';

CREATE TABLE grupo_condicion (
  id_grupo         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_version_regla BIGINT NOT NULL REFERENCES version_regla(id_version_regla),
  id_grupo_padre   BIGINT REFERENCES grupo_condicion(id_grupo),
  operador_logico  VARCHAR(8) NOT NULL CHECK (operador_logico IN ('AND','OR','AL_MENOS')),
  min_cumplidas    SMALLINT CHECK (min_cumplidas >= 1),
  orden            SMALLINT NOT NULL,
  CONSTRAINT uq_grupo_orden UNIQUE NULLS NOT DISTINCT (id_version_regla, id_grupo_padre, orden),
  CONSTRAINT ck_grupo_min CHECK ((operador_logico = 'AL_MENOS') = (min_cumplidas IS NOT NULL))
);

CREATE TABLE variable_clinica (
  id_variable   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo        VARCHAR(20) NOT NULL UNIQUE,
  nombre        VARCHAR(80) NOT NULL,
  fuente        VARCHAR(12) NOT NULL CHECK (fuente IN ('laboratorio','signo_vital','antecedente',
                                     'diagnostico','medicamento','alergia','variante','imagen')),
  tipo_valor    VARCHAR(10) NOT NULL CHECK (tipo_valor IN ('numerico','codigo','booleano')),
  id_prueba     BIGINT REFERENCES prueba(id_prueba),
  id_tipo_signo BIGINT REFERENCES tipo_signo_vital(id_tipo_signo),
  CONSTRAINT ck_variable_prueba CHECK ((fuente = 'laboratorio') = (id_prueba IS NOT NULL)),
  CONSTRAINT ck_variable_signo  CHECK ((fuente = 'signo_vital') = (id_tipo_signo IS NOT NULL))
);

CREATE TABLE operador (
  id_operador BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  simbolo     VARCHAR(15) NOT NULL UNIQUE,
  nombre      VARCHAR(40) NOT NULL,
  aridad      SMALLINT NOT NULL CHECK (aridad IN (0,1,2))
);

CREATE TABLE condicion_regla (
  id_condicion     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_grupo         BIGINT NOT NULL REFERENCES grupo_condicion(id_grupo),
  orden            SMALLINT NOT NULL,
  id_variable      BIGINT NOT NULL REFERENCES variable_clinica(id_variable),
  id_operador      BIGINT NOT NULL REFERENCES operador(id_operador),
  valor_numerico   NUMERIC(12,4),
  valor_numerico_2 NUMERIC(12,4),
  valor_codigo     VARCHAR(30),
  id_unidad        BIGINT REFERENCES unidad(id_unidad),
  ventana_horas    INTEGER CHECK (ventana_horas > 0),
  CONSTRAINT uq_condicion_orden UNIQUE (id_grupo, orden)
);

-- F. Recomendación, evidencia y decisión médica
CREATE TABLE recomendacion (
  id_recomendacion     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_encuentro         BIGINT NOT NULL REFERENCES encuentro(id_encuentro),
  id_version_regla     BIGINT NOT NULL REFERENCES version_regla(id_version_regla),
  prioridad_asignada   VARCHAR(8) NOT NULL CHECK (prioridad_asignada IN ('baja','media','alta','critica')),
  texto_generado       TEXT NOT NULL,
  fecha_hora           TIMESTAMP NOT NULL DEFAULT clock_timestamp(),
  mongo_explicacion_id CHAR(24),
  CONSTRAINT uq_recomendacion UNIQUE (id_encuentro, id_version_regla, fecha_hora)
);
CREATE INDEX ix_recomendacion_encuentro ON recomendacion(id_encuentro);

CREATE TABLE evidencia (
  id_evidencia        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_recomendacion    BIGINT NOT NULL REFERENCES recomendacion(id_recomendacion),
  id_condicion        BIGINT NOT NULL REFERENCES condicion_regla(id_condicion),
  cumplida            BOOLEAN NOT NULL,
  valor_observado     VARCHAR(100),
  id_unidad           BIGINT REFERENCES unidad(id_unidad),
  fecha_dato          TIMESTAMP,
  id_resultado        BIGINT REFERENCES resultado(id_resultado),
  id_diagnostico      BIGINT REFERENCES diagnostico(id_diagnostico),
  id_antecedente      BIGINT REFERENCES antecedente(id_antecedente),
  id_alergia          BIGINT REFERENCES alergia(id_alergia),
  id_prescripcion     BIGINT REFERENCES prescripcion(id_prescripcion),
  id_estudio_imagen   BIGINT REFERENCES estudio_imagen(id_estudio),
  id_estudio_genomico BIGINT REFERENCES estudio_genomico(id_estudio_genomico),
  id_serie            BIGINT REFERENCES serie_signos_ref(id_serie),
  mongo_doc_id        CHAR(24),
  CONSTRAINT ck_evidencia_origen CHECK (num_nonnulls(id_resultado, id_diagnostico, id_antecedente,
           id_alergia, id_prescripcion, id_estudio_imagen, id_estudio_genomico, id_serie) <= 1),
  CONSTRAINT ck_evidencia_mongo CHECK ((id_serie IS NULL AND id_estudio_genomico IS NULL)
                                       OR mongo_doc_id IS NOT NULL)
);
CREATE INDEX ix_evidencia_recomendacion ON evidencia(id_recomendacion);

CREATE TABLE decision_medica (
  id_decision                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_recomendacion           BIGINT NOT NULL UNIQUE REFERENCES recomendacion(id_recomendacion),
  id_medico                  BIGINT NOT NULL REFERENCES medico(id_medico),
  tipo                       VARCHAR(10) NOT NULL CHECK (tipo IN ('aceptada','rechazada','modificada')),
  accion_final               TEXT,
  justificacion              TEXT NOT NULL CHECK (length(trim(justificacion)) >= 10),
  id_orden_resultante        BIGINT REFERENCES orden_medica(id_orden),
  id_prescripcion_resultante BIGINT REFERENCES prescripcion(id_prescripcion),
  fecha_hora                 TIMESTAMP NOT NULL DEFAULT now(),
  CONSTRAINT ck_decision_modificada CHECK (tipo <> 'modificada' OR accion_final IS NOT NULL)
);
