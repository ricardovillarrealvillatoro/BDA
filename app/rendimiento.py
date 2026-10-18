from flask import Blueprint, render_template
from app.db import conectar
from app.auth import login_required

# Mismo prefijo que la ruta /performance que existía en main.py
bp = Blueprint('rendimiento', __name__, url_prefix='/performance')

# Concordancia médico–copiloto: PGC = (aceptadas + ½ modificadas) / decididas
CONTEOS = """
    COUNT(*) AS decididas,
    COUNT(*) FILTER (WHERE dm.tipo = 'aceptada') AS aceptadas,
    COUNT(*) FILTER (WHERE dm.tipo = 'modificada') AS modificadas,
    COUNT(*) FILTER (WHERE dm.tipo = 'rechazada') AS rechazadas,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE dm.tipo = 'aceptada')
                   + 0.5 * COUNT(*) FILTER (WHERE dm.tipo = 'modificada')) / NULLIF(COUNT(*), 0), 1) AS pgc
"""

@bp.route('/')
@login_required
def inicio():
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT {CONTEOS} FROM decision_medica dm")
            totales = cur.fetchone()

            cur.execute("SELECT COUNT(*) FROM recomendacion")
            ind = {'recomendaciones': cur.fetchone()['count'], 'decisiones': totales['decididas'],
                   'pgc_global': totales['pgc']}

            cur.execute(f"""
                SELECT rc.codigo AS regla, rc.nombre AS regla_nombre, vr.numero_version,
                       vr.estado AS estado_version, {CONTEOS}
                FROM decision_medica dm
                JOIN recomendacion r ON dm.id_recomendacion = r.id_recomendacion
                JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla
                JOIN regla_clinica rc ON vr.id_regla = rc.id_regla
                GROUP BY rc.codigo, rc.nombre, vr.numero_version, vr.estado
                ORDER BY pgc, rc.codigo, vr.numero_version
            """)
            por_regla = cur.fetchall()

            cur.execute(f"""
                SELECT u.nombre || ' ' || u.apellido_paterno AS medico, {CONTEOS}
                FROM decision_medica dm
                JOIN usuario u ON dm.id_medico = u.id_usuario
                GROUP BY u.id_usuario, u.nombre, u.apellido_paterno
                ORDER BY pgc DESC
            """)
            por_medico = cur.fetchall()

            cur.execute("SELECT * FROM vw_consultas_por_especialidad ORDER BY total_atenciones DESC")
            especialidades = cur.fetchall()

            cur.execute("SELECT * FROM vw_indicadores_atencion ORDER BY total_encuentros DESC")
            indicadores = cur.fetchall()

    return render_template('rendimiento/inicio.html', ind=ind, totales=totales, por_regla=por_regla,
                           por_medico=por_medico, especialidades=especialidades, indicadores=indicadores)
