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
# Notas que se reconocen debajo del título de cada consulta en db/consultas.sql
ETIQUETAS_NOTA = ('Tipo', 'Pregunta', 'Resultado', 'Aplicación')

TABLAS_RE = re.compile(r'\b(?:FROM|JOIN)\s+([a-z_][a-z0-9_]*)', re.IGNORECASE)


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
    # Cada consulta de db/consultas.sql lleva arriba un comentario "--Título" y debajo sus notas
    # ("-- Pregunta: ...", "-- Resultado: ...", "-- Aplicación: ..."; "-- Tipo: ..." reemplaza la etiqueta de clasificar).
    # Un comentario seguido de una línea en blanco es un encabezado de sección y no se usa.
    # Se lee en cada petición para que lo que se agregue al archivo aparezca sin reiniciar la app
    consultas, titulo, notas, etiqueta, sql = [], None, {}, None, []
    for linea in ARCHIVO_SQL.read_text(encoding='utf-8').splitlines():
        texto = linea.strip()
        if not sql and texto.startswith('--'):
            comentario = texto.lstrip('-').strip()
            nombre, separador, resto = comentario.partition(':')
            if titulo is None:
                titulo = comentario
            elif separador and nombre in ETIQUETAS_NOTA:
                etiqueta = nombre
                notas[etiqueta] = resto.strip()
            elif etiqueta:
                # Continuación de la nota anterior
                notas[etiqueta] += ' ' + comentario
            continue
        if not texto and not sql:
            titulo, notas, etiqueta = None, {}, None
            continue
        sql.append(linea)
        if texto.endswith(';'):
            cuerpo = '\n'.join(sql).strip().rstrip(';')
            consultas.append({
                'id': len(consultas) + 1,
                'titulo': titulo or f'Consulta {len(consultas) + 1}',
                'tipo': notas.pop('Tipo', None) or clasificar(cuerpo),
                'notas': notas,
                'tablas': sorted(set(t.lower() for t in TABLAS_RE.findall(cuerpo))),
                'sql': cuerpo,
            })
            titulo, notas, etiqueta, sql = None, {}, None, []
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
