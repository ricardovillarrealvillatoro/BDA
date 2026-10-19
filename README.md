# MedAssist · Copiloto clínico

Aplicación web en Flask + PostgreSQL para el registro de pacientes, médicos y consultas,
con el seguimiento de las recomendaciones del copiloto clínico (Equipo 06).

## Requisitos

- Python 3.10 o superior
- PostgreSQL 14 o superior (`db/triggers.sql` usa `CREATE OR REPLACE TRIGGER`)
- `psql` reciente (17.6, 16.10, 15.14 o 14.19 en adelante): `db/06_datos_prueba.sql` es un volcado de
  `pg_dump` que usa los comandos `\restrict` / `\unrestrict`

## Instalación

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Base de datos

1. Crear el usuario y la base (como superusuario `postgres`):

   ```sql
   CREATE ROLE medassist_app LOGIN PASSWORD 'cambie-esta-clave';
   CREATE DATABASE medassist OWNER medassist_app;
   ```

2. Cargar los scripts **en este orden** (`01_schema.sql` borra todo lo anterior, así que sirve para reiniciar la base):

   ```bash
   for f in 01_schema 06_datos_prueba views procedimientos triggers; do
     psql -h localhost -U medassist_app -d medassist -v ON_ERROR_STOP=1 -f "db/$f.sql" || break
   done
   ```

   | Archivo | Contenido |
   |---|---|
   | `01_schema.sql` | Tablas, restricciones e índices |
   | `06_datos_prueba.sql` | Datos sintéticos: 14 usuarios, 42 pacientes, 12 médicos, 93 consultas |
   | `views.sql` | 9 vistas (`vw_*`), documentadas en [`docs/vistas.md`](docs/vistas.md) |
   | `procedimientos.sql` | 15 procedimientos almacenados (`sp_*`), documentados en [`docs/procedimientos.md`](docs/procedimientos.md) |
   | `triggers.sql` | Auditoría automática de 16 tablas y bitácora inmutable |
   | `consultas.sql` | 12 consultas JOIN y complementarias, cada una con su pregunta, resultado y aplicación (las ejecuta la página *Consultas SQL*), documentadas en [`docs/consultas.md`](docs/consultas.md) |

## Configuración

La conexión se toma de variables de entorno (`app/db.py`); los valores por defecto sirven para una instalación local:

| Variable | Por defecto | Uso |
|---|---|---|
| `DB_HOST` | `localhost` | Servidor de PostgreSQL |
| `DB_NAME` | `medassist` | Base de datos |
| `DB_USER` | `medassist_app` | Usuario |
| `DB_PASSWORD` | *(vacía)* | Contraseña del usuario |
| `SECRET_KEY` | `dev-cambiar-esta-clave` | Firma de la sesión de Flask; cámbiela fuera de desarrollo |

```bash
export DB_PASSWORD='cambie-esta-clave'   # Windows (PowerShell): $env:DB_PASSWORD = '...'
```

## Ejecutar

```bash
python main.py
```

Abrir <http://127.0.0.1:5000>.

### Usuarios de prueba

Todos usan la contraseña `MedAssist2026!`.

| Usuario | Rol | Qué ve |
|---|---|---|
| `admin` | Administrador clínico y médico | Todo; da de alta y baja a médicos y pacientes |
| `helen.rostova` | Médico | Su espacio clínico, consultas, pacientes, médicos, laboratorio e informes |
| `auditor` | Auditor | Consultas (solo lectura), médicos, rendimiento, auditoría y consultas SQL |
| `copiloto` | Sistema | Solo el tablero general |

Los demás médicos (`clara.mercer`, `jorge.salinas`, …) también tienen rol de médico.

## Estructura

```
main.py              App Flask, registro de Blueprints, filtros y páginas de error
app/
  auth.py            Inicio de sesión, permisos por rol (PERMISOS) y token CSRF
  db.py              Conexión a PostgreSQL (psycopg 3)
  panel.py           Panel principal: espacio del médico y tablero general
  pacientes.py       CRUD de pacientes
  medicos.py         CRUD de médicos y especialidades
  consultas.py       CRUD de consultas: diagnósticos, órdenes, recetas y decisiones
  laboratorio.py     Captura de resultados de laboratorio
  reportes.py        Informes médicos imprimibles
  rendimiento.py     Concordancia del copiloto por regla, médico y especialidad
  auditoria.py       Bitácora de auditoría con filtros y exportación a CSV
  consultas_sql.py   Ejecuta en solo lectura las consultas de db/consultas.sql
templates/           Plantillas Jinja2 (una carpeta por módulo)
static/              CSS y JavaScript
db/                  Scripts SQL (ver la tabla de arriba)
```

## Dónde se usa cada objeto de la base

- **Procedimientos almacenados:** todas las altas y cambios de pacientes, médicos y consultas pasan por un `sp_*`
  que valida las reglas de negocio. Por ejemplo, no se puede cancelar una consulta con resultados o decisiones,
  ni dar de baja a un médico con consultas abiertas.
- **Vistas:**
  - `vw_pacientes_ultima_consulta`: lista de pacientes y búsqueda de informes.
  - `vw_historial_consultas_medico`: expediente del paciente y consultas.
  - `vw_pacientes_consultas_pendientes` y `vw_alertas_activas`: panel principal.
  - `vw_resultados_laboratorio`: laboratorio y órdenes de la consulta.
  - `vw_contexto_clinico`: contexto clínico de la consulta.
  - `vw_consultas_por_especialidad` y `vw_indicadores_atencion`: rendimiento.
  - `vw_auditoria_por_usuario`: auditoría.
- **Triggers:** cada alta, cambio o baja hecha desde la app queda en la tabla `auditoria` con el usuario
  y la IP de la sesión, sin el hash de la contraseña. Los registros de auditoría no se pueden modificar ni borrar.
- **Consultas JOIN:** la página *Consultas SQL* (administrador y auditor) lee `db/consultas.sql`, muestra el tipo
  de JOIN de cada consulta y la ejecuta en una transacción de solo lectura.
