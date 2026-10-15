from flask import render_template, Flask

app = Flask("__app__")

@app.route("/")
def index():
    return render_template("index.html")
