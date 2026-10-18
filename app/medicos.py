from flask import Blueprint, render_template, request, redirect, url_for, flash
from db import conectar
from app.auth import login_required

bp = Blueprint('medicos', __name__, url_prefix='/medicos')

@bp.route('/')
@login_required
def lista():
    q = request.args.get('q', '').strip()
    pagina = int(request.args.get('pagina', 1))
    tam = 15
    offset = (pagina - 1) * tam

    sql = """
        SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS nombre_completo, 
               u.username, m.cedula_profesional, u.activo,
               COUNT(e.id_encuentro) AS consultas,
               COUNT(CASE WHEN e.estado = 'abierto' THEN 1 END) AS abiertas
        FROM medico m
        JOIN usuario u ON m.id_medico = u.id_usuario
        LEFT JOIN encuentro e ON m.id_medico = e.id_medico
        WHERE 1=1
    """
    params = []
    if q:
        sql += " AND (u.nombre ILIKE %s OR u.username ILIKE %s OR m.cedula_profesional ILIKE %s)"
        params.extend([f"%{q}%", f"%{q}%", f"%{q}%"])

    sql += " GROUP BY m.id_medico, u.nombre, u.apellido_paterno, u.username, m.cedula_profesional, u.activo"

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM ({sql}) AS count_tbl", params)
            total = cur.fetchone()['count']

            sql += " LIMIT %s OFFSET %s"
            params.extend([tam, offset])
            cur.execute(sql, params)
            medicos = cur.fetchall()

            cur.execute("SELECT id_especialidad, nombre FROM especialidad")
            especialidades = cur.fetchall()

    return render_template('lista_medico.html', medicos=medicos, q=q, especialidades=especialidades, pagina=pagina, tam=tam, total=total)

@bp.route('/<int:id_medico>')
@login_required
def detalle(id_medico):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS nombre_completo,
                       u.username, u.email, u.activo, m.cedula_profesional,
                       COUNT(e.id_encuentro) AS consultas,
                       COUNT(CASE WHEN e.estado = 'abierto' THEN 1 END) AS abiertas
                FROM medico m
                JOIN usuario u ON m.id_medico = u.id_usuario
                LEFT JOIN encuentro e ON m.id_medico = e.id_medico
                WHERE m.id_medico = %s
                GROUP BY m.id_medico, u.nombre, u.apellido_paterno, u.username, u.email, u.activo, m.cedula_profesional
            """, (id_medico,))
            medico = cur.fetchone()

            cur.execute("SELECT * FROM v_historial_consultas_medico WHERE id_medico = %s LIMIT 30", (id_medico,))
            historial = cur.fetchall()

    return render_template('detalle_medico.html', m=medico, especialidades=[], concordancia=[], historial=historial)
