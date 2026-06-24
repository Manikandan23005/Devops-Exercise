# Exercise 22: Horizontal and Cluster Autoscaling Architecture

This diagram illustrates the dual-level autoscaling system implemented in EKS:
1. **Horizontal Pod Autoscaler (HPA)**: Scales the application pods horizontally based on CPU load.
2. **Cluster Autoscaler (CA)**: Scales the EKS cluster worker nodes based on pending (unschedulable) pods.

## Autoscaling Workflow

```mermaid
graph TD
    %% Load Generation
    LoadGen[Load Testing Tools: hey / ab / k6] -->|High Traffic / Requests| Service[Service: cpu-load-service]
    Service -->|Routes Traffic| Pods[Pods: cpu-load-app]

    %% Pod Metric Collection and HPA
    MetricsServer[Metrics Server] -->|Scrapes CPU Metrics| Pods
    HPA[Horizontal Pod Autoscaler] -->|1. Polls Metrics API| MetricsServer
    HPA -->|2. Compares to Target: 50% CPU| HPA
    HPA -->|3. Scales Replicas 2 -> 20| ReplicaSet[ReplicaSet / Deployment]
    ReplicaSet -->|4. Attempts to Schedule Pods| Pods

    %% Node Scaling Trigger (Cluster Autoscaler)
    subgraph EKS Worker Node Pools
        Node1[EKS Node 1: Running]
        Node2[EKS Node 2: Running]
        Node3[EKS Node 3: Running]
        
        PendingPods[Pods in PENDING State: Insufficient CPU]
    end

    Pods -->|Scheduler assigns to nodes| EKSWorkerPool[EKS Node Pools]
    ReplicaSet -->|Scheduler fails to place due to resource exhaustion| PendingPods

    CA[Cluster Autoscaler Pod] -->|1. Detects Pending Pods| PendingPods
    CA -->|2. STS AssumeRoleWithWebIdentity| CAServiceAccount[ServiceAccount with IRSA Role]
    CA -->|3. API Call: SetDesiredCapacity 3 -> 6| ASG[AWS Auto Scaling Group]
    ASG -->|4. Provisions EC2 Instances| EKSWorkerPool
    EKSWorkerPool -->|5. Nodes Join Cluster| Kubelet[Kubernetes Scheduler]
    Kubelet -->|6. Schedules Pending Pods| Pods

    style LoadGen fill:#f9f,stroke:#333,stroke-width:2px
    style HPA fill:#f96,stroke:#333,stroke-width:2px
    style CA fill:#6cf,stroke:#333,stroke-width:2px
    style PendingPods fill:#fcc,stroke:#f00,stroke-width:2px
```

## Scaling Logic Breakdown

### 1. Pod Scaling (HPA)
* The HPA polls the Metrics API (`v1beta1.metrics.k8s.io`) every 15 seconds.
* HPA calculation formula:
  $$\text{DesiredReplicas} = \lceil \text{CurrentReplicas} \times \frac{\text{CurrentMetricValue}}{\text{TargetMetricValue}} \rceil$$
* If the average CPU load across pods is 80% and the target is 50%, HPA scales the replica count up.

### 2. Node Scaling (Cluster Autoscaler)
* When HPA scales replicas up to 20, the physical limits of the existing nodes (3 nodes) are reached.
* The Kubernetes scheduler fails to assign the new pods to any node due to CPU exhaustion, putting them in `Pending` state.
* The Cluster Autoscaler daemon detects pods stuck in `Pending` due to lack of resources.
* It communicates with the AWS Auto Scaling Group (ASG) API via IRSA permissions to adjust the desired capacity (e.g., from 3 to 6).
* Once the new EC2 nodes join the EKS cluster, the scheduler runs the pending pods on them.
