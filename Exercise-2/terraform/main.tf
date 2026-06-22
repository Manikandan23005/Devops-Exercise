terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  type        = string
  description = "AWS Region for deployment"
  default     = "ap-south-1"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for EKS cluster VPC (Minimum 2 subnets in different AZs)"
  default     = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
}

# Caller identity
data "aws_caller_identity" "current" {}

# DynamoDB Table
resource "aws_dynamodb_table" "customer_data" {
  name         = "customer-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = "production"
    Project     = "customer-app"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "production-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "production_eks" {
  name     = "production-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# OIDC Certificate Data
data "tls_certificate" "eks" {
  url = aws_eks_cluster.production_eks.identity[0].oidc[0].issuer
}

# OIDC Provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.production_eks.identity[0].oidc[0].issuer
}

# IAM Role for IRSA (Assumed by Kubernetes ServiceAccount)
resource "aws_iam_role" "customer_app_irsa_role" {
  name = "customer-app-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.production_eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:customer-app:customer-sa"
            "${replace(aws_eks_cluster.production_eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# IRSA IAM Policy (DynamoDB access)
resource "aws_iam_role_policy" "customer_app_irsa_policy" {
  name = "customer-app-irsa-policy"
  role = aws_iam_role.customer_app_irsa_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = "*"
      }
    ]
  })
}

# Worker Node Group IAM Role
resource "aws_iam_role" "eks_nodegroup_role" {
  name = "eks-nodegroup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# EKS Worker Node standard policies
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# Outputs
output "eks_cluster_name" {
  value = aws_eks_cluster.production_eks.name
}

output "irsa_role_arn" {
  value = aws_iam_role.customer_app_irsa_role.arn
}

output "nodegroup_role_arn" {
  value = aws_iam_role.eks_nodegroup_role.arn
}
