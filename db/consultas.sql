--Pacientes con diagnósticos confirmados y sus médicos
SELECT p.nombre, p.apellido_paterno, d.codigo_cie10, c.descripcion, u.nombre AS medico
FROM paciente p
INNER JOIN encuentro e ON p.id_paciente = e.id_paciente
INNER JOIN diagnostico d ON e.id_encuentro = d.id_encuentro
INNER JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10
INNER JOIN usuario u ON e.id_medico = u.id_usuario
WHERE d.estado = 'confirmado';

--Obtener todos los pacientes registrados y sus alergias conocidas (y los que no tienen alergias registradas)
SELECT p.id_paciente, p.nombre, p.apellido_paterno, a.reaccion, a.severidad
FROM paciente p
LEFT JOIN alergia a ON p.id_paciente = a.id_paciente
ORDER BY p.id_paciente;

--lista de medicamentos del catálogo y prescripciones asociadas que se han realizado
SELECT pr.id_prescripcion, pr.dosis, m.nombre_comercial, m.presentacion
FROM prescripcion pr
RIGHT JOIN medicamento m ON pr.id_medicamento = m.id_medicamento;

--Relacionar todos los medicamentos y principios activos para identificar principios activos que no tienen medicamento comerical registrado
SELECT m.nombre_comercial, pa.nombre AS principio_activo
FROM medicamento m
FULL OUTER JOIN medicamento_componente mc ON m.id_medicamento = mc.id_medicamento
FULL OUTER JOIN principio_activo pa ON mc.id_principio_activo = pa.id_principio_activo;

--Evaluar compatibilidad entre vías de administración y unidades de dosis registradas
SELECT v.nombre AS via, u.nombre AS unidad
FROM via_administracion v
CROSS JOIN unidad u;

--Jerarquía de grupos de condiciones configurados en las reglas clínicas
SELECT g.id_grupo AS grupo_hijo, g.operador_logico, padre.id_grupo AS grupo_padre, padre.operador_logico AS operador_padre
FROM grupo_condicion g
LEFT JOIN grupo_condicion padre ON g.id_grupo_padre = padre.id_grupo;

--Detalles completos de recomendaciones automáticas generadas poe sistema copiloto para encuentros clínicos, con datos de paciente, médico y regla aplicada
SELECT r.id_recomendacion, p.nombre AS paciente, u.nombre AS medico, vr.plantilla_texto, r.prioridad_asignada, r.fecha_hora
FROM recomendacion r
JOIN encuentro e ON r.id_encuentro = e.id_encuentro
JOIN paciente p ON e.id_paciente = p.id_paciente
JOIN usuario u ON e.id_medico = u.id_usuario
JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla;


--Complementarios
SELECT 
    e.tipo,
    COUNT(e.id_encuentro) AS total_consultas,
    MIN(e.fecha_inicio) AS primera_consulta,
    MAX(e.fecha_inicio) AS ultima_consulta
FROM encuentro e
GROUP BY e.tipo;

--Pacientes que han tenido un número de consultas superior al promedio general
SELECT p.id_paciente, p.nombre, p.apellido_paterno
FROM paciente p
WHERE (
    SELECT COUNT(*) 
    FROM encuentro e 
    WHERE e.id_paciente = p.id_paciente
) > (
    SELECT AVG(total_e) 
    FROM (SELECT COUNT(*) AS total_e FROM encuentro GROUP BY id_paciente) sub
);


--Pacientes con diagnóstivos de alta prioridad o enfermedades crónicas específicas
SELECT nombre, apellido_paterno, curp 
FROM paciente 
WHERE id_paciente IN (
    SELECT e.id_paciente 
    FROM encuentro e
    JOIN diagnostico d ON e.id_encuentro = d.id_encuentro
    WHERE d.codigo_cie10 IN ('E11', 'I10')
);

--WITH
WITH ResumenMedicos AS (
    SELECT 
        m.id_medico,
        u.nombre || ' ' || u.apellido_paterno AS medico,
        COUNT(e.id_encuentro) AS total_atenciones
    FROM medico m
    JOIN usuario u ON m.id_medico = u.id_usuario
    LEFT JOIN encuentro e ON m.id_medico = e.id_medico
    GROUP BY m.id_medico, u.nombre, u.apellido_paterno
)
SELECT medico, total_atenciones
FROM ResumenMedicos
WHERE total_atenciones > 5
ORDER BY total_atenciones DESC;

--Ventana Func
SELECT 
    e.id_encuentro,
    e.id_paciente,
    e.fecha_inicio,
    ROW_NUMBER() OVER(PARTITION BY e.id_paciente ORDER BY e.fecha_inicio DESC) AS num_consulta_paciente,
    RANK() OVER(ORDER BY e.fecha_inicio DESC) AS ranking_global_fecha
FROM encuentro e;
