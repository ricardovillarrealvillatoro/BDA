import os

import psycopg
from psycopg.rows import dict_row


def conectar():
    # Los valores por defecto coinciden con db/06_datos_prueba.sql; se pueden cambiar con variables de entorno
    return psycopg.connect(
            host=os.environ.get("DB_HOST", "localhost"),
            user=os.environ.get("DB_USER", "medassist_app"),
            dbname=os.environ.get("DB_NAME", "medassist"),
            password=os.environ.get("DB_PASSWORD"),
            row_factory=dict_row,
            )
