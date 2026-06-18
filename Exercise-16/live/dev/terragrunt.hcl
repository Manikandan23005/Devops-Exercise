include "root" {
  path = find_in_parent_folders()
}

locals {
  environment = "dev"
  cluster_name = "eks-dev-cluster"
  node_group_desired = 2
  node_group_min = 1
  node_group_max = 4
  instance_type = "t3.small"
}

terraform {
  source = "../../modules//eks-cluster"
}

inputs = {
  environment      = local.environment
  cluster_name     = local.cluster_name
  kubernetes_version = "1.32"
  
  node_group_name = "${local.cluster_name}-ng-dev"
  node_group_desired = local.node_group_desired
  node_group_min = local.node_group_min
  node_group_max = local.node_group_max
  instance_types = [local.instance_type]
  disk_size = 50
  
  tags = {
    Environment = local.environment
    ManagedBy   = "Terragrunt"
    Project     = "EKS-Platform"
  }
}
