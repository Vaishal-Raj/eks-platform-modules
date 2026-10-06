output "addon_versions" {
  description = "Map of add-on name -> installed version"
  value       = { for name, a in aws_eks_addon.this : name => a.addon_version }
}

output "addon_arns" {
  description = "Map of add-on name -> add-on ARN"
  value       = { for name, a in aws_eks_addon.this : name => a.arn }
}
