-- 1. Vista de pacientes y su última consulta (Alineada con lista_paciente.html)
CREATE OR REPLACE VIEW vw_pacientes_ultima_consulta AS
SELECT 
    p.id_paciente,
    p.nombre || ' ' || p.apellido_paterno || ' ' || COALESCE(p.apellido_materno, '') AS nombre_completo,
    p.curp,
    p.sexo,
    EXTRACT(YEAR FROM age(p.fecha_nacimiento)) AS edad,
    p.activo,
    MAX(e.fecha_inicio) AS fecha_ultima_consulta,
    COUNT(e.id_encuentro) AS total_consultas,
    (SELECT u.nombre || ' ' || u.apellido_paterno 
     FROM encuentro e2 
     JOIN usuario u ON e2.id_medico = u.id_usuario 
     WHERE e2.id_paciente = p.id_paciente ORDER BY e2.fecha_inicio DESC LIMIT 1) AS medico_ultima_consulta,
    (SELECT e2.estado FROM encuentro e2 WHERE e2.id_paciente = p.id_paciente ORDER BY e2.fecha_inicio DESC LIMIT 1) AS estado_ultima_consulta,
    (SELECT e2.id_encuentro FROM encuentro e2 WHERE e2.id_paciente = p.id_paciente ORDER BY e2.fecha_inicio DESC LIMIT 1) AS id_ultima_consulta
FROM paciente p
LEFT JOIN encuentro e ON p.id_paciente = e.id_paciente
GROUP BY p.id_paciente, p.nombre, p.apellido_paterno, p.apellido_materno, p.curp, p.sexo, p.fecha_nacimiento, p.activo;

-- 2. Vista del historial de consultas por médico (Alineada con consultas_lista.html)
CREATE OR REPLACE VIEW vw_historial_consultas_medico AS
SELECT 
    m.id_medico,
    u.nombre || ' ' || u.apellido_paterno AS medico,
    m.cedula_profesional,
    e.id_encuentro,
    e.id_paciente,
    e.fecha_inicio,
    e.tipo,
    e.estado,
    e.motivo,
    p.nombre || ' ' || p.apellido_paterno AS paciente,
    p.curp,
    (SELECT esp.nombre 
     FROM especialidad esp 
     JOIN medico_especialidad me ON esp.id_especialidad = me.id_especialidad 
     WHERE me.id_medico = m.id_medico AND me.es_principal = TRUE LIMIT 1) AS especialidad,
    (SELECT d.codigo_cie10 
     FROM diagnostico d 
     WHERE d.id_encuentro = e.id_encuentro AND d.tipo = 'principal' LIMIT 1) AS dx_principal,
    (SELECT c.descripcion 
     FROM diagnostico d 
     JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10 
     WHERE d.id_encuentro = e.id_encuentro AND d.tipo = 'principal' LIMIT 1) AS dx_descripcion
FROM medico m
JOIN usuario u ON m.id_medico = u.id_usuario
JOIN encuentro e ON m.id_medico = e.id_medico
JOIN paciente p ON e.id_paciente = p.id_paciente;

-- 3. Vista de consultas por especialidad
CREATE OR REPLACE VIEW vw_consultas_por_especialidad AS
SELECT 
    esp.nombre AS especialidad,
    COUNT(e.id_encuentro) AS total_atenciones,
    COUNT(DISTINCT e.id_paciente) AS pacientes_unicos
FROM especialidad esp
JOIN medico_especialidad me ON esp.id_especialidad = me.id_especialidad
JOIN encuentro e ON me.id_medico = e.id_medico
GROUP BY esp.id_especialidad, esp.nombre;

-- 4. Vista de indicadores de atención médica
CREATE OR REPLACE VIEW vw_indicadores_atencion AS
SELECT 
    e.tipo AS tipo_encuentro,
    COUNT(e.id_encuentro) AS total_encuentros,
    AVG(EXTRACT(EPOCH FROM (e.fecha_fin - e.fecha_inicio))/60)::NUMERIC(10,2) AS duracion_promedio_minutos
FROM encuentro e
WHERE e.estado = 'cerrado'
GROUP BY e.tipo;

-- 5. Vista de pacientes con consultas pendientes/abiertas, con lo que falta por resolver en cada una
--    (Alineada con panel/general.html y panel/medico.html)
CREATE OR REPLACE VIEW vw_pacientes_consultas_pendientes AS
SELECT 
    p.id_paciente,
    p.nombre || ' ' || p.apellido_paterno AS paciente,
    p.telefono,
    e.id_encuentro,
    e.fecha_inicio,
    e.motivo,
    u.nombre || ' ' || u.apellido_paterno AS medico_atendiendo,
    e.tipo,
    e.id_medico,
    (SELECT COUNT(*) FROM detalle_orden d
     JOIN orden_medica o ON d.id_orden = o.id_orden
     WHERE o.id_encuentro = e.id_encuentro AND d.estado IN ('pendiente', 'tomada')) AS pruebas_pendientes,
    (SELECT COUNT(*) FROM recomendacion r
     WHERE r.id_encuentro = e.id_encuentro
       AND NOT EXISTS (SELECT 1 FROM decision_medica dm WHERE dm.id_recomendacion = r.id_recomendacion)) AS recomendaciones_pendientes
FROM paciente p
JOIN encuentro e ON p.id_paciente = e.id_paciente
JOIN medico m ON e.id_medico = m.id_medico
JOIN usuario u ON m.id_medico = u.id_usuario
WHERE e.estado = 'abierto';

-- 6. Vista de pruebas ordenadas con su último resultado, interpretado con el rango de referencia
--    por sexo y edad del paciente (Alineada con laboratorio/inicio.html y consultas/detalle.html)
CREATE OR REPLACE VIEW vw_resultados_laboratorio AS
SELECT
    o.id_orden,
    o.id_encuentro,
    o.fecha_orden,
    o.prioridad,
    d.id_detalle,
    d.estado AS estado_detalle,
    pr.nombre AS prueba,
    pr.codigo_loinc,
    un.codigo_ucum AS unidad,
    e.id_paciente,
    e.estado AS estado_encuentro,
    p.nombre || ' ' || p.apellido_paterno AS paciente,
    u.nombre || ' ' || u.apellido_paterno AS medico,
    r.id_resultado,
    r.valor_numerico,
    r.valor_texto,
    r.fecha_resultado,
    CASE
        WHEN r.id_resultado IS NULL THEN NULL
        WHEN r.valor_numerico IS NULL OR rr.id_rango IS NULL THEN 'sin_rango'
        WHEN r.valor_numerico < rr.critico_min OR r.valor_numerico > rr.critico_max THEN 'critico'
        WHEN r.valor_numerico < rr.ref_min OR r.valor_numerico > rr.ref_max THEN 'fuera_rango'
        ELSE 'normal'
    END AS estado_resultado
FROM detalle_orden d
JOIN orden_medica o ON d.id_orden = o.id_orden
JOIN prueba pr ON d.id_prueba = pr.id_prueba
LEFT JOIN unidad un ON pr.id_unidad = un.id_unidad
JOIN encuentro e ON o.id_encuentro = e.id_encuentro
JOIN paciente p ON e.id_paciente = p.id_paciente
JOIN usuario u ON o.id_medico = u.id_usuario
LEFT JOIN LATERAL (
    SELECT * FROM resultado r2 WHERE r2.id_detalle = d.id_detalle
    ORDER BY r2.fecha_resultado DESC LIMIT 1
) r ON TRUE
LEFT JOIN LATERAL (
    -- Rango del sexo del paciente si existe; si no, el general ('X')
    SELECT * FROM rango_referencia rr2
    WHERE rr2.id_prueba = d.id_prueba
      AND rr2.sexo IN (p.sexo, 'X')
      AND EXTRACT(YEAR FROM age(r.fecha_resultado, p.fecha_nacimiento)) >= rr2.edad_min_anios
      AND EXTRACT(YEAR FROM age(r.fecha_resultado, p.fecha_nacimiento)) < rr2.edad_max_anios
    ORDER BY rr2.sexo = 'X'
    LIMIT 1
) rr ON TRUE;

-- 7. Vista del contexto clínico de cada paciente: todo lo que el copiloto conoce de él en una sola lista
--    (Alineada con consultas/detalle.html y el resumen de panel/medico.html)
CREATE OR REPLACE VIEW vw_contexto_clinico AS
SELECT e.id_paciente, 'diagnostico' AS fuente,
       d.codigo_cie10 || ' ' || c.descripcion AS concepto,
       d.estado::TEXT AS valor, NULL::VARCHAR AS unidad, d.fecha::TIMESTAMP AS fecha
FROM diagnostico d
JOIN encuentro e ON d.id_encuentro = e.id_encuentro
JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10
WHERE d.estado <> 'descartado'
UNION ALL
SELECT r.id_paciente, 'laboratorio', r.prueba,
       COALESCE(trim_scale(r.valor_numerico)::TEXT, r.valor_texto), r.unidad, r.fecha_resultado
FROM vw_resultados_laboratorio r
WHERE r.id_resultado IS NOT NULL
UNION ALL
SELECT a.id_paciente, 'alergia', COALESCE(pa.nombre, a.sustancia_otra),
       a.severidad || COALESCE(' · ' || a.reaccion, ''), NULL, a.fecha_registro::TIMESTAMP
FROM alergia a
LEFT JOIN principio_activo pa ON a.id_principio_activo = pa.id_principio_activo
UNION ALL
SELECT an.id_paciente, 'antecedente', ta.nombre || ': ' || COALESCE(c.descripcion, an.descripcion),
       an.estado || COALESCE(' · ' || an.parentesco, ''), NULL, an.fecha_inicio::TIMESTAMP
FROM antecedente an
JOIN tipo_antecedente ta ON an.id_tipo_antecedente = ta.id_tipo_antecedente
LEFT JOIN catalogo_cie10 c ON an.codigo_cie10 = c.codigo_cie10
UNION ALL
-- Solo medicación vigente
SELECT e.id_paciente, 'medicamento', m.nombre_comercial,
       trim_scale(pr.dosis)::TEXT || ' c/' || pr.frecuencia_horas || ' h', u.codigo_ucum, pr.fecha_inicio::TIMESTAMP
FROM prescripcion pr
JOIN encuentro e ON pr.id_encuentro = e.id_encuentro
JOIN medicamento m ON pr.id_medicamento = m.id_medicamento
JOIN unidad u ON pr.id_unidad_dosis = u.id_unidad
WHERE pr.fecha_fin IS NULL OR pr.fecha_fin >= CURRENT_DATE;

-- 8. Vista de alertas activas: recomendaciones del copiloto sin decisión en consultas abiertas
--    (Alineada con panel/general.html; nivel_prioridad sirve para ordenar de la más urgente a la menos)
CREATE OR REPLACE VIEW vw_alertas_activas AS
SELECT
    r.id_recomendacion,
    r.id_encuentro,
    e.id_paciente,
    e.id_medico,
    p.nombre || ' ' || p.apellido_paterno AS paciente,
    u.nombre || ' ' || u.apellido_paterno AS medico,
    rc.codigo AS regla,
    rc.nombre AS regla_nombre,
    r.prioridad_asignada,
    CASE r.prioridad_asignada WHEN 'critica' THEN 4 WHEN 'alta' THEN 3 WHEN 'media' THEN 2 ELSE 1 END AS nivel_prioridad,
    r.texto_generado,
    r.fecha_hora
FROM recomendacion r
JOIN encuentro e ON r.id_encuentro = e.id_encuentro
JOIN paciente p ON e.id_paciente = p.id_paciente
JOIN usuario u ON e.id_medico = u.id_usuario
JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla
JOIN regla_clinica rc ON vr.id_regla = rc.id_regla
WHERE e.estado = 'abierto'
  AND NOT EXISTS (SELECT 1 FROM decision_medica dm WHERE dm.id_recomendacion = r.id_recomendacion);

-- 9. Vista de actividad de la bitácora por usuario y tabla (Alineada con auditoria/inicio.html)
CREATE OR REPLACE VIEW vw_auditoria_por_usuario AS
SELECT
    COALESCE(u.username, '(sin sesión)') AS usuario,
    a.tabla,
    COUNT(*) FILTER (WHERE a.accion = 'INSERT') AS inserciones,
    COUNT(*) FILTER (WHERE a.accion = 'UPDATE') AS actualizaciones,
    COUNT(*) FILTER (WHERE a.accion = 'DELETE') AS eliminaciones,
    MAX(a.fecha_hora) AS ultima_accion
FROM auditoria a
LEFT JOIN usuario u ON a.id_usuario = u.id_usuario
GROUP BY u.username, a.tabla;
