import re
from datetime import datetime
from pathlib import Path

import psycopg
from flask import Blueprint, abort, flash, render_template
from app.db import conectar, mensaje_error
from app.auth import login_required

bp = Blueprint('consultas_sql', __name__, url_prefix='/consultas-sql')

ARCHIVO_SQL = Path(__file__).resolve().parent.parent / 'db' / 'consultas.sql'
MAX_FILAS = 200

TABLAS_RE = re.compile(r'\b(?:FROM|JOIN)\s+([a-z_]+)', re.IGNORECASE)


def clasificar(sql):
    # Tipo de consulta que se muestra como etiqueta; el orden importa (una CTE también lleva JOINs)
    s = ' '.join(sql.upper().split())
    tablas = [t.lower() for t in TABLAS_RE.findall(sql)]
    if s.startswith('WITH'):
        return 'CTE (WITH)'
    if 'OVER(' in s.replace('OVER (', 'OVER('):
        return 'Función de ventana'
    if re.search(r'(IN|WHERE)\s*\(\s*SELECT', s):
        return 'Subconsulta'
    if 'FULL OUTER JOIN' in s:
        return 'FULL OUTER JOIN'
    if 'CROSS JOIN' in s:
        return 'CROSS JOIN'
    if 'RIGHT JOIN' in s:
        return 'RIGHT JOIN'
    if len(tablas) != len(set(tablas)):
        return 'SELF JOIN'
    if 'LEFT JOIN' in s:
        return 'LEFT JOIN'
    if 'GROUP BY' in s:
        return 'Agregación'
    return 'INNER JOIN'


def cargar_consultas():
    # Cada consulta de db/consultas.sql lleva arriba un comentario "--Título"; se lee en cada
    # petición para que lo que se agregue al archivo aparezca sin reiniciar la app
    consultas, titulo, sql = [], None, []
    for linea in ARCHIVO_SQL.read_text(encoding='utf-8').splitlines():
        texto = linea.strip()
        if not sql and texto.startswith('--'):
            titulo = texto.lstrip('-').strip()
            continue
        if not texto and not sql:
            continue
        sql.append(linea)
        if texto.endswith(';'):
            cuerpo = '\n'.join(sql).strip().rstrip(';')
            consultas.append({
                'id': len(consultas) + 1,
                'titulo': titulo or f'Consulta {len(consultas) + 1}',
                'tipo': clasificar(cuerpo),
                'tablas': sorted(set(t.lower() for t in TABLAS_RE.findall(cuerpo))),
                'sql': cuerpo,
            })
            titulo, sql = None, []
    return consultas


@bp.route('/')
@login_required
def inicio():
    return render_template('consultas_sql/inicio.html', consultas=cargar_consultas())


@bp.route('/<int:id_consulta>')
@login_required
def detalle(id_consulta):
    consultas = cargar_consultas()
    c = next((x for x in consultas if x['id'] == id_consulta), None)
    if c is None:
        abort(404)

    columnas, filas, total = [], [], 0
    try:
        with conectar() as conn:
            # Solo lectura: aunque alguien edite el archivo, la página no puede modificar datos
            conn.read_only = True
            with conn.cursor() as cur:
                cur.execute("SET LOCAL statement_timeout = '5s'")
                cur.execute(c['sql'])
                columnas = [col.name for col in cur.description]
                total = cur.rowcount
                filas = cur.fetchmany(MAX_FILAS)
    except psycopg.Error as e:
        flash(f"Error al ejecutar la consulta: {mensaje_error(e)}", "error")

    return render_template('consultas_sql/detalle.html', c=c, consultas=consultas,
                           columnas=columnas, filas=filas, total=total, ahora=datetime.now)
