variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_group_name" {
  description = "Name for the node group"
  type        = string
}

variable "node_group_desired" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "node_group_min" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1
}

variable "node_group_max" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 4
}

variable "instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
