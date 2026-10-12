output "role_arn" {
  description = "IRSA role of the controller"
  value       = module.irsa.role_arn
}

output "policy_mode" {
  description = "Permission mode in use: target-group-binding or full"
  value       = var.policy_mode
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.this.name
}

output "namespace" {
  description = "Namespace the controller runs in"
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Installed chart version"
  value       = helm_release.this.version
}

output "service_account_name" {
  description = "ServiceAccount the controller runs as"
  value       = var.service_account_name
}
