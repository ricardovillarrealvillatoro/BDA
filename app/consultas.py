import psycopg
from flask import Blueprint, abort, render_template, request, redirect, url_for, flash, session
from app.db import conectar, mensaje_error
from app.auth import login_required, tiene_rol

bp = Blueprint('consultas', __name__, url_prefix='/consultas')

# Mismos valores que permite el CHECK de encuentro.tipo en db/01_schema.sql
TIPO_CONSULTA = {'consulta': 'Consulta médica', 'urgencia': 'Urgencia', 'hospitalizacion': 'Hospitalización'}
ESTADO_CONSULTA = {'abierto': 'Abierta', 'cerrado': 'Cerrada', 'cancelado': 'Cancelada'}
ESTADO_RESULTADO = {'normal': 'Normal', 'fuera_rango': 'Fuera de rango', 'critico': 'Crítico', 'sin_rango': 'Sin rango'}

@bp.route('/')
@login_required
def lista():
    q = request.args.get('q', '').strip()
    estado = request.args.get('estado', '')
    pagina = request.args.get("pagina", 1, type=int)
    tam = 15
    offset = (pagina - 1) * tam

    sql = "SELECT * FROM vw_historial_consultas_medico WHERE 1=1"
    params = []

    if q:
        sql += " AND (paciente ILIKE %s OR curp ILIKE %s OR motivo ILIKE %s)"
        params.extend([f"%{q}%", f"%{q}%", f"%{q}%"])

    if estado:
        sql += " AND estado = %s"
        params.append(estado)

    # Filtros del formulario de consultas/lista.html: "mias" (médicos) o "medico" (los demás) y rango de fechas
    mias = request.args.get('mias', '1' if 'medico' in session.get('roles', []) else '')
    medico = request.args.get('medico', '')
    desde = request.args.get('desde', '')
    hasta = request.args.get('hasta', '')
    if 'medico' in session.get('roles', []) and mias == '1':
        sql += " AND id_medico = %s"
        params.append(session['id_usuario'])
    elif medico:
        sql += " AND id_medico = %s"
        params.append(medico)
    if desde:
        sql += " AND fecha_inicio >= %s"
        params.append(desde)
    if hasta:
        sql += " AND fecha_inicio < %s::date + 1"
        params.append(hasta)

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM ({sql}) AS c_tbl", params)
            total = cur.fetchone()['count']

            sql += " ORDER BY fecha_inicio DESC LIMIT %s OFFSET %s"
            params.extend([tam, offset])
            cur.execute(sql, params)
            consultas = cur.fetchall()

            cur.execute("SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS nombre FROM medico m JOIN usuario u ON m.id_medico = u.id_usuario")
            medicos = cur.fetchall()

    return render_template(
        'consultas/lista.html', consultas=consultas, q=q, estado=estado, medicos=medicos,
        mias=mias, medico=medico, desde=desde, hasta=hasta,
        total=total, pagina=pagina, tam=tam, TIPO_CONSULTA=TIPO_CONSULTA, ESTADO_CONSULTA=ESTADO_CONSULTA
    )

def validar_consulta(form, nueva=False, es_admin=False):
    # Mismas reglas que consultas/form.html y los CHECK de encuentro en db/01_schema.sql
    errores = {}
    if nueva and not (form.get('id_paciente') or '').isdigit():
        errores['id_paciente'] = 'Seleccione un paciente.'
    if nueva and es_admin and not (form.get('id_medico') or '').isdigit():
        errores['id_medico'] = 'Seleccione el médico tratante.'
    if form.get('tipo') not in TIPO_CONSULTA:
        errores['tipo'] = 'Seleccione el tipo de atención.'
    motivo = (form.get('motivo') or '').strip()
    if not 5 <= len(motivo) <= 1000:
        errores['motivo'] = 'Describa el motivo (mínimo 5 caracteres).'
    if len(form.get('notas') or '') > 4000:
        errores['notas'] = 'Las notas admiten hasta 4000 caracteres.'
    return errores

@bp.route('/nueva', methods=['GET', 'POST'])
@login_required
def nueva():
    # El administrador elige al médico tratante; un médico abre la consulta a su nombre
    es_admin = tiene_rol('admin_clinico')
    errores = {}
    if request.method == 'POST':
        errores = validar_consulta(request.form, nueva=True, es_admin=es_admin)
        if not errores:
            id_medico = int(request.form['id_medico']) if es_admin else session['id_usuario']
            try:
                with conectar() as conn:
                    with conn.cursor() as cur:
                        cur.execute("CALL sp_abrir_encuentro(%s, %s, %s, %s, NULL)", (
                            int(request.form['id_paciente']), id_medico, request.form['tipo'],
                            request.form['motivo'].strip()))
                        id_encuentro = cur.fetchone()['p_id_encuentro']
                flash("Consulta abierta exitosamente.", "success")
                return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro))
            except psycopg.Error as e:
                flash(f"Error al abrir la consulta: {mensaje_error(e)}", "error")
        f = request.form
    else:
        # pacientes/detalle.html enlaza aquí con ?paciente=<id> para dejarlo seleccionado
        f = {'id_paciente': request.args.get('paciente', ''), 'tipo': 'consulta'}

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id_paciente, nombre || ' ' || apellido_paterno AS nombre, curp FROM paciente WHERE activo ORDER BY apellido_paterno, nombre")
            pacientes = cur.fetchall()
            cur.execute("SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS nombre FROM medico m JOIN usuario u ON m.id_medico = u.id_usuario WHERE u.activo ORDER BY u.apellido_paterno, u.nombre")
            medicos = cur.fetchall()

    return render_template('consultas/form.html', modo='nueva', enc=None, pacientes=pacientes, medicos=medicos,
                           tipos=TIPO_CONSULTA, f=f, errores=errores, es_admin=es_admin), 400 if errores else 200

def obtener_encuentro(cur, id_encuentro):
    cur.execute("""
        SELECT e.*, p.nombre || ' ' || p.apellido_paterno AS paciente, p.curp, p.sexo,
               EXTRACT(YEAR FROM age(p.fecha_nacimiento)) AS edad,
               u.nombre || ' ' || u.apellido_paterno AS medico
        FROM encuentro e
        JOIN paciente p ON e.id_paciente = p.id_paciente
        JOIN usuario u ON e.id_medico = u.id_usuario
        WHERE e.id_encuentro = %s
    """, (id_encuentro,))
    enc = cur.fetchone()
    if not enc:
        abort(404)
    return enc


def puede_modificar(enc):
    # El médico tratante o un administrador clínico; el auditor solo consulta
    return tiene_rol('admin_clinico') or (tiene_rol('medico') and enc['id_medico'] == session['id_usuario'])


def validar_modificable(cur, id_encuentro):
    # Para los POST: la consulta debe estar abierta y el usuario debe poder modificarla
    enc = obtener_encuentro(cur, id_encuentro)
    if not puede_modificar(enc):
        abort(403)
    if enc['estado'] != 'abierto':
        flash("La consulta ya no está abierta.", "error")
        return None
    return enc


# Consultas que comparten el detalle de la consulta, el panel del médico (app/panel.py) y el informe (app/reportes.py)
def obtener_diagnosticos(cur, id_encuentro):
    cur.execute("SELECT d.*, c.descripcion FROM diagnostico d JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10 WHERE d.id_encuentro = %s ORDER BY d.tipo, d.fecha", (id_encuentro,))
    return cur.fetchall()


def obtener_prescripciones(cur, id_encuentro):
    cur.execute("""
        SELECT pr.*, trim_scale(pr.dosis)::text AS dosis_txt, m.nombre_comercial, m.presentacion,
               u.codigo_ucum, v.nombre AS via
        FROM prescripcion pr
        JOIN medicamento m ON pr.id_medicamento = m.id_medicamento
        JOIN unidad u ON pr.id_unidad_dosis = u.id_unidad
        JOIN via_administracion v ON pr.id_via = v.id_via
        WHERE pr.id_encuentro = %s ORDER BY pr.fecha_inicio DESC
    """, (id_encuentro,))
    return cur.fetchall()


def obtener_ordenes(cur, id_encuentro):
    # Órdenes con su resultado ya interpretado (vista vw_resultados_laboratorio de db/views.sql)
    cur.execute("SELECT * FROM vw_resultados_laboratorio WHERE id_encuentro = %s ORDER BY fecha_orden DESC, id_detalle", (id_encuentro,))
    return cur.fetchall()


def obtener_recomendaciones(cur, id_encuentro):
    # Recomendaciones del copiloto con su regla, protocolo, decisión y la evidencia que usó cada una
    cur.execute("""
        SELECT r.id_recomendacion, r.prioridad_asignada, r.texto_generado, r.fecha_hora,
               rc.codigo AS regla, rc.nombre AS regla_nombre, vr.numero_version, vr.tipo_accion,
               pa.nombre AS farmaco_objetivo, pt.codigo AS protocolo, vp.version AS version_protocolo,
               dm.tipo AS decision, dm.justificacion, dm.accion_final, dm.fecha_hora AS fecha_decision,
               um.nombre || ' ' || um.apellido_paterno AS medico_decide
        FROM recomendacion r
        JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla
        JOIN regla_clinica rc ON vr.id_regla = rc.id_regla
        JOIN version_protocolo vp ON vr.id_version_protocolo = vp.id_version_protocolo
        JOIN protocolo pt ON vp.id_protocolo = pt.id_protocolo
        LEFT JOIN principio_activo pa ON vr.id_pa_objetivo = pa.id_principio_activo
        LEFT JOIN decision_medica dm ON r.id_recomendacion = dm.id_recomendacion
        LEFT JOIN usuario um ON dm.id_medico = um.id_usuario
        WHERE r.id_encuentro = %s ORDER BY r.fecha_hora DESC
    """, (id_encuentro,))
    recomendaciones = cur.fetchall()

    cur.execute("""
        SELECT ev.id_recomendacion, vc.nombre AS variable, op.simbolo AS operador,
               COALESCE(trim_scale(cr.valor_numerico)::text, cr.valor_codigo) AS umbral,
               uu.codigo_ucum AS unidad_umbral, g.operador_logico, g.min_cumplidas, g.orden AS orden_grupo,
               ev.valor_observado, ue.codigo_ucum AS unidad, vc.fuente AS origen, ev.cumplida
        FROM evidencia ev
        JOIN recomendacion r ON ev.id_recomendacion = r.id_recomendacion
        JOIN condicion_regla cr ON ev.id_condicion = cr.id_condicion
        JOIN grupo_condicion g ON cr.id_grupo = g.id_grupo
        JOIN variable_clinica vc ON cr.id_variable = vc.id_variable
        JOIN operador op ON cr.id_operador = op.id_operador
        LEFT JOIN unidad uu ON cr.id_unidad = uu.id_unidad
        LEFT JOIN unidad ue ON ev.id_unidad = ue.id_unidad
        WHERE r.id_encuentro = %s ORDER BY ev.id_recomendacion, g.orden, cr.orden
    """, (id_encuentro,))
    evidencia = cur.fetchall()
    for rec in recomendaciones:
        rec['evidencia'] = [e for e in evidencia if e['id_recomendacion'] == rec['id_recomendacion']]
    return recomendaciones


@bp.route('/<int:id_encuentro>')
@login_required
def detalle(id_encuentro):
    with conectar() as conn:
        with conn.cursor() as cur:
            enc = obtener_encuentro(cur, id_encuentro)
            diagnosticos = obtener_diagnosticos(cur, id_encuentro)
            prescripciones = obtener_prescripciones(cur, id_encuentro)
            ordenes = obtener_ordenes(cur, id_encuentro)
            recomendaciones = obtener_recomendaciones(cur, id_encuentro)

            cur.execute("SELECT * FROM vw_contexto_clinico WHERE id_paciente = %s ORDER BY fecha DESC NULLS LAST, fuente", (enc['id_paciente'],))
            contexto = cur.fetchall()

            cur.execute("SELECT codigo_cie10, descripcion FROM catalogo_cie10 ORDER BY codigo_cie10")
            cie10 = cur.fetchall()
            cur.execute("SELECT id_medicamento, nombre_comercial || ' · ' || presentacion AS nombre FROM medicamento ORDER BY nombre_comercial")
            medicamentos = cur.fetchall()
            cur.execute("SELECT id_unidad, codigo_ucum FROM unidad ORDER BY codigo_ucum")
            unidades = cur.fetchall()
            cur.execute("SELECT id_via, nombre FROM via_administracion ORDER BY id_via")
            vias = cur.fetchall()
            cur.execute("SELECT id_prueba, nombre, tipo FROM prueba ORDER BY tipo, nombre")
            pruebas = cur.fetchall()

    return render_template('consultas/detalle.html', enc=enc, diagnosticos=diagnosticos, cie10=cie10,
                           prescripciones=prescripciones, ordenes=ordenes, recomendaciones=recomendaciones, contexto=contexto,
                           medicamentos=medicamentos, unidades=unidades, vias=vias, pruebas=pruebas,
                           puede_modificar=puede_modificar(enc), ESTADO_CONSULTA=ESTADO_CONSULTA,
                           TIPO_CONSULTA=TIPO_CONSULTA, ESTADO_RESULTADO=ESTADO_RESULTADO)

@bp.route('/<int:id_encuentro>/diagnostico', methods=['POST'])
@login_required
def agregar_diagnostico(id_encuentro):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                if validar_modificable(cur, id_encuentro):
                    cur.execute("CALL sp_registrar_diagnostico(%s, %s, %s, %s)", (
                        id_encuentro, request.form.get('codigo_cie10'),
                        request.form.get('tipo'), request.form.get('estado')))
                    flash("Diagnóstico agregado.", "success")
    except psycopg.Error as e:
        flash(f"Error al agregar el diagnóstico: {mensaje_error(e)}", "error")
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro) + '#diagnosticos')

@bp.route('/<int:id_encuentro>/prescribir', methods=['POST'])
@login_required
def prescribir(id_encuentro):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                if validar_modificable(cur, id_encuentro):
                    cur.execute(
                        "CALL sp_prescribir_medicamento(%s, %s, %s, %s::numeric, %s, %s, %s::smallint, %s)", (
                            id_encuentro, int(request.form['id_medicamento']), session['id_usuario'],
                            request.form['dosis'], int(request.form['id_unidad']), int(request.form['id_via']),
                            int(request.form['frecuencia_horas']), request.form.get('indicacion', '').strip() or None))
                    flash("Prescripción registrada.", "success")
    except (psycopg.Error, KeyError, ValueError) as e:
        flash(f"Error al prescribir: {mensaje_error(e)}", "error")
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro) + '#prescripciones')

@bp.route('/<int:id_encuentro>/orden', methods=['POST'])
@login_required
def crear_orden(id_encuentro):
    pruebas = request.form.getlist('pruebas', type=int)
    if not pruebas:
        flash("Seleccione al menos una prueba.", "error")
        return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro) + '#ordenes')
    try:
        # La orden y sus pruebas se guardan en la misma transacción
        with conectar() as conn:
            with conn.cursor() as cur:
                enc = validar_modificable(cur, id_encuentro)
                if enc:
                    id_medico = session['id_usuario'] if tiene_rol('medico') else enc['id_medico']
                    cur.execute("CALL sp_generar_orden_medica(%s, %s, %s, NULL)",
                                (id_encuentro, id_medico, request.form.get('prioridad', 'rutina')))
                    id_orden = cur.fetchone()['p_id_orden']
                    cur.executemany("INSERT INTO detalle_orden (id_orden, id_prueba) VALUES (%s, %s)",
                                    [(id_orden, p) for p in pruebas])
                    flash(f"Orden #{id_orden} creada con {len(pruebas)} prueba(s).", "success")
    except psycopg.Error as e:
        flash(f"Error al crear la orden: {mensaje_error(e)}", "error")
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro) + '#ordenes')

@bp.route('/recomendacion/<int:id_recomendacion>/decidir', methods=['POST'])
@login_required
def decidir(id_recomendacion):
    tipo = request.form.get('tipo')
    justificacion = request.form.get('justificacion', '').strip()
    accion_final = request.form.get('accion_final', '').strip() or None
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id_encuentro FROM recomendacion WHERE id_recomendacion = %s", (id_recomendacion,))
            rec = cur.fetchone()
    if not rec:
        abort(404)
    id_encuentro = rec['id_encuentro']

    if tipo == 'modificada' and not accion_final:
        flash("Describa la acción final que tomó en lugar de la sugerencia.", "error")
    else:
        try:
            with conectar() as conn:
                with conn.cursor() as cur:
                    if validar_modificable(cur, id_encuentro):
                        cur.execute("CALL sp_registrar_decision_medica(%s, %s, %s, %s, %s)",
                                    (id_recomendacion, session['id_usuario'], tipo, justificacion, accion_final))
                        flash("Decisión registrada.", "success")
        except psycopg.Error as e:
            flash(f"Error al registrar la decisión: {mensaje_error(e)}", "error")

    if request.form.get('volver') == 'panel':
        return redirect(url_for('panel.inicio', encuentro=id_encuentro))
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro) + f'#rec-{id_recomendacion}')

@bp.route('/<int:id_encuentro>/cerrar', methods=['POST'])
@login_required
def cerrar(id_encuentro):
    # El botón de cerrar no manda notas; con NULL el SP conserva las que ya tenía
    notas = request.form.get('notas')
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                if validar_modificable(cur, id_encuentro):
                    cur.execute("CALL sp_cerrar_encuentro(%s, %s)", (id_encuentro, notas))
                    flash("Consulta cerrada.", "success")
    except psycopg.Error as e:
        flash(f"Error al cerrar: {mensaje_error(e)}", "error")
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro))

@bp.route('/<int:id_encuentro>/editar', methods=['GET', 'POST'])
@login_required
def editar(id_encuentro):
    with conectar() as conn:
        with conn.cursor() as cur:
            enc = validar_modificable(cur, id_encuentro)
    if not enc:
        return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro))

    errores = {}
    if request.method == 'POST':
        errores = validar_consulta(request.form)
        if not errores:
            try:
                with conectar() as conn:
                    with conn.cursor() as cur:
                        cur.execute("CALL sp_actualizar_encuentro(%s, %s, %s, %s)", (
                            id_encuentro, request.form['tipo'], request.form['motivo'].strip(),
                            (request.form.get('notas') or '').strip() or None))
                flash("Consulta actualizada.", "success")
                # panel/medico.html también guarda notas con este formulario
                if request.form.get('volver') == 'panel':
                    return redirect(url_for('panel.inicio', encuentro=id_encuentro))
                return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro))
            except psycopg.Error as e:
                flash(f"Error al actualizar la consulta: {mensaje_error(e)}", "error")
        f = request.form
    else:
        f = enc

    return render_template('consultas/form.html', modo='editar', enc=enc, tipos=TIPO_CONSULTA,
                           f=f, errores=errores), 400 if errores else 200

@bp.route('/<int:id_encuentro>/cancelar', methods=['POST'])
@login_required
def cancelar(id_encuentro):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                if validar_modificable(cur, id_encuentro):
                    cur.execute("CALL sp_cancelar_encuentro(%s, %s)", (id_encuentro, request.form.get('motivo', '')))
                    flash("Consulta cancelada. Queda en el historial como cancelada.", "warning")
    except psycopg.Error as e:
        flash(mensaje_error(e), "error")
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro))
