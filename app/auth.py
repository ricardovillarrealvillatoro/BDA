import functools
import secrets

from flask import (Blueprint, abort, current_app, flash, redirect, render_template,
                   request, session, url_for)
from werkzeug.security import check_password_hash

from app.db import conectar

bp = Blueprint("auth", __name__)

# Roles que pueden abrir cada página, por nombre de la vista ("lab") o de un Blueprint
# completo ("pacientes" cubre pacientes.lista, pacientes.detalle, ...).
# Una vista que no aparece aquí la puede ver cualquier usuario con sesión.
PERMISOS = {
    "laboratorio": {"medico", "admin_clinico"},
    "reportes": {"medico", "admin_clinico"},
    "rendimiento": {"admin_clinico", "auditor"},
    "auditoria": {"admin_clinico", "auditor"},
    "consultas": {"medico", "admin_clinico", "auditor"},
    "pacientes": {"medico", "admin_clinico"},
    "consultas_sql": {"admin_clinico", "auditor"},
    "medicos": {"medico", "admin_clinico", "auditor"},
    # Permisos por acción: tienen prioridad sobre los del Blueprint completo
    "medicos.nuevo": {"admin_clinico"},
    "medicos.editar": {"admin_clinico"},
    "medicos.baja": {"admin_clinico"},
    "medicos.reactivar": {"admin_clinico"},
    "medicos.asignar_especialidad": {"admin_clinico"},
    # El auditor ve las consultas pero no las abre ni las modifica
    "consultas.nueva": {"medico", "admin_clinico"},
    "consultas.editar": {"medico", "admin_clinico"},
    "consultas.cerrar": {"medico", "admin_clinico"},
    "consultas.cancelar": {"medico", "admin_clinico"},
    "consultas.agregar_diagnostico": {"medico", "admin_clinico"},
    "consultas.crear_orden": {"medico", "admin_clinico"},
    "consultas.prescribir": {"medico"},
    "consultas.decidir": {"medico"},
}

NOMBRES_ROL = {
    "admin_clinico": "Administrador clínico",
    "auditor": "Auditor",
    "medico": "Médico",
    "sistema": "Sistema",
}


def puede_ver(endpoint):
    # Falso si el endpoint no existe, así base.html no enlaza a una ruta mal escrita
    if endpoint not in current_app.view_functions:
        return False
    permitidos = PERMISOS.get(endpoint, PERMISOS.get(endpoint.split(".")[0]))
    return permitidos is None or tiene_rol(*permitidos)


def tiene_rol(*roles):
    return any(r in session.get("roles", []) for r in roles)


def login_required(vista):
    # Decorador: si no hay sesión, manda al login y recuerda a dónde quería ir.
    # Si hay sesión pero el rol no tiene permiso para la página (ver PERMISOS), responde 403.
    @functools.wraps(vista)
    def envoltura(*args, **kwargs):
        if "id_usuario" not in session:
            return redirect(url_for("auth.login", next=request.path))
        if not puede_ver(request.endpoint):
            abort(403)
        return vista(*args, **kwargs)
    return envoltura


def csrf_token():
    # Token por sesión para que otro sitio no pueda enviar el formulario por el usuario
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return session["csrf_token"]


@bp.before_app_request
def validar_csrf():
    # Todo POST de la app (login, bajas, cierres, formularios) debe traer el token de csrf_token()
    if request.method == "POST":
        if not secrets.compare_digest(request.form.get("csrf_token", ""), csrf_token()):
            abort(400)


@bp.record_once
def registrar_globales(state):
    # Globales (no context processor) para que también funcionen dentro de macros importadas,
    # como boton_post de partials/_macros.html
    state.app.jinja_env.globals.update(
        csrf_token=csrf_token, puede_ver=puede_ver, tiene_rol=tiene_rol, NOMBRES_ROL=NOMBRES_ROL,
    )


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip().lower()
        password = request.form.get("password", "")

        with conectar() as conn:
            usuario = conn.execute(
                "SELECT id_usuario, username, password_hash, nombre, apellido_paterno"
                " FROM usuario WHERE username = %s AND activo",
                (username,),
            ).fetchone()

            # Mismo mensaje si no existe el usuario o la contraseña es incorrecta
            if usuario is None or not check_password_hash(usuario["password_hash"], password):
                flash("Usuario o contraseña incorrectos.", "error")
                return render_template("auth/login.html", username=username), 401

            roles = [r["nombre"] for r in conn.execute(
                "SELECT r.nombre FROM usuario_rol ur JOIN rol r USING (id_rol)"
                " WHERE ur.id_usuario = %s",
                (usuario["id_usuario"],),
            )]

        # Se limpia la sesión anterior para evitar fijación de sesión
        session.clear()
        session["id_usuario"] = usuario["id_usuario"]
        session["username"] = usuario["username"]
        session["nombre"] = f'{usuario["nombre"]} {usuario["apellido_paterno"]}'
        session["roles"] = roles

        # Solo se acepta "next" si es una ruta interna (evita redirecciones a otros sitios)
        siguiente = request.args.get("next", "")
        if not siguiente.startswith("/") or siguiente.startswith("//"):
            siguiente = url_for("panel.inicio")
        return redirect(siguiente)

    return render_template("auth/login.html")


# GET para los enlaces de las plantillas viejas, POST para el botón de base.html
@bp.route("/logout", methods=["GET", "POST"])
def logout():
    session.clear()
    flash("Sesión cerrada.", "success")
    return redirect(url_for("auth.login"))
