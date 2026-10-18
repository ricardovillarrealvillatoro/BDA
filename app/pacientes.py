import re
from datetime import date

import psycopg
from flask import Blueprint, abort, render_template, request, redirect, url_for, flash
from app.db import conectar, mensaje_error
from app.auth import login_required, tiene_rol

bp = Blueprint('pacientes', __name__, url_prefix='/pacientes')

EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
TELEFONO_RE = re.compile(r'^[0-9 +()\-]{7,20}$')
# Mismo patrón que ck_paciente_curp en db/01_schema.sql
CURP_RE = re.compile(r'^[A-Z]{4}[0-9]{6}[HMX][A-Z]{5}[A-Z0-9][0-9]$')


def validar_paciente(form, nuevo=False):
    # La tabla paciente no valida correo ni teléfono, así que se revisan aquí (mismas reglas que pacientes/form.html).
    # Al registrar también se revisan CURP, sexo y fecha para no mostrar los errores de PostgreSQL en inglés
    errores = {}
    for campo, mensaje in [('nombre', 'Escriba el nombre.'), ('apellido_paterno', 'Escriba el apellido paterno.')]:
        if not (form.get(campo) or '').strip():
            errores[campo] = mensaje
    email = (form.get('email') or '').strip()
    if email and not EMAIL_RE.match(email):
        errores['email'] = 'Escriba un correo válido.'
    telefono = (form.get('telefono') or '').strip()
    if telefono and not TELEFONO_RE.match(telefono):
        errores['telefono'] = 'Solo dígitos, espacios, +, ( ) y guiones.'
    if nuevo:
        if not CURP_RE.match((form.get('curp') or '').strip().upper()):
            errores['curp'] = 'La CURP debe tener el formato oficial de 18 caracteres.'
        if form.get('sexo') not in ('F', 'M', 'I'):
            errores['sexo'] = 'Seleccione el sexo.'
        try:
            if date.fromisoformat(form.get('fecha_nacimiento') or '') > date.today():
                errores['fecha_nacimiento'] = 'La fecha de nacimiento no puede ser futura.'
        except ValueError:
            errores['fecha_nacimiento'] = 'Escriba una fecha de nacimiento válida.'
    return errores

@bp.route('/')
@login_required
def lista():
    q = request.args.get('q', '').strip()
    estado = request.args.get('estado', 'activos')
    pagina = request.args.get("pagina", 1, type=int)
    tam = 15
    offset = (pagina - 1) * tam

    sql = "SELECT * FROM vw_pacientes_ultima_consulta WHERE 1=1"
    params = []

    if q:
        sql += " AND (nombre_completo ILIKE %s OR curp ILIKE %s)"
        params.extend([f"%{q}%", f"%{q}%"])

    if estado == 'activos':
        sql += " AND activo = TRUE"
    elif estado == 'sin_consultas':
        sql += " AND activo = TRUE AND total_consultas = 0"
    elif estado == 'baja':
        sql += " AND activo = FALSE"

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM ({sql}) AS count_tbl", params)
            total = cur.fetchone()['count']

            sql += " ORDER BY id_paciente DESC LIMIT %s OFFSET %s"
            params.extend([tam, offset])
            cur.execute(sql, params)
            pacientes = cur.fetchall()

    return render_template('pacientes/lista.html', pacientes=pacientes, q=q, estado=estado, pagina=pagina, tam=tam, total=total)

@bp.route('/<int:id_paciente>')
@login_required
def detalle(id_paciente):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT *, EXTRACT(YEAR FROM age(fecha_nacimiento)) AS edad FROM paciente WHERE id_paciente = %s", (id_paciente,))
            paciente = cur.fetchone()
            if not paciente:
                flash("Paciente no encontrado", "error")
                return redirect(url_for('pacientes.lista'))

            cur.execute("SELECT * FROM vw_historial_consultas_medico WHERE id_paciente = %s ORDER BY fecha_inicio DESC", (id_paciente,))
            consultas = cur.fetchall()

            # La alergia es a un principio activo del catálogo o a otra sustancia escrita a mano (ck_alergia_origen)
            cur.execute("""
                SELECT a.*, COALESCE(pa.nombre, a.sustancia_otra) AS sustancia
                FROM alergia a
                LEFT JOIN principio_activo pa ON a.id_principio_activo = pa.id_principio_activo
                WHERE a.id_paciente = %s
                ORDER BY a.fecha_registro DESC
            """, (id_paciente,))
            alergias = cur.fetchall()

            cur.execute("""
                SELECT ta.nombre AS tipo, an.codigo_cie10, COALESCE(an.descripcion, c.descripcion) AS descripcion,
                       an.parentesco, an.estado
                FROM antecedente an
                JOIN tipo_antecedente ta ON an.id_tipo_antecedente = ta.id_tipo_antecedente
                LEFT JOIN catalogo_cie10 c ON an.codigo_cie10 = c.codigo_cie10
                WHERE an.id_paciente = %s
                ORDER BY an.estado, an.fecha_inicio DESC NULLS LAST
            """, (id_paciente,))
            antecedentes = cur.fetchall()

            # Medicación vigente: mismo criterio que la fuente 'medicamento' de vw_contexto_clinico
            cur.execute("""
                SELECT m.nombre_comercial, trim_scale(pr.dosis)::text AS dosis_txt, u.codigo_ucum,
                       pr.frecuencia_horas, pr.fecha_inicio, pr.fecha_fin
                FROM prescripcion pr
                JOIN encuentro e ON pr.id_encuentro = e.id_encuentro
                JOIN medicamento m ON pr.id_medicamento = m.id_medicamento
                JOIN unidad u ON pr.id_unidad_dosis = u.id_unidad
                WHERE e.id_paciente = %s AND (pr.fecha_fin IS NULL OR pr.fecha_fin >= CURRENT_DATE)
                ORDER BY pr.fecha_inicio DESC
            """, (id_paciente,))
            medicacion = cur.fetchall()

    return render_template('pacientes/detalle.html', p=paciente, consultas=consultas, alergias=alergias,
                           antecedentes=antecedentes, medicacion=medicacion)

@bp.route('/nuevo', methods=['GET', 'POST'])
@login_required
def nuevo():
    errores = {}
    if request.method == 'POST':
        curp = request.form.get('curp', '').upper().strip()
        nombre = request.form.get('nombre', '').strip()
        apellido_paterno = request.form.get('apellido_paterno', '').strip()
        apellido_materno = request.form.get('apellido_materno', '').strip() or None
        fecha_nacimiento = request.form.get('fecha_nacimiento')
        sexo = request.form.get('sexo')
        telefono = request.form.get('telefono', '').strip() or None
        email = request.form.get('email', '').strip() or None
        direccion = request.form.get('direccion', '').strip() or None

        errores = validar_paciente(request.form, nuevo=True)
        if not errores:
            try:
                with conectar() as conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            "CALL sp_registrar_paciente(%s, %s, %s, %s, %s, %s, %s, %s, %s, NULL)",
                            (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, telefono, email, direccion)
                        )
                        id_paciente = cur.fetchone()['p_id_paciente']
                flash("Paciente registrado correctamente.", "success")
                return redirect(url_for('pacientes.detalle', id_paciente=id_paciente))
            except psycopg.Error as e:
                # El SP marca la CURP repetida y la fecha futura con USING COLUMN; ese error va junto al campo
                campo = getattr(e.diag, 'column_name', None)
                if campo in ('curp', 'fecha_nacimiento'):
                    errores[campo] = mensaje_error(e)
                else:
                    flash(f"Error al registrar: {mensaje_error(e)}", "error")

    return render_template('pacientes/form.html', modo='nuevo', paciente=None, f=request.form,
                           errores=errores), 400 if errores else 200

@bp.route('/<int:id_paciente>/editar', methods=['GET', 'POST'])
@login_required
def editar(id_paciente):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM paciente WHERE id_paciente = %s", (id_paciente,))
            paciente = cur.fetchone()
    if not paciente:
        abort(404)

    if request.method == 'POST':
        nombre = request.form.get('nombre')
        apellido_paterno = request.form.get('apellido_paterno')
        apellido_materno = request.form.get('apellido_materno') or None
        telefono = request.form.get('telefono') or None
        email = request.form.get('email') or None
        direccion = request.form.get('direccion') or None

        errores = validar_paciente(request.form)
        if errores:
            return render_template('pacientes/form.html', modo='editar', paciente=paciente, f=request.form, errores=errores), 400

        try:
            with conectar() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE paciente
                        SET nombre=%s, apellido_paterno=%s, apellido_materno=%s, telefono=%s, email=%s, direccion=%s
                        WHERE id_paciente=%s
                    """, (nombre, apellido_paterno, apellido_materno, telefono, email, direccion, id_paciente))
            flash("Datos actualizados correctamente.", "success")
            return redirect(url_for('pacientes.detalle', id_paciente=id_paciente))
        except psycopg.Error as e:
            # La base rechaza datos inválidos (campos demasiado largos, etc.); se vuelve al formulario
            flash(f"Error al actualizar: {mensaje_error(e)}", "error")
            return render_template('pacientes/form.html', modo='editar', paciente=paciente, f=request.form, errores={})

    return render_template('pacientes/form.html', modo='editar', paciente=paciente, f=paciente, errores={})

@bp.route('/<int:id_paciente>/baja', methods=['POST'])
@login_required
def baja(id_paciente):
    # Solo el administrador clínico puede dar de baja (mismo criterio que el botón en pacientes/detalle.html)
    if not tiene_rol('admin_clinico'):
        abort(403)
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("CALL sp_desactivar_paciente(%s)", (id_paciente,))
        flash("Paciente dado de baja.", "warning")
    except psycopg.Error as e:
        flash(mensaje_error(e), "error")
    return redirect(url_for('pacientes.lista'))
