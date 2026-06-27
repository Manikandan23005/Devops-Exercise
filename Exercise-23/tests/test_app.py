import pytest
from app.app import app

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_home_page(client):
    """Test that the home page loads successfully with HTML."""
    response = client.get("/")
    assert response.status_code == 200
    assert b"CI/CD Troubleshooting Lab" in response.data

def test_health_check(client):
    """Test that the healthz check returns correct JSON format."""
    response = client.get("/healthz")
    assert response.status_code == 200
    
    data = response.get_json()
    assert data == {"status": "healthy"}
