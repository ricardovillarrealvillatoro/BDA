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

-- 5. Vista de pacientes con consultas pendientes/abiertas
CREATE OR REPLACE VIEW vw_pacientes_consultas_pendientes AS
SELECT 
    p.id_paciente,
    p.nombre || ' ' || p.apellido_paterno AS paciente,
    p.telefono,
    e.id_encuentro,
    e.fecha_inicio,
    e.motivo,
    u.nombre || ' ' || u.apellido_paterno AS medico_atendiendo
FROM paciente p
JOIN encuentro e ON p.id_paciente = e.id_paciente
JOIN medico m ON e.id_medico = m.id_medico
JOIN usuario u ON m.id_medico = u.id_usuario
WHERE e.estado = 'abierto';
