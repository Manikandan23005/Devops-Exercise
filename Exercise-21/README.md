# Exercise 21: Production ALB Ingress Setup

This exercise demonstrates how to deploy the AWS Load Balancer Controller in an EKS cluster and configure a single AWS Application Load Balancer (ALB) to expose three separate services (`api-service`, `admin-service`, and `dashboard-service`) using path-based routing (`/api/*`, `/admin/*`, `/dashboard/*`).

It includes SSL termination, automatic HTTP-to-HTTPS redirect, target group health checks, and direct-to-pod routing (`target-type: ip`).

---

## Folder Structure

```text
Exercise-21/
├── README.md
├── architecture-diagram.md
├── manifests/
│   ├── namespace.yaml
│   ├── apps-deployments.yaml
│   ├── apps-services.yaml
│   └── ingress.yaml
├── terraform/
│   └── main.tf
├── helm/
│   └── alb-controller-values.yaml
├── scripts/
│   └── deploy.sh
└── validation/
    └── test-ingress.sh
```

---

## Configuration Overview

### 1. Ingress Annotations Explained

The following annotations in [ingress.yaml](file:///home/satoru/Projects/Devops-Exercise/Exercise-21/manifests/ingress.yaml) control the behavior of the ALB:

* **`kubernetes.io/ingress.class: alb` & `spec.ingressClassName: alb`**
  Instructs the AWS Load Balancer Controller to reconcile this ingress resource and provision an ALB.
* **`alb.ingress.kubernetes.io/scheme: internet-facing`**
  Creates a public-facing load balancer with public IP addresses.
* **`alb.ingress.kubernetes.io/target-type: ip`**
  Routes traffic directly to Pod IPs rather than Node IPs. This reduces latency by bypassing kube-proxy and enables fine-grained network policies.
* **`alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'`**
  Configures the ALB to listen on both port 80 (HTTP) and port 443 (HTTPS).
* **`alb.ingress.kubernetes.io/ssl-redirect: '443'`**
  Instructs the ALB to automatically return a `301 Moved Permanently` redirect for any incoming HTTP (port 80) traffic, forwarding them to the HTTPS version.
* **`alb.ingress.kubernetes.io/certificate-arn`**
  Points to the ACM Certificate ARN to apply to the HTTPS listener.
* **`alb.ingress.kubernetes.io/healthcheck-*`**
  Configures target group active health check thresholds, protocols, intervals, and paths.

---

## ACM and Route53 Integration Guidance

To configure the domain name system (DNS) and SSL for your ALB:

### Step 1: Request or Import an SSL Certificate in ACM
1. Navigate to the **AWS Certificate Manager (ACM)** console in your cluster's region (`ap-south-1`).
2. Click **Request a certificate** -> Select **Request a public certificate**.
3. Add your domain name (e.g. `apps.example.com` or wildcard `*.example.com`).
4. Select **DNS validation** (recommended).
5. Click Request. Copy the DNS CNAME record name and value shown in the console.

### Step 2: Validate the Certificate in Route53
1. If your domain's DNS zone is in Route53, click **Create records in Route 53** in ACM to create validation records automatically.
2. If using another registrar, add the CNAME validation record manually.
3. Wait for ACM status to update to **Issued**.
4. Copy the certificate ARN and update the `alb.ingress.kubernetes.io/certificate-arn` annotation in `manifests/ingress.yaml`.

### Step 3: Configure DNS Record in Route53
Once the ALB is provisioned and has a hostname (e.g., `k8s-devops-xxxxxx-xxxxxx.ap-south-1.elb.amazonaws.com`):
1. Go to **Route 53** -> **Hosted zones** -> Select your domain.
2. Click **Create record**.
3. Set **Record name** (e.g. `apps` for `apps.example.com`).
4. Select **Record type**: `A` (IPv4).
5. Enable **Alias** toggle.
6. Select **Route traffic to**: `Alias to Application and Classic Load Balancer`.
7. Choose the region (`ap-south-1`) and select your ALB DNS name from the dropdown.
8. Click **Save**.

---

## Deployment Steps

### Prerequisite
Ensure you are connected to the correct Kubernetes context:
```bash
kubectl config current-context
# Expected: arn:aws:eks:ap-south-1:028987315631:cluster/production-eks
```

### Step 1: Run Terraform to set up AWS IAM policies and Roles
```bash
cd terraform
terraform init
terraform apply -auto-approve
```
This output includes the Role ARN for the Service Account.

### Step 2: Update Ingress and Deploy
Edit the `alb.ingress.kubernetes.io/certificate-arn` annotation in `manifests/ingress.yaml` to match your ACM certificate. If you do not have one, you can still test it via port forwarding or HTTP rules.

Deploy everything:
```bash
./scripts/deploy.sh
```

---

## Validation & Testing

Run the validation script:
```bash
./validation/test-ingress.sh
```

### Manual Curl Commands
If the ALB is fully provisioned, run:
```bash
# Verify HTTP-to-HTTPS redirect
curl -I http://<ALB-DNS-NAME>/api/

# Verify path routing
curl -k https://<ALB-DNS-NAME>/api/index.html
curl -k https://<ALB-DNS-NAME>/admin/index.html
curl -k https://<ALB-DNS-NAME>/dashboard/index.html
```

---

## Production Best Practices
1. **Multi-AZ Availability**: Ensure your EKS nodes and VPC subnets span at least 2 Availability Zones. The AWS ALB requires subnets in at least two AZs.
2. **Resource Requests & Limits**: Pods are configured with CPU/Memory requests to ensure scheduling stability.
3. **Target Group healthcheck-interval**: Configured at 15s with an unhealthy threshold of 3. This ensures failing pods are evicted from traffic routes within 45 seconds.
4. **WAF Association**: In production, link an AWS WAF (Web Application Firewall) to the ALB using the annotation:
   `alb.ingress.kubernetes.io/wafv2-acl-arn: <WAF-ARN>`

## Security Considerations
* **SSL/TLS Policies**: Avoid using older TLS protocols. Configure the security policy annotation to enforce TLS 1.2 or 1.3:
  `alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06`
* **Internal vs Internet-Facing**: If the apps are internal backend services, change `alb.ingress.kubernetes.io/scheme` to `internal`.
* **Security Groups**: The ALB Ingress controller creates a security group for the ALB by default. You can restrict ingress ports or control outbound traffic using custom security groups.

## Cost Considerations
* **ALB Billing**: ALB billing is based on LCU (Load Balancer Capacity Units) and run time. To optimize costs, group multiple ingress resources under a single ALB using the `alb.ingress.kubernetes.io/group.name` annotation.
* **Direct Routing**: Using `target-type: ip` prevents traffic bouncing from Node IPs (via NodePorts), saving intra-VPC data transfer costs.

---

## Troubleshooting Guide

### 1. Ingress does not get an Address
Check the AWS Load Balancer Controller logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
```
Common issues:
* **Missing Subnet Tags**: Public subnets must be tagged with `kubernetes.io/role/elb: 1`. Private subnets must be tagged with `kubernetes.io/role/internal-elb: 1`.
* **Security Group Limits**: The AWS account has hit the maximum number of security groups.

### 2. Services return 502 Bad Gateway
* Ensure your pods are actually running and healthy: `kubectl get pods -n exercise21`.
* Check if Nginx is listening on port 80 and the service `targetPort` matches it.
* Check if target group health checks are failing due to wrong path configurations. The health check path must be reachable at `/healthz`.

---

## Cleanup
To destroy all created resources:
```bash
kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/apps-services.yaml
kubectl delete -f manifests/apps-deployments.yaml
kubectl delete -f manifests/namespace.yaml

cd terraform
terraform destroy -auto-approve
```
