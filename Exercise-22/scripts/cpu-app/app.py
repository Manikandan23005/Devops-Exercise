import time
import math
import os
from flask import Flask, jsonify, request

app = Flask(__name__)

# Basic Health Check
@app.route('/healthz', methods=['GET'])
def healthz():
    return "OK", 200

# Home Page showing status
@app.route('/', methods=['GET'])
def status():
    return jsonify({
        "status": "healthy",
        "app": "cpu-intensive-service",
        "cpu_limit_env": os.environ.get("CPU_LIMIT", "not_set")
    })

# Route to generate artificial CPU load
@app.route('/load', methods=['GET'])
def generate_load():
    # Allow duration specification via query parameter (default to 5 seconds)
    duration = float(request.args.get('duration', 5.0))
    iterations = int(request.args.get('iterations', 1000000))
    
    start_time = time.time()
    count = 0
    # Execute CPU intensive math calculation for the requested duration/iterations
    while (time.time() - start_time) < duration:
        # Perform square roots, exponentiations, and trig functions
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
    # Listen on port 8080
    app.run(host='0.0.0.0', port=8080)
