# Exercise 24: DynamoDB Application Architecture (IRSA)

This diagram shows the end-to-end authentication and authorization flow of the customer application accessing DynamoDB using IAM Roles for Service Accounts (IRSA).

## System Flow

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client / Tester
    participant Pod as Flask Pod (customer-app)
    participant K8s as EKS Control Plane
    participant STS as AWS STS (Security Token Service)
    participant Dynamo as Amazon DynamoDB (exercise24-customers)

    Note over Pod, K8s: Pod is bound to ServiceAccount "customer-sa"
    K8s->>Pod: Mounts OIDC Web Identity Token at:<br/>/var/run/secrets/eks.amazonaws.com/serviceaccount/token
    K8s->>Pod: Sets environment variables:<br/>AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE

    Client->>Pod: HTTP POST /customer
    Note over Pod: boto3 client initialized

    Pod->>STS: sts:AssumeRoleWithWebIdentity<br/>(Passes JWT token + Target Role ARN)
    STS->>STS: Validates token signature<br/>via EKS OIDC Provider trust
    STS-->>Pod: Returns temporary AWS credentials<br/>(AccessKey, SecretKey, SessionToken)

    Pod->>Dynamo: dynamodb:PutItem (Writes customer record)
    Dynamo-->>Pod: HTTP 200 (Success)
    Pod-->>Client: HTTP 210 (Customer Created)
```

## Description of Steps

1. **Token Ingestion**: The EKS pod admission controller mutates pods that specify `serviceAccountName: customer-sa`. It projects the OIDC Web Identity token file into the pod and configures the environment variables `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`.
2. **REST Request**: The client fires a CRUD request (POST/GET/PUT) to the Flask microservice.
3. **AWS STS AssumeRole**: The AWS SDK (`boto3`) notices the `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` environment variables. It automatically handles calling AWS STS using `AssumeRoleWithWebIdentity` to exchange the projected token for short-lived credentials.
4. **Trust Validation**: AWS STS validates the projected token's signature against the EKS cluster's OIDC Identity Provider configured in IAM.
5. **Session Credentials**: STS returns temporary, rotated credentials valid for 1 hour.
6. **DynamoDB Access**: Boto3 uses the temporary credentials to sign requests and securely query or modify items in the DynamoDB table.
