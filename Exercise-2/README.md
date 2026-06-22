# Exercise-02: IAM / IRSA Failure Investigation

## Incident Story

A production application running inside EKS suddenly loses access to DynamoDB.

Developers report:
> "No deployment was done. The application was working yesterday. Today all DynamoDB reads are failing."

Application logs:
```text
2026-05-10T08:12:13Z ERROR

botocore.exceptions.ClientError:
An error occurred (AccessDeniedException) when calling the GetItem operation:
User: arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role is not authorized to perform: dynamodb:GetItem on resource: arn:aws:dynamodb:ap-south-1:123456789012:table/customer-data
```

---

## Learning Objectives

After solving this exercise, you should understand:
* IAM Roles for Service Accounts (IRSA)
* EKS OIDC Provider
* ServiceAccount annotations
* Pod IAM credential flow
* Difference between Node IAM Role and IRSA Role
* How AWS SDK gets credentials inside Kubernetes Pods

---

## Environment Setup

The playground simulates a production-grade EKS cluster in the `ap-south-1` region with the following components:

1. **EKS Cluster**: `production-eks` (ap-south-1)
2. **Worker Nodes Role**: `eks-nodegroup-role` (does *not* have DynamoDB read/write permissions)
3. **DynamoDB Table**: `customer-data`
4. **IAM Role for IRSA**: `customer-app-irsa-role` (with policy allowing `dynamodb:GetItem` and `dynamodb:PutItem`)
5. **Kubernetes Namespace**: `customer-app`
6. **ServiceAccount**: `customer-sa`
7. **Deployment**: `customer-api`

### Directory Structure
```text
Exercise-2/
├── README.md
├── hands-on/
│   ├── namespace.yaml
│   ├── serviceaccount.yaml      ← Active IRSA annotation config
│   └── deployment.yaml          ← customer-api deployment running get-item loop
├── broken-state/
│   └── serviceaccount.yaml      ← Simulates the failure state (missing annotation)
└── terraform/
    └── main.tf                  ← Infrastructure definition
```

---

## Architecture Flow

### Expected Behavior (With IRSA Annotation)
```text
1) K8s Deployment in Namespace with ServiceAccount: The Pod runs in the namespace (e.g., customer-app) using customer-sa.
2) IRSA (IAM Roles for Service Accounts): The ServiceAccount has an annotation linking it to a specific AWS IAM Role ARN: eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/customer-app-irsa-role
3) EKS OIDC (OpenID Connect): EKS acts as an OIDC Identity Provider. It creates a cryptographically signed web identity token (JWT) for the ServiceAccount and mounts it into the Pod.
4) AWS STS (Security Token Service): (Crucial middleman) The AWS SDK inside the Pod takes the OIDC token and calls AWS STS using AssumeRoleWithWebIdentity. AWS checks the IAM Role's trust policy to verify it trust the EKS OIDC provider and the specific ServiceAccount name.
5) DynamoDB: STS returns temporary credentials to the Pod, which the application uses to access the DynamoDB table.
```

### Actual Behavior (Broken State / Without Annotation)
```text
1. Pod (customer-api): The pod is running in the namespace and using the customer-sa ServiceAccount.
2. Missing Annotation: The customer-sa ServiceAccount lacks the critical eks.amazonaws.com/role-arn annotation. Because this annotation is missing, the IRSA mechanism is not triggered.
3. EKS Webhook: The EKS Pod Identity Webhook fails to inject the necessary configuration (like AWS_ROLE_ARN and the OIDC token file) into the Pod's environment.
4. AWS SDK Fallback: The AWS SDK inside the customer-api container automatically falls back to using the credentials of the underlying EC2 worker node.
5. Node IAM Role: The worker node is attached to the 'eks-nodegroup-role', which does not have permissions to access the DynamoDB table.
6. DynamoDB Access Denied: The SDK attempts to perform an operation (e.g., GetItem) on the DynamoDB table using the node's IAM role, resulting in an AccessDeniedException.
```

AWS SDK automatically falls back to node credentials if pod-level IRSA is not configured properly.

---

## Investigation Steps

### Step 1: Check Pod Status & Log Output
Confirm that the deployment and pods appear healthy on the cluster:
```bash
kubectl get pods -n customer-app
kubectl get deploy -n customer-app
```
Then, inspect the logs of the running pod:
```bash
kubectl logs -n customer-app deployment/customer-api
```
**Observation**: You find `AccessDeniedException` logs. The API request caller is identified as: `User: arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role`.
This is a critical clue: the pod is using the host node's IAM role instead of the specific IRSA role.

---

### Step 2: Verify the Deployment ServiceAccount
Check that the deployment is correctly configured to use the custom ServiceAccount:
```bash
kubectl get deployment customer-api -n customer-app -o yaml | grep serviceAccountName
```
**Expected**:
```yaml
serviceAccountName: customer-sa
```
If the deployment uses `default` or another ServiceAccount, it will not fetch the intended role.

---

### Step 3: Check the ServiceAccount Annotations
Inspect the metadata and annotations on the `customer-sa` ServiceAccount:
```bash
kubectl get sa customer-sa -n customer-app -o yaml
```
**Observation**:
```yaml
metadata:
  annotations: null
```
(or empty annotations `{}`). The required `eks.amazonaws.com/role-arn` annotation is missing from the ServiceAccount.

---

### Step 4: Verify the Pod Environment Variables
Look inside the active pod container's environment variables for AWS token settings:
```bash
kubectl exec -it deployment/customer-api -n customer-app -- env | grep AWS
```
**Observation**:
You will see that `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` are **missing**.
When IRSA is fully active, the EKS Pod Identity Webhook automatically injects these variables and mounts the token volume. Their absence confirms that the webhook did not process the pod because the ServiceAccount annotation was missing.

---

## Root Cause Analysis (RCA)

* **Direct Cause**: The `eks.amazonaws.com/role-arn` annotation was removed or missing from the `customer-sa` ServiceAccount.
* **Mechanism**: Without the annotation, the EKS Pod Identity Webhook did not inject the OIDC token volume and AWS role environment variables into the `customer-api` pods.
* **SDK Fallback**: The AWS SDK inside the container fell back to the EC2 Instance Metadata Service (IMDS) credentials, assuming the node group's IAM role (`eks-nodegroup-role`).
* **Failure**: The worker node role lacks permissions to read the DynamoDB table `customer-data`, resulting in `AccessDeniedException`.

---

## Recovery & Fix

### 1. Re-add the Annotation to the ServiceAccount
Add the annotation using `kubectl annotate` (or apply the manifest from `hands-on/serviceaccount.yaml`):
```bash
kubectl annotate serviceaccount customer-sa \
  -n customer-app \
  eks.amazonaws.com/role-arn=arn:aws:iam::123456789012:role/customer-app-irsa-role \
  --overwrite
```

### 2. Rollout Restart the Deployment
Since Kubernetes pods do not dynamically load environment changes from ServiceAccount configuration updates, you must restart the pods:
```bash
kubectl rollout restart deployment customer-api -n customer-app
```

### 3. Verify the Resolution
Check the ServiceAccount:
```bash
kubectl get sa customer-sa -n customer-app -o yaml
```
Ensure the annotation is present:
```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/customer-app-irsa-role
```

Check the pod logs:
```bash
kubectl logs -n customer-app -f deployment/customer-api
```
Ensure the DynamoDB item retrieve requests are succeeding without authorization failures.

---

## Interview Questions Covered

1. **What is IAM Roles for Service Accounts (IRSA) in AWS EKS?**
   It is a feature that allows you to map a Kubernetes ServiceAccount to an AWS IAM Role. Pods using that ServiceAccount are granted the permissions of the IAM Role via OIDC identity federation.

2. **Why did the application pod fall back to using the worker node IAM role?**
   When the ServiceAccount lacks the necessary IRSA annotations, the Kubernetes Pod Identity Webhook does not inject the required AWS credentials (OIDC token and role ARN) into the pod. Consequently, the AWS SDK within the application falls back to using the default credentials from the environment, which in this case were the EC2 instance metadata service (IMDS) credentials of the worker node.

3. **What are the key components involved in an IRSA authentication flow?**
   * **EKS Cluster**: Provides the OIDC Identity Provider.
   * **ServiceAccount**: The Kubernetes resource that represents the application's identity within the cluster.
   * **ServiceAccount Annotation**: The `eks.amazonaws.com/role-arn` annotation on the ServiceAccount, which links it to the AWS IAM Role.
   * **EKS Pod Identity Webhook**: A mutating webhook that injects the OIDC token and environment variables into the Pod.
   * **OIDC Token**: A JSON Web Token (JWT) issued by the EKS OIDC provider, cryptographically signed and unique to the ServiceAccount.
   * **AWS STS (Security Token Service)**: Used for the `AssumeRoleWithWebIdentity` operation to exchange the OIDC token for temporary AWS credentials.
   * **IAM Role Trust Policy**: A policy on the IAM Role that trusts the EKS OIDC provider and the specific ServiceAccount.

4. **How do you verify that IRSA is correctly configured for a pod?**
   * Check that the ServiceAccount has the `eks.amazonaws.com/role-arn` annotation.
   * Verify that the EKS Pod Identity Webhook is running (`kubectl get pods -n kube-system | grep -i webhook`).
   * Inspect the pod's environment variables for `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`.
   * Check that the `serviceAccountToken.expiration
  ↓ [No Web Identity Token injected]
Node Metadata Service (IMDS)
  ↓
Node IAM Role (eks-nodegroup-role)
  ↓ [Fails authorization: No dynamodb:GetItem permission]
DynamoDB (customer-data) ❌ AccessDenied
```

AWS SDK automatically falls back to node credentials if pod-level IRSA is not configured properly.

---

## Investigation Steps

### Step 1: Check Pod Status & Log Output
Confirm that the deployment and pods appear healthy on the cluster:
```bash
kubectl get pods -n customer-app
kubectl get deploy -n customer-app
```
Then, inspect the logs of the running pod:
```bash
kubectl logs -n customer-app deployment/customer-api
```
**Observation**:
You find `AccessDeniedException` logs. The API request caller is identified as:
`User: arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role`
This is a critical clue: the pod is using the host node's IAM role instead of the specific IRSA role.

---

### Step 2: Verify the Deployment ServiceAccount
Check that the deployment is correctly configured to use the custom ServiceAccount:
```bash
kubectl get deployment customer-api -n customer-app -o yaml | grep serviceAccountName
```
**Expected**:
```yaml
serviceAccountName: customer-sa
```
If the deployment uses `default` or another ServiceAccount, it will not fetch the intended role.

---

### Step 3: Check the ServiceAccount Annotations
Inspect the metadata and annotations on the `customer-sa` ServiceAccount:
```bash
kubectl get sa customer-sa -n customer-app -o yaml
```
**Observation**:
```yaml
metadata:
  annotations: null
```
(or empty annotations `{}`). The required `eks.amazonaws.com/role-arn` annotation is missing from the ServiceAccount.

---

### Step 4: Verify the Pod Environment Variables
Look inside the active pod container's environment variables for AWS token settings:
```bash
kubectl exec -it deployment/customer-api -n customer-app -- env | grep AWS
```
**Observation**:
You will see that `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` are **missing**.
When IRSA is fully active, the EKS Pod Identity Webhook automatically injects these variables and mounts the token volume. Their absence confirms that the webhook did not process the pod because the ServiceAccount annotation was missing.

---

## Root Cause Analysis (RCA)

* **Direct Cause**: The `eks.amazonaws.com/role-arn` annotation was removed or missing from the `customer-sa` ServiceAccount.
* **Mechanism**: Without the annotation, the EKS Pod Identity Webhook did not inject the OIDC token volume and AWS role environment variables into the `customer-api` pods.
* **SDK Fallback**: The AWS SDK inside the container fell back to the EC2 Instance Metadata Service (IMDS) credentials, assuming the node group's IAM role (`eks-nodegroup-role`).
* **Failure**: The worker node role lacks permissions to read the DynamoDB table `customer-data`, resulting in `AccessDeniedException`.

---

## Recovery & Fix

### 1. Re-add the Annotation to the ServiceAccount
Add the annotation using `kubectl annotate` (or apply the manifest from `hands-on/serviceaccount.yaml`):
```bash
kubectl annotate serviceaccount customer-sa \
  -n customer-app \
  eks.amazonaws.com/role-arn=arn:aws:iam::123456789012:role/customer-app-irsa-role \
  --overwrite
```

### 2. Rollout Restart the Deployment
Since Kubernetes pods do not dynamically load environment changes from ServiceAccount configuration updates, you must restart the pods:
```bash
kubectl rollout restart deployment customer-api -n customer-app
```

### 3. Verify the Resolution
Check the ServiceAccount:
```bash
kubectl get sa customer-sa -n customer-app -o yaml
```
Ensure the annotation is present:
```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/customer-app-irsa-role
```

Check the pod logs:
```bash
kubectl logs -n customer-app -f deployment/customer-api
```
Ensure the DynamoDB item retrieve requests are succeeding without authorization failures.

---

## Interview Questions Covered

1. **What is IAM Roles for Service Accounts (IRSA) in AWS EKS?**
   It is a feature that allows you to map a Kubernetes ServiceAccount to an AWS IAM Role. Pods using that ServiceAccount are granted the permissions of the IAM Role via OIDC identity federation.

2. **Why did the application pod fall back to using the worker node IAM role?**
   When the IRSA annotation is missing, the EKS Webhook does not inject the token or the role ARN variables. The AWS SDK defaults to its standard provider chain, which queries the EC2 IMDS endpoint, thus inheriting the node's IAM role.

3. **What is the security risk of pods inheriting node-level credentials?**
   It violates the principle of least privilege. If any pod on a node can access services using the node role, a compromise of one container could expose access to any AWS services the node role permits.

4. **Why do we need to restart the deployment pods after annotating a ServiceAccount?**
   The Pod Identity Webhook only injects the token volume mounts and environment variables during the Pod *creation* phase (admission controller). Modifying an existing ServiceAccount does not automatically update already running pods.
