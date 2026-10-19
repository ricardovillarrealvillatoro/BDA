-- Formato: "--Título" y debajo sus notas ("-- Pregunta:", "-- Resultado:", "-- Aplicación:" y, si hace falta,
-- "-- Tipo:" para cambiar la etiqueta automática). La página Consultas SQL (app/consultas_sql.py) muestra las notas
-- junto al código y al resultado de la ejecución. Los números de "Resultado" son los de db/06_datos_prueba.sql.

--Pacientes con diagnósticos confirmados y sus médicos
-- Pregunta: ¿Qué diagnósticos confirmados tiene cada paciente y qué médico lo atendió en esa consulta?
-- Resultado: 105 filas, una por diagnóstico confirmado. Como es INNER JOIN, solo salen las filas con coincidencia en
-- las cinco tablas: un paciente sin consultas o sin diagnósticos confirmados no aparece.
-- Aplicación: Es la relación paciente–consulta–diagnóstico–médico que muestran el historial del expediente
-- (vw_historial_consultas_medico) y el informe médico de cada consulta.
SELECT p.nombre, p.apellido_paterno, d.codigo_cie10, c.descripcion, u.nombre AS medico
FROM paciente p
INNER JOIN encuentro e ON p.id_paciente = e.id_paciente
INNER JOIN diagnostico d ON e.id_encuentro = d.id_encuentro
INNER JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10
INNER JOIN usuario u ON e.id_medico = u.id_usuario
WHERE d.estado = 'confirmado';

--Todos los pacientes y sus alergias conocidas (incluidos los que no tienen alergias registradas)
-- Pregunta: ¿Qué alergias tiene registradas cada paciente, incluidos los que no tienen ninguna?
-- Resultado: 42 filas, una por paciente: 4 con su alergia y 38 con reacción y severidad en NULL. Un INNER JOIN solo
-- devolvería las 4 filas con alergia; el LEFT JOIN conserva a todos los pacientes (la tabla de la izquierda).
-- Aplicación: El expediente del paciente arma la sección Alergias con un LEFT JOIN y, cuando no hay coincidencia,
-- muestra "Sin alergias conocidas".
SELECT p.id_paciente, p.nombre, p.apellido_paterno, a.reaccion, a.severidad
FROM paciente p
LEFT JOIN alergia a ON p.id_paciente = a.id_paciente
ORDER BY p.id_paciente;

--Medicamentos del catálogo y las prescripciones en que se han recetado
-- Pregunta: ¿Qué medicamentos del catálogo se han recetado y cuáles nunca?
-- Resultado: 47 filas: 38 recetas con su medicamento y 9 medicamentos que nunca se han recetado, con id_prescripcion y
-- dosis en NULL. El RIGHT JOIN conserva todos los medicamentos (la tabla de la derecha); un INNER JOIN daría solo las 38 recetas.
-- Aplicación: El formulario de prescripción de la consulta ofrece el catálogo completo de medicamentos; esta consulta
-- muestra cuáles no se han usado.
SELECT pr.id_prescripcion, pr.dosis, m.nombre_comercial, m.presentacion
FROM prescripcion pr
RIGHT JOIN medicamento m ON pr.id_medicamento = m.id_medicamento;

--Medicamentos y principios activos, incluidos los principios activos sin medicamento comercial registrado
-- Pregunta: ¿Cómo se relacionan los medicamentos con sus principios activos, incluidos los que no tienen pareja?
-- Resultado: 19 filas: 18 parejas medicamento–principio activo y 1 principio activo sin medicamento (Clopidogrel, con
-- nombre_comercial en NULL). El FULL OUTER JOIN también conservaría un medicamento sin principio activo (con
-- principio_activo en NULL), pero en los datos de prueba todos los medicamentos tienen al menos uno.
-- Aplicación: Las alergias se registran contra principios activos (tabla alergia), así que un principio activo sin
-- medicamento comercial, como Clopidogrel, sirve para registrar una alergia aunque no se pueda recetar.
SELECT m.nombre_comercial, pa.nombre AS principio_activo
FROM medicamento m
FULL OUTER JOIN medicamento_componente mc ON m.id_medicamento = mc.id_medicamento
FULL OUTER JOIN principio_activo pa ON mc.id_principio_activo = pa.id_principio_activo;

--Combinaciones de vía de administración y unidad de dosis
-- Pregunta: ¿Qué combinaciones de vía de administración y unidad de dosis se pueden capturar en una receta?
-- Resultado: 190 filas = 10 vías × 19 unidades. El CROSS JOIN no lleva condición: combina cada vía con cada unidad.
-- Aplicación: En el formulario de prescripción la vía y la unidad se eligen por separado, así que estas son todas las
-- combinaciones que se pueden capturar; la lista sirve para revisar cuáles tienen sentido clínico (Oral con miligramos
-- sí, Oftálmica con kilogramos no).
SELECT v.nombre AS via, u.nombre AS unidad
FROM via_administracion v
CROSS JOIN unidad u;

--Jerarquía de grupos de condiciones configurados en las reglas clínicas
-- Pregunta: ¿Qué grupos de condiciones de las reglas clínicas están dentro de otro grupo?
-- Resultado: 11 filas, una por grupo. Los grupos 6 y 8 (OR) están dentro de los grupos 5 y 7 (AND); los otros 9 son
-- grupos raíz y salen con grupo_padre en NULL. La tabla grupo_condicion se une consigo misma con dos alias (g y padre)
-- por id_grupo_padre; es LEFT JOIN para no perder los grupos raíz.
-- Aplicación: El copiloto evalúa cada regla clínica con estos grupos anidados, por ejemplo A AND (B OR C). La evidencia
-- de cada recomendación en la consulta se muestra por grupo y operador lógico.
SELECT g.id_grupo AS grupo_hijo, g.operador_logico, padre.id_grupo AS grupo_padre, padre.operador_logico AS operador_padre
FROM grupo_condicion g
LEFT JOIN grupo_condicion padre ON g.id_grupo_padre = padre.id_grupo;

--Recomendaciones del copiloto con su paciente, médico y regla aplicada
-- Tipo: JOIN de 3 o más tablas
-- Pregunta: ¿Qué recomendaciones generó el copiloto, para qué paciente y médico, y con qué regla?
-- Resultado: 70 filas, una por recomendación, uniendo 5 tablas: recomendacion, encuentro, paciente, usuario (el
-- médico) y version_regla.
-- Aplicación: Es la misma relación que usan las alertas del Panel (vw_alertas_activas) y las recomendaciones del
-- detalle de la consulta y del informe médico.
SELECT r.id_recomendacion, p.nombre AS paciente, u.nombre AS medico, vr.plantilla_texto, r.prioridad_asignada, r.fecha_hora
FROM recomendacion r
JOIN encuentro e ON r.id_encuentro = e.id_encuentro
JOIN paciente p ON e.id_paciente = p.id_paciente
JOIN usuario u ON e.id_medico = u.id_usuario
JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla;


--Complementarios

--Total de consultas por tipo con la primera y la última fecha registrada
-- Pregunta: ¿Cuántas consultas hay de cada tipo y entre qué fechas se registraron?
-- Resultado: 3 filas: consulta 73, urgencia 16 y hospitalización 4 (93 en total), con la primera y la última fecha de
-- cada tipo. Usa COUNT, MIN y MAX con GROUP BY.
-- Aplicación: La página Rendimiento muestra los indicadores de atención por tipo de consulta (vw_indicadores_atencion).
SELECT
    e.tipo,
    COUNT(e.id_encuentro) AS total_consultas,
    MIN(e.fecha_inicio) AS primera_consulta,
    MAX(e.fecha_inicio) AS ultima_consulta
FROM encuentro e
GROUP BY e.tipo;

--Pacientes que han tenido un número de consultas superior al promedio general
-- Pregunta: ¿Qué pacientes han tenido más consultas que el promedio?
-- Resultado: 19 pacientes. Una subconsulta correlacionada cuenta las consultas de cada paciente y otra calcula el
-- promedio de consultas por paciente (2.51 entre los que tienen al menos una).
-- Aplicación: Identifica a los pacientes frecuentes; la lista de Pacientes muestra cuántas consultas tiene cada uno
-- (vw_pacientes_ultima_consulta).
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


--Pacientes con diagnóstico de diabetes tipo 2 (E11) o hipertensión esencial (I10)
-- Pregunta: ¿Qué pacientes tienen diagnosticada diabetes tipo 2 o hipertensión esencial?
-- Resultado: 6 pacientes. La subconsulta con IN devuelve los pacientes que tienen alguno de los dos códigos. La
-- comparación es exacta: los 6 salen por I10, porque en los datos de prueba la diabetes está registrada como E11.9.
-- Aplicación: Identifica pacientes crónicos para darles seguimiento; sus diagnósticos aparecen en el contexto clínico
-- de cada consulta (vw_contexto_clinico).
SELECT nombre, apellido_paterno, curp
FROM paciente
WHERE id_paciente IN (
    SELECT e.id_paciente
    FROM encuentro e
    JOIN diagnostico d ON e.id_encuentro = d.id_encuentro
    WHERE d.codigo_cie10 IN ('E11', 'I10')
);

--WITH: médicos con más de 5 atenciones registradas
-- Pregunta: ¿Qué médicos han atendido más de 5 consultas?
-- Resultado: 8 médicos, encabezados por Tomás Leal con 17. La CTE ResumenMedicos cuenta las consultas de cada médico
-- (con LEFT JOIN para incluir a los que no tienen ninguna) y la consulta principal se queda con los que pasan de 5.
-- Aplicación: La página Rendimiento y el detalle de cada médico muestran su actividad y su concordancia con el copiloto.
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

--Funciones de ventana: número de consulta de cada paciente y ranking global por fecha
-- Pregunta: ¿Qué número de consulta es cada una para su paciente y qué lugar ocupa entre todas por fecha?
-- Resultado: 93 filas, una por consulta. ROW_NUMBER() reinicia la cuenta en cada paciente (PARTITION BY id_paciente; 1
-- es la más reciente y llega hasta 4) y RANK() ordena todas las consultas por fecha: las que tienen la misma fecha
-- comparten lugar.
-- Aplicación: El historial del expediente del paciente lista sus consultas en este orden, de la más reciente a la más antigua.
SELECT
    e.id_encuentro,
    e.id_paciente,
    e.fecha_inicio,
    ROW_NUMBER() OVER(PARTITION BY e.id_paciente ORDER BY e.fecha_inicio DESC) AS num_consulta_paciente,
    RANK() OVER(ORDER BY e.fecha_inicio DESC) AS ranking_global_fecha
FROM encuentro e;
