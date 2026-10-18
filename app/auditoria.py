import csv
import io
import json
from datetime import datetime

from flask import Blueprint, Response, render_template, request
from app.db import conectar
from app.auth import login_required

# Mismo prefijo que la ruta /audit que existía en main.py
bp = Blueprint('auditoria', __name__, url_prefix='/audit')

ACCIONES = ('INSERT', 'UPDATE', 'DELETE')


def filtros():
    # Filtros del formulario de auditoria/inicio.html; los usan la tabla y la exportación a CSV
    f = {k: request.args.get(k, '').strip() for k in ('usuario', 'tabla', 'accion', 'desde', 'hasta')}
    sql = """
        SELECT a.*, COALESCE(u.username, '(sin sesión)') AS usuario
        FROM auditoria a LEFT JOIN usuario u ON a.id_usuario = u.id_usuario
        WHERE 1=1
    """
    params = []
    if f['usuario']:
        sql += " AND u.username ILIKE %s"
        params.append(f"%{f['usuario']}%")
    if f['tabla']:
        sql += " AND a.tabla = %s"
        params.append(f['tabla'])
    if f['accion'] in ACCIONES:
        sql += " AND a.accion = %s"
        params.append(f['accion'])
    if f['desde']:
        sql += " AND a.fecha_hora >= %s"
        params.append(f['desde'])
    if f['hasta']:
        sql += " AND a.fecha_hora < %s::date + 1"
        params.append(f['hasta'])
    return f, sql, params


def cambios(a):
    # (campo, antes, después) de cada registro: en UPDATE solo lo que cambió, en INSERT/DELETE la fila completa
    antes = a['valores_anteriores'] or {}
    despues = a['valores_nuevos'] or {}
    if a['accion'] == 'UPDATE':
        return [(k, antes.get(k), v) for k, v in despues.items() if antes.get(k) != v]
    if a['accion'] == 'DELETE':
        return [(k, None, v) for k, v in antes.items()]
    return [(k, None, v) for k, v in despues.items() if v is not None]


@bp.route('/')
@login_required
def inicio():
    f, sql, params = filtros()
    pagina = request.args.get("pagina", 1, type=int)
    tam = 25
    offset = (pagina - 1) * tam

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM ({sql}) AS c_tbl", params)
            total = cur.fetchone()['count']

            cur.execute(sql + " ORDER BY a.fecha_hora DESC, a.id_auditoria DESC LIMIT %s OFFSET %s", params + [tam, offset])
            filas = cur.fetchall()
            for a in filas:
                a['cambios'] = cambios(a)

            cur.execute("SELECT * FROM vw_auditoria_por_usuario ORDER BY ultima_accion DESC, usuario, tabla")
            resumen = cur.fetchall()

            cur.execute("SELECT DISTINCT tabla FROM auditoria ORDER BY tabla")
            tablas = [r['tabla'] for r in cur.fetchall()]

    return render_template('auditoria/inicio.html', filas=filas, resumen=resumen, tablas=tablas,
                           total=total, pagina=pagina, tam=tam, **f)


@bp.route('/exportar')
@login_required
def exportar():
    _, sql, params = filtros()
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(sql + " ORDER BY a.fecha_hora DESC, a.id_auditoria DESC", params)
            filas = cur.fetchall()

    salida = io.StringIO()
    # BOM para que Excel abra bien los acentos
    salida.write('﻿')
    w = csv.writer(salida)
    w.writerow(['fecha_hora', 'usuario', 'tabla', 'id_registro', 'accion', 'valores_anteriores', 'valores_nuevos', 'ip'])
    for a in filas:
        w.writerow([a['fecha_hora'].isoformat(sep=' ', timespec='seconds'), a['usuario'], a['tabla'], a['id_registro'],
                    a['accion'],
                    json.dumps(a['valores_anteriores'], ensure_ascii=False) if a['valores_anteriores'] else '',
                    json.dumps(a['valores_nuevos'], ensure_ascii=False) if a['valores_nuevos'] else '',
                    a['ip'] or ''])
    nombre = f"auditoria_{datetime.now():%Y%m%d_%H%M}.csv"
    return Response(salida.getvalue(), mimetype='text/csv',
                    headers={'Content-Disposition': f'attachment; filename="{nombre}"'})
