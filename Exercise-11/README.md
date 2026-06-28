# Exercise 11 – CrashLoopBackOff Investigation

## 📋 Incident Overview
The `payment-service` pod is stuck in a `CrashLoopBackOff` status. The application logs report:
```text
panic: dial tcp 10.20.0.15:5432: connection refused
```
The Kubernetes events show:
```text
Back-off restarting failed container
```

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure the simulation in your local Kubernetes cluster:

### 1. Create the `payment-crash` namespace & deploy the crashing service:
```bash
kubectl apply -f manifests/
```

### 2. Verify the pod enters CrashLoopBackOff:
```bash
kubectl get pods -n payment-crash
```

### 3. Inspect the logs to verify the connection refused panic:
```bash
kubectl logs -n payment-crash -l app=payment-service
```

---

## 🔍 Step 2: Diagnostic Breakdown

To determine the root cause, we evaluate the three proposed potential issue categories: **DNS**, **Database**, or **Secret**.

### 1. DNS Issue? (No)
* **Reasoning**: The error logs explicitly show the application attempting to dial the raw IP address `10.20.0.15` on port `5432`.
* **Explanation**: A DNS issue occurs when a domain name or service name (e.g., `postgres-service.db.svc.cluster.local`) cannot be resolved to an IP address by the cluster's DNS provider (CoreDNS). If it were a DNS issue, the error would show something like `dial tcp: lookup postgres-service: no such host`. Because the application is directly calling an IP address (or has already successfully resolved it), this is not a DNS issue.

### 2. Database Issue? (Yes - Root Cause)
* **Reasoning**: The TCP connection attempt returned `connection refused`.
* **Explanation**: The `connection refused` error indicates that a connection request reached the destination host (`10.20.0.15`), but the host actively rejected it (sent a TCP `RST` packet). This occurs when:
  * **Database Process Down**: The database service/process (e.g. PostgreSQL) is not running on the target machine.
  * **Not Listening on Host Interface**: The database is running but listening only on the loopback interface (`localhost` / `127.0.0.1`) instead of all interfaces (`0.0.0.0`) or the interface associated with `10.20.0.15`.
  * **Port Mismatch**: The database is running and listening on a different port than `5432`.
  * **Network Security / Firewall / NetworkPolicy**: A network filter or security group configuration on the network layer is actively rejecting the connection.

### 3. Secret Issue? (No)
* **Reasoning**: A Secret issue (credentials mismatch, expired tokens, incorrect username/password) happens *after* a successful TCP handshake.
* **Explanation**: If the database was reachable, but the application had the wrong credentials, the TCP connection would succeed, and the database would reject the database-level authentication handshake. The logs would show database-specific error messages such as:
  * `pq: password authentication failed for user "..."`
  * `Fatal: role "..." does not exist`
  * `FATAL: database "..." does not exist`
  Because the TCP handshake failed (`connection refused`), the client never reached the authentication phase.

---

## 🔬 Step 3: Recommended Troubleshooting Steps

To troubleshoot this issue, execute the following commands in the cluster:

### Step 1: Verify the Database Pod & Service Status
Check if the database pod is running and healthy:
```bash
kubectl get pods -A | grep -E "postgres|db"
```
Verify that the database service exists and points to the correct endpoints:
```bash
kubectl get svc,endpoints -A | grep -E "postgres|db"
```

### Step 2: Test Network Connectivity from a Debug Pod
Launch a temporary pod inside the same namespace and attempt to run a network connection test (like `nc` or `telnet`) to the target IP:
```bash
kubectl run net-test --rm -it --image=busybox --restart=Never -- nc -zv 10.20.0.15 5432
```
* If it returns `open`, the port is active, and there may be a routing mismatch or service binding issue.
* If it returns `connection refused`, the database service itself is down, bound incorrectly, or a firewall/NetworkPolicy is blocking the traffic.

### Step 3: Check Database Listening Configurations
If you have access to the database server, verify that the service is configured to listen on all interfaces. In PostgreSQL (`postgresql.conf`):
```ini
listen_addresses = '*'
```
Also, ensure the host-based authentication config (`pg_hba.conf`) allows incoming connections from the application's subnet range.

### Step 4: Verify Network Policies
Check if there are any `NetworkPolicy` objects restricting egress from the `payment` namespace or ingress to the database namespace:
```bash
kubectl get netpol -A
```

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace payment-crash
```
