# Exercise 24: DynamoDB Application Deployment (IRSA)

This exercise demonstrates the deployment of a Python Flask microservice to Amazon EKS that performs CRUD (Create, Read, Update) operations on an Amazon DynamoDB table. 

Crucially, **no static AWS Access Keys, Secrets, or credential environment variables are used**. Authentication is handled entirely through EKS **IAM Roles for Service Accounts (IRSA)** utilizing the AWS SDK (`boto3`) Default Credential Chain.

---

## Folder Structure

```text
Exercise-24/
├── README.md
├── architecture-diagram.md
├── manifests/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── serviceaccount.yaml
├── terraform/
│   ├── dynamodb-table.tf
│   └── irsa.tf
└── scripts/
    ├── app/
    │   ├── app.py
    │   ├── Dockerfile
    │   └── requirements.txt
    ├── create-table.sh
    ├── test-api.sh
    └── validation/
        └── verify-db.sh
```

---

## Technical Specifications

* **Terraform Version**: `>= 1.0` (compatible with `~> 5.0` AWS Provider)
* **Helm Version**: `v3.x`
* **Python Version**: `3.11` (Alpine base)
* **Boto3 SDK**: `1.34.x`

---

## Deployment Steps

### Prerequisite
Verify connection to EKS cluster `production-eks` in region `ap-south-1`.

### Step 1: Provision Infrastructure via Terraform
Apply Terraform to create the DynamoDB table and IAM Role/Policy/Trust Relationship:
```bash
cd terraform
terraform init
terraform apply -auto-approve
```
*Note: This generates the Role ARN `arn:aws:iam::028987315631:role/exercise24-customer-role`. Make sure the annotation in `manifests/serviceaccount.yaml` matches this ARN.*

### Step 2: Deploy Kubernetes Resources
Apply the Kubernetes manifests:
```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/serviceaccount.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
```

Verify that the application pods are running and healthy:
```bash
kubectl rollout status deployment/customer-app -n exercise24
```

---

## Verification & API Testing

Run the automated integration tests:
```bash
./scripts/test-api.sh
```
This script performs the following validation steps:

### 1. Verify STS AssumeRole (IRSA Verification)
Runs `aws sts get-caller-identity` from within the application container to verify that the projected web identity is assumed correctly:
```bash
kubectl exec -it <POD_NAME> -n exercise24 -c app -- python -c "
import boto3
sts = boto3.client('sts')
print(sts.get_caller_identity()['Arn'])
"
# Expected Output: arn:aws:sts::028987315631:assumed-role/exercise24-customer-role/<session-id>
```

### 2. Create a Customer (Write)
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"id": "c101", "name": "Manikandan", "email": "mani@example.com", "phone": "123456789"}' \
  http://localhost:5000/customer
```

### 3. Read Customer Details (Read)
```bash
curl http://localhost:5000/customer/c101
```

### 4. Update Customer Details (Update)
```bash
curl -X PUT -H "Content-Type: application/json" \
  -d '{"name": "Mani Satoru", "email": "satoru@example.com"}' \
  http://localhost:5000/customer/c101
```

### 5. Check Table items via AWS CLI
```bash
./validation/verify-db.sh
```

---

## Production Best Practices

1. **Least Privilege Policies**:
   The IAM policy is strictly scoped down. It only allows `GetItem`, `PutItem`, and `UpdateItem` actions. It explicitly denies broad administrative actions like `DeleteTable` or `CreateTable` and targets only the specific ARN of the `exercise24-customers` table.
2. **SDK Connections Pooling**:
   In production, instantiate `boto3` client connections at the global application context (as done in `app.py`) to reuse TCP connections across REST requests, reducing latency.
3. **App Readiness and Liveness Probes**:
   The application deployment specifies Kubernetes probes to guarantee traffic is only routed to pods once Flask and boto3 clients are initialized.

## Security Considerations
* **Web Identity Token Projection**:
  Token projection limits token exposure. Temporary AWS credentials expire after 1 hour and are rotated automatically, significantly reducing the blast radius in the event of a pod compromise.
* **No Hardcoded Credentials**:
  The application uses the default AWS credential chain which finds the token file injected by the EKS control plane automatically. No secrets are stored in git repositories or environment variables.

## Cost Considerations
* **DynamoDB Billing Mode**:
  Using `PAY_PER_REQUEST` (On-Demand billing) ensures we only pay for the exact read/write request units consumed, saving up to 90% in costs compared to Provisioned Capacity for workloads with variable traffic.
* **Region Affinity**:
  Deploying the EKS cluster and the DynamoDB table in the same region (`ap-south-1`) eliminates cross-region data transfer fees.

---

## Troubleshooting Guide

### 1. Pod logs show AccessDeniedException
Check if the ServiceAccount name and namespace in the trust relationship match your deployment:
```json
"StringEquals": {
  "oidc.eks.ap-south-1.amazonaws.com/id/86D6B434F29852D47A1FD1563AB52058:sub": "system:serviceaccount:exercise24:customer-sa"
}
```
If there is a mismatch (e.g. namespace is `default` or ServiceAccount name is wrong), AWS STS will reject the request.

### 2. Credentials endpoint returns 404 or boto3 client fails to load credentials
Ensure that the ServiceAccount is bound to the pod using `serviceAccountName: customer-sa` in the pod spec. Verify that the env vars `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` are actually present inside the running pod container:
```bash
kubectl exec -it <POD_NAME> -n exercise24 -- env | grep AWS
```

---

## Cleanup
To destroy the deployed infrastructure:
```bash
kubectl delete -f manifests/service.yaml
kubectl delete -f manifests/deployment.yaml
kubectl delete -f manifests/serviceaccount.yaml
kubectl delete -f manifests/namespace.yaml

cd terraform
terraform destroy -auto-approve
```
