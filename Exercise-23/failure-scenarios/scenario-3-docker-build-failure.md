# Scenario 3: Docker Build Failure

This scenario demonstrates a failure in the **Docker Image Build** stage of the pipeline caused by a syntax typo in the file path configuration.

---

## 🎯 Pipeline Stage Behaviour

When the runner attempts to build the container using a broken build instruction, the stage fails:
```text
Git Push
   ↓
Unit Tests ✅ [PASSED]
   ↓
Bandit Scan ✅ [PASSED]
   ↓
Docker Build ❌ [FAILED]
   ↓
Pipeline Halts (Image push and GitOps updates skipped)
```

---

## 💥 Failure Injection

Introduce a typo inside `docker/Dockerfile` by changing the suffix of `requirements.txt`:

### ❌ Broken Dockerfile (docker/Dockerfile)
```dockerfile
FROM python:3.9-slim AS builder
WORKDIR /build

# Inject typo by renaming file name target
COPY app/requirements.tx .

RUN pip install --no-cache-dir --user -r requirements.txt
```

---

## 🔍 Log Analysis & Investigation

The docker daemon returns a missing file reference error during the copy phase:

### 📝 Expected Docker Build Failure Log
```text
[internal] load build context
transferring context: 2.12kB done
[builder 1/3] FROM docker.io/library/python:3.9-slim@sha256:7b1a20...
[builder 2/3] WORKDIR /build
[builder 3/3] COPY app/requirements.tx .
ERROR: failed to solve: failed to compute cache key: failed to walk /var/lib/docker/tmp/buildkit-mount302914/app: lstat /var/lib/docker/tmp/buildkit-mount302914/app/requirements.tx: no such file or directory
Error: Process completed with exit code 1.
```

### 🛠️ Debugging Commands
To troubleshoot and test the image build process locally from the `Exercise-23` directory:
```bash
# Build the image locally specifying the file path
docker build -f docker/Dockerfile -t test-flask-app .
```

---

## 💡 Root Cause Analysis

* **Error Identification:** Docker returns `lstat ... app/requirements.tx: no such file or directory`.
* **Problem:** The `COPY` command points to `app/requirements.tx` (which does not exist). The target workspace folder contains `app/requirements.txt`.

---

## 🛠️ Recovery & Fix

Correct the target file name target within the `COPY` instruction to restore successful builds.

###  Fixed Dockerfile (docker/Dockerfile)
```dockerfile
FROM python:3.9-slim AS builder
WORKDIR /build

# Restored correct filename
COPY app/requirements.txt .

RUN pip install --no-cache-dir --user -r requirements.txt
```

### 🔄 Recovery Steps
Push the corrected Dockerfile configuration to trigger a clean pipeline execution:
```bash
git add docker/Dockerfile
git commit -m "Fix Dockerfile: correct copy path for requirements"
git push origin main
```

### 🚀 Success Validation Log
```text
Sending build context to Docker daemon  14.34kB
Step 1/13 : FROM python:3.9-slim AS builder
 ---> 8b3bc1b6932e
Step 2/13 : WORKDIR /build
 ---> Running in b5a0e0c031d2
 ---> Removed intermediate container b5a0e0c031d2
 ---> ce126830cb85
Step 3/13 : COPY app/requirements.txt .
 ---> Running in 7289ca582eb7
 ---> Removed intermediate container 7289ca582eb7
 ---> fd97c9b0e12d
Step 4/13 : RUN pip install --no-cache-dir --user -r requirements.txt
 ---> Running in a1b827e8a9bc
...
Successfully built fd97c9b0e12d
Successfully tagged test-flask-app:latest
```
Build runs successfully and proceeds to the image push stage.
