from flask import Flask, Response

app = Flask(__name__)

@app.get("/health")
def health():
    return Response("OK", status=200, mimetype="text/plain")

@app.get("/")
def root():
    return Response("Hello Green DevOps (Python)", status=200, mimetype="text/plain")

if __name__ == "__main__":
    # Flask domyślnie na 5000
    app.run(host="0.0.0.0", port=5000)
