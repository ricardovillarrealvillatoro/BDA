# Vistas

Código en [`db/views.sql`](../db/views.sql). Son **9 vistas** (`CREATE OR REPLACE VIEW`) y las 9 se consultan desde la
aplicación Flask con `SELECT * FROM vw_... WHERE ...`: la vista arma los JOIN y los cálculos, y Flask solo agrega el filtro
(paciente, médico, fechas) y el orden de cada página.

**Cómo se obtuvieron los resultados.** Las consultas de ejemplo se ejecutaron el 18/10/2026 sobre los datos de prueba
(`db/06_datos_prueba.sql`: 14 usuarios, 42 pacientes, 93 consultas). Como `vw_pacientes_ultima_consulta` usa la fecha actual
para calcular la edad, y `vw_contexto_clinico` la usa para saber qué medicación sigue vigente, esas columnas pueden cambiar
con los días.

| # | Vista | Qué devuelve | Páginas que la usan |
|---|---|---|---|
| 1 | [`vw_pacientes_ultima_consulta`](#1-vw_pacientes_ultima_consulta) | Un renglón por paciente con su última consulta | Pacientes, Informes médicos |
| 2 | [`vw_historial_consultas_medico`](#2-vw_historial_consultas_medico) | Un renglón por consulta con médico, paciente y diagnóstico principal | Consultas, expediente del paciente, detalle del médico, Informes médicos |
| 3 | [`vw_consultas_por_especialidad`](#3-vw_consultas_por_especialidad) | Consultas y pacientes por especialidad | Rendimiento |
| 4 | [`vw_indicadores_atencion`](#4-vw_indicadores_atencion) | Consultas cerradas y su duración promedio por tipo | Rendimiento, Panel general |
| 5 | [`vw_pacientes_consultas_pendientes`](#5-vw_pacientes_consultas_pendientes) | Consultas abiertas con lo que falta por resolver | Panel general, espacio del médico |
| 6 | [`vw_resultados_laboratorio`](#6-vw_resultados_laboratorio) | Pruebas ordenadas con su último resultado interpretado | Laboratorio, detalle de la consulta, espacio del médico |
| 7 | [`vw_contexto_clinico`](#7-vw_contexto_clinico) | Todo lo clínico de un paciente en una sola lista | Detalle de la consulta, espacio del médico |
| 8 | [`vw_alertas_activas`](#8-vw_alertas_activas) | Recomendaciones del copiloto sin decisión en consultas abiertas | Panel general, espacio del médico |
| 9 | [`vw_auditoria_por_usuario`](#9-vw_auditoria_por_usuario) | Altas y cambios de la bitácora por usuario y tabla | Auditoría |

---

## 1. `vw_pacientes_ultima_consulta`

**Propósito:** listar a cada paciente con su edad, cuántas consultas tiene y cómo fue la última (fecha, médico, estado).

**Tablas:** `paciente`, `encuentro`, `usuario`.

**Cómo funciona:**
- `paciente LEFT JOIN encuentro` con `GROUP BY` del paciente: `COUNT` da el total de consultas y `MAX` la fecha de la última.
  Por ser LEFT JOIN, los pacientes sin consultas también aparecen, con 0 consultas y fecha en `NULL`.
- Tres subconsultas correlacionadas (`ORDER BY fecha_inicio DESC LIMIT 1`) traen el médico, el estado y el id de la última consulta.
- `edad` se calcula con `age(fecha_nacimiento)`, así que no se guarda en la tabla y siempre está al día.

**Columnas:** `id_paciente`, `nombre_completo`, `curp`, `sexo`, `edad`, `activo`, `fecha_ultima_consulta`, `total_consultas`,
`medico_ultima_consulta`, `estado_ultima_consulta`, `id_ultima_consulta`.

**Dónde se usa:**
- `app/pacientes.py` › lista de **Pacientes** (`/pacientes/`): búsqueda por nombre o CURP y filtros activos, sin consultas y dados de baja.
- `app/reportes.py` › búsqueda de pacientes en **Informes médicos** (`/report/`).

**Evidencia:**

```sql
SELECT count(*) AS pacientes,
       count(*) FILTER (WHERE total_consultas = 0) AS sin_consultas,
       count(*) FILTER (WHERE NOT activo) AS dados_de_baja
FROM vw_pacientes_ultima_consulta;
```

| pacientes | sin_consultas | dados_de_baja |
|---|---|---|
| 42 | 5 | 1 |

```sql
SELECT id_paciente, nombre_completo, edad, total_consultas, fecha_ultima_consulta::date,
       medico_ultima_consulta, estado_ultima_consulta
FROM vw_pacientes_ultima_consulta WHERE id_paciente IN (5, 15);
```

| id_paciente | nombre_completo | edad | total_consultas | fecha_ultima_consulta | medico_ultima_consulta | estado_ultima_consulta |
|---|---|---|---|---|---|---|
| 5 | Carlos Garza García | 75 | 4 | 2026-10-17 | Helen Rostova | abierto |
| 15 | Carlos Treviño Villarreal | 69 | 4 | 2026-10-17 | Sofía Cantú | abierto |

---

## 2. `vw_historial_consultas_medico`

**Propósito:** el historial de consultas con el médico que atendió, su especialidad principal, el paciente y el diagnóstico principal.

**Tablas:** `medico`, `usuario`, `encuentro`, `paciente`, `especialidad`, `medico_especialidad`, `diagnostico`, `catalogo_cie10`.

**Cómo funciona:**
- `INNER JOIN` de `medico` → `usuario` (nombre del médico) → `encuentro` → `paciente`: un renglón por consulta.
- Subconsultas para la especialidad principal (`es_principal = TRUE`) y para el código y la descripción del diagnóstico
  `principal`. Si la consulta no tiene diagnóstico principal (cancelada o todavía abierta), esas columnas quedan en `NULL`.

**Columnas:** `id_medico`, `medico`, `cedula_profesional`, `id_encuentro`, `id_paciente`, `fecha_inicio`, `tipo`, `estado`,
`motivo`, `paciente`, `curp`, `especialidad`, `dx_principal`, `dx_descripcion`.

**Dónde se usa:**
- `app/consultas.py` › lista de **Consultas** (`/consultas/`) con filtros por estado, tipo, fechas y "solo mis consultas".
- `app/pacientes.py` › historial del **expediente del paciente**.
- `app/medicos.py` › últimas 30 consultas en el **detalle del médico**.
- `app/reportes.py` › consultas de cada paciente en **Informes médicos**, con cuántas recomendaciones se decidieron.

**Evidencia:** 93 renglones, uno por consulta; 6 sin diagnóstico principal.

```sql
SELECT id_encuentro, medico, especialidad, paciente, fecha_inicio::date, tipo, estado, dx_principal, dx_descripcion
FROM vw_historial_consultas_medico WHERE id_paciente = 2 ORDER BY fecha_inicio DESC LIMIT 3;
```

| id_encuentro | medico | especialidad | paciente | fecha_inicio | tipo | estado | dx_principal | dx_descripcion |
|---|---|---|---|---|---|---|---|---|
| 52 | Helen Rostova | Endocrinología | Patricia Aguilar | 2026-07-18 | urgencia | cerrado | R73.9 | Hiperglucemia, no especificada |
| 47 | Tomás Leal | Medicina Interna | Patricia Aguilar | 2026-07-11 | urgencia | cerrado | E66.9 | Obesidad, no especificada |
| 4 | Tomás Leal | Medicina Interna | Patricia Aguilar | 2026-05-05 | urgencia | cancelado | *NULL* | *NULL* |

---

## 3. `vw_consultas_por_especialidad`

**Propósito:** cuántas consultas y cuántos pacientes distintos atendió cada especialidad.

**Tablas:** `especialidad`, `medico_especialidad`, `encuentro`.

**Cómo funciona:** `INNER JOIN` de la especialidad con los médicos que la tienen y con sus consultas, agrupado por especialidad.
`COUNT(DISTINCT id_paciente)` cuenta a cada paciente una sola vez. Cuenta todas las especialidades del médico, no solo la
principal: la consulta de un médico con dos especialidades suma en ambas, por eso el total (108) es mayor que 93.

**Columnas:** `especialidad`, `total_atenciones`, `pacientes_unicos`.

**Dónde se usa:** `app/rendimiento.py` › tabla por especialidad en **Rendimiento** (`/performance/`).

**Evidencia:**

```sql
SELECT * FROM vw_consultas_por_especialidad ORDER BY total_atenciones DESC;
```

| especialidad | total_atenciones | pacientes_unicos |
|---|---|---|
| Medicina Interna | 37 | 16 |
| Geriatría | 18 | 14 |
| Endocrinología | 16 | 7 |
| Medicina Familiar | 12 | 11 |
| Cardiología | 7 | 6 |
| Medicina de Urgencias | 7 | 6 |
| Nefrología | 7 | 3 |
| Neumología | 4 | 3 |

---

## 4. `vw_indicadores_atencion`

**Propósito:** cuántas consultas se cerraron de cada tipo y cuánto duraron en promedio.

**Tablas:** `encuentro`.

**Cómo funciona:** filtra las consultas `cerrado` (las únicas con `fecha_fin`), agrupa por tipo y calcula la duración con
`EXTRACT(EPOCH FROM fecha_fin - fecha_inicio) / 60`, en minutos.

**Columnas:** `tipo_encuentro`, `total_encuentros`, `duracion_promedio_minutos`.

**Dónde se usa:**
- `app/rendimiento.py` › indicadores por tipo de consulta en **Rendimiento**.
- `app/panel.py` › "horas promedio por consulta" del **Panel general**, como promedio ponderado de los tres tipos.

**Evidencia:** 81 consultas cerradas de las 93 (las demás están abiertas o canceladas).

```sql
SELECT * FROM vw_indicadores_atencion ORDER BY total_encuentros DESC;
```

| tipo_encuentro | total_encuentros | duracion_promedio_minutos |
|---|---|---|
| consulta | 65 | 135.80 |
| urgencia | 14 | 125.64 |
| hospitalizacion | 2 | 124.50 |

---

## 5. `vw_pacientes_consultas_pendientes`

**Propósito:** las consultas abiertas, con cuántas pruebas de laboratorio y cuántas recomendaciones del copiloto faltan por resolver.

**Tablas:** `paciente`, `encuentro`, `medico`, `usuario`, `orden_medica`, `detalle_orden`, `recomendacion`, `decision_medica`.

**Cómo funciona:**
- `INNER JOIN` de paciente, consulta y médico, filtrado por `estado = 'abierto'`.
- `pruebas_pendientes`: subconsulta que cuenta los detalles de orden en estado `pendiente` o `tomada`.
- `recomendaciones_pendientes`: subconsulta con `NOT EXISTS` que cuenta las recomendaciones que todavía no tienen decisión médica.

**Columnas:** `id_paciente`, `paciente`, `telefono`, `id_encuentro`, `fecha_inicio`, `motivo`, `medico_atendiendo`, `tipo`,
`id_medico`, `pruebas_pendientes`, `recomendaciones_pendientes`.

**Dónde se usa:** `app/panel.py` › lista de consultas abiertas del **Panel general** (todas) y del **espacio del médico**
(solo las suyas, filtradas por `id_medico`).

**Evidencia:** 9 consultas abiertas.

```sql
SELECT id_encuentro, paciente, medico_atendiendo, fecha_inicio::date, tipo, pruebas_pendientes, recomendaciones_pendientes
FROM vw_pacientes_consultas_pendientes ORDER BY fecha_inicio LIMIT 3;
```

| id_encuentro | paciente | medico_atendiendo | fecha_inicio | tipo | pruebas_pendientes | recomendaciones_pendientes |
|---|---|---|---|---|---|---|
| 89 | Andrés Cavazos | Ana Gutiérrez | 2026-10-17 | hospitalizacion | 0 | 0 |
| 86 | Francisco López | Jorge Salinas | 2026-10-17 | hospitalizacion | 3 | 1 |
| 87 | Carlos Garza | Helen Rostova | 2026-10-17 | consulta | 0 | 0 |

---

## 6. `vw_resultados_laboratorio`

**Propósito:** cada prueba ordenada con su último resultado, interpretado contra el rango de referencia que corresponde al
sexo y la edad del paciente.

**Tablas:** `detalle_orden`, `orden_medica`, `prueba`, `unidad`, `encuentro`, `paciente`, `usuario`, `resultado`, `rango_referencia`.

**Cómo funciona:**
- `INNER JOIN` del detalle con su orden, prueba, consulta, paciente y médico; `LEFT JOIN` con la unidad.
- `LEFT JOIN LATERAL` con `resultado` para tomar solo el más reciente de cada detalle. Si la prueba no tiene resultado, el
  renglón se conserva con `id_resultado` en `NULL`.
- Otro `LEFT JOIN LATERAL` elige el rango de referencia de la prueba para el sexo del paciente y su edad en la fecha del
  resultado; si no hay uno de su sexo, usa el general (`'X'`).
- `estado_resultado` (`CASE`): `critico` fuera del rango crítico, `fuera_rango` fuera del de referencia, `normal`,
  `sin_rango` cuando no hay valor numérico o rango, y `NULL` si todavía no hay resultado.

**Columnas:** `id_orden`, `id_encuentro`, `fecha_orden`, `prioridad`, `id_detalle`, `estado_detalle`, `prueba`, `codigo_loinc`,
`unidad`, `id_paciente`, `estado_encuentro`, `paciente`, `medico`, `id_resultado`, `valor_numerico`, `valor_texto`,
`fecha_resultado`, `estado_resultado`.

**Dónde se usa:**
- `app/laboratorio.py` › **Laboratorio** (`/lab/`): resultados capturados con filtros y pruebas pendientes de captura.
- `app/consultas.py` › órdenes de laboratorio en el **detalle de la consulta**.
- `app/panel.py` › últimos resultados del paciente en el **espacio del médico**.

**Evidencia:** 218 pruebas ordenadas: 196 con resultado y 22 todavía sin resultado.

```sql
SELECT estado_resultado, count(*) FROM vw_resultados_laboratorio GROUP BY estado_resultado ORDER BY 1;
```

| estado_resultado | count |
|---|---|
| critico | 4 |
| fuera_rango | 124 |
| normal | 68 |
| *NULL* (sin resultado) | 22 |

```sql
SELECT id_detalle, paciente, prueba, valor_numerico, unidad, estado_resultado
FROM vw_resultados_laboratorio WHERE estado_resultado = 'critico' LIMIT 2;
```

| id_detalle | paciente | prueba | valor_numerico | unidad | estado_resultado |
|---|---|---|---|---|---|
| 13 | Carlos Treviño | Potasio sérico | 6.9000 | mmol/L | critico |
| 56 | Carlos Garza | Glucosa sérica | 515.6000 | mg/dL | critico |

---

## 7. `vw_contexto_clinico`

**Propósito:** todo lo que el copiloto conoce de un paciente (diagnósticos, laboratorio, alergias, antecedentes y medicación
vigente) en una sola lista con las mismas columnas.

**Tablas:** `diagnostico`, `encuentro`, `catalogo_cie10`, `alergia`, `principio_activo`, `antecedente`, `tipo_antecedente`,
`prescripcion`, `medicamento`, `unidad`, y la vista `vw_resultados_laboratorio`.

**Cómo funciona:** cinco `SELECT` unidos con `UNION ALL`, uno por `fuente`, que llevan sus datos a las mismas seis columnas:
- `diagnostico`: código y descripción CIE-10, sin los descartados.
- `laboratorio`: los resultados de la vista 6 (una vista que usa otra vista).
- `alergia`: el principio activo o la sustancia escrita a mano, con severidad y reacción.
- `antecedente`: tipo y descripción, con estado y parentesco.
- `medicamento`: solo la medicación vigente (`fecha_fin` vacía o futura), con dosis y frecuencia.

**Columnas:** `id_paciente`, `fuente`, `concepto`, `valor`, `unidad`, `fecha`.

**Dónde se usa:**
- `app/consultas.py` › sección de contexto clínico del **detalle de la consulta**.
- `app/panel.py` › conteo por fuente en el resumen del paciente del **espacio del médico**.

**Evidencia:** 438 renglones en total.

```sql
SELECT fuente, count(*) FROM vw_contexto_clinico GROUP BY fuente ORDER BY 1;
```

| fuente | count |
|---|---|
| alergia | 4 |
| antecedente | 47 |
| diagnostico | 164 |
| laboratorio | 196 |
| medicamento | 27 |

```sql
SELECT fuente, concepto, valor, unidad, fecha::date
FROM vw_contexto_clinico WHERE id_paciente = 2 ORDER BY fecha DESC NULLS LAST LIMIT 4;
```

| fuente | concepto | valor | unidad | fecha |
|---|---|---|---|---|
| laboratorio | Hemoglobina A1c (HbA1c) | 7.4 | % | 2026-07-18 |
| laboratorio | Colesterol LDL | 143.4 | mg/dL | 2026-07-18 |
| diagnostico | E11.9 Diabetes mellitus tipo 2 sin complicaciones | presuntivo | | 2026-07-18 |
| laboratorio | Glucosa sérica | 176.3 | mg/dL | 2026-07-18 |

---

## 8. `vw_alertas_activas`

**Propósito:** las recomendaciones del copiloto que siguen sin decisión del médico en consultas abiertas, con una prioridad
numérica para ordenarlas de la más urgente a la menos.

**Tablas:** `recomendacion`, `encuentro`, `paciente`, `usuario`, `version_regla`, `regla_clinica`, `decision_medica`.

**Cómo funciona:**
- `INNER JOIN` de la recomendación con su consulta, paciente, médico y la versión y regla clínica que la generó.
- Filtro: consulta `abierto` y `NOT EXISTS` de una decisión médica para esa recomendación.
- `nivel_prioridad` (`CASE`): crítica 4, alta 3, media 2, baja 1.

**Columnas:** `id_recomendacion`, `id_encuentro`, `id_paciente`, `id_medico`, `paciente`, `medico`, `regla`, `regla_nombre`,
`prioridad_asignada`, `nivel_prioridad`, `texto_generado`, `fecha_hora`.

**Dónde se usa:**
- `app/panel.py` › las 15 alertas más urgentes del **Panel general**.
- `app/panel.py` › prioridad más alta de la consulta elegida en el **espacio del médico**.

**Evidencia:** 5 alertas activas: 2 críticas, 2 altas y 1 media.

```sql
SELECT paciente, medico, regla, prioridad_asignada, nivel_prioridad, texto_generado
FROM vw_alertas_activas ORDER BY nivel_prioridad DESC, fecha_hora DESC LIMIT 3;
```

| paciente | medico | regla | prioridad_asignada | nivel_prioridad | texto_generado |
|---|---|---|---|---|---|
| Carlos Treviño | Sofía Cantú | RC-07 | critica | 4 | Dos o más indicadores fuera de rango: revisión médica inmediata… |
| Roberto Medina | Sofía Cantú | RC-07 | critica | 4 | Dos o más indicadores fuera de rango: revisión médica inmediata… |
| Francisco López | Jorge Salinas | RC-41 | alta | 3 | Potasio elevado con IECA/ARA II: revisar dosis y función renal. |

---

## 9. `vw_auditoria_por_usuario`

**Propósito:** resumen de la bitácora de auditoría: cuántas altas, cambios y bajas hizo cada usuario en cada tabla y cuándo fue la última.

**Tablas:** `auditoria`, `usuario`.

**Cómo funciona:** `auditoria LEFT JOIN usuario` (los cambios hechos sin sesión, como la carga directa por `psql`, salen como
`(sin sesión)`), agrupado por usuario y tabla. `COUNT(*) FILTER (WHERE accion = ...)` cuenta cada tipo de acción en una sola pasada.

**Columnas:** `usuario`, `tabla`, `inserciones`, `actualizaciones`, `eliminaciones`, `ultima_accion`.

**Dónde se usa:** `app/auditoria.py` › tabla de resumen de **Auditoría** (`/audit/`).

**Evidencia:** 78 combinaciones de usuario y tabla, con 1,098 inserciones, 165 actualizaciones y ninguna eliminación (los
pacientes y médicos se dan de baja lógica, no se borran).

```sql
SELECT * FROM vw_auditoria_por_usuario ORDER BY inserciones DESC LIMIT 3;
```

| usuario | tabla | inserciones | actualizaciones | eliminaciones | ultima_accion |
|---|---|---|---|---|---|
| copiloto | RECOMENDACION | 70 | 70 | 0 | 2026-10-17 16:05 |
| admin | ANTECEDENTE | 47 | 0 | 0 | 2026-10-17 16:05 |
| tomas.leal | DETALLE_ORDEN | 47 | 0 | 0 | 2026-10-17 16:05 |
