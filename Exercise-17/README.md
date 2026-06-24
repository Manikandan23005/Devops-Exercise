# Exercise 17: Production Implementation of IRSA

This exercise demonstrates the production setup of IAM Roles for Service Accounts (IRSA) on AWS EKS to grant fine-grained permissions to a Kubernetes Pod. Specifically, it enables a pod to read and write to an Amazon DynamoDB table without using static AWS Access Keys or Secrets.

## Architecture

```text
DynamoDB (exercise17-users)
    ^
    | (Fine-grained access)
IAM Policy (Exercise17DynamoDBPolicy)
    ^
    | (Attached to Role)
IAM Role (Exercise17DynamoDBRole)
    ^
    | (sts:AssumeRoleWithWebIdentity)
IRSA Annotation (eks.amazonaws.com/role-arn)
    ^
    | (Mutates Pod env/volumes)
ServiceAccount (dynamodb-sa in namespace exercise17)
    ^
    | (Assigned to)
Application Pod (dynamodb-test)
    ^
    | (Running in)
EKS Cluster (production-eks in ap-south-1)
```

No AWS access keys or secrets are stored in the cluster or image. The AWS SDK/CLI automatically assumes the target role using the projected OIDC web identity token.

---

## Configurations

### 1. IAM Configurations

* **IAM Policy** (`iam/dynamodb-policy.json`): Allows DynamoDB GetItem, PutItem, and UpdateItem on the `exercise17-users` table.
* **IAM Trust Policy** (`iam/trust-policy.json`): Allows the EKS cluster's OIDC provider to assume the `Exercise17DynamoDBRole` role when requested by the `dynamodb-sa` ServiceAccount in the `exercise17` namespace.

### 2. Kubernetes configurations

* **Namespace** (`k8s/namespace.yaml`): Creates the `exercise17` namespace.
* **ServiceAccount** (`k8s/serviceaccount.yaml`): Creates the `dynamodb-sa` service account, annotated with the IAM Role ARN.
* **Pod** (`k8s/pod.yaml`): Runs the test container (using the `amazon/aws-cli` image) attached to `dynamodb-sa`.

---

## Deployment Steps

### Step 1: Verify EKS Cluster and OIDC Provider
Confirm the EKS cluster (`production-eks`) is active and check the OpenID Connect issuer URL:
```bash
aws eks describe-cluster \
  --name production-eks \
  --query "cluster.identity.oidc.issuer" \
  --output text
```
Ensure this OIDC issuer is added as an OpenID Connect Provider in AWS IAM.
![AWS OIDC Provider Settings](screenshots/oidc-provider.png)

### Step 2: Create Namespace
```bash
kubectl apply -f k8s/namespace.yaml
```

### Step 3: Create DynamoDB Table
Create the `exercise17-users` table in `ap-south-1` (same region as the EKS cluster):
```bash
aws dynamodb create-table \
  --table-name exercise17-users \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

### Step 4: Create IAM Policy
```bash
aws iam create-policy \
  --policy-name Exercise17DynamoDBPolicy \
  --policy-document file://iam/dynamodb-policy.json
```
![IAM Policy Settings](screenshots/iam-policy.png)

### Step 5: Create IAM Role and Trust Relationship
Ensure `iam/trust-policy.json` is updated with your correct AWS Account ID and OIDC ID:
```bash
aws iam create-role \
  --role-name Exercise17DynamoDBRole \
  --assume-role-policy-document file://iam/trust-policy.json
```
Attach the policy to the role:
```bash
aws iam attach-role-policy \
  --role-name Exercise17DynamoDBRole \
  --policy-arn arn:aws:iam::028987315631:policy/Exercise17DynamoDBPolicy
```
![IAM Role Configurations](screenshots/iam-role.png)

### Step 6: Apply Kubernetes Resources
Apply the ServiceAccount and Test Pod YAML configs:
```bash
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/pod.yaml
```
Verify the ServiceAccount annotation:
```bash
kubectl get sa dynamodb-sa -n exercise17 -o yaml
```
![ServiceAccount configuration](screenshots/serviceaccount.png)

---

## Verification & Testing

### 1. Verify STS AssumeRole
Exec into the pod and verify that `aws sts get-caller-identity` returns the assumed IRSA role rather than the underlying EC2 node's instance role:
```bash
kubectl exec -it dynamodb-test -n exercise17 -- aws sts get-caller-identity
```
Expected output shows the ARN of `Exercise17DynamoDBRole`:
![STS Caller Identity Result](screenshots/sts-identity.png)

### 2. PutItem
Insert a user item:
```bash
kubectl exec -it dynamodb-test -n exercise17 -- aws dynamodb put-item \
  --table-name exercise17-users \
  --item '{"id":{"S":"1"}, "name":{"S":"Manikandan"}}' \
  --region ap-south-1
```
![Put Item Result](screenshots/put-item.png)

### 3. GetItem
Retrieve the item:
```bash
kubectl exec -it dynamodb-test -n exercise17 -- aws dynamodb get-item \
  --table-name exercise17-users \
  --key '{"id":{"S":"1"}}' \
  --region ap-south-1
```
![Get Item Result](screenshots/get-item.png)

### 4. UpdateItem
Update the item:
```bash
kubectl exec -it dynamodb-test -n exercise17 -- aws dynamodb update-item \
  --table-name exercise17-users \
  --key '{"id":{"S":"1"}}' \
  --update-expression "SET #n = :v" \
  --expression-attribute-names '{"#n":"name"}' \
  --expression-attribute-values '{":v":{"S":"Satoru"}}' \
  --region ap-south-1
```
Verify the updated item:
```bash
kubectl exec -it dynamodb-test -n exercise17 -- aws dynamodb get-item \
  --table-name exercise17-users \
  --key '{"id":{"S":"1"}}' \
  --region ap-south-1
```
![Update and Get Item Result](screenshots/update-item.png)
