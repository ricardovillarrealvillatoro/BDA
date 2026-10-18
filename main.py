import os
import psycopg
from flask import Flask, render_template
from werkzeug.exceptions import HTTPException
from app.auth import bp as auth_bp
from app.pacientes import bp as pacientes_bp
from app.consultas import bp as consultas_bp
from app.medicos import bp as medicos_bp
from app.laboratorio import bp as laboratorio_bp
from app.rendimiento import bp as rendimiento_bp
from app.consultas_sql import bp as consultas_sql_bp
from app.panel import bp as panel_bp
from app.auditoria import bp as auditoria_bp
from app.reportes import bp as reportes_bp

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-cambiar-esta-clave")

# Registro de Blueprints
app.register_blueprint(auth_bp)
app.register_blueprint(pacientes_bp)
app.register_blueprint(consultas_bp)
app.register_blueprint(medicos_bp)
app.register_blueprint(laboratorio_bp)
app.register_blueprint(rendimiento_bp)
app.register_blueprint(consultas_sql_bp)
app.register_blueprint(panel_bp)
app.register_blueprint(auditoria_bp)
app.register_blueprint(reportes_bp)

# Páginas de error en español (templates/errores/error.html)
ERRORES = {
    400: ('Solicitud no válida', 'El formulario expiró o llegó incompleto. Vuelva a la página anterior, recárguela e intente de nuevo.'),
    403: ('Acceso denegado', 'Su rol no tiene permiso para ver esta página o hacer esta acción.'),
    404: ('Página no encontrada', 'La página o el registro que busca no existe.'),
    405: ('Método no permitido', 'Esta dirección no acepta ese tipo de solicitud.'),
    500: ('Error interno', 'Ocurrió un error inesperado. Intente de nuevo más tarde.'),
}

@app.errorhandler(HTTPException)
def pagina_error(e):
    titulo, mensaje = ERRORES.get(e.code, ('Error', 'No se pudo completar la solicitud.'))
    return render_template('errores/error.html', codigo=e.code, titulo=titulo, mensaje=mensaje), e.code

# PostgreSQL apagado o variables DB_* incorrectas: el detalle queda en la consola, no en la página
@app.errorhandler(psycopg.OperationalError)
def error_base_datos(e):
    app.logger.error("Error de conexión con PostgreSQL: %s", e)
    return render_template('errores/error.html', codigo=503, titulo='Base de datos no disponible',
                           mensaje='No se pudo conectar con la base de datos. Intente de nuevo en unos momentos.'), 503

# Globals y Macros de Jinja2
app.jinja_env.globals["icono"] = app.jinja_env.get_template("partials/_iconos.html").module.icono

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

@app.template_filter('num')
def filtro_num(val):
    # 1234.50 -> "1,234.5"; sin valor -> "—"
    if val is None:
        return '—'
    return f"{val:,.2f}".rstrip('0').rstrip('.')

if __name__ == '__main__':
    app.run(debug=True)
