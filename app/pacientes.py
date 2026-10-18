from flask import Blueprint, render_template, request, redirect, url_for, flash
from db import conectar
from app.auth import login_required

bp = Blueprint('pacientes', __name__, url_prefix='/pacientes')

@bp.route('/')
@login_required
def lista():
    q = request.args.get('q', '').strip()
    estado = request.args.get('estado', 'activos')
    pagina = int(request.args.get('pagina', 1))
    tam = 15
    offset = (pagina - 1) * tam

    sql = "SELECT * FROM v_pacientes_ultima_consulta WHERE 1=1"
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

    return render_template('lista_paciente.html', pacientes=pacientes, q=q, estado=estado, pagina=pagina, tam=tam, total=total)

@bp.route('/<int:id_paciente>')
@login_required
def detalle(id_paciente):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT *, EXTRACT(YEAR FROM age(fecha_nacimiento)) AS edad FROM paciente WHERE id_paciente = %s", (id_paciente,))
            paciente = cur.fetchone()
            if not paciente:
                flash("Paciente no encontrado", "danger")
                return redirect(url_for('pacientes.lista'))

            cur.execute("SELECT * FROM v_historial_consultas_medico WHERE id_paciente = %s ORDER BY fecha_inicio DESC", (id_paciente,))
            consultas = cur.fetchall()

            cur.execute("SELECT * FROM alergia WHERE id_paciente = %s", (id_paciente,))
            alergias = cur.fetchall()

    return render_template('detalle_paciente.html', p=paciente, consultas=consultas, alergias=alergias, antecedentes=[], medicacion=[])

@bp.route('/nuevo', methods=['GET', 'POST'])
@login_required
def nuevo():
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

        try:
            with conectar() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "CALL sp_registrar_paciente(%s, %s, %s, %s, %s, %s, %s, %s, %s, NULL)",
                        (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, telefono, email, direccion)
                    )
            flash("Paciente registrado correctamente.", "success")
            return redirect(url_for('pacientes.lista'))
        except Exception as e:
            flash(f"Error al registrar: {str(e)}", "danger")

    return render_template('form_paciente.html', modo='nuevo', paciente=None, f=request.form, errores={})

@bp.route('/<int:id_paciente>/editar', methods=['GET', 'POST'])
@login_required
def editar(id_paciente):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM paciente WHERE id_paciente = %s", (id_paciente,))
            paciente = cur.fetchone()

    if request.method == 'POST':
        nombre = request.form.get('nombre')
        apellido_paterno = request.form.get('apellido_paterno')
        apellido_materno = request.form.get('apellido_materno') or None
        telefono = request.form.get('telefono') or None
        email = request.form.get('email') or None
        direccion = request.form.get('direccion') or None

        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE paciente 
                    SET nombre=%s, apellido_paterno=%s, apellido_materno=%s, telefono=%s, email=%s, direccion=%s 
                    WHERE id_paciente=%s
                """, (nombre, apellido_paterno, apellido_materno, telefono, email, direccion, id_paciente))
        flash("Datos actualizados correctamente.", "success")
        return redirect(url_for('pacientes.detalle', id_paciente=id_paciente))

    return render_template('form_paciente.html', modo='editar', paciente=paciente, f=paciente, errores={})

@bp.route('/<int:id_paciente>/baja', methods=['POST'])
@login_required
def baja(id_paciente):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("CALL sp_desactivar_paciente(%s)", (id_paciente,))
        flash("Paciente dado de baja.", "warning")
    except Exception as e:
        flash(f"Error en baja: {str(e)}", "danger")
    return redirect(url_for('pacientes.lista'))
