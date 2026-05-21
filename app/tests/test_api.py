from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_status():
    response = client.get("/status")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_data():
    response = client.post("/data", json={"key": "test", "value": "hello"})
    assert response.status_code == 200
    assert response.json()["received"] == True

def test_data_missing_body():
    response = client.post("/data", json={})
    assert response.status_code == 422  