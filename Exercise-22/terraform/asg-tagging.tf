# Terraform code to tag existing EKS Auto Scaling Groups (ASG) for Auto Discovery
# Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group_tag

variable "asg_names" {
  type        = list(string)
  description = "List of Auto Scaling Group names to tag for Cluster Autoscaler"
  default     = [] # Users can override this with their actual ASG names
}

resource "aws_autoscaling_group_tag" "ca_enabled" {
  for_each               = toset(var.asg_names)
  autoscaling_group_name = each.value

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "ca_cluster" {
  for_each               = toset(var.asg_names)
  autoscaling_group_name = each.value

  tag {
    key                 = "k8s.io/cluster-autoscaler/production-eks"
    value               = "owned"
    propagate_at_launch = true
  }
}
