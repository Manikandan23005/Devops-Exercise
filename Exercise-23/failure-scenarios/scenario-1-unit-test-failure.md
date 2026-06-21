# Scenario 1: Unit Test Failure

This scenario demonstrates a failure in the **Unit Testing** stage of the pipeline where application endpoint responses do not align with defined assertions.

---

## 🎯 Pipeline Stage Behaviour

When a code change is pushed, the GitHub Actions runner runs Pytest inside the test container:
```text
Git Push
   ↓
Unit Tests ❌ [FAILED]
   ↓
Pipeline Halts (Subsequent stages are skipped)
```

---

## 💥 Failure Injection

Modify `app/app.py` so that the default route `/healthz` returns plain text instead of the structured JSON key-value expected by the test:

### ❌ Broken Code (app/app.py)
```python
@app.route("/healthz")
def healthz():
    # Broken response injected for testing
    return "healthy"
```

---

## 🔍 Log Analysis & Investigation

When the test runner executes, the test fails with the following standard output:

### 📝 Expected Pytest Failure Log
```text
==================================== FAILURES ====================================
_______________________________ test_health_check ________________________________

client = <FlaskClient <Flask 'app.app'>>

    def test_health_check(client):
        """Test that the healthz check returns correct JSON format."""
        response = client.get("/healthz")
        assert response.status_code == 200
        
        data = response.get_json()
>       assert data == {"status": "healthy"}
E       AssertionError: assert None == {'status': 'healthy'}
E        +  where None = <bound method Response.get_json of <WrapperTestResponse stream [200 OK]>>()

tests/test_app.py:20: AssertionError
============================ 1 failed, 1 passed in 0.12s ===========================
```

### 🛠️ Debugging Commands
To reproduce the issue locally, run:
```bash
# Execute pytest with verbose output
pytest -v tests/test_app.py
```

---

## 💡 Root Cause Analysis

* **Error Identification:** The test `test_health_check` expects a JSON formatted response dictionary `{"status": "healthy"}`.
* **Problem:** The Flask application's `/healthz` route returns a plain text string `"healthy"`. This causes `response.get_json()` to parse as `None`, failing the assertion.

---

## 🛠️ Recovery & Fix

To resolve the issue, return a JSON response object using `flask.jsonify` or a Python dictionary:

###  Fixed Code (app/app.py)
```python
from flask import jsonify

@app.route("/healthz")
def healthz():
    # Production-ready health check returns JSON matching unit tests
    return jsonify({"status": "healthy"})
```

### 🔄 Recovery Steps
Commit and push the fixed application code to trigger a clean pipeline execution:
```bash
git add app/app.py
git commit -m "Fix failing unit test: restore healthz JSON response"
git push origin main
```

### 🚀 Success Validation Log
```text
============================= test session starts ==============================
platform linux -- Python 3.9.19, pytest-8.2.2, pluggy-1.5.0
cachedir: .pytest_cache
rootdir: /home/satoru/Projects/Devops-Exercise/Exercise-23
collected 2 items

tests/test_app.py::test_home_page PASSED                                  [ 50%]
tests/test_app.py::test_health_check PASSED                               [100%]

============================== 2 passed in 0.15s ===============================
```
Chart pipeline output goes green and continues execution.
