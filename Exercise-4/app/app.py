import os
import sys
# pyrefly: ignore [missing-import]
from flask import Flask, jsonify

# Check database password
db_password = os.environ.get("DB_PASSWORD")
if not db_password:
    print("FATAL:", file=sys.stderr)
    print("Database password not found", file=sys.stderr)
    print("Environment Variable DB_PASSWORD missing", file=sys.stderr)
    sys.exit(1)

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({"message": "Hello from application!", "db_password_status": "Loaded"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
