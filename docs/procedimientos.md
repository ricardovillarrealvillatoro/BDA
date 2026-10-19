# Procedimientos almacenados

Código en [`db/procedimientos.sql`](../db/procedimientos.sql). Son **15 procedimientos** (`CREATE PROCEDURE`, se invocan con `CALL`) y
los 15 se ejecutan desde la aplicación Flask.

La base también tiene **2 funciones**, que no cuentan para el mínimo de procedimientos: `fn_auditoria()` y
`fn_auditoria_inmutable()` (`CREATE FUNCTION ... RETURNS trigger`, en [`db/triggers.sql`](../db/triggers.sql)). No se invocan
con `CALL` ni con `SELECT`: las ejecuta PostgreSQL desde los triggers de auditoría.

**Cómo se obtuvieron los resultados.** Cada ejemplo se ejecutó el 18/10/2026 sobre los datos de prueba
(`db/06_datos_prueba.sql`), dentro de una transacción que después se revirtió. Los id generados (por ejemplo, el del
paciente nuevo) dependen de la secuencia de la tabla, así que pueden ser otros en cada base.

**Manejo de errores en Flask.** Cada `CALL` se ejecuta dentro de `with conectar() as conn` (`app/db.py`): si el
procedimiento lanza una excepción, la transacción completa se revierte y la página muestra el mensaje principal del error
(`mensaje_error`). Los errores con `USING COLUMN` se muestran junto al campo del formulario.

| # | Procedimiento | Página que lo usa |
|---|---|---|
| 1 | [`sp_registrar_paciente`](#1-sp_registrar_paciente) | Pacientes › Registrar paciente |
| 2 | [`sp_desactivar_paciente`](#2-sp_desactivar_paciente) | Expediente del paciente › Dar de baja |
| 3 | [`sp_abrir_encuentro`](#3-sp_abrir_encuentro) | Consultas › Abrir consulta |
| 4 | [`sp_cerrar_encuentro`](#4-sp_cerrar_encuentro) | Detalle de la consulta › Cerrar consulta |
| 5 | [`sp_registrar_diagnostico`](#5-sp_registrar_diagnostico) | Detalle de la consulta › Diagnósticos |
| 6 | [`sp_prescribir_medicamento`](#6-sp_prescribir_medicamento) | Detalle de la consulta › Prescripciones |
| 7 | [`sp_generar_orden_medica`](#7-sp_generar_orden_medica) | Detalle de la consulta › Órdenes de laboratorio |
| 8 | [`sp_registrar_resultado_laboratorio`](#8-sp_registrar_resultado_laboratorio) | Laboratorio › Capturar resultado |
| 9 | [`sp_registrar_decision_medica`](#9-sp_registrar_decision_medica) | Detalle de la consulta y Panel › Recomendaciones |
| 10 | [`sp_asignar_especialidad_medico`](#10-sp_asignar_especialidad_medico) | Detalle del médico › Asignar especialidad |
| 11 | [`sp_registrar_medico`](#11-sp_registrar_medico) | Médicos › Registrar médico |
| 12 | [`sp_actualizar_medico`](#12-sp_actualizar_medico) | Médicos › Editar |
| 13 | [`sp_cambiar_estado_medico`](#13-sp_cambiar_estado_medico) | Detalle del médico › Dar de baja / Reactivar |
| 14 | [`sp_actualizar_encuentro`](#14-sp_actualizar_encuentro) | Consultas › Editar y notas del Panel |
| 15 | [`sp_cancelar_encuentro`](#15-sp_cancelar_encuentro) | Detalle de la consulta › Cancelar consulta |

---

## 1. `sp_registrar_paciente`

**Propósito:** dar de alta un paciente nuevo y devolver su id.
**Ruta Flask:** `POST /pacientes/nuevo` (`pacientes.nuevo`), roles médico y administrador clínico.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_curp` | `CHAR(18)` | IN | CURP en mayúsculas |
| `p_nombre`, `p_apellido_paterno` | `VARCHAR` | IN | Obligatorios |
| `p_apellido_materno` | `VARCHAR(60)` | IN | Opcional |
| `p_fecha_nacimiento` | `DATE` | IN | No puede ser futura |
| `p_sexo` | `CHAR(1)` | IN | `F`, `M` o `I` |
| `p_telefono`, `p_email`, `p_direccion` | `VARCHAR` | IN | Opcionales |
| `p_id_paciente` | `BIGINT` | OUT | Id del paciente creado |

**Tablas:** `paciente`.

**Reglas de negocio:**
- La fecha de nacimiento no puede ser futura.
- No puede haber dos pacientes con la misma CURP.
- La tabla valida además el formato oficial de la CURP (`ck_paciente_curp`) y el sexo.
- El paciente se crea activo.

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| Fecha futura | `23514` | La fecha de nacimiento no puede ser futura. (columna `fecha_nacimiento`) |
| CURP repetida | `23505` | Ya existe un paciente con la CURP …. (columna `curp`) |

**Ejemplo y resultados:**

```sql
CALL sp_registrar_paciente('PEAA900501MNLRLL09', 'Ana', 'Pérez', 'López', '1990-05-01', 'F',
                           '8112345678', 'ana.perez@correo.example', 'Av. Juárez 100, Monterrey, N.L.', NULL);
```
- Esperado: devuelve el id del paciente nuevo, que queda activo.
- Obtenido: `p_id_paciente = 46`; el paciente 46 tiene la CURP `PEAA900501MNLRLL09` y `activo = true`.

```sql
CALL sp_registrar_paciente('AUPP460420MNLGRT04', 'Otra', 'Persona', NULL, '1946-04-20', 'F', NULL, NULL, NULL, NULL);
```
- Esperado: error, porque la CURP ya es del paciente 2.
- Obtenido: `23505` · Ya existe un paciente con la CURP AUPP460420MNLGRT04.

```sql
CALL sp_registrar_paciente('PEAA900501MNLRLL09', 'Ana', 'Pérez', NULL, '2999-01-01', 'F', NULL, NULL, NULL, NULL);
```
- Esperado: error de fecha futura.
- Obtenido: `23514` · La fecha de nacimiento no puede ser futura.

---

## 2. `sp_desactivar_paciente`

**Propósito:** baja lógica de un paciente. No se borra la fila para conservar su historial clínico, que está ligado por
llaves foráneas.
**Ruta Flask:** `POST /pacientes/<id>/baja` (`pacientes.baja`), solo administrador clínico.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_paciente` | `BIGINT` | IN | Paciente a dar de baja |

**Tablas:** `paciente`.

**Reglas de negocio:**
- Cambia `activo` a falso y guarda `fecha_baja`.
- Un paciente dado de baja ya no aparece entre los activos y no puede abrir consultas (ver `sp_abrir_encuentro`).

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| No existe o ya estaba de baja | `P0001` | El paciente con ID … no existe o ya está desactivado. |

**Ejemplo y resultados:**

```sql
CALL sp_desactivar_paciente(2);
```
- Esperado: el paciente 2 queda inactivo y con fecha de baja.
- Obtenido: `activo = false` y `fecha_baja` registrada.

```sql
CALL sp_desactivar_paciente(37);
```
- Esperado: error, porque el paciente 37 ya está dado de baja en los datos de prueba.
- Obtenido: `P0001` · El paciente con ID 37 no existe o ya está desactivado.

---

## 3. `sp_abrir_encuentro`

**Propósito:** abrir una consulta (encuentro) para un paciente con un médico y devolver su id.
**Ruta Flask:** `POST /consultas/nueva` (`consultas.nueva`), roles médico y administrador clínico. Un médico solo puede
abrir consultas a su nombre; el administrador elige el médico.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_paciente` | `BIGINT` | IN | Paciente |
| `p_id_medico` | `BIGINT` | IN | Médico tratante |
| `p_tipo` | `VARCHAR(20)` | IN | `consulta`, `urgencia` u `hospitalizacion` |
| `p_motivo` | `TEXT` | IN | Motivo de la consulta (mínimo 5 caracteres) |
| `p_id_encuentro` | `BIGINT` | OUT | Id de la consulta creada |

**Tablas:** `encuentro`, `paciente`, `medico`, `usuario`.

**Reglas de negocio:**
- El paciente debe existir y estar activo.
- El médico debe existir y su cuenta debe estar activa.
- Un paciente solo puede tener una consulta abierta a la vez; el índice único parcial `ux_encuentro_abierto_paciente` lo
  garantiza también en la tabla.
- La consulta se crea en estado `abierto` con la fecha y hora actuales.

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| Paciente inexistente o de baja | `P0001` | El paciente no existe o está dado de baja. |
| Médico inexistente o desactivado | `P0001` | El médico no existe o su cuenta está desactivada. |
| Ya tiene una consulta abierta | `P0001` | El paciente ya tiene una consulta abierta en curso. |
| Tipo o motivo inválido | `23514` | Restricciones CHECK de `encuentro` |

**Ejemplo y resultados:**

```sql
CALL sp_abrir_encuentro(2, 5, 'consulta', 'Control de presión arterial', NULL);
```
- Esperado: devuelve el id de la consulta nueva, en estado `abierto`.
- Obtenido: `p_id_encuentro = 100`, con paciente 2, médico 5 y estado `abierto`.

```sql
CALL sp_abrir_encuentro(13, 5, 'consulta', 'Control de presión arterial', NULL);
```
- Esperado: error, porque el paciente 13 tiene abierta la consulta 86.
- Obtenido: `P0001` · El paciente ya tiene una consulta abierta en curso.

```sql
CALL sp_abrir_encuentro(37, 5, 'consulta', 'Control de presión arterial', NULL);
```
- Esperado: error, porque el paciente 37 está dado de baja.
- Obtenido: `P0001` · El paciente no existe o está dado de baja.

---

## 4. `sp_cerrar_encuentro`

**Propósito:** cerrar una consulta abierta y registrar sus notas finales.
**Ruta Flask:** `POST /consultas/<id>/cerrar` (`consultas.cerrar`), el médico tratante o el administrador clínico.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_encuentro` | `BIGINT` | IN | Consulta a cerrar |
| `p_notas` | `TEXT` | IN | Notas finales; con `NULL` se conservan las notas que ya tenía |

**Tablas:** `encuentro`.

**Reglas de negocio:**
- Solo se cierran consultas en estado `abierto`.
- Guarda `fecha_fin`; la restricción `ck_encuentro_cierre` exige que toda consulta cerrada la tenga.
- Si no se mandan notas, no se borran las que ya había.

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| No existe, o ya está cerrada o cancelada | `P0001` | La consulta … no existe o ya fue cerrada/cancelada. |

**Ejemplo y resultados:**

```sql
CALL sp_cerrar_encuentro(91, 'Paciente estable, control en 3 meses.');
```
- Esperado: la consulta 91 queda cerrada, con fecha de fin y las notas.
- Obtenido: `estado = 'cerrado'`, `fecha_fin` registrada y la nota guardada.

```sql
CALL sp_cerrar_encuentro(1, NULL);
```
- Esperado: error, porque la consulta 1 ya está cerrada.
- Obtenido: `P0001` · La consulta 1 no existe o ya fue cerrada/cancelada.

---

## 5. `sp_registrar_diagnostico`

**Propósito:** agregar un diagnóstico CIE-10 a una consulta.
**Ruta Flask:** `POST /consultas/<id>/diagnostico` (`consultas.agregar_diagnostico`). Antes de llamarlo, Flask comprueba
que la consulta esté abierta y que el usuario sea el médico tratante o el administrador (`validar_modificable`).

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_encuentro` | `BIGINT` | IN | Consulta |
| `p_codigo_cie10` | `VARCHAR(10)` | IN | Código del catálogo CIE-10 |
| `p_tipo` | `VARCHAR(12)` | IN | `principal` o `secundario` |
| `p_estado` | `VARCHAR(12)` | IN | `presuntivo`, `confirmado` o `descartado` |

**Tablas:** `diagnostico`; se relaciona con `encuentro` y `catalogo_cie10` por llave foránea.

**Reglas de negocio** (las aplican las restricciones de la tabla):
- El código debe existir en el catálogo CIE-10.
- Una consulta tiene un solo diagnóstico principal (`ux_diagnostico_principal`).
- El mismo código no se repite en una consulta (`uq_diagnostico`).
- Tipo y estado deben ser valores válidos (CHECK).

**Excepciones:**

| Caso | SQLSTATE | Restricción |
|---|---|---|
| Segundo diagnóstico principal | `23505` | `ux_diagnostico_principal` |
| Código repetido en la consulta | `23505` | `uq_diagnostico` |
| Código que no está en el catálogo | `23503` | `diagnostico_codigo_cie10_fkey` |
| Tipo o estado inválido | `23514` | CHECK de `diagnostico` |

**Ejemplo y resultados:**

```sql
CALL sp_registrar_diagnostico(86, 'J06.9', 'secundario', 'presuntivo');
```
- Esperado: la consulta 86 pasa a tener 3 diagnósticos.
- Obtenido: I10 principal, E78.0 secundario y J06.9 secundario.

```sql
CALL sp_registrar_diagnostico(86, 'E11.9', 'principal', 'confirmado');
```
- Esperado: error, porque la consulta 86 ya tiene un diagnóstico principal (I10).
- Obtenido: `23505` · violación de `ux_diagnostico_principal`.

```sql
CALL sp_registrar_diagnostico(86, 'X99', 'secundario', 'presuntivo');
```
- Esperado: error, porque el código no existe en el catálogo.
- Obtenido: `23503` · violación de `diagnostico_codigo_cie10_fkey`.

---

## 6. `sp_prescribir_medicamento`

**Propósito:** recetar un medicamento en una consulta.
**Ruta Flask:** `POST /consultas/<id>/prescribir` (`consultas.prescribir`), solo el rol médico. El médico que receta es
el usuario en sesión.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_encuentro` | `BIGINT` | IN | Consulta |
| `p_id_medicamento` | `BIGINT` | IN | Medicamento del catálogo |
| `p_id_medico` | `BIGINT` | IN | Médico que receta |
| `p_dosis` | `NUMERIC(10,3)` | IN | Mayor que cero |
| `p_id_unidad_dosis` | `BIGINT` | IN | Unidad de la dosis (por ejemplo `mg`) |
| `p_id_via` | `BIGINT` | IN | Vía de administración |
| `p_frecuencia_horas` | `SMALLINT` | IN | Cada cuántas horas |
| `p_indicacion` | `TEXT` | IN | Indicaciones para el paciente (opcional) |

**Tablas:** `prescripcion`; se relaciona con `encuentro`, `medicamento`, `medico`, `unidad` y `via_administracion`.

**Reglas de negocio:**
- La receta se registra con origen `interna` y fecha de inicio de hoy.
- La tabla exige dosis y frecuencia mayores que cero.
- Una receta interna debe tener médico (`ck_prescripcion_medico`).
- El mismo medicamento no se receta dos veces el mismo día en una consulta (`uq_prescripcion`).
- Flask verifica antes que la consulta esté abierta y sea del médico.

**Excepciones:**

| Caso | SQLSTATE | Restricción |
|---|---|---|
| Dosis o frecuencia en cero | `23514` | `prescripcion_dosis_check` / `prescripcion_frecuencia_horas_check` |
| Mismo medicamento el mismo día | `23505` | `uq_prescripcion` |
| Medicamento, unidad o vía inexistente | `23503` | Llaves foráneas de `prescripcion` |

**Ejemplo y resultados:**

```sql
CALL sp_prescribir_medicamento(86, 1, 6, 850, 9, 1, 12::smallint, 'Tomar con alimentos');
```
- Esperado: Metformina 850 mg por vía oral cada 12 h, origen `interna` e inicio hoy.
- Obtenido: prescripción 44 con `dosis = 850.000`, `frecuencia_horas = 12`, `origen = 'interna'` y `fecha_inicio = 2026-10-18`.

```sql
CALL sp_prescribir_medicamento(86, 1, 6, 0, 9, 1, 12::smallint, NULL);
```
- Esperado: error, porque la dosis es cero.
- Obtenido: `23514` · violación de `prescripcion_dosis_check`.

Si se receta Metformina dos veces el mismo día en la consulta 86:
- Esperado: error en la segunda receta.
- Obtenido: `23505` · violación de `uq_prescripcion`.

---

## 7. `sp_generar_orden_medica`

**Propósito:** crear una orden de laboratorio en estado `pendiente` y devolver su id.
**Ruta Flask:** `POST /consultas/<id>/orden` (`consultas.crear_orden`). En la misma transacción, Flask inserta en
`detalle_orden` una fila por cada prueba seleccionada. Si falla una, no se guarda ni la orden ni ninguna prueba.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_encuentro` | `BIGINT` | IN | Consulta |
| `p_id_medico` | `BIGINT` | IN | Médico que ordena |
| `p_prioridad` | `VARCHAR(8)` | IN | `rutina` o `urgente` |
| `p_id_orden` | `BIGINT` | OUT | Id de la orden creada |

**Tablas:** `orden_medica`; luego Flask usa `detalle_orden`.

**Reglas de negocio:**
- La orden nace `pendiente`.
- La prioridad solo puede ser `rutina` o `urgente`.
- Flask exige al menos una prueba y que la consulta esté abierta.
- Una prueba no se repite en la misma orden (`uq_detalle_orden`).

**Excepciones:**

| Caso | SQLSTATE | Restricción |
|---|---|---|
| Prioridad inválida | `23514` | `orden_medica_prioridad_check` |
| Consulta o médico inexistente | `23503` | Llaves foráneas de `orden_medica` |

**Ejemplo y resultados:**

```sql
CALL sp_generar_orden_medica(91, 13, 'urgente', NULL);
```
- Esperado: devuelve el id de una orden urgente y pendiente.
- Obtenido: `p_id_orden = 106`, con `prioridad = 'urgente'` y `estado = 'pendiente'`.

```sql
CALL sp_generar_orden_medica(91, 13, 'alta', NULL);
```
- Esperado: error, porque la prioridad no es válida.
- Obtenido: `23514` · violación de `orden_medica_prioridad_check`.

---

## 8. `sp_registrar_resultado_laboratorio`

**Propósito:** capturar el resultado de una prueba de laboratorio y marcar la prueba como reportada.
**Ruta Flask:** `POST /lab/<id_detalle>/capturar` (`laboratorio.capturar`), roles médico y administrador clínico. Quien
valida el resultado es el usuario en sesión.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_detalle` | `BIGINT` | IN | Prueba de la orden (`detalle_orden`) |
| `p_valor_numerico` | `NUMERIC(12,4)` | IN | Valor numérico (opcional) |
| `p_valor_texto` | `TEXT` | IN | Valor cualitativo (opcional) |
| `p_id_validador` | `BIGINT` | IN | Usuario que valida |

**Tablas:** `resultado` y `detalle_orden`.

**Reglas de negocio:**
- Guardar el resultado y cambiar la prueba a `reportada` ocurren en la misma transacción.
- Debe venir al menos un valor, numérico o de texto (`ck_resultado_valor`).
- La página de Laboratorio solo ofrece capturar pruebas pendientes o tomadas de consultas abiertas.

**Excepciones:**

| Caso | SQLSTATE | Restricción |
|---|---|---|
| Sin valor | `23514` | `ck_resultado_valor` |
| Prueba inexistente | `23503` | `resultado_id_detalle_fkey` |

**Ejemplo y resultados:**

```sql
CALL sp_registrar_resultado_laboratorio(199, 4.2, NULL, 4);
```
- Esperado: se guarda el potasio sérico (4.2) y la prueba 199 pasa a `reportada`.
- Obtenido: `valor_numerico = 4.2000` y `detalle_orden.estado = 'reportada'`.

```sql
CALL sp_registrar_resultado_laboratorio(199, NULL, NULL, 4);
```
- Esperado: error, porque no se envió ningún valor.
- Obtenido: `23514` · violación de `ck_resultado_valor`.

```sql
CALL sp_registrar_resultado_laboratorio(999999, 4.2, NULL, 4);
```
- Esperado: error, porque la prueba no existe.
- Obtenido: `23503` · violación de `resultado_id_detalle_fkey`.

---

## 9. `sp_registrar_decision_medica`

**Propósito:** registrar la decisión del médico sobre una recomendación del copiloto: aceptarla, rechazarla o
modificarla. Es la base del indicador de concordancia de la página Rendimiento.
**Ruta Flask:** `POST /consultas/recomendacion/<id>/decidir` (`consultas.decidir`), solo el rol médico; se usa desde el
detalle de la consulta y desde el Panel.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_recomendacion` | `BIGINT` | IN | Recomendación del copiloto |
| `p_id_medico` | `BIGINT` | IN | Médico que decide |
| `p_tipo` | `VARCHAR(10)` | IN | `aceptada`, `rechazada` o `modificada` |
| `p_justificacion` | `TEXT` | IN | Mínimo 10 caracteres |
| `p_accion_final` | `TEXT` | IN | Obligatoria si se modificó (valor por defecto `NULL`) |

**Tablas:** `decision_medica`; se relaciona con `recomendacion` y `medico`.

**Reglas de negocio:**
- Una recomendación tiene una sola decisión (UNIQUE en `id_recomendacion`).
- La justificación es obligatoria y tiene mínimo 10 caracteres.
- Si la decisión es `modificada`, hay que describir la acción final (`ck_decision_modificada`).
- Flask verifica antes que la consulta esté abierta.

**Excepciones:**

| Caso | SQLSTATE | Restricción |
|---|---|---|
| La recomendación ya tenía decisión | `23505` | `decision_medica_id_recomendacion_key` |
| Modificada sin acción final | `23514` | `ck_decision_modificada` |
| Justificación corta | `23514` | `decision_medica_justificacion_check` |

**Ejemplo y resultados:**

```sql
CALL sp_registrar_decision_medica(63, 4, 'aceptada', 'Concuerdo con la recomendación del copiloto.');
```
- Esperado: queda registrada la decisión `aceptada` de la médica 4 sobre la recomendación 63.
- Obtenido: fila en `decision_medica` con `tipo = 'aceptada'`.

```sql
CALL sp_registrar_decision_medica(1, 4, 'aceptada', 'Concuerdo con la recomendación del copiloto.');
```
- Esperado: error, porque la recomendación 1 ya tenía decisión.
- Obtenido: `23505` · violación de `decision_medica_id_recomendacion_key`.

```sql
CALL sp_registrar_decision_medica(63, 4, 'modificada', 'Ajusto la dosis por función renal.');
```
- Esperado: error, porque es `modificada` y no trae acción final.
- Obtenido: `23514` · violación de `ck_decision_modificada`.

```sql
CALL sp_registrar_decision_medica(63, 4, 'rechazada', 'No');
```
- Esperado: error, porque la justificación tiene menos de 10 caracteres.
- Obtenido: `23514` · violación de `decision_medica_justificacion_check`.

---

## 10. `sp_asignar_especialidad_medico`

**Propósito:** asignar una especialidad a un médico, con su cédula de especialidad.
**Ruta Flask:** `POST /medicos/<id>/especialidad` (`medicos.asignar_especialidad`), solo administrador clínico.
`sp_registrar_medico` también lo llama.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_medico` | `BIGINT` | IN | Médico |
| `p_id_especialidad` | `BIGINT` | IN | Especialidad del catálogo |
| `p_cedula_especialidad` | `VARCHAR(20)` | IN | Única en todo el sistema |
| `p_es_principal` | `BOOLEAN` | IN | Si será su especialidad principal |

**Tablas:** `medico_especialidad`.

**Reglas de negocio:**
- Un médico tiene una sola especialidad principal: al marcar una nueva como principal, la anterior deja de serlo.
- No se repite la misma especialidad en un médico (llave primaria).
- La cédula de especialidad es única.

**Excepciones:**

| Caso | SQLSTATE | Restricción |
|---|---|---|
| El médico ya tiene esa especialidad | `23505` | `medico_especialidad_pkey` |
| Cédula de especialidad repetida | `23505` | `medico_especialidad_cedula_especialidad_key` |
| Médico o especialidad inexistente | `23503` | Llaves foráneas de `medico_especialidad` |

**Ejemplo y resultados:**

```sql
CALL sp_asignar_especialidad_medico(5, 2, 'E9200001', TRUE);
```
- Esperado: la médica 5 suma Cardiología (2) como principal y Oftalmología (4) deja de ser principal.
- Obtenido: especialidad 2 con `es_principal = true` y especialidad 4 con `es_principal = false`.

```sql
CALL sp_asignar_especialidad_medico(4, 3, 'E9200002', FALSE);
```
- Esperado: error, porque la médica 4 ya tiene Endocrinología (3).
- Obtenido: `23505` · violación de `medico_especialidad_pkey`.

---

## 11. `sp_registrar_medico`

**Propósito:** dar de alta un médico completo en una sola operación: su cuenta de usuario, el rol `medico`, su cédula
profesional y, si se indica, su especialidad principal.
**Ruta Flask:** `POST /medicos/nuevo` (`medicos.nuevo`), solo administrador clínico. Flask calcula el hash de la
contraseña con `werkzeug.security.generate_password_hash`; la contraseña nunca llega en texto plano a la base.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_username` | `VARCHAR(50)` | IN | Minúsculas, números, punto o guion bajo |
| `p_password_hash` | `VARCHAR(255)` | IN | Hash de la contraseña |
| `p_nombre`, `p_apellido_paterno`, `p_apellido_materno` | `VARCHAR` | IN | Nombre del médico (apellido materno opcional) |
| `p_email` | `VARCHAR(120)` | IN | Correo único |
| `p_cedula_profesional` | `VARCHAR(20)` | IN | Cédula única |
| `p_id_especialidad` | `BIGINT` | IN | Especialidad principal (opcional) |
| `p_cedula_especialidad` | `VARCHAR(20)` | IN | Cédula de la especialidad (si hay especialidad) |
| `p_id_medico` | `BIGINT` | OUT | Id del médico, que es también su id de usuario |

**Tablas:** `usuario`, `usuario_rol`, `rol`, `medico` y `medico_especialidad`.

**Reglas de negocio:**
- El usuario, el correo (sin distinguir mayúsculas), la cédula profesional y la cédula de especialidad no pueden estar repetidos.
- Las cuatro inserciones ocurren en la misma transacción: si una falla, no queda un usuario a medias.
- Si se indica especialidad, se asigna como principal con `sp_asignar_especialidad_medico`.

**Excepciones** (todas con `USING COLUMN` para mostrarse en el campo del formulario):

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| Usuario repetido | `23505` | El usuario … ya existe. |
| Correo repetido | `23505` | El correo … ya está registrado. |
| Cédula profesional repetida | `23505` | La cédula profesional … ya está registrada. |
| Cédula de especialidad repetida | `23505` | La cédula de especialidad … ya está registrada. |

**Ejemplo y resultados:**

```sql
CALL sp_registrar_medico('mario.luna', '<hash de la contraseña>', 'Mario', 'Luna', NULL,
                         'mario.luna@medassist.example', '9100013', 2, 'E9100013', NULL);
```
- Esperado: devuelve el id del médico nuevo, con rol `medico` y Cardiología como especialidad principal.
- Obtenido: `p_id_medico = 20`, usuario `mario.luna`, rol `medico`, cédula `9100013` y especialidad 2 con `es_principal = true`.

```sql
CALL sp_registrar_medico('helen.rostova', '<hash>', 'Mario', 'Luna', NULL, 'mario.luna@medassist.example', '9100013', NULL, NULL, NULL);
```
- Esperado: error, porque el usuario ya existe.
- Obtenido: `23505` · El usuario helen.rostova ya existe. (columna `username`)

```sql
CALL sp_registrar_medico('mario.luna', '<hash>', 'Mario', 'Luna', NULL, 'mario.luna@medassist.example', '9100002', NULL, NULL, NULL);
```
- Esperado: error, porque la cédula ya es de otra médica.
- Obtenido: `23505` · La cédula profesional 9100002 ya está registrada. (columna `cedula_profesional`)

---

## 12. `sp_actualizar_medico`

**Propósito:** modificar los datos personales y la cédula profesional de un médico.
**Ruta Flask:** `POST /medicos/<id>/editar` (`medicos.editar`), solo administrador clínico.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_medico` | `BIGINT` | IN | Médico |
| `p_nombre`, `p_apellido_paterno`, `p_apellido_materno` | `VARCHAR` | IN | Nombre |
| `p_email` | `VARCHAR(120)` | IN | Correo |
| `p_cedula_profesional` | `VARCHAR(20)` | IN | Cédula |

**Tablas:** `usuario` y `medico`.

**Reglas de negocio:**
- El médico debe existir.
- El correo y la cédula no pueden pertenecer a otro usuario; sí puede conservar los suyos.
- Ambas tablas se actualizan en la misma transacción.

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| Médico inexistente | `P0001` | El médico con ID … no existe. |
| Correo de otro usuario | `23505` | El correo … ya está registrado. (columna `email`) |
| Cédula de otro médico | `23505` | La cédula profesional … ya está registrada. (columna `cedula_profesional`) |

**Ejemplo y resultados:**

```sql
CALL sp_actualizar_medico(5, 'Clara', 'Mercer', 'Ibarra', 'clara.mercer@medassist.example', '9100003');
```
- Esperado: se agrega el apellido materno y se conservan el correo y la cédula.
- Obtenido: `apellido_materno = 'Ibarra'`, sin error por el correo propio.

```sql
CALL sp_actualizar_medico(5, 'Clara', 'Mercer', NULL, 'helen.rostova@medassist.example', '9100003');
```
- Esperado: error, porque el correo es de otra médica.
- Obtenido: `23505` · El correo helen.rostova@medassist.example ya está registrado.

```sql
CALL sp_actualizar_medico(999, 'X', 'Y', NULL, 'x@medassist.example', '1');
```
- Esperado: error, porque el médico no existe.
- Obtenido: `P0001` · El médico con ID 999 no existe.

---

## 13. `sp_cambiar_estado_medico`

**Propósito:** baja lógica o reactivación de la cuenta de un médico. Su historial clínico se conserva.
**Ruta Flask:** `POST /medicos/<id>/baja` y `POST /medicos/<id>/reactivar` (`medicos.baja`, `medicos.reactivar`), solo
administrador clínico. Flask impide además que un usuario se desactive a sí mismo.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_medico` | `BIGINT` | IN | Médico |
| `p_activo` | `BOOLEAN` | IN | `FALSE` para dar de baja, `TRUE` para reactivar |

**Tablas:** `usuario`, `medico` y `encuentro`.

**Reglas de negocio:**
- No se puede desactivar a un médico con consultas abiertas: primero hay que cerrarlas o cancelarlas.
- Un médico desactivado no puede iniciar sesión, porque el login solo acepta usuarios activos.
- Tampoco se le pueden abrir consultas (ver `sp_abrir_encuentro`).

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| Médico inexistente | `P0001` | El médico con ID … no existe. |
| Tiene consultas abiertas | `P0001` | El médico tiene … consulta(s) abierta(s). Ciérrelas o cancélelas antes de desactivar la cuenta. |
| Ya estaba en ese estado | `P0001` | La cuenta del médico ya está activa / desactivada. |

**Ejemplo y resultados:**

```sql
CALL sp_cambiar_estado_medico(5, FALSE);
```
- Esperado: la cuenta de `clara.mercer`, que no tiene consultas abiertas, queda inactiva.
- Obtenido: `usuario.activo = false`.

```sql
CALL sp_cambiar_estado_medico(4, FALSE);
```
- Esperado: error, porque `helen.rostova` tiene 3 consultas abiertas.
- Obtenido: `P0001` · El médico tiene 3 consulta(s) abierta(s). Ciérrelas o cancélelas antes de desactivar la cuenta.

```sql
CALL sp_cambiar_estado_medico(8, TRUE);
```
- Esperado: error, porque la cuenta ya está activa.
- Obtenido: `P0001` · La cuenta del médico ya está activa.

---

## 14. `sp_actualizar_encuentro`

**Propósito:** corregir el tipo, el motivo o las notas de una consulta que sigue abierta.
**Ruta Flask:** `POST /consultas/<id>/editar` (`consultas.editar`), el médico tratante o el administrador clínico. El
Panel lo usa para guardar las notas de la consulta.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_encuentro` | `BIGINT` | IN | Consulta |
| `p_tipo` | `VARCHAR(20)` | IN | `consulta`, `urgencia` u `hospitalizacion` |
| `p_motivo` | `TEXT` | IN | Mínimo 5 caracteres |
| `p_notas` | `TEXT` | IN | Notas de la consulta |

**Tablas:** `encuentro`.

**Reglas de negocio:**
- Solo se modifican consultas abiertas; una consulta cerrada o cancelada ya es parte del historial.
- El tipo y el motivo se validan con las restricciones CHECK de la tabla.

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| No existe, o está cerrada o cancelada | `P0001` | La consulta … no existe o ya fue cerrada/cancelada. |
| Tipo o motivo inválido | `23514` | CHECK de `encuentro` |

**Ejemplo y resultados:**

```sql
CALL sp_actualizar_encuentro(86, 'urgencia', 'Dolor torácico de inicio súbito', 'Se solicita electrocardiograma.');
```
- Esperado: la consulta 86 cambia a urgencia, con el motivo y la nota nuevos.
- Obtenido: `tipo = 'urgencia'`, con el motivo y las notas actualizados.

```sql
CALL sp_actualizar_encuentro(1, 'consulta', 'Cambio de motivo', NULL);
```
- Esperado: error, porque la consulta 1 está cerrada.
- Obtenido: `P0001` · La consulta 1 no existe o ya fue cerrada/cancelada.

---

## 15. `sp_cancelar_encuentro`

**Propósito:** cancelar una consulta abierta por error, siempre que todavía no tenga información clínica.
**Ruta Flask:** `POST /consultas/<id>/cancelar` (`consultas.cancelar`), el médico tratante o el administrador clínico.

| Parámetro | Tipo | E/S | Descripción |
|---|---|---|---|
| `p_id_encuentro` | `BIGINT` | IN | Consulta |
| `p_motivo` | `TEXT` | IN | Motivo de la cancelación (mínimo 10 caracteres) |

**Tablas:** `encuentro`, `orden_medica`, `detalle_orden`, `resultado`, `diagnostico`, `recomendacion` y `decision_medica`.

**Reglas de negocio:**
- Hay que explicar el motivo, con mínimo 10 caracteres.
- Solo se cancelan consultas abiertas.
- No se cancela si ya tiene resultados de laboratorio, diagnósticos confirmados o decisiones sobre recomendaciones: esa
  información clínica no se puede perder.
- Las órdenes y pruebas pendientes se cancelan.
- La consulta queda en estado `cancelado` con fecha de fin, y el motivo se agrega a sus notas. No se borra nada.

**Excepciones:**

| Caso | SQLSTATE | Mensaje |
|---|---|---|
| Motivo corto | `P0001` | Explique el motivo de la cancelación (mínimo 10 caracteres). |
| No existe, o está cerrada o cancelada | `P0001` | La consulta … no existe o ya fue cerrada/cancelada. |
| Tiene resultados | `P0001` | No se puede cancelar: la consulta ya tiene resultados de laboratorio. |
| Tiene diagnósticos confirmados | `P0001` | No se puede cancelar: la consulta ya tiene diagnósticos confirmados. |
| Tiene decisiones | `P0001` | No se puede cancelar: ya hay decisiones médicas sobre sus recomendaciones. |

**Ejemplo y resultados:**

```sql
CALL sp_cancelar_encuentro(86, 'Consulta abierta por error en otro paciente');
```
- Esperado: la consulta 86, que solo tiene una orden pendiente, queda cancelada junto con su orden y sus 3 pruebas.
- Obtenido: `encuentro.estado = 'cancelado'`, 1 orden `cancelada` y 3 pruebas `cancelada`.

```sql
CALL sp_cancelar_encuentro(85, 'Consulta abierta por error en otro paciente');
```
- Esperado: error, porque la consulta 85 ya tiene resultados de laboratorio.
- Obtenido: `P0001` · No se puede cancelar: la consulta ya tiene resultados de laboratorio.

```sql
CALL sp_cancelar_encuentro(86, 'error');
```
- Esperado: error, porque el motivo es demasiado corto.
- Obtenido: `P0001` · Explique el motivo de la cancelación (mínimo 10 caracteres).
