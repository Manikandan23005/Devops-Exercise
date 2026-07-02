# Exercise 7 – ALB Ingress Failure

## 📋 Incident Overview
The application is inaccessible from the external load balancer, resulting in **HTTP 504 Gateway Timeout** errors for external clients. 

* **Ingress Configuration**: The Ingress resource uses the AWS Load Balancer Controller with target-type IP:
  ```yaml
  alb.ingress.kubernetes.io/target-type: ip
  ```
* **Ingress Events**: Describing the ingress shows:
  ```text
  Warning  TargetRegistrationFailed  Target registration failed: unable to register target IPs with AWS Target Group
  ```
* **ALB Controller Logs**: Checking the controller logs in the cluster reveals:
  ```text
  E0702 11:20:00.000000 1 controller.go:102] Unable to discover subnets for ALB. Ensure public subnets are tagged with kubernetes.io/role/elb=1.
  ```

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure and trigger the simulation in your local cluster:

### 1. Deploy the namespace and application ingress manifests:
```bash
kubectl apply -f manifests/
```

### 2. Verify Ingress events:
Describe the ingress resource to inspect target registration warning events:
```bash
kubectl describe ingress payment-app-ingress -n alb-failure-lab
```
*Expected Output*: Contains a warning event: `TargetRegistrationFailed: Target registration failed: unable to register target IPs...`

### 3. Check the simulated AWS Load Balancer Controller logs:
Inspect the logs of the controller deployment to locate the root cause:
```bash
kubectl logs -n alb-failure-lab -l app=aws-load-balancer-controller
```
*Expected Output*: Shows the error `Unable to discover subnets for ALB`.

---

## 🔍 Step 2: Diagnostic Breakdown

To determine the root cause, we evaluate the configuration of the **Ingress**, **AWS ALB Target Type**, or the **VPC Subnet Tags**.

### 1. Target Type Mismatch? (No)
* **Reasoning**: The target-type annotation (`alb.ingress.kubernetes.io/target-type: ip`) is valid.
* **Explanation**: In EKS, the `ip` target-type routes traffic directly to the Pod IPs rather than the Node port IPs. This is preferred for performance but requires the pods to run on a network layer that is routeable within the VPC (e.g. AWS VPC CNI). Since the VPC CNI is healthy, this configuration itself is correct.

### 2. AWS Load Balancer Controller Logs? (Yes - Root Cause)
* **Reasoning**: The controller logs explicitly report `Unable to discover subnets for ALB`.
* **Explanation**: For the AWS Load Balancer Controller to dynamically provision an Application Load Balancer, it must determine which subnets to place it in. It does this by scanning all subnets in the VPC for specific Kubernetes discovery tags. If those tags are missing, the controller cannot locate public/private subnets, target group registration fails, and the ALB is never properly wired to the pods.

---

## 🛠️ Step 3: Resolution & Remediation

To resolve the subnet discovery failure, add the mandatory tags to your VPC subnets in AWS:

### 1. Tag Public Subnets (For internet-facing ALBs)
Ensure all public subnets in your EKS VPC have the following tags:
* `kubernetes.io/role/elb` = `1`
* `kubernetes.io/cluster/<cluster-name>` = `owned` (or `shared`)

### 2. Tag Private Subnets (For internal ALBs)
Ensure all private subnets have the following tags:
* `kubernetes.io/role/internal-elb` = `1`
* `kubernetes.io/cluster/<cluster-name>` = `owned` (or `shared`)

If managing the VPC using Terraform, add the tags to your subnet resources:
```hcl
# Inside public subnet configuration:
tags = {
  "kubernetes.io/role/elb"                  = "1"
  "kubernetes.io/cluster/production-cluster" = "shared"
}

# Inside private subnet configuration:
tags = {
  "kubernetes.io/role/internal-elb"         = "1"
  "kubernetes.io/cluster/production-cluster" = "shared"
}
```

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace alb-failure-lab
```
