import os

from flask import render_template, Flask

from app.auth import bp as auth_bp, login_required

app = Flask(__name__)
# TODO: en producción definir SECRET_KEY como variable de entorno
app.secret_key = os.environ.get("SECRET_KEY", "dev-cambiar-esta-clave")
app.register_blueprint(auth_bp)
# Macro de íconos disponible en todas las plantillas sin importarla (la usan base.html y sus hijas)
app.jinja_env.globals["icono"] = app.jinja_env.get_template("partials/_iconos.html").module.icono

@app.route("/")
@login_required
def index():
    return render_template("panel/index.html")

@app.route("/audit")
@login_required
def audit():
    return render_template("auditoria/audit.html")

@app.route("/lab")
@login_required
def lab():
    return render_template("laboratorio/lab.html")

@app.route("/performance")
@login_required
def performance():
    return render_template("rendimiento/performance.html")

@app.route("/report")
@login_required
def report():
    return render_template("reportes/report.html")
