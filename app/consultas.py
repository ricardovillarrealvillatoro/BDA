from flask import Blueprint, render_template, request, redirect, url_for, flash
from db import conectar
from app.auth import login_required

bp = Blueprint('consultas', __name__, url_prefix='/consultas')

TIPO_CONSULTA = {'consulta': 'Consulta médica', 'urgencia': 'Urgencia', 'seguimiento': 'Seguimiento'}
ESTADO_CONSULTA = {'abierto': 'Abierta', 'cerrado': 'Cerrada', 'cancelado': 'Cancelada'}
ESTADO_RESULTADO = {'normal': 'Normal', 'anormal': 'Anormal', 'critico': 'Crítico'}

@bp.route('/')
@login_required
def lista():
    q = request.args.get('q', '').strip()
    estado = request.args.get('estado', '')
    pagina = int(request.args.get('pagina', 1))
    tam = 15
    offset = (pagina - 1) * tam

    sql = "SELECT * FROM v_historial_consultas_medico WHERE 1=1"
    params = []

    if q:
        sql += " AND (paciente ILIKE %s OR curp ILIKE %s OR motivo ILIKE %s)"
        params.extend([f"%{q}%", f"%{q}%", f"%{q}%"])

    if estado:
        sql += " AND estado = %s"
        params.append(estado)

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
        'consultas_lista.html', consultas=consultas, q=q, estado=estado, medicos=medicos,
        total=total, pagina=pagina, tam=tam, TIPO_CONSULTA=TIPO_CONSULTA, ESTADO_CONSULTA=ESTADO_CONSULTA
    )

@bp.route('/nueva', methods=['GET', 'POST'])
@login_required
def nueva():
    if request.method == 'POST':
        id_paciente = request.form.get('id_paciente')
        id_medico = request.form.get('id_medico') or 1
        tipo = request.form.get('tipo')
        motivo = request.form.get('motivo')

        try:
            with conectar() as conn:
                with conn.cursor() as cur:
                    cur.execute("CALL sp_abrir_encuentro(%s, %s, %s, %s, NULL)", (id_paciente, id_medico, tipo, motivo))
            flash("Consulta abierta exitosamente.", "success")
            return redirect(url_for('consultas.lista'))
        except Exception as e:
            flash(f"Error al abrir la consulta: {str(e)}", "danger")

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id_paciente, nombre || ' ' || apellido_paterno || ' · ' || curp AS nombre FROM paciente WHERE activo = TRUE")
            pacientes = cur.fetchall()
            cur.execute("SELECT m.id_medico, u.nombre || ' ' || u.apellido_paterno AS nombre FROM medico m JOIN usuario u ON m.id_medico = u.id_usuario")
            medicos = cur.fetchall()

    return render_template('consultas_form.html', modo='nueva', enc=None, pacientes=pacientes, medicos=medicos, tipos=TIPO_CONSULTA, f=request.form, errores={}, es_admin=True)

@bp.route('/<int:id_encuentro>')
@login_required
def detalle(id_encuentro):
    with conectar() as conn:
        with conn.cursor() as cur:
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

            cur.execute("SELECT d.*, c.descripcion FROM diagnostico d JOIN catalogo_cie10 c ON d.codigo_cie10 = c.codigo_cie10 WHERE d.id_encuentro = %s", (id_encuentro,))
            diagnosticos = cur.fetchall()

            cur.execute("SELECT codigo_cie10, descripcion FROM catalogo_cie10 LIMIT 50")
            cie10 = cur.fetchall()

    return render_template('consultas_detalle.html', enc=enc, diagnosticos=diagnosticos, cie10=cie10, prescripciones=[], ordenes=[], recomendaciones=[], contexto=[], puede_modificar=True, ESTADO_CONSULTA=ESTADO_CONSULTA, TIPO_CONSULTA=TIPO_CONSULTA, ESTADO_RESULTADO=ESTADO_RESULTADO)

@bp.route('/<int:id_encuentro>/cerrar', methods=['POST'])
@login_required
def cerrar(id_encuentro):
    notas = request.form.get('notas', '')
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("CALL sp_cerrar_encuentro(%s, %s)", (id_encuentro, notas))
        flash("Consulta cerrada.", "info")
    except Exception as e:
        flash(f"Error al cerrar: {str(e)}", "danger")
    return redirect(url_for('consultas.detalle', id_encuentro=id_encuentro))
