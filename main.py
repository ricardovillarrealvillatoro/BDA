from flask import render_template, Flask
import psycopg

app = Flask("__app__")

# TODO: añadir informacion de acceso a la base de datos

def conectar():
    return psycopg.connect(
            host="aa",
            user="aa",
            dbname="",
            password="Aa",
            )

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/audit")
def audit():
    return render_template("audit.html")

@app.route("/lab")
def lab():
    return render_template("lab.html")

@app.route("/performance")
def performance():
    return render_template("performance.html")

@app.route("/report")
def report():
    return render_template("report.hml")
