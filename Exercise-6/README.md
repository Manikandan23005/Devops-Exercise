# Exercise 6 – EKS Node Scale Failure

## 📋 Incident Overview
Users are complaining that the application is slow and experiencing errors during a high-traffic window. The DevOps team has configured an HPA to scale the application pods automatically, but the scaling has stalled.

* **HPA Status**: Desired replicas is `15`, but current replicas is stuck at `5`.
* **Pod Status**: There are `10` pods stuck in the `Pending` state. Checking their events reveals:
  ```text
  0/3 nodes available: 3 Insufficient CPU.
  ```
* **Cluster Autoscaler Logs**: Searching `kube-system` logs for the Cluster Autoscaler shows:
  ```text
  I0702 11:00:00.000000 1 static_autoscaler.go:210] No node group config found matching tags k8s.io/cluster-autoscaler/enabled=true.
  ```

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure and trigger the simulation in your local cluster:

### 1. Deploy the namespace and application manifests:
```bash
kubectl apply -f manifests/
```

### 2. Verify HPA desired vs current replicas:
```bash
kubectl get hpa -n scale-failure-lab
```
*Expected Output*: Desired replicas will show `15`, but current replicas is stuck at `5`.

### 3. Check for Pending pods:
```bash
kubectl get pods -n scale-failure-lab
```
*Expected Output*: You should see `5` running pods and `10` pending pods.

### 4. Inspect the pending pod events:
Describe one of the pending pods to verify the `Insufficient CPU` error:
```bash
kubectl describe pod -n scale-failure-lab -l app=payment-processor | grep -A 5 "Events:"
```

### 5. Check the simulated Cluster Autoscaler logs:
Check the logs of the simulated autoscaler pod in the cluster:
```bash
kubectl logs -n scale-failure-lab -l app=cluster-autoscaler
```
*Expected Output*: Prints the error that no node group configuration was found.

---

## 🔍 Step 2: Diagnostic Breakdown

To determine the root cause, we evaluate the three components: **HPA**, **Kubernetes Nodes**, or **Cluster Autoscaler**.

### 1. HPA Issue? (No)
* **Reasoning**: The HPA is functioning correctly.
* **Explanation**: The HPA successfully monitored target metric utilization, calculated that the cluster required `15` replicas to handle the load, and updated the Deployment's replica count. The fact that the deployment shows `Desired: 15` proves the HPA has done its job.

### 2. Node Resource Issue? (Yes - Intermediate Symptom)
* **Reasoning**: The physical cluster nodes do not have enough allocatable CPU capacity to host the new pods.
* **Explanation**: Each pod requests `2000m` (2 CPU cores) in its resource spec. The scheduler tried to assign these pods but failed because the current EKS nodes are fully saturated. However, this is an intermediate symptom—the EKS cluster should have automatically added more nodes to resolve this.

### 3. Autoscaler Issue? (Yes - Root Cause)
* **Reasoning**: The Cluster Autoscaler is active but cannot scale up the AWS EC2 Auto Scaling Group (ASG).
* **Explanation**: The logs show `No node group config found matching tags...`. The AWS Cluster Autoscaler relies on specific tags on the EC2 ASGs to automatically discover them. If these tags are missing, the autoscaler does not know which ASG to scale up, and the pending pods remain unscheduled indefinitely.

---

## 🛠️ Step 3: Resolution & Remediation

To resolve the node scaling failure:

### 1. Add Auto Scaling Group Discovery Tags in AWS
You must ensure the EC2 Auto Scaling Groups for the EKS worker nodes are tagged with:
* `k8s.io/cluster-autoscaler/enabled` = `true`
* `k8s.io/cluster-autoscaler/<cluster-name>` = `owned`

If managing the cluster via Terraform, update the ASG resources:
```hcl
tag {
  key                 = "k8s.io/cluster-autoscaler/enabled"
  value               = "true"
  propagate_at_launch = true
}

tag {
  key                 = "k8s.io/cluster-autoscaler/production-eks"
  value               = "owned"
  propagate_at_launch = true
}
```
Or apply manually via the AWS CLI:
```bash
aws autoscaling create-or-update-tags --tags \
  ResourceId=eks-node-group-asg,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
  ResourceId=eks-node-group-asg,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/production-eks,Value=owned,PropagateAtLaunch=true
```

### 2. Verify IAM Role Permissions (IRSA)
Ensure the Cluster Autoscaler pod is running with an IAM ServiceAccount that has the following permissions:
* `autoscaling:DescribeAutoScalingGroups`
* `autoscaling:DescribeAutoScalingInstances`
* `autoscaling:DescribeLaunchConfigurations`
* `autoscaling:DescribeTags`
* `autoscaling:SetDesiredCapacity`
* `autoscaling:TerminateInstanceInAutoScalingGroup`

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace scale-failure-lab
```
