# Scenario 2: Security Scan Failure

This scenario demonstrates a failure in the **Security Auditing** stage of the pipeline caused by introducing hardcoded sensitive credentials in the codebase.

---

## 🎯 Pipeline Stage Behaviour

When code containing secrets is pushed, the security scanner stops the workflow:
```text
Git Push
   ↓
Unit Tests ✅ [PASSED]
   ↓
Bandit Scan ❌ [FAILED]
   ↓
Pipeline Halts
```

---

## 💥 Failure Injection

Modify `app/app.py` to store a password directly inside a variable definition:

### ❌ Broken Code (app/app.py)
```python
# Vulnerability injected: Hardcoded credentials
APP_PASSWORD = "admin_super_secret_password_123!"
```

---

## 🔍 Log Analysis & Investigation

When the GitHub Actions pipeline runs Bandit, it detects a high-severity alert:

### 📝 Expected Bandit Failure Log
```text
[bandit] Run started:2026-06-22 00:15:30 +0000
>> Issue: [B105:hardcoded_password_string] Possible hardcoded password: 'admin_super_secret_password_123!'
   Severity: Medium   Confidence: Medium
   CWE: CWE-259 (Use of Hard-coded Password)
   Location: app/app.py:6:15
5	
6	APP_PASSWORD = "admin_super_secret_password_123!"
7	

--------------------------------------------------
Code scanned:
	Total lines of code: 82
	Semgrep / Bandit Rules loaded: 142
	Files skipped: 0

Run metrics:
	Total issues by severity:
		Undefined: 0
		Low: 0
		Medium: 1
		High: 0
	Total issues by confidence:
		Undefined: 0
		Low: 0
		Medium: 1
		High: 0

Files with issues:
	app/app.py (1 issues)

Error: Process completed with exit code 1.
```

### 🛠️ Debugging Commands
To audit code vulnerabilities locally before pushing:
```bash
# Scan app folder recursively using Bandit
bandit -r app/
```

---

## 💡 Root Cause Analysis

* **Error Identification:** Bandit flagged rule `B105:hardcoded_password_string` inside `app/app.py`.
* **Problem:** Storing password strings directly inside source control commits exposes passwords to anyone with repository access and breaks compliance standards.

---

## 🛠️ Recovery & Fix

Remove the plaintext credentials from the source code and configure the system to load them dynamically using environment variables.

###  Fixed Code (app/app.py)
```python
import os

# Secure credentials loading via OS environment
APP_PASSWORD = os.getenv("APP_PASSWORD", "default_safe_password_321")
```

### 🔄 Recovery Steps
1. Push the corrected code to the repository.
2. In production, configure the values dynamically via **GitHub Secrets**, **Kubernetes Secrets**, or **AWS Secrets Manager**:
```yaml
# Inside Kubernetes Deployment spec (k8s/deployment.yaml)
env:
  - name: APP_PASSWORD
    valueFrom:
      secretKeyRef:
        name: flask-app-secrets
        key: APP_PASSWORD
```

Run the push to trigger the pipeline validation:
```bash
git add app/app.py
git commit -m "Fix security failure: use env variable for credentials"
git push origin main
```

### 🚀 Success Validation Log
```text
[bandit] Run started:2026-06-22 00:18:12 +0000

--------------------------------------------------
Code scanned:
	Total lines of code: 82
	Files skipped: 0

Run metrics:
	Total issues by severity:
		Undefined: 0
		Low: 0
		Medium: 0
		High: 0

No issues identified.
```
Pipeline scanning turns green and passes.
