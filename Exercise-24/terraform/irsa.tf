
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "eks_cluster_name" {
  type    = string
  default = "production-eks"
}

data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

data "aws_iam_openid_connect_provider" "eks_oidc" {
  url = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_policy" "customer_dynamodb_policy" {
  name        = "Exercise24DynamoDBAccessPolicy"
  description = "IAM Policy allowing Flask App to read, write, and update customer table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:ap-south-1:028987315631:table/exercise24-customers"
      }
    ]
  })
}

resource "aws_iam_role" "customer_irsa_role" {
  name = "exercise24-customer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks_oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:exercise24:customer-sa"
            "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "customer_dynamodb_attach" {
  policy_arn = aws_iam_policy.customer_dynamodb_policy.arn
  role       = aws_iam_role.customer_irsa_role.name
}

output "customer_irsa_role_arn" {
  description = "ARN of the Customer IRSA IAM Role"
  value       = aws_iam_role.customer_irsa_role.arn
}
