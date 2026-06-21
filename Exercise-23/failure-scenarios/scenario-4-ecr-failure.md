# Scenario 4: AWS ECR Push Failure

This scenario demonstrates a failure in the **AWS ECR Login/Push** stage of the pipeline caused by incorrect or expired authentication tokens configured in GitHub Secrets.

---

## 🎯 Pipeline Stage Behaviour

When executing the registry authentication phase, the credentials verify triggers an authorization error:
```text
Git Push
   ↓
Unit Tests ✅ [PASSED]
   ↓
Bandit Scan ✅ [PASSED]
   ↓
Docker Build ✅ [PASSED]
   ↓
Login to Amazon ECR ❌ [FAILED]
   ↓
Pipeline Halts (Image push and GitOps commits are aborted)
```

---

## 💥 Failure Injection

To simulate this failure:
1. Open the GitHub repository settings.
2. Go to **Settings > Secrets and variables > Actions**.
3. Modify the value of `AWS_SECRET_ACCESS_KEY` to an invalid string (e.g. `invalid-secret-key-456`) or configure a typo in the secret name itself.

---

## 🔍 Log Analysis & Investigation

The checkout run returns authorization denial logs:

### 📝 Expected ECR Login Failure Log
```text
Run aws-actions/configure-aws-credentials@v4
Error: Could not load credentials from any providers.
Error: Credentials invalid: The security token included in the request is invalid.
Error: Process completed with exit code 1.
```
If the credentials configure correctly but the ECR policy denies access:
```text
Run aws-actions/amazon-ecr-login@v2
Error: An error occurred (AccessDeniedException) when calling the GetAuthorizationToken operation: User: arn:aws:iam::123456789012:user/github-actions-bot is not authorized to perform: ecr:GetAuthorizationToken on resource: *
Error: Process completed with exit code 1.
```

### 🛠️ Debugging Commands
To verify your AWS CLI credential configuration and permission profiles locally:
```bash
# 1. Inspect active user entity details
aws sts get-caller-identity

# 2. Test fetching docker authorization token directly
aws ecr get-login-password --region us-east-1
```

---

## 💡 Root Cause Analysis

* **Error Identification:** AWS API response `The security token included in the request is invalid` or `AccessDeniedException`.
* **Problem:** 
  1. The API secrets loaded inside the pipeline environment do not match active IAM configuration credentials on AWS.
  2. The IAM User associated with the credentials lacks the IAM permission policy to read or write to Amazon ECR (`ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`).

---

## 🛠️ Recovery & Fix

### 🔐 Required GitHub Secrets Configuration
Ensure the following variables are configured under **Settings > Secrets and variables > Actions > Repository secrets**:

* `AWS_ACCESS_KEY_ID`: Your IAM user access key ID.
* `AWS_SECRET_ACCESS_KEY`: Your IAM user secret access key.
* `AWS_REGION`: The target AWS region (e.g. `us-east-1`).
* `ECR_REPOSITORY`: The name of the target ECR repository (e.g. `flask-app`).
* `AWS_ACCOUNT_ID`: The AWS Account ID hosting the registry (e.g. `123456789012`).

### 🔄 Recovery Steps
1. Navigate to **Repository Settings > Secrets > Actions** in GitHub.
2. Edit `AWS_SECRET_ACCESS_KEY` and input the correct active secret access key.
3. Open the failing workflow run in GitHub Actions.
4. Click **Re-run jobs > Re-run failed jobs** to trigger retry logic.

### 🚀 Success Validation Log
```text
Run aws-actions/configure-aws-credentials@v4
AWS Credentials configured successfully.
Active Role / Identity: arn:aws:iam::123456789012:user/github-actions-bot

Run aws-actions/amazon-ecr-login@v2
Logged into Amazon ECR Registry: 123456789012.dkr.ecr.us-east-1.amazonaws.com
Registry URL: 123456789012.dkr.ecr.us-east-1.amazonaws.com
```
The registry logins successfully and image upload proceeds.
