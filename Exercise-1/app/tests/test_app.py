# pyrefly: ignore [missing-import]
import pytest
import json
from app import app

@pytest.fixture
def client():
    app.testing = True
    with app.test_client() as client:
        yield client


def test_health_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_health_returns_correct_body(client):
    response = client.get("/")
    data = json.loads(response.data)
    assert data["service"] == "payment-service"
    assert data["status"] == "healthy"


def test_metrics_endpoint_returns_200(client):
    response = client.get("/metrics")
    assert response.status_code == 200


def test_metrics_content_type(client):
    response = client.get("/metrics")
    assert "text/plain" in response.content_type
