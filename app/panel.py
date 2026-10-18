from flask import Blueprint, render_template, request, session
from app.db import conectar
from app.auth import login_required, tiene_rol
from app.consultas import (obtener_encuentro, obtener_diagnosticos, obtener_prescripciones,
                           obtener_recomendaciones, puede_modificar)
from app.rendimiento import CONTEOS

bp = Blueprint('panel', __name__)

@bp.route('/')
@login_required
def inicio():
    # El médico ve su espacio clínico; los demás roles (y el admin con ?vista=general) el tablero general
    if tiene_rol('medico') and request.args.get('vista') != 'general':
        return espacio_medico()
    return tablero_general()


def tablero_general():
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    (SELECT COUNT(*) FROM paciente WHERE activo) AS pacientes_activos,
                    (SELECT COUNT(*) FROM medico m JOIN usuario u ON m.id_medico = u.id_usuario WHERE u.activo) AS medicos_activos,
                    (SELECT COUNT(*) FROM encuentro) AS consultas_totales,
                    (SELECT COUNT(*) FROM encuentro WHERE estado = 'abierto') AS consultas_abiertas,
                    (SELECT COUNT(*) FROM recomendacion) AS recomendaciones,
                    (SELECT COUNT(*) FROM decision_medica) AS decisiones,
                    -- Promedio ponderado por tipo de vw_indicadores_atencion (minutos -> horas)
                    (SELECT ROUND(SUM(total_encuentros * duracion_promedio_minutos) / NULLIF(SUM(total_encuentros), 0) / 60, 1)
                     FROM vw_indicadores_atencion) AS horas_promedio_consulta
            """)
            ind = cur.fetchone()
            cur.execute(f"SELECT {CONTEOS} FROM decision_medica dm")
            ind['pgc_global'] = cur.fetchone()['pgc']

            cur.execute("SELECT * FROM vw_pacientes_consultas_pendientes ORDER BY fecha_inicio")
            pendientes = cur.fetchall()

            cur.execute("SELECT * FROM vw_alertas_activas ORDER BY nivel_prioridad DESC, fecha_hora DESC LIMIT 15")
            alertas = cur.fetchall()

    return render_template('panel/general.html', ind=ind, pendientes=pendientes, alertas=alertas)


def espacio_medico():
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM vw_pacientes_consultas_pendientes WHERE id_medico = %s ORDER BY fecha_inicio DESC, id_encuentro DESC",
                        (session['id_usuario'],))
            mias = cur.fetchall()
            if not mias:
                return render_template('panel/medico.html', enc=None, mias=[])

            # La consulta elegida en la lista (?encuentro=) o la más reciente
            elegida = request.args.get('encuentro', type=int)
            id_encuentro = next((m['id_encuentro'] for m in mias if m['id_encuentro'] == elegida), mias[0]['id_encuentro'])
            enc = obtener_encuentro(cur, id_encuentro)

            # Último resultado de cada prueba del paciente
            cur.execute("""
                SELECT * FROM (
                    SELECT DISTINCT ON (prueba) prueba, valor_numerico, valor_texto, unidad,
                           estado_resultado AS estado, fecha_resultado
                    FROM vw_resultados_laboratorio
                    WHERE id_paciente = %s AND id_resultado IS NOT NULL
                    ORDER BY prueba, fecha_resultado DESC
                ) ultimos ORDER BY fecha_resultado DESC LIMIT 8
            """, (enc['id_paciente'],))
            labs = cur.fetchall()

            cur.execute("SELECT prioridad_asignada FROM vw_alertas_activas WHERE id_encuentro = %s ORDER BY nivel_prioridad DESC LIMIT 1",
                        (id_encuentro,))
            alerta = cur.fetchone()

            cur.execute("SELECT fuente, COUNT(*) AS n FROM vw_contexto_clinico WHERE id_paciente = %s GROUP BY fuente",
                        (enc['id_paciente'],))
            resumen_contexto = {r['fuente']: r['n'] for r in cur.fetchall()}

            diagnosticos = obtener_diagnosticos(cur, id_encuentro)
            prescripciones = obtener_prescripciones(cur, id_encuentro)
            recomendaciones = obtener_recomendaciones(cur, id_encuentro)

    return render_template('panel/medico.html', enc=enc, mias=mias, labs=labs,
                           riesgo=alerta['prioridad_asignada'] if alerta else None,
                           resumen_contexto=resumen_contexto, diagnosticos=diagnosticos, prescripciones=prescripciones,
                           recomendaciones=recomendaciones, pendientes=[r for r in recomendaciones if not r['decision']],
                           puede_modificar=puede_modificar(enc))
