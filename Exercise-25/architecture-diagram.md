# Exercise 25: Observability Platform Architecture

This diagram illustrates the flow of metrics, logs, and traces from EKS application pods through the Grafana Alloy collector to the storage engines (Prometheus, Loki, Tempo), and their aggregation in Grafana.

## System Flow

```mermaid
graph TD
    subgraph EKS Application Pods
        AppPod[Application Pods <br> e.g. customer-app]
        AppPod -->|Logs to stdout| ContainerLogs[/var/log/pods/*]
        AppPod -->|Traces: OTLP/gRPC port 4317| Alloy
        AppPod -->|Metrics: /metrics HTTP| Alloy
    end

    subgraph Observability Namespace
        %% Collector Pipeline
        Alloy[Grafana Alloy Collector]
        ContainerLogs -->|Tails Files| Alloy
        
        %% Storage Engines
        Prometheus[Prometheus Server]
        Loki[Grafana Loki]
        Tempo[Grafana Tempo]
        
        Alloy -->|1. Pushes Metrics| Prometheus
        Alloy -->|2. Pushes Logs| Loki
        Alloy -->|3. Pushes Traces| Tempo
        
        %% Visualization
        Grafana[Grafana Dashboard Server]
        Grafana -->|Queries Metrics| Prometheus
        Grafana -->|Queries Logs| Loki
        Grafana -->|Queries Traces| Tempo
    end

    User([DevOps Engineer]) -->|HTTP Port 3000| Grafana

    style User fill:#f9f,stroke:#333,stroke-width:2px
    style Alloy fill:#6cf,stroke:#333,stroke-width:2px
    style Grafana fill:#f96,stroke:#333,stroke-width:2px
    style Prometheus fill:#ffc,stroke:#333,stroke-width:1px
    style Loki fill:#ffc,stroke:#333,stroke-width:1px
    style Tempo fill:#ffc,stroke:#333,stroke-width:1px
```

## Description of Ingestion Channels

1. **Metrics Collection**:
   * **Pull Model**: Prometheus scrapes the targets configuration directly.
   * **Push Model (Alloy)**: Grafana Alloy scrapes local endpoints (like its own metrics or pod endpoints configured with prometheus annotations) and exports them to Prometheus using `remote_write` API endpoints.
2. **Log Tailing**:
   * EKS node container engines write logs to the host directories `/var/log/pods`.
   * Grafana Alloy runs as a DaemonSet, discovers pod metadata from EKS, mounts host log paths, tails the log files, matches them to Kubernetes metadata (labels, namespace, pod name), and pushes them to Loki.
3. **Trace Ingestion**:
   * Microservices instrumented with the **OpenTelemetry (OTel) SDK** push trace spans over OTLP/gRPC to port 4317 on the Grafana Alloy Collector.
   * Alloy buffers and pushes these traces to Tempo for indexing and chunk storage.
4. **Grafana Visualization**:
   * Pre-configured datasources query the APIs. Grafana correlates Loki logs and Tempo traces dynamically by linking trace IDs, allowing users to drill down from a slow trace directly into the corresponding pod log file at that exact timestamp.
