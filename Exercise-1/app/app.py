import os
import time
import json
import logging
import boto3
import botocore.exceptions
# pyrefly: ignore [missing-import]
from flask import Flask, jsonify
# pyrefly: ignore [missing-import]
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# ─── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger(__name__)

# ─── Flask App ────────────────────────────────────────────────────────────────

# Flask application instance
app = Flask(__name__)

# ─── Prometheus Metrics ───────────────────────────────────────────────────────

REQUEST_COUNT = Counter(
    "payment_service_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "status"],
)

REQUEST_LATENCY = Histogram(
    "payment_service_request_latency_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
)

ERROR_COUNT = Counter(
    "payment_service_errors_total",
    "Total number of errors",
    ["endpoint", "error_type"],
)

# ─── AWS Secrets Manager ─────────────────────────────────────────────────────

def get_secret():
    """Fetch payment-service-secret from AWS Secrets Manager via IRSA."""
    region = os.environ.get("AWS_REGION", "ap-south-1")
    secret_name = os.environ.get("SECRET_NAME", "payment-service-secret")
    try:
        client = boto3.client("secretsmanager", region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response["SecretString"])
        logger.info("Secret fetched successfully from Secrets Manager")
        return secret
    except botocore.exceptions.ClientError as e:
        logger.error("Failed to fetch secret: %s", e)
        return {}

# ─── Routes ──────────────────────────────────────────────────────────────────

@app.route("/")
def health():
    start = time.time()
    REQUEST_COUNT.labels(method="GET", endpoint="/", status="200").inc()
    REQUEST_LATENCY.labels(method="GET", endpoint="/").observe(time.time() - start)
    return jsonify({"service": "payment-service", "status": "healthy"}), 200


@app.route("/metrics")
def metrics():
    """Expose Prometheus metrics."""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/secret-check")
def secret_check():
    """Verify IRSA + Secrets Manager access (debug endpoint)."""
    start = time.time()
    secret = get_secret()
    status = "ok" if secret else "error"
    code = 200 if secret else 500
    REQUEST_COUNT.labels(method="GET", endpoint="/secret-check", status=str(code)).inc()
    REQUEST_LATENCY.labels(method="GET", endpoint="/secret-check").observe(
        time.time() - start
    )
    if not secret:
        ERROR_COUNT.labels(endpoint="/secret-check", error_type="secrets_manager").inc()
    return jsonify({"status": status, "db_host": secret.get("DB_HOST", "N/A")}), code


# ─── Entry Point ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    logger.info("Starting payment-service on port %d", port)
    app.run(host="0.0.0.0", port=port)
