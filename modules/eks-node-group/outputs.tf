output "node_group_name" {
  description = "Managed node group name"
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "Managed node group ARN"
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "ACTIVE when healthy"
  value       = aws_eks_node_group.this.status
}

output "node_role_arn" {
  description = "IAM role the nodes run as"
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "IAM role name (to attach more policies from outside)"
  value       = aws_iam_role.node.name
}

output "launch_template_id" {
  description = "Launch template used by the nodes"
  value       = aws_launch_template.this.id
}

output "autoscaling_group_names" {
  description = "Auto Scaling groups EKS created for this node group"
  value       = flatten([for r in aws_eks_node_group.this.resources : [for a in r.autoscaling_groups : a.name]])
}
