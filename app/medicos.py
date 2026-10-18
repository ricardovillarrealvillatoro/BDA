import re

import psycopg
from flask import Blueprint, abort, render_template, request, redirect, url_for, flash, session
from werkzeug.security import generate_password_hash
from app.db import conectar, mensaje_error
from app.auth import login_required
from app.pacientes import EMAIL_RE
from app.rendimiento import CONTEOS

bp = Blueprint('medicos', __name__, url_prefix='/medicos')

# Mismas reglas que los pattern de medicos/form.html y los CHECK de db/01_schema.sql
USERNAME_RE = re.compile(r'^[a-z0-9._]{3,50}$')
CEDULA_RE = re.compile(r'^[0-9A-Z]{5,20}$')
CAMPOS = ('username', 'email', 'cedula_profesional', 'cedula_especialidad')


def datos_medico(form):
    # Limpia el formulario igual que el navegador (minúsculas en usuario, mayúsculas en cédulas)
    return {
        'username': (form.get('username') or '').strip().lower(),
        'password': form.get('password') or '',
        'password2': form.get('password2') or '',
        'nombre': (form.get('nombre') or '').strip(),
        'apellido_paterno': (form.get('apellido_paterno') or '').strip(),
        'apellido_materno': (form.get('apellido_materno') or '').strip() or None,
        'email': (form.get('email') or '').strip().lower(),
        'cedula_profesional': (form.get('cedula_profesional') or '').strip().upper(),
        'id_especialidad': (form.get('id_especialidad') or '').strip(),
        'cedula_especialidad': (form.get('cedula_especialidad') or '').strip().upper(),
    }


def validar_medico(d, nuevo):
    errores = {}
    if nuevo:
        if not USERNAME_RE.match(d['username']):
            errores['username'] = 'Use minúsculas, números, punto o guion bajo (3 a 50).'
        if len(d['password']) < 10 or not re.search(r'[A-Za-z]', d['password']) or not re.search(r'\d', d['password']):
            errores['password'] = 'Mínimo 10 caracteres con letras y números.'
        elif d['password'] != d['password2']:
            errores['password2'] = 'Las contraseñas no coinciden.'
        if d['id_especialidad'] and not d['id_especialidad'].isdigit():
            errores['id_especialidad'] = 'Seleccione una especialidad válida.'
        elif d['id_especialidad'] and not CEDULA_RE.match(d['cedula_especialidad']):
            errores['cedula_especialidad'] = 'Capture la cédula de la especialidad (5 a 20 caracteres).'
    for campo, mensaje in [('nombre', 'Escriba el nombre.'), ('apellido_paterno', 'Escriba el apellido paterno.')]:
        if not d[campo]:
            errores[campo] = mensaje
    if not EMAIL_RE.match(d['email']):
        errores['email'] = 'Escriba un correo válido.'
    if not CEDULA_RE.match(d['cedula_profesional']):
        errores['cedula_profesional'] = 'De 5 a 20 dígitos o letras mayúsculas.'
    return errores


def error_de_campo(e, errores):
    # Los SP marcan los duplicados con USING COLUMN; ese error se muestra junto al campo
    campo = getattr(e.diag, 'column_name', None)
    if campo in CAMPOS:
        errores[campo] = mensaje_error(e)
        return True
    return False


def obtener_especialidades(cur):
    cur.execute("SELECT id_especialidad, nombre FROM especialidad ORDER BY nombre")
    return cur.fetchall()


@bp.route('/')
@login_required
def lista():
    q = request.args.get('q', '').strip()
    especialidad = request.args.get('especialidad', '')
    estado = request.args.get('estado', 'activos')
    pagina = request.args.get("pagina", 1, type=int)
    tam = 15
    offset = (pagina - 1) * tam

    sql = """
        SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS nombre_completo,
               u.username, m.cedula_profesional, u.activo, esp.nombre AS especialidad,
               COUNT(e.id_encuentro) AS consultas,
               COUNT(CASE WHEN e.estado = 'abierto' THEN 1 END) AS abiertas
        FROM medico m
        JOIN usuario u ON m.id_medico = u.id_usuario
        LEFT JOIN medico_especialidad me ON m.id_medico = me.id_medico AND me.es_principal
        LEFT JOIN especialidad esp ON me.id_especialidad = esp.id_especialidad
        LEFT JOIN encuentro e ON m.id_medico = e.id_medico
        WHERE 1=1
    """
    params = []
    if q:
        sql += " AND (u.nombre || ' ' || u.apellido_paterno ILIKE %s OR u.username ILIKE %s OR m.cedula_profesional ILIKE %s)"
        params.extend([f"%{q}%", f"%{q}%", f"%{q}%"])
    if especialidad.isdigit():
        # Cualquier especialidad del médico, no solo la principal
        sql += " AND EXISTS (SELECT 1 FROM medico_especialidad x WHERE x.id_medico = m.id_medico AND x.id_especialidad = %s)"
        params.append(int(especialidad))
    if estado == 'activos':
        sql += " AND u.activo"
    elif estado == 'inactivos':
        sql += " AND NOT u.activo"

    sql += " GROUP BY m.id_medico, u.nombre, u.apellido_paterno, u.username, m.cedula_profesional, u.activo, esp.nombre"

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM ({sql}) AS count_tbl", params)
            total = cur.fetchone()['count']

            sql += " ORDER BY u.apellido_paterno, u.nombre LIMIT %s OFFSET %s"
            params.extend([tam, offset])
            cur.execute(sql, params)
            medicos = cur.fetchall()

            especialidades = obtener_especialidades(cur)

    return render_template('medicos/lista.html', medicos=medicos, q=q, especialidad=especialidad, estado=estado,
                           especialidades=especialidades, pagina=pagina, tam=tam, total=total)

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

            if not medico:
                abort(404)

            cur.execute("SELECT * FROM vw_historial_consultas_medico WHERE id_medico = %s ORDER BY fecha_inicio DESC LIMIT 30", (id_medico,))
            historial = cur.fetchall()

            cur.execute("""
                SELECT e.id_especialidad, e.nombre, me.cedula_especialidad, me.es_principal
                FROM medico_especialidad me JOIN especialidad e ON me.id_especialidad = e.id_especialidad
                WHERE me.id_medico = %s ORDER BY me.es_principal DESC, e.nombre
            """, (id_medico,))
            especialidades = cur.fetchall()

            # Especialidades que todavía no tiene, para el formulario de asignación
            cur.execute("""
                SELECT id_especialidad, nombre FROM especialidad
                WHERE id_especialidad NOT IN (SELECT id_especialidad FROM medico_especialidad WHERE id_medico = %s)
                ORDER BY nombre
            """, (id_medico,))
            catalogo = cur.fetchall()

            cur.execute(f"""
                SELECT rc.codigo AS regla, rc.nombre AS regla_nombre, vr.numero_version, {CONTEOS}
                FROM decision_medica dm
                JOIN recomendacion r ON dm.id_recomendacion = r.id_recomendacion
                JOIN version_regla vr ON r.id_version_regla = vr.id_version_regla
                JOIN regla_clinica rc ON vr.id_regla = rc.id_regla
                WHERE dm.id_medico = %s
                GROUP BY rc.codigo, rc.nombre, vr.numero_version
                ORDER BY rc.codigo, vr.numero_version
            """, (id_medico,))
            concordancia = cur.fetchall()

    return render_template('medicos/detalle.html', m=medico, especialidades=especialidades, catalogo=catalogo,
                           concordancia=concordancia, historial=historial)

@bp.route('/nuevo', methods=['GET', 'POST'])
@login_required
def nuevo():
    with conectar() as conn:
        with conn.cursor() as cur:
            especialidades = obtener_especialidades(cur)

    errores = {}
    if request.method == 'POST':
        d = datos_medico(request.form)
        errores = validar_medico(d, nuevo=True)
        if not errores:
            try:
                with conectar() as conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            "CALL sp_registrar_medico(%s, %s, %s, %s, %s, %s, %s, %s, %s, NULL)",
                            (d['username'], generate_password_hash(d['password']), d['nombre'], d['apellido_paterno'],
                             d['apellido_materno'], d['email'], d['cedula_profesional'],
                             int(d['id_especialidad']) if d['id_especialidad'] else None,
                             d['cedula_especialidad'] or None)
                        )
                        id_medico = cur.fetchone()['p_id_medico']
                flash("Médico registrado. Ya puede iniciar sesión con su usuario.", "success")
                return redirect(url_for('medicos.detalle', id_medico=id_medico))
            except psycopg.Error as e:
                if not error_de_campo(e, errores):
                    flash(f"Error al registrar: {mensaje_error(e)}", "error")

    # Las contraseñas nunca se vuelven a llenar en el formulario
    f = {k: v for k, v in request.form.items() if not k.startswith('password')}
    return render_template('medicos/form.html', modo='nuevo', medico=None, f=f, errores=errores,
                           especialidades=especialidades), 400 if errores else 200

@bp.route('/<int:id_medico>/editar', methods=['GET', 'POST'])
@login_required
def editar(id_medico):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT m.id_medico, m.cedula_profesional, u.nombre, u.apellido_paterno, u.apellido_materno, u.email
                FROM medico m JOIN usuario u ON m.id_medico = u.id_usuario
                WHERE m.id_medico = %s
            """, (id_medico,))
            medico = cur.fetchone()
    if not medico:
        abort(404)

    errores = {}
    if request.method == 'POST':
        d = datos_medico(request.form)
        errores = validar_medico(d, nuevo=False)
        if not errores:
            try:
                with conectar() as conn:
                    with conn.cursor() as cur:
                        cur.execute("CALL sp_actualizar_medico(%s, %s, %s, %s, %s, %s)", (
                            id_medico, d['nombre'], d['apellido_paterno'], d['apellido_materno'],
                            d['email'], d['cedula_profesional']))
                flash("Datos del médico actualizados.", "success")
                return redirect(url_for('medicos.detalle', id_medico=id_medico))
            except psycopg.Error as e:
                if not error_de_campo(e, errores):
                    flash(f"Error al actualizar: {mensaje_error(e)}", "error")
        f = request.form
    else:
        f = medico

    return render_template('medicos/form.html', modo='editar', medico=medico, f=f, errores=errores,
                           especialidades=[]), 400 if errores else 200

def cambiar_estado(id_medico, activo):
    if not activo and id_medico == session['id_usuario']:
        flash("No puede desactivar su propia cuenta.", "error")
        return redirect(url_for('medicos.detalle', id_medico=id_medico))
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("CALL sp_cambiar_estado_medico(%s, %s)", (id_medico, activo))
        if activo:
            flash("Cuenta reactivada.", "success")
        else:
            flash("Cuenta desactivada. El médico ya no puede iniciar sesión; su historial se conserva.", "warning")
    except psycopg.Error as e:
        flash(mensaje_error(e), "error")
    return redirect(url_for('medicos.detalle', id_medico=id_medico))

@bp.route('/<int:id_medico>/baja', methods=['POST'])
@login_required
def baja(id_medico):
    return cambiar_estado(id_medico, False)

@bp.route('/<int:id_medico>/reactivar', methods=['POST'])
@login_required
def reactivar(id_medico):
    return cambiar_estado(id_medico, True)

@bp.route('/<int:id_medico>/especialidad', methods=['POST'])
@login_required
def asignar_especialidad(id_medico):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("CALL sp_asignar_especialidad_medico(%s, %s, %s, %s)", (
                    id_medico, int(request.form['id_especialidad']),
                    request.form.get('cedula_especialidad', '').strip().upper(),
                    request.form.get('es_principal') == '1'))
        flash("Especialidad asignada.", "success")
    except (psycopg.Error, KeyError, ValueError) as e:
        flash(f"Error al asignar la especialidad: {mensaje_error(e)}", "error")
    return redirect(url_for('medicos.detalle', id_medico=id_medico))
