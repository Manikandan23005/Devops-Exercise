# Scenario 5: GitOps Repository Update Failure

This scenario demonstrates a failure in the **GitOps Manifest Update** stage of the pipeline caused by expired or incorrectly scoped GitHub Personal Access Tokens (PAT).

---

## 🎯 Pipeline Stage Behaviour

When the runner attempts to push the updated deployment image tag to the GitOps configuration store, authorization is rejected:
```text
Git Push
   ↓
Unit Tests ✅ [PASSED]
   ↓
Bandit Scan ✅ [PASSED]
   ↓
Docker Build ✅ [PASSED]
   ↓
ECR Push ✅ [PASSED]
   ↓
Update GitOps Repository ❌ [FAILED]
   ↓
Pipeline Halts (ArgoCD Auto Sync is not triggered)
```

---

## 💥 Failure Injection

To simulate this failure:
1. Open the GitHub repository settings.
2. Go to **Settings > Secrets and variables > Actions**.
3. Modify the value of `GITOPS_TOKEN` to an invalid or expired token string, or delete the secret entirely.

---

## 🔍 Log Analysis & Investigation

The workflow run returns git credentials verification failures:

### 📝 Expected Git Push Failure Log
```text
Run git remote set-url origin https://x-access-token:${{ secrets.GITOPS_TOKEN }}@github.com/...
Run git push origin main
fatal: Authentication failed for 'https://github.com/Manikandan23005/Devops-Exercise.git/'
remote: Invalid username or password.
Error: Process completed with exit code 128.
```
If the token is valid but lacks write permissions on the target repository:
```text
remote: Permission to Manikandan23005/Devops-Exercise.git denied to github-actions[bot].
fatal: unable to access 'https://github.com/Manikandan23005/Devops-Exercise.git/': The requested URL returned error: 403
Error: Process completed with exit code 128.
```

### 🛠️ Debugging Commands
To verify the token's validity and check permissions locally:
```bash
# Attempt to clone using the token directly (replace vars accordingly)
git clone https://<GITOPS_TOKEN_VALUE>@github.com/Manikandan23005/Devops-Exercise.git temp-dir/
```

---

## 💡 Root Cause Analysis

* **Error Identification:** Git returns `fatal: Authentication failed` (HTTP 401) or `The requested URL returned error: 403` (HTTP 403).
* **Problem:** 
  1. The Personal Access Token stored in `GITOPS_TOKEN` has expired (standard expiration limit reached).
  2. The PAT lacks the required access scope permissions to push changes back to the codebase.

---

## 🛠️ Recovery & Fix

### 🔑 Step-by-Step GitHub Token Generation
To generate a functional, correctly scoped Personal Access Token:

1. Log in to GitHub.
2. Go to **Settings > Developer settings > Personal access tokens > Tokens (classic)**.
3. Click **Generate new token > Generate new token (classic)**.
4. Set a descriptive name (e.g. `GitOps Pipeline Token`).
5. Select scopes:
   * **`repo`** (Full control of private repositories)
   * **`write:packages`** (Optional, if using package registry)
   * **`admin:repo_hook`** (Optional)
6. Scroll to the bottom and click **Generate token**.
7. **Copy** the token immediately (it will not be shown again).

### 🔄 Recovery Steps
1. Navigate to your repository page in GitHub.
2. Select **Settings > Secrets and variables > Actions**.
3. Under **Repository Secrets**, find `GITOPS_TOKEN` and click edit (or click new secret).
4. Paste the copied token and click update.
5. In GitHub Actions, navigate to the failed run and click **Re-run failed jobs**.

### 🚀 Success Validation Log
```text
Run git push origin main
Active URL: https://x-access-token:***@github.com/Manikandan23005/Devops-Exercise.git
To https://github.com/Manikandan23005/Devops-Exercise.git
   d8e05c2..a6e35d1  main -> main
   
# Manifest committed and pushed successfully. 
# ArgoCD sync gets automatically triggered.
```
The pipeline push completes, and ArgoCD starts syncing the updated image.
