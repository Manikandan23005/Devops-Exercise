# Exercise 2 – IAM / IRSA Failure Investigation

## Objective

Investigate why an application running inside Kubernetes cannot access DynamoDB even though IAM Roles for Service Accounts (IRSA) is configured.

---

## Scenario

### Incident

The application suddenly loses access to DynamoDB.

### Application Logs

```text
2026-05-10T08:12:13Z ERROR

botocore.exceptions.ClientError:
An error occurred (AccessDeniedException)
when calling the GetItem operation:

User:
arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role

is not authorized to perform:
dynamodb:GetItem

on resource:
arn:aws:dynamodb:ap-south-1:123456789012:table/customer-data
```

---

## Architecture

```text
Pod
 ↓
ServiceAccount
 ↓
IAM Role (IRSA)
 ↓
DynamoDB
```

Expected Behavior:

```text
Pod
 ↓
ServiceAccount
 ↓
IRSA Role
 ↓
STS AssumeRoleWithWebIdentity
 ↓
Temporary Credentials
 ↓
DynamoDB
```

Actual Behavior:

```text
Pod
 ↓
Node IAM Role
 ↓
DynamoDB
```

---

# Investigation

## Step 1: Identify Which IAM Role Is Being Used

The error message shows:

```text
arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role
```

This indicates that the pod is using the worker node IAM role instead of the IRSA role.

---

## Step 2: Verify Service Account Assignment

Check the pod configuration:

```bash
kubectl get pod payment-service -o yaml
```

Look for:

```yaml
serviceAccountName: payment-sa
```

Incorrect Example:

```yaml
serviceAccountName: default
```

If the default service account is used, IRSA will not work.

---

## Step 3: Verify Service Account Annotation

Check the Service Account:

```bash
kubectl get sa payment-sa -o yaml
```

Expected Output:

```yaml
apiVersion: v1
kind: ServiceAccount

metadata:
  name: payment-sa

  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/payment-irsa-role
```

If the annotation is missing, the pod cannot assume the IAM role.

---

## Step 4: Verify OIDC Provider

IRSA requires an OIDC provider.

Check EKS OIDC issuer:

```bash
aws eks describe-cluster \
--name mycluster \
--query cluster.identity.oidc.issuer
```

List IAM OIDC providers:

```bash
aws iam list-open-id-connect-providers
```

If the cluster OIDC provider does not exist in IAM, IRSA cannot function.

---

## Step 5: Verify IAM Trust Policy

Retrieve the IAM role:

```bash
aws iam get-role \
--role-name payment-irsa-role
```

Expected Trust Relationship:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/<OIDC_PROVIDER>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity"
    }
  ]
}
```

Missing or incorrect trust relationships prevent role assumption.

---

## Step 6: Verify Credentials Inside Pod

Enter the container:

```bash
kubectl exec -it payment-service -- sh
```

Run:

```bash
aws sts get-caller-identity
```

### Incorrect Result

```text
arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role
```

### Correct Result

```text
arn:aws:sts::123456789012:assumed-role/payment-irsa-role
```

---

# Root Cause Analysis (RCA)

### Evidence

Application logs show:

```text
assumed-role/eks-nodegroup-role
```

### Conclusion

The application is using the worker node IAM role rather than the intended IRSA role.

### Possible Causes

* Service Account not specified in deployment
* Service Account annotation missing
* OIDC provider not configured
* Incorrect IAM trust policy
* Pod not restarted after Service Account modification

---

# Fix

## Create Service Account

```yaml
apiVersion: v1
kind: ServiceAccount

metadata:
  name: payment-sa

  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/payment-irsa-role
```

---

## Update Deployment

```yaml
spec:
  serviceAccountName: payment-sa
```

---

## Restart Deployment

```bash
kubectl rollout restart deployment payment-service
```

---

## Verify

```bash
kubectl exec -it payment-service -- \
aws sts get-caller-identity
```

Expected:

```text
payment-irsa-role
```

---

# Key Concepts Learned

## What is IRSA?

IRSA (IAM Roles for Service Accounts) allows Kubernetes pods to access AWS services without storing AWS access keys.

---

## Why Does IRSA Use OIDC?

OIDC provides identity federation between Kubernetes Service Accounts and AWS IAM.

---

## Why Is sts Required?

AWS Security Token Service (STS) uses the Service Account token to generate temporary AWS credentials.

---

## Why Is Using the Node Role Dangerous?

If pods use the node role:

* Every pod inherits the same permissions.
* Violates least-privilege principles.
* Increases security risk.

IRSA provides pod-level IAM permissions.

---

# Validation Checklist

* [ ] Service Account created
* [ ] IAM Role created
* [ ] OIDC provider configured
* [ ] Trust policy verified
* [ ] Deployment uses correct Service Account
* [ ] Pod restarted
* [ ] `aws sts get-caller-identity` returns IRSA role
* [ ] DynamoDB access restored

---

# Commands Summary

```bash
kubectl get pod payment-service -o yaml

kubectl get sa payment-sa -o yaml

aws eks describe-cluster \
--name mycluster \
--query cluster.identity.oidc.issuer

aws iam list-open-id-connect-providers

aws iam get-role \
--role-name payment-irsa-role

kubectl exec -it payment-service -- \
aws sts get-caller-identity

kubectl rollout restart deployment payment-service
```
