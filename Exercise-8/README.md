# Exercise 8 – Egress Restriction Incident

## 📋 Incident Overview
The application is reporting timeout errors when trying to connect to downstream AWS database services (DynamoDB).

* **Application Logs**: 
  ```text
  ERROR: Connection timeout when querying dynamodb.ap-south-1.amazonaws.com:443
  ```
* **Curl Test**: Running a manual curl request inside the application container also times out:
  ```bash
  kubectl exec -it <pod-name> -n egress-lab -- curl -I https://dynamodb.ap-south-1.amazonaws.com --connect-timeout 5
  ```
  *Expected Result*: `curl: (28) Connection timed out after 5001 milliseconds`

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure and trigger the simulation in your local cluster:

### 1. Deploy the namespace, application, and NetworkPolicy:
```bash
kubectl apply -f manifests/
```

### 2. Verify application connectivity timeout in logs:
```bash
kubectl logs -n egress-lab -l app=payment-app --tail=30
```
*Expected Output*: Displays continuous connection timeouts to AWS DynamoDB.

### 3. Run a manual network connection test:
Get the pod name and run a curl test to verify the timeout:
```bash
POD_NAME=$(kubectl get pods -n egress-lab -l app=payment-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -n egress-lab -- curl -I https://dynamodb.ap-south-1.amazonaws.com --connect-timeout 5
```
*Expected Output*: Returns a connection timeout error.

---

## 🔍 Step 2: Diagnostic Breakdown

To determine the root cause, we investigate the four core areas of egress network flow: **Network Policies**, **Security Groups**, **Route Tables**, and **VPC Endpoints**.

### 1. Security Groups? (Yes - Potential Cause in Cloud)
* **Explanation**: In AWS EKS, worker nodes run within EC2 security groups. If the egress rules of the node security group do not allow outbound traffic on port `443` (HTTPS) to the internet or to AWS public IP ranges, all calls to AWS APIs (like DynamoDB) will time out.

### 2. Route Tables & NAT Gateways? (Yes - Potential Cause in Cloud)
* **Explanation**: EKS worker nodes usually reside in private subnets. For these nodes to access public AWS endpoints (like DynamoDB), the private subnet's route table must route internet-bound traffic (`0.0.0.0/0`) to a **NAT Gateway** residing in a public subnet. If the NAT Gateway is deleted, has its elastic IP released, or the route entry is missing, connection timeouts will occur.

### 3. VPC Endpoints? (Yes - Best Practice Recommendation)
* **Explanation**: Instead of routing traffic through a NAT Gateway (which incurs data processing charges), AWS allows you to create a **VPC Gateway Endpoint** for DynamoDB. This routes traffic privately within the AWS network. If the VPC endpoint is misconfigured, has an restrictive endpoint policy, or is missing, traffic routes back to the NAT Gateway (which might be blocked).

### 4. Kubernetes Network Policies? (Yes - Root Cause in this Lab)
* **Reasoning**: A custom `NetworkPolicy` is applied to the namespace blocking egress.
* **Explanation**: Run the following command to check if any Kubernetes network policies are restricting traffic:
  ```bash
  kubectl get netpol -n egress-lab
  ```
  Describe the policy to see its rules:
  ```bash
  kubectl describe netpol deny-egress -n egress-lab
  ```
  *Expected Output*: Shows that all egress traffic is denied except to CoreDNS on port 53 (UDP/TCP). This prevents the pod from connecting to any external IPs.

---

## 🛠️ Step 3: Resolution & Remediation

To resolve the egress blockage:

### Option A: Allow Egress in Kubernetes (For this Lab)
Delete the blocking `NetworkPolicy` or patch it to allow egress to the DynamoDB address range:
```bash
kubectl delete netpol deny-egress -n egress-lab
```
After deleting the network policy, re-test connectivity to verify it is restored:
```bash
kubectl exec -it $POD_NAME -n egress-lab -- curl -I https://dynamodb.ap-south-1.amazonaws.com --connect-timeout 5
```

### Option B: Deploy an AWS VPC Gateway Endpoint for DynamoDB (Production Best Practice)
To enable private, secure, and cost-effective routing to DynamoDB inside AWS without going through the NAT Gateway:
1. Create a VPC Endpoint for DynamoDB using Terraform:
   ```hcl
   resource "aws_vpc_endpoint" "dynamodb" {
     vpc_id            = var.vpc_id
     service_name      = "com.amazonaws.ap-south-1.dynamodb"
     vpc_endpoint_type = "Gateway"
     route_table_ids   = var.private_route_table_ids
   }
   ```
2. Verify that the routing tables of your private subnets contain a route pointing to the VPC Endpoint (e.g., `vpce-xxxxxx` targeting the DynamoDB prefix list `pl-xxxxxx`).

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace egress-lab
```
