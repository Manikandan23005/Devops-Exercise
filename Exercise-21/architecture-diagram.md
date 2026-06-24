# Exercise 21: Production ALB Ingress Architecture

Below is the request flow from the end user to the specific Kubernetes microservice in the EKS cluster.

## Request Flow

```mermaid
graph TD
    Client[Client / Web Browser] -->|1. Resolves DNS| Route53[AWS Route 53]
    Client -->|2. Requests HTTPS:443 /api/index.html| ALB[AWS Application Load Balancer]
    Client -->|3. Requests HTTP:80 /api/| ALB
    
    subgraph AWS Application Load Balancer
        Redirect[Listener HTTP:80] -->|Redirect 301| HTTPS[Listener HTTPS:443]
        HTTPS -->|Rule: /api/*| TG_API[Target Group: api-service]
        HTTPS -->|Rule: /admin/*| TG_ADMIN[Target Group: admin-service]
        HTTPS -->|Rule: /dashboard/*| TG_DASHBOARD[Target Group: dashboard-service]
    end

    subgraph Amazon EKS Cluster
        subgraph Namespace: exercise21
            TG_API -->|Forward to Pod IP| Pod_API1[api-service-pod-1]
            TG_API -->|Forward to Pod IP| Pod_API2[api-service-pod-2]
            
            TG_ADMIN -->|Forward to Pod IP| Pod_ADMIN1[admin-service-pod-1]
            TG_ADMIN -->|Forward to Pod IP| Pod_ADMIN2[admin-service-pod-2]
            
            TG_DASHBOARD -->|Forward to Pod IP| Pod_DASH1[dashboard-service-pod-1]
            TG_DASHBOARD -->|Forward to Pod IP| Pod_DASH2[dashboard-service-pod-2]
        end
    end

    style Client fill:#f9f,stroke:#333,stroke-width:2px
    style Route53 fill:#f96,stroke:#333,stroke-width:2px
    style ALB fill:#6cf,stroke:#333,stroke-width:2px
    style TG_API fill:#ffc,stroke:#333,stroke-width:1px
    style TG_ADMIN fill:#ffc,stroke:#333,stroke-width:1px
    style TG_DASHBOARD fill:#ffc,stroke:#333,stroke-width:1px
```

## Description of Key Components

1. **Route 53**: Resolves the custom domain name (e.g. `apps.example.com`) to the AWS ALB CNAME.
2. **Application Load Balancer**: Created automatically by the AWS Load Balancer Controller based on the Ingress resource annotations.
3. **HTTP (80) Listener**: Automatically configured with a redirect rule to route all plain HTTP requests to HTTPS (443).
4. **HTTPS (443) Listener**: Offloads SSL/TLS using the AWS Certificate Manager (ACM) SSL Certificate.
5. **Path Rules**: Evaluated sequentially:
   - `/api/*` -> API Target Group
   - `/admin/*` -> Admin Target Group
   - `/dashboard/*` -> Dashboard Target Group
6. **EKS Target Groups**: Configure with `target-type: ip` which routes traffic directly to the Pod IPs, bypassing the NodePort kube-proxy layer for reduced latency.
