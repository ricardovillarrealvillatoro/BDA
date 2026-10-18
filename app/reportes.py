from datetime import datetime

from flask import Blueprint, abort, render_template, request
from app.db import conectar
from app.auth import login_required
from app.consultas import (obtener_encuentro, obtener_diagnosticos, obtener_prescripciones, obtener_ordenes,
                           obtener_recomendaciones)

# Mismo prefijo que la ruta /report que existía en main.py
bp = Blueprint('reportes', __name__, url_prefix='/report')

@bp.route('/')
@login_required
def inicio():
    q = request.args.get('q', '').strip()
    id_paciente = request.args.get('paciente', type=int)
    pacientes, paciente, consultas = [], None, []

    with conectar() as conn:
        with conn.cursor() as cur:
            if len(q) >= 2:
                cur.execute("""
                    SELECT * FROM vw_pacientes_ultima_consulta
                    WHERE nombre_completo ILIKE %s OR curp ILIKE %s
                    ORDER BY nombre_completo LIMIT 20
                """, (f"%{q}%", f"%{q}%"))
                pacientes = cur.fetchall()

            if id_paciente:
                cur.execute("SELECT *, EXTRACT(YEAR FROM age(fecha_nacimiento)) AS edad FROM paciente WHERE id_paciente = %s",
                            (id_paciente,))
                paciente = cur.fetchone()
                if paciente:
                    # Historial (vw_historial_consultas_medico) con cuántas recomendaciones tuvo y cuántas se decidieron
                    cur.execute("""
                        SELECT h.*, rc.recomendaciones, rc.decididas
                        FROM vw_historial_consultas_medico h
                        CROSS JOIN LATERAL (
                            SELECT COUNT(r.id_recomendacion) AS recomendaciones, COUNT(dm.id_decision) AS decididas
                            FROM recomendacion r
                            LEFT JOIN decision_medica dm ON r.id_recomendacion = dm.id_recomendacion
                            WHERE r.id_encuentro = h.id_encuentro
                        ) rc
                        WHERE h.id_paciente = %s
                        ORDER BY h.fecha_inicio DESC
                    """, (id_paciente,))
                    consultas = cur.fetchall()

    return render_template('reportes/inicio.html', q=q, pacientes=pacientes, paciente=paciente, consultas=consultas)

@bp.route('/consulta/<int:id_encuentro>')
@login_required
def consulta(id_encuentro):
    with conectar() as conn:
        with conn.cursor() as cur:
            enc = obtener_encuentro(cur, id_encuentro)

            cur.execute("SELECT *, EXTRACT(YEAR FROM age(fecha_nacimiento)) AS edad FROM paciente WHERE id_paciente = %s",
                        (enc['id_paciente'],))
            p = cur.fetchone()

            cur.execute("""
                SELECT m.cedula_profesional, esp.nombre AS especialidad
                FROM medico m
                LEFT JOIN medico_especialidad me ON m.id_medico = me.id_medico AND me.es_principal
                LEFT JOIN especialidad esp ON me.id_especialidad = esp.id_especialidad
                WHERE m.id_medico = %s
            """, (enc['id_medico'],))
            medico = cur.fetchone()
            if medico is None:
                abort(404)
            enc['especialidad'] = medico['especialidad']

            diagnosticos = obtener_diagnosticos(cur, id_encuentro)
            ordenes = obtener_ordenes(cur, id_encuentro)
            prescripciones = obtener_prescripciones(cur, id_encuentro)
            recomendaciones = obtener_recomendaciones(cur, id_encuentro)

    return render_template('reportes/consulta.html', enc=enc, p=p, medico=medico, diagnosticos=diagnosticos,
                           ordenes=ordenes, prescripciones=prescripciones, recomendaciones=recomendaciones,
                           ahora=datetime.now)
