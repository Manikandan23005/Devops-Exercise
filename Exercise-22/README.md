# Exercise 22: Horizontal and Cluster Autoscaling

This exercise demonstrates the implementation of automatic scaling in Amazon EKS. We configure **Horizontal Pod Autoscaling (HPA)** to scale pods from 2 to 20 based on CPU utilization and **Cluster Autoscaling (CA)** to scale EKS worker nodes from 3 to 6 when resource limits are reached.

---

## Folder Structure

```text
Exercise-22/
├── README.md
├── architecture-diagram.md
├── manifests/
│   ├── namespace.yaml
│   ├── cpu-app-deployment.yaml
│   ├── cpu-app-service.yaml
│   ├── hpa.yaml
│   └── cluster-autoscaler-autodiscover.yaml
├── terraform/
│   ├── asg-tagging.tf
│   └── ca-irsa.tf
├── helm/
│   └── cluster-autoscaler-values.yaml
├── scripts/
│   ├── cpu-app/
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   ├── load-test.sh
│   └── load-test-k6.js
└── validation/
    └── verify-scaling.sh
```

---

## Prerequisites

1. **Metrics Server**: HPA requires the Metrics Server to collect CPU and Memory metrics. Ensure it is installed:
   ```bash
   helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
   helm upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system
   ```
   Verify the metrics API is responding:
   ```bash
   kubectl get apiservice v1beta1.metrics.k8s.io
   ```

2. **ASG Discovery Tags**: The AWS Cluster Autoscaler requires specific tags on the EC2 Auto Scaling Groups to locate them automatically:
   * `k8s.io/cluster-autoscaler/enabled` = `true`
   * `k8s.io/cluster-autoscaler/production-eks` = `owned` (or `shared`)

---

## Deployment Steps

### Step 1: Tag the AWS Auto Scaling Group
Update [terraform/asg-tagging.tf](file:///home/satoru/Projects/Devops-Exercise/Exercise-22/terraform/asg-tagging.tf) with your actual EKS Node Group Auto Scaling Group names, then run:
```bash
cd terraform
terraform init
terraform apply -auto-approve
```
*Note: If you do not manage the node group via Terraform, you can apply these tags manually using the AWS CLI or Console.*
```bash
aws autoscaling create-or-update-tags --tags \
  ResourceId=<ASG_NAME>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
  ResourceId=<ASG_NAME>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/production-eks,Value=owned,PropagateAtLaunch=true
```

### Step 2: Apply the Kubernetes Manifests
Apply the CPU-intensive test app and HPA:
```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/cpu-app-deployment.yaml
kubectl apply -f manifests/cpu-app-service.yaml
kubectl apply -f manifests/hpa.yaml
```

### Step 3: Deploy the Cluster Autoscaler
Update the role ARN in `manifests/cluster-autoscaler-autodiscover.yaml` if needed, then deploy:
```bash
kubectl apply -f manifests/cluster-autoscaler-autodiscover.yaml
```

Verify that the Cluster Autoscaler starts successfully:
```bash
kubectl rollout status deployment/cluster-autoscaler -n kube-system
```

---

## Load Testing & Validation

To trigger scaling, you must generate a CPU load on the application.

### Running Load Tests
We provide three load generator configurations:

#### Option 1: Using `hey`
```bash
./scripts/load-test.sh
```
This script port-forwards the application service locally and runs `hey` to send concurrent requests to the `/load` endpoint.

#### Option 2: Apache Benchmark (`ab`)
Run manually:
```bash
ab -n 5000 -c 50 http://localhost:8080/load?duration=1.0
```

#### Option 3: k6 (Modern Load Generator)
```bash
k6 run scripts/load-test-k6.js
```

### Monitoring the Scaling

In separate terminal windows, run the following verification tools:

1. **Watch HPA Scaling**:
   ```bash
   kubectl get hpa cpu-load-hpa -n exercise22 -w
   ```
   You should see target CPU utilization rise past 50% (e.g., to 120%) and the replicas count scale up from 2 to 20.

2. **Watch Pod Scaling**:
   ```bash
   kubectl get pods -n exercise22 -w
   ```
   You will see new pods transition from `Pending` as EKS reaches its physical capacity.

3. **Watch Node Scaling**:
   ```bash
   kubectl get nodes -w
   ```
   When the scheduler fails to assign pending pods, the Cluster Autoscaler triggers ASG scaling. You will see the node count scale from 3 to 6.

4. **Verify Resource Usage**:
   Run the validation script to display current metrics:
   ```bash
   ./validation/verify-scaling.sh
   ```

---

## Production Best Practices

1. **Resource Limits and Requests**:
   Always specify CPU and Memory requests for your containers. HPAs use resource requests to calculate utilization percentage. If no request is set, HPA cannot run.
2. **Cluster Autoscaler Priority Expander**:
   In production, configure the Priority Expander to scale cheaper spot instances first before falling back to on-demand instances.
3. **Disruption Budgets**:
   Configure `PodDisruptionBudgets` (PDBs) to ensure that the Cluster Autoscaler does not drain too many pods concurrently when scaling down.
4. **Cooldown/Scale-Down Delays**:
   Ensure `scale-down-unneeded-time` is set appropriately (default is 10 minutes) to prevent cluster "thrashing" (rapidly scaling up and down).

## Security Considerations
* **IRSA Principle of Least Privilege**:
  The Cluster Autoscaler IAM Role is restricted to describing and modifying Auto Scaling Groups tagged with the cluster identifier.
* **Running as Non-Root**:
  The Cluster Autoscaler deployment runs as non-root user `65534` (nobody) and disables privilege escalation to prevent container escape exploits.

## Cost Considerations
* **Scale Down Nodes**:
  The Cluster Autoscaler automatically scales down node groups when nodes are under-utilized (less than 50% utilization for 10 minutes) to save cost.
* **Spot Instances Integration**:
  Combine CA with EKS Managed Node Groups containing Spot instances for dev/staging environments to cut computing costs by up to 70%.

---

## Troubleshooting Guide

### 1. HPA targets show `<unknown>`
* Verify that the Metrics Server is running: `kubectl get deployment metrics-server -n kube-system`.
* Verify the target deployment specifies `resources.requests.cpu`.
* Ensure that the network policy allows communication between kube-apiserver and the Metrics Server.

### 2. Cluster Autoscaler does not scale up nodes
* Check CA logs: `kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100`.
* Verify that your EKS nodes' ASGs are tagged with `k8s.io/cluster-autoscaler/enabled=true` and `k8s.io/cluster-autoscaler/<cluster-name>=owned`.
* Ensure the IAM role ARN is correctly annotated on the `cluster-autoscaler` ServiceAccount in `kube-system`.

---

## Cleanup
To tear down the environment:
```bash
kubectl delete -f manifests/hpa.yaml
kubectl delete -f manifests/cpu-app-service.yaml
kubectl delete -f manifests/cpu-app-deployment.yaml
kubectl delete -f manifests/namespace.yaml
kubectl delete -f manifests/cluster-autoscaler-autodiscover.yaml

cd terraform
terraform destroy -auto-approve
```
