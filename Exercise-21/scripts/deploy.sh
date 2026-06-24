#!/usr/bin/env bash
set -euo pipefail

# Navigation to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo "Starting deployment for Exercise 21"
echo "============================================="

# 1. Initialize and apply Terraform (IAM setup)
echo "--> Applying Terraform configurations..."
cd "$BASE_DIR/terraform"
terraform init
terraform apply -auto-approve

# Get the Role ARN output from Terraform
ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn || echo "arn:aws:iam::028987315631:role/aws-load-balancer-controller-role")
echo "IAM Role for ALB Controller: $ROLE_ARN"

# 2. Add Helm repo and install/upgrade AWS Load Balancer Controller
echo "--> Installing/Updating AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install/upgrade the controller chart in kube-system namespace
# Note: In production, the helm upgrade will update the values.
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  -f "$BASE_DIR/helm/alb-controller-values.yaml"

# 3. Apply Kubernetes Manifests for the applications
echo "--> Creating Namespace and deploying applications..."
cd "$BASE_DIR"
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/apps-deployments.yaml
kubectl apply -f manifests/apps-services.yaml

# 4. Deploy Ingress
echo "--> Deploying ALB Ingress Resource..."
kubectl apply -f manifests/ingress.yaml

echo "============================================="
echo "Exercise 21 Deployment Completed Successfully!"
echo "============================================="
