import os

import psycopg
from flask import has_request_context, request, session
from psycopg.rows import dict_row


# Conectar a la base de datos (variables DB_* en README.md)
def conectar():
    # Los valores por defecto coinciden con db/06_datos_prueba.sql; se pueden cambiar con variables de entorno
    conn = psycopg.connect(
            host=os.environ.get("DB_HOST", "localhost"),
            user=os.environ.get("DB_USER", "medassist_app"),
            dbname=os.environ.get("DB_NAME", "medassist"),
            password=os.environ.get("DB_PASSWORD"),
            row_factory=dict_row,
            )
    # Usuario e IP de la petición para los triggers de auditoría (db/triggers.sql).
    # Se confirma de inmediato para que la conexión empiece limpia (consultas_sql la pone en solo lectura)
    if has_request_context() and "id_usuario" in session:
        conn.execute("SELECT set_config('app.id_usuario', %s, false), set_config('app.ip', %s, false)",
                     (str(session["id_usuario"]), request.remote_addr or ""))
        conn.commit()
    return conn


def mensaje_error(e):
    # Solo el mensaje principal de PostgreSQL (sin CONTEXT ni el SQL interno) para mostrarlo al usuario
    diag = getattr(e, "diag", None)
    return (diag and diag.message_primary) or str(e)
