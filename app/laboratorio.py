import psycopg
from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import conectar, mensaje_error
from app.auth import login_required

# Mismo prefijo que la ruta /lab que existía en main.py
bp = Blueprint('laboratorio', __name__, url_prefix='/lab')

ESTADO_RESULTADO = {'normal': 'Normal', 'fuera_rango': 'Fuera de rango', 'critico': 'Crítico', 'sin_rango': 'Sin rango'}

@bp.route('/')
@login_required
def inicio():
    q = request.args.get('q', '').strip()
    estado = request.args.get('estado', '')
    pagina = request.args.get("pagina", 1, type=int)
    tam = 15
    offset = (pagina - 1) * tam

    # Resultados interpretados con la vista vw_resultados_laboratorio (db/views.sql)
    sql = "SELECT * FROM vw_resultados_laboratorio WHERE id_resultado IS NOT NULL"
    params = []
    if q:
        sql += " AND (paciente ILIKE %s OR prueba ILIKE %s)"
        params.extend([f"%{q}%", f"%{q}%"])
    if estado:
        sql += " AND estado_resultado = %s"
        params.append(estado)

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM vw_resultados_laboratorio"
                " WHERE estado_detalle IN ('pendiente', 'tomada') AND estado_encuentro = 'abierto'"
                " ORDER BY prioridad = 'urgente' DESC, fecha_orden"
            )
            pendientes = cur.fetchall()

            cur.execute(f"SELECT COUNT(*) FROM ({sql}) AS c_tbl", params)
            total = cur.fetchone()['count']

            sql += " ORDER BY fecha_resultado DESC LIMIT %s OFFSET %s"
            params.extend([tam, offset])
            cur.execute(sql, params)
            resultados = cur.fetchall()

    return render_template('laboratorio/inicio.html', pendientes=pendientes, resultados=resultados,
                           q=q, estado=estado, estados=ESTADO_RESULTADO, total=total, pagina=pagina, tam=tam)

@bp.route('/<int:id_detalle>/capturar', methods=['POST'])
@login_required
def capturar(id_detalle):
    valor_numerico = request.form.get('valor_numerico', '').strip() or None
    valor_texto = request.form.get('valor_texto', '').strip() or None
    if valor_numerico is None and valor_texto is None:
        flash("Capture un valor numérico o cualitativo.", "error")
        return redirect(url_for('laboratorio.inicio'))
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("CALL sp_registrar_resultado_laboratorio(%s, %s::numeric, %s, %s)",
                            (id_detalle, valor_numerico, valor_texto, session['id_usuario']))
        flash("Resultado registrado.", "success")
    except psycopg.Error as e:
        flash(f"Error al registrar el resultado: {mensaje_error(e)}", "error")
    return redirect(url_for('laboratorio.inicio'))
