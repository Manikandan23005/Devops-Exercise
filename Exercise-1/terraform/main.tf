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

# ─── Variables ───────────────────────────────────────────────────────────────

variable "aws_region" {
  type        = string
  description = "AWS Region for deployment"
  default     = "ap-south-1"
}

variable "account_id" {
  type        = string
  description = "AWS Account ID"
  default     = "028987315631"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for EKS cluster VPC (minimum 2 subnets in different AZs)"
  default     = [
    "subnet-0b61943fc05880709",  # ap-south-1c
    "subnet-08b95f52d9a4209f8",  # ap-south-1a
    "subnet-0c07d9a09608f2ef3"   # ap-south-1b
  ]
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for ALB controller"
  default     = "vpc-09c126c4b9ddf5d39"
}

# ─── Caller Identity ─────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ─── ECR Repository ──────────────────────────────────────────────────────────

resource "aws_ecr_repository" "payment_service" {
  name                 = "payment-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "production"
    Project     = "payment-service"
  }
}

# ─── AWS Secrets Manager ─────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "payment_service_secret" {
  name        = "payment-service-secret"
  description = "Database credentials for payment-service"

  tags = {
    Environment = "production"
    Project     = "payment-service"
  }
}

resource "aws_secretsmanager_secret_version" "payment_service_secret_version" {
  secret_id = aws_secretsmanager_secret.payment_service_secret.id
  secret_string = jsonencode({
    DB_HOST     = "payment-db.internal"
    DB_USER     = "paymentuser"
    DB_PASSWORD = "SuperSecretPassword"
  })
}

# ─── IAM Role: EKS Cluster ───────────────────────────────────────────────────

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

# ─── IAM Role: Worker Node Group ─────────────────────────────────────────────

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

# ─── EKS Cluster ─────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "production_eks" {
  name     = "production-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# ─── Managed Node Group ──────────────────────────────────────────────────────

resource "aws_eks_node_group" "payment_nodes" {
  cluster_name    = aws_eks_cluster.production_eks.name
  node_group_name = "payment-nodes"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 9
    max_size     = 12
    min_size     = 5
  }

  instance_types = ["t3.micro"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]
}
# ─── EKS Access Entry for root user ─────────────────────────────────────────

resource "aws_eks_access_entry" "root_admin" {
  cluster_name  = aws_eks_cluster.production_eks.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "root_admin" {
  cluster_name  = aws_eks_cluster.production_eks.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.root_admin]
}


data "tls_certificate" "eks" {
  url = aws_eks_cluster.production_eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.production_eks.identity[0].oidc[0].issuer
}

# ─── IRSA Role: payment-service-irsa-role ────────────────────────────────────

resource "aws_iam_role" "payment_service_irsa_role" {
  name = "payment-service-irsa-role"

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
            "${replace(aws_eks_cluster.production_eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:payment:payment-service-sa"
            "${replace(aws_eks_cluster.production_eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "payment_service_irsa_policy" {
  name = "payment-service-irsa-policy"
  role = aws_iam_role.payment_service_irsa_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.payment_service_secret.arn
      }
    ]
  })
}

# ─── IRSA Role: AWS Load Balancer Controller ─────────────────────────────────

resource "aws_iam_role" "alb_controller_irsa_role" {
  name = "aws-load-balancer-controller-irsa-role"

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
            "${replace(aws_eks_cluster.production_eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(aws_eks_cluster.production_eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# AWS managed policy for ALB controller (must be created separately in real env)
resource "aws_iam_role_policy" "alb_controller_policy" {
  name = "AWSLoadBalancerControllerIAMPolicy"
  role = aws_iam_role.alb_controller_irsa_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*", "ec2:*", "iam:CreateServiceLinkedRole"]
        Resource = "*"
      }
    ]
  })
}

# ─── GitHub Actions OIDC & IAM Role ──────────────────────────────────────────

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "github_actions_ecr_role" {
  name = "github-actions-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Manikandan23005/Devops-Exercise:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_ecr_policy" {
  name = "github-actions-ecr-policy"
  role = aws_iam_role.github_actions_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  value = aws_eks_cluster.production_eks.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.production_eks.endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.payment_service.repository_url
}

output "payment_irsa_role_arn" {
  value = aws_iam_role.payment_service_irsa_role.arn
}

output "alb_controller_irsa_role_arn" {
  value = aws_iam_role.alb_controller_irsa_role.arn
}

output "secret_arn" {
  value = aws_secretsmanager_secret.payment_service_secret.arn
}
