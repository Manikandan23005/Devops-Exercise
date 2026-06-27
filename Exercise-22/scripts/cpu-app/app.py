import time
import math
import os
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/healthz', methods=['GET'])
def healthz():
    return "OK", 200

@app.route('/', methods=['GET'])
def status():
    return jsonify({
        "status": "healthy",
        "app": "cpu-intensive-service",
        "cpu_limit_env": os.environ.get("CPU_LIMIT", "not_set")
    })

@app.route('/load', methods=['GET'])
def generate_load():
    duration = float(request.args.get('duration', 5.0))
    iterations = int(request.args.get('iterations', 1000000))
    
    start_time = time.time()
    count = 0
    while (time.time() - start_time) < duration:
        x = math.sqrt(math.pi * iterations)
        y = math.sin(x) * math.cos(x)
        count += 1
        
    end_time = time.time()
    
    return jsonify({
        "message": "CPU load generation finished",
        "elapsed_seconds": round(end_time - start_time, 4),
        "calculations_performed": count
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
