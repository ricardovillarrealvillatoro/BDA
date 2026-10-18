import os
from flask import Flask, render_template
from app.auth import bp as auth_bp, login_required
from app.pacientes import bp as pacientes_bp
from app.consultas import bp as consultas_bp
from app.medicos import bp as medicos_bp

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-cambiar-esta-clave")

# Registro de Blueprints
app.register_blueprint(auth_bp)
app.register_blueprint(pacientes_bp)
app.register_blueprint(consultas_bp)
app.register_blueprint(medicos_bp)

# Globals y Macros de Jinja2
app.jinja_env.globals["icono"] = app.jinja_env.get_template("partials/_iconos.html").module.icono
app.jinja_env.globals["tiene_rol"] = lambda *roles: True

# Filtros para formatear fechas y género en tus plantillas HTML
@app.template_filter('fecha')
def filtro_fecha(val):
    return val.strftime('%d/%m/%Y') if val else '—'

@app.template_filter('fechahora')
def filtro_fechahora(val):
    return val.strftime('%d/%m/%Y %H:%M') if val else '—'

@app.template_filter('sexo')
def filtro_sexo(val):
    mapa = {'M': 'Masculino', 'F': 'Femenino', 'I': 'Intersexual'}
    return mapa.get(val, val)

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

if __name__ == '__main__':
    app.run(debug=True)
