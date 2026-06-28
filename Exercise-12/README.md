# Exercise 12 – Node NotReady Production Incident

## 📋 Incident Summary
* **Node Status**: `NotReady`
* **Node Condition**: `DiskPressure=True`
* **System Log**: `Journal: no space left on device`
* **Additional Evidence**: `du -sh /var/log/containers/*` reveals **95GB** of disk space consumed by container logs.

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure and trigger the simulation in your local cluster:

### 1. Create the `disk-pressure-lab` namespace & deploy the heavy log generator:
```bash
kubectl apply -f manifests/
```

### 2. Verify the pod is running and writing logs:
```bash
kubectl get pods -n disk-pressure-lab
kubectl logs -n disk-pressure-lab -l app=heavy-logger --tail=20
```

---

## ⚠️ The Danger of Direct Deletion (`rm`)
> [!CAUTION]
> **Do not run `rm /var/log/containers/*.log`!**
> 
> If a container process is actively running and writing to a log file, deleting the file with `rm` will remove the directory entry, but the file descriptor will remain open by the running process. The disk space will **not** be reclaimed (showing up as a `(deleted)` open file in `lsof`) until the writing process is terminated or restarted. Additionally, deleting log files directly can break log auditing, cause container runtime sync issues, or corrupt logging pipelines.

---

## 🛠️ Step 2: Step-by-Step Recovery Runbook

Follow these steps to safely restore the affected node back to a healthy state:

### Step 1: Isolate the Node (Cordon)
Mark the node as unschedulable to prevent Kubernetes from assigning new workloads to it while it is under disk pressure:
```bash
kubectl cordon <node-name>
```

### Step 2: Relocate Running Workloads (Drain)
Attempt to safely evict and reschedule running pods to other healthy nodes in the cluster.
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force
```
*Note: If the node is completely unresponsive, the drain might hang. Proceed to host-level steps if the drain command is blocked.*

### Step 3: Access the Host Node
SSH into the affected node or access it via AWS Systems Manager Session Manager (SSM):
```bash
ssh admin@<node-ip-address>
```

### Step 4: Identify the Offending Log Files
Find the largest log files under `/var/log/containers/` (or `/var/log/pods/`):
```bash
sudo du -sh /var/log/containers/* | sort -rh | head -n 10
```

### Step 5: Reclaim Disk Space Safely (Truncation)
Rather than deleting the files, truncate their contents to `0` bytes. This immediately releases the disk blocks back to the OS while keeping the open file descriptors valid:
```bash
# To truncate a specific large log file:
sudo truncate -s 0 /var/log/containers/<large-log-file-name>.log

# Or use redirection to clear it:
sudo true > /var/log/containers/<large-log-file-name>.log

# To truncate ALL log files larger than 100MB under /var/log/pods:
sudo find /var/log/pods/ -name "*.log" -size +100M -exec sh -c 'truncate -s 0 "{}"' \;
```

### Step 6: Clean Up Stopped Containers and Dangling Images
Free up additional space by clearing unused container images and terminated containers.
* **If running Containerd (Default modern runtime)**:
  ```bash
  # Remove stopped pods and containers
  sudo crictl rm $(sudo crictl ps -a -q --state Exited)
  # Prune unused container images
  sudo crictl rmi --prune
  ```
* **If running Docker**:
  ```bash
  # Prune all stopped containers, unused networks, and images
  sudo docker system prune -a --volumes -f
  ```

### Step 7: Restart System Services
If the node's disk was at 100%, the local kubelet or container runtime may have frozen. Restart them to pick up the changes and clear the `DiskPressure` state:
```bash
sudo systemctl restart containerd   # or docker
sudo systemctl restart kubelet
```

### Step 8: Verify Node Health & Uncordon
1. Verify disk space has been freed on the node:
   ```bash
   df -h
   ```
2. Verify node status and check if `DiskPressure` is now `False`:
   ```bash
   kubectl get nodes
   kubectl describe node <node-name> | grep -A 5 -i pressure
   ```
3. Once the node is `Ready` and `DiskPressure=False`, allow workloads to run on it again:
   ```bash
   kubectl uncordon <node-name>
   ```

---

## 🔒 Step 3: Long-Term Prevention Strategy

To prevent this incident from recurring:

### 1. Configure Container Runtime Log Rotation
Ensure log limits are configured in the container runtime.
* **For Docker (`/etc/docker/daemon.json`)**:
  ```json
  {
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "50m",
      "max-file": "3"
    }
  }
  ```
  Restart Docker afterwards: `sudo systemctl restart docker`.
* **For Containerd**: Check and ensure that log limits are integrated within the system config or managed by Kubelet.

### 2. Configure Host-level `logrotate`
Verify `/etc/logrotate.d/kubernetes` (or create a custom configuration) is scheduled to periodically rotate container log files:
```text
/var/log/pods/*/*.log
/var/log/containers/*.log {
    rotate 3
    daily
    maxsize 50M
    copytruncate
    missingok
    notifempty
    compress
}
```
> [!IMPORTANT]
> The `copytruncate` directive is critical here; it tells `logrotate` to copy the log file and truncate the original in place rather than moving it, preventing open file descriptor issues.

### 3. Deploy Log Collection Shippers
Configure Grafana Alloy, Promtail, or Fluentbit to stream container logs to a remote, centralized logging backend (e.g., Loki or Elasticsearch) and aggressively rotate local files on the node.

### 4. Enable Disk Space Monitoring & Alerting
Create Prometheus alerts to notify the team when disk utilization on nodes crosses threshold limits:
* **Warning**: Node disk usage > 80% (`NodeDiskRunningOutofSpace`)
* **Critical**: Node disk usage > 90% (triggers before Kubelet starts evicting pods under extreme Disk Pressure).

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace disk-pressure-lab
```
