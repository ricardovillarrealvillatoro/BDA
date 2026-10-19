# Consultas JOIN y complementarias

Código en [`db/consultas.sql`](../db/consultas.sql). Son **12 consultas**: 7 de JOIN (INNER, LEFT, RIGHT, FULL OUTER, CROSS,
SELF y un JOIN de 5 tablas) y 5 complementarias (agregación, dos subconsultas, CTE y funciones de ventana).

**Dónde verlas en la aplicación.** La página **Consultas SQL** (`/consultas-sql/`, roles administrador clínico y auditor) lee
`db/consultas.sql`, muestra el tipo, la pregunta, el resultado y la aplicación de cada consulta, y la ejecuta en una transacción
de solo lectura con límite de 5 segundos. Las notas de cada consulta (`-- Pregunta:`, `-- Resultado:`, `-- Aplicación:`) salen
de los comentarios del mismo archivo.

**Cómo se obtuvieron los resultados.** Cada consulta se ejecutó el 18/10/2026 sobre los datos de prueba
(`db/06_datos_prueba.sql`). Las tablas de evidencia muestran el total de filas y algunas filas representativas.

| # | Tipo | Consulta | Filas |
|---|---|---|---|
| 1 | INNER JOIN | [Pacientes con diagnósticos confirmados y sus médicos](#1-inner-join) | 105 |
| 2 | LEFT JOIN | [Todos los pacientes y sus alergias](#2-left-join) | 42 |
| 3 | RIGHT JOIN | [Medicamentos del catálogo y sus prescripciones](#3-right-join) | 47 |
| 4 | FULL OUTER JOIN | [Medicamentos y principios activos](#4-full-outer-join) | 19 |
| 5 | CROSS JOIN | [Combinaciones de vía de administración y unidad](#5-cross-join) | 190 |
| 6 | SELF JOIN | [Jerarquía de grupos de condiciones](#6-self-join) | 11 |
| 7 | JOIN de 5 tablas | [Recomendaciones con paciente, médico y regla](#7-join-de-5-tablas) | 70 |
| 8 | Agregación | [Consultas por tipo](#8-agregación) | 3 |
| 9 | Subconsulta | [Pacientes con más consultas que el promedio](#9-subconsulta-correlacionada) | 19 |
| 10 | Subconsulta | [Pacientes con diabetes tipo 2 o hipertensión](#10-subconsulta-con-in) | 6 |
| 11 | CTE (WITH) | [Médicos con más de 5 atenciones](#11-cte-with) | 8 |
| 12 | Funciones de ventana | [Número de consulta y ranking por fecha](#12-funciones-de-ventana) | 93 |

---

## Consultas JOIN

### 1. INNER JOIN

**Pacientes con diagnósticos confirmados y sus médicos**

**Pregunta:** ¿qué diagnósticos confirmados tiene cada paciente y qué médico lo atendió en esa consulta?

```sql
SELECT p.nombre, p.apellido_paterno, d.codigo_cie10, c.descripcion, u.nombre AS medico
FROM paciente p
INNER JOIN encuentro e ON p.id_paciente = e.id_paciente
INNER JOIN diagnostico d ON e.id_encuentro = d.id_encuentro
INNER JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10
INNER JOIN usuario u ON e.id_medico = u.id_usuario
WHERE d.estado = 'confirmado';
```

**Explicación:** el INNER JOIN solo devuelve las filas que tienen coincidencia en las cinco tablas: un paciente sin consultas
o una consulta sin diagnósticos confirmados no aparece.

**Evidencia:** 105 filas, una por diagnóstico confirmado.

| nombre | apellido_paterno | codigo_cie10 | descripcion | medico |
|---|---|---|---|---|
| Carlos | Garza | E66.9 | Obesidad, no especificada | Helen |
| Carlos | Garza | R73.9 | Hiperglucemia, no especificada | Helen |
| Mónica | Treviño | M25.5 | Dolor en articulación | Jorge |

**Aplicación:** es la relación paciente–consulta–diagnóstico–médico que muestran el historial del expediente
(`vw_historial_consultas_medico`) y el informe médico de cada consulta.

### 2. LEFT JOIN

**Todos los pacientes y sus alergias conocidas, incluidos los que no tienen alergias registradas**

**Pregunta:** ¿qué alergias tiene registradas cada paciente, incluidos los que no tienen ninguna?

```sql
SELECT p.id_paciente, p.nombre, p.apellido_paterno, a.reaccion, a.severidad
FROM paciente p
LEFT JOIN alergia a ON p.id_paciente = a.id_paciente
ORDER BY p.id_paciente;
```

**Explicación:** el LEFT JOIN conserva todas las filas de la tabla de la izquierda (`paciente`). Cuando un paciente no tiene
alergias, las columnas de `alergia` salen en `NULL`. Un INNER JOIN solo devolvería las 4 filas con alergia.

**Evidencia:** 42 filas: 4 con alergia y 38 con `reaccion` y `severidad` en `NULL`.

| id_paciente | nombre | apellido_paterno | reaccion | severidad |
|---|---|---|---|---|
| 2 | Patricia | Aguilar | *NULL* | *NULL* |
| 12 | Adriana | Villarreal | Prurito | leve |
| 28 | Mónica | Ramírez | Urticaria generalizada | grave |

**Aplicación:** el expediente del paciente arma la sección Alergias con un LEFT JOIN y, cuando no hay coincidencia, muestra
"Sin alergias conocidas".

### 3. RIGHT JOIN

**Medicamentos del catálogo y las prescripciones en que se han recetado**

**Pregunta:** ¿qué medicamentos del catálogo se han recetado y cuáles nunca?

```sql
SELECT pr.id_prescripcion, pr.dosis, m.nombre_comercial, m.presentacion
FROM prescripcion pr
RIGHT JOIN medicamento m ON pr.id_medicamento = m.id_medicamento;
```

**Explicación:** el RIGHT JOIN conserva todas las filas de la tabla de la derecha (`medicamento`). Los medicamentos que nunca se
han recetado salen con `id_prescripcion` y `dosis` en `NULL`. Un INNER JOIN daría solo las 38 recetas.

**Evidencia:** 47 filas: 38 recetas y 9 medicamentos sin recetar.

| id_prescripcion | dosis | nombre_comercial | presentacion |
|---|---|---|---|
| 1 | 850.000 | Metformina | 850 mg caja con 30 |
| 2 | 5.000 | Warfarina | 5 mg caja con 25 |
| *NULL* | *NULL* | Omeprazol | 20 mg caja con 14 |
| *NULL* | *NULL* | Espironolactona | 25 mg caja con 20 |

**Aplicación:** el formulario de prescripción de la consulta ofrece el catálogo completo de medicamentos; esta consulta
muestra cuáles no se han usado.

### 4. FULL OUTER JOIN

**Medicamentos y principios activos, incluidos los principios activos sin medicamento comercial registrado**

**Pregunta:** ¿cómo se relacionan los medicamentos con sus principios activos, incluidos los que no tienen pareja?

```sql
SELECT m.nombre_comercial, pa.nombre AS principio_activo
FROM medicamento m
FULL OUTER JOIN medicamento_componente mc ON m.id_medicamento = mc.id_medicamento
FULL OUTER JOIN principio_activo pa ON mc.id_principio_activo = pa.id_principio_activo;
```

**Explicación:** el FULL OUTER JOIN conserva las filas de las dos tablas aunque no tengan pareja. Un principio activo sin
medicamento sale con `nombre_comercial` en `NULL`, y un medicamento sin principio activo saldría con `principio_activo` en
`NULL`. En los datos de prueba todos los medicamentos tienen al menos un principio activo, así que solo aparece el primer caso.

**Evidencia:** 19 filas: 18 parejas y 1 principio activo sin medicamento.

| nombre_comercial | principio_activo |
|---|---|
| Metformina | Metformina |
| Insulina glargina | Insulina glargina |
| *NULL* | Clopidogrel |

**Aplicación:** las alergias se registran contra principios activos (tabla `alergia`), así que un principio activo sin
medicamento comercial, como Clopidogrel, sirve para registrar una alergia aunque no se pueda recetar.

### 5. CROSS JOIN

**Combinaciones de vía de administración y unidad de dosis**

**Pregunta:** ¿qué combinaciones de vía de administración y unidad de dosis se pueden capturar en una receta?

```sql
SELECT v.nombre AS via, u.nombre AS unidad
FROM via_administracion v
CROSS JOIN unidad u;
```

**Explicación:** el CROSS JOIN no lleva condición: combina cada fila de una tabla con cada fila de la otra (producto cartesiano).

**Evidencia:** 190 filas = 10 vías × 19 unidades.

| via | unidad |
|---|---|
| Oral | miligramos por decilitro |
| Oral | gramos por decilitro |
| Oral | miligramos por litro |

**Aplicación:** en el formulario de prescripción la vía y la unidad se eligen por separado, así que estas son todas las
combinaciones que se pueden capturar. La lista sirve para revisar cuáles tienen sentido clínico (Oral con miligramos sí,
Oftálmica con kilogramos no).

### 6. SELF JOIN

**Jerarquía de grupos de condiciones configurados en las reglas clínicas**

**Pregunta:** ¿qué grupos de condiciones de las reglas clínicas están dentro de otro grupo?

```sql
SELECT g.id_grupo AS grupo_hijo, g.operador_logico, padre.id_grupo AS grupo_padre, padre.operador_logico AS operador_padre
FROM grupo_condicion g
LEFT JOIN grupo_condicion padre ON g.id_grupo_padre = padre.id_grupo;
```

**Explicación:** la tabla `grupo_condicion` se une consigo misma con dos alias (`g` y `padre`) por la columna `id_grupo_padre`.
Es LEFT JOIN para no perder los grupos raíz, que no tienen padre.

**Evidencia:** 11 filas, una por grupo. Los grupos 6 y 8 (OR) están dentro de los grupos 5 y 7 (AND); los otros 9 son raíz.

| grupo_hijo | operador_logico | grupo_padre | operador_padre |
|---|---|---|---|
| 6 | OR | 5 | AND |
| 8 | OR | 7 | AND |
| 1 | AND | *NULL* | *NULL* |

**Aplicación:** el copiloto evalúa cada regla clínica con estos grupos anidados, por ejemplo `A AND (B OR C)`. La evidencia de
cada recomendación en la consulta se muestra por grupo y operador lógico.

### 7. JOIN de 5 tablas

**Recomendaciones del copiloto con su paciente, médico y regla aplicada**

**Pregunta:** ¿qué recomendaciones generó el copiloto, para qué paciente y médico, y con qué regla?

```sql
SELECT r.id_recomendacion, p.nombre AS paciente, u.nombre AS medico, vr.plantilla_texto, r.prioridad_asignada, r.fecha_hora
FROM recomendacion r
JOIN encuentro e ON r.id_encuentro = e.id_encuentro
JOIN paciente p ON e.id_paciente = p.id_paciente
JOIN usuario u ON e.id_medico = u.id_usuario
JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla;
```

**Explicación:** une cinco tablas siguiendo las llaves foráneas: la recomendación pertenece a una consulta, la consulta a un
paciente y a un médico (`usuario`), y la recomendación se generó con una versión de regla.

**Evidencia:** 70 filas, una por recomendación.

| id_recomendacion | paciente | medico | plantilla_texto | prioridad_asignada | fecha_hora |
|---|---|---|---|---|---|
| 1 | Carlos | Helen | Control glucémico deficiente pese a metformina: revisar adherencia… | media | 2026-04-26 13:25 |
| 2 | Mónica | Jorge | Paciente anticoagulado con dolor musculoesquelético: evitar ibuprofeno… | media | 2026-04-29 16:10 |
| 3 | Mónica | Laura | Potasio elevado con IECA/ARA II: revisar dosis y función renal. | alta | 2026-05-03 12:10 |

**Aplicación:** es la misma relación que usan las alertas del Panel (`vw_alertas_activas`) y las recomendaciones del detalle de
la consulta y del informe médico.

---

## Consultas complementarias

### 8. Agregación

**Total de consultas por tipo con la primera y la última fecha registrada**

**Pregunta:** ¿cuántas consultas hay de cada tipo y entre qué fechas se registraron?

```sql
SELECT e.tipo, COUNT(e.id_encuentro) AS total_consultas,
       MIN(e.fecha_inicio) AS primera_consulta, MAX(e.fecha_inicio) AS ultima_consulta
FROM encuentro e
GROUP BY e.tipo;
```

**Explicación:** `GROUP BY` forma un grupo por tipo y las funciones de agregación `COUNT`, `MIN` y `MAX` resumen cada grupo en una fila.

**Evidencia:** 3 filas, 93 consultas en total.

| tipo | total_consultas | primera_consulta | ultima_consulta |
|---|---|---|---|
| consulta | 73 | 2026-04-29 15:15 | 2026-10-17 15:05 |
| urgencia | 16 | 2026-04-26 12:30 | 2026-09-28 16:15 |
| hospitalizacion | 4 | 2026-05-29 16:30 | 2026-10-17 15:05 |

**Aplicación:** la página Rendimiento muestra los indicadores de atención por tipo de consulta (`vw_indicadores_atencion`).

### 9. Subconsulta correlacionada

**Pacientes que han tenido un número de consultas superior al promedio general**

**Pregunta:** ¿qué pacientes han tenido más consultas que el promedio?

```sql
SELECT p.id_paciente, p.nombre, p.apellido_paterno
FROM paciente p
WHERE (SELECT COUNT(*) FROM encuentro e WHERE e.id_paciente = p.id_paciente)
    > (SELECT AVG(total_e) FROM (SELECT COUNT(*) AS total_e FROM encuentro GROUP BY id_paciente) sub);
```

**Explicación:** la primera subconsulta es correlacionada: se ejecuta para cada paciente (`e.id_paciente = p.id_paciente`) y
cuenta sus consultas. La segunda calcula el promedio de consultas por paciente (2.51, contando solo a los que tienen al menos
una) con una subconsulta en el `FROM`.

**Evidencia:** 19 pacientes.

| id_paciente | nombre | apellido_paterno |
|---|---|---|
| 2 | Patricia | Aguilar |
| 3 | Emilio | Castro |
| 4 | Verónica | García |

**Aplicación:** identifica a los pacientes frecuentes; la lista de Pacientes muestra cuántas consultas tiene cada uno
(`vw_pacientes_ultima_consulta`).

### 10. Subconsulta con IN

**Pacientes con diagnóstico de diabetes tipo 2 (E11) o hipertensión esencial (I10)**

**Pregunta:** ¿qué pacientes tienen diagnosticada diabetes tipo 2 o hipertensión esencial?

```sql
SELECT nombre, apellido_paterno, curp
FROM paciente
WHERE id_paciente IN (
    SELECT e.id_paciente
    FROM encuentro e
    JOIN diagnostico d ON e.id_encuentro = d.id_encuentro
    WHERE d.codigo_cie10 IN ('E11', 'I10')
);
```

**Explicación:** la subconsulta devuelve los id de los pacientes que tienen alguno de los dos códigos, y la consulta principal
se queda con esos pacientes. La comparación es exacta: en los datos de prueba la diabetes está registrada como `E11.9`, así
que los 6 pacientes salen por `I10`.

**Evidencia:** 6 pacientes.

| nombre | apellido_paterno | curp |
|---|---|---|
| Fernando | Martínez | MARF790814HNLRMR00 |
| Rosa | Medina | MECR470214MNLDVS05 |
| Andrés | Cavazos | CAMA440909HNLVDN01 |

**Aplicación:** identifica pacientes crónicos para darles seguimiento; sus diagnósticos aparecen en el contexto clínico de cada
consulta (`vw_contexto_clinico`).

### 11. CTE (WITH)

**Médicos con más de 5 atenciones registradas**

**Pregunta:** ¿qué médicos han atendido más de 5 consultas?

```sql
WITH ResumenMedicos AS (
    SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS medico, COUNT(e.id_encuentro) AS total_atenciones
    FROM medico m
    JOIN usuario u ON m.id_medico = u.id_usuario
    LEFT JOIN encuentro e ON m.id_medico = e.id_medico
    GROUP BY m.id_medico, u.nombre, u.apellido_paterno
)
SELECT medico, total_atenciones
FROM ResumenMedicos
WHERE total_atenciones > 5
ORDER BY total_atenciones DESC;
```

**Explicación:** la CTE `ResumenMedicos` es una consulta con nombre que cuenta las consultas de cada médico (con LEFT JOIN para
incluir a los que no tienen ninguna). La consulta principal la usa como si fuera una tabla y se queda con los que pasan de 5.

**Evidencia:** 8 médicos.

| medico | total_atenciones |
|---|---|
| Tomás Leal | 17 |
| Helen Rostova | 16 |
| Laura Reyes | 13 |

**Aplicación:** la página Rendimiento y el detalle de cada médico muestran su actividad y su concordancia con el copiloto.

### 12. Funciones de ventana

**Número de consulta de cada paciente y ranking global por fecha**

**Pregunta:** ¿qué número de consulta es cada una para su paciente y qué lugar ocupa entre todas por fecha?

```sql
SELECT e.id_encuentro, e.id_paciente, e.fecha_inicio,
       ROW_NUMBER() OVER(PARTITION BY e.id_paciente ORDER BY e.fecha_inicio DESC) AS num_consulta_paciente,
       RANK() OVER(ORDER BY e.fecha_inicio DESC) AS ranking_global_fecha
FROM encuentro e;
```

**Explicación:** las funciones de ventana calculan un valor por fila sin agruparlas. `ROW_NUMBER()` reinicia la cuenta en cada
paciente (`PARTITION BY id_paciente`): 1 es su consulta más reciente. `RANK()` ordena todas las consultas por fecha, y las que
tienen la misma fecha comparten lugar (por eso después de dos en el lugar 1 sigue el 3).

**Evidencia:** 93 filas, una por consulta; `num_consulta_paciente` llega hasta 4.

| id_encuentro | id_paciente | fecha_inicio | num_consulta_paciente | ranking_global_fecha |
|---|---|---|---|---|
| 91 | 22 | 2026-10-17 15:05 | 1 | 1 |
| 86 | 13 | 2026-10-17 15:05 | 1 | 1 |
| 89 | 11 | 2026-10-17 14:05 | 1 | 3 |

**Aplicación:** el historial del expediente del paciente lista sus consultas en este orden, de la más reciente a la más antigua.
