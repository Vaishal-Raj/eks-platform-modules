output "role_arn" {
  description = "IRSA role of the controller"
  value       = module.irsa.role_arn
}

output "namespace" {
  description = "Namespace the operator runs in"
  value       = helm_release.this.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.this.name
}

output "chart_version" {
  description = "Installed chart version"
  value       = helm_release.this.version
}

output "service_account_name" {
  description = "ServiceAccount the controller runs as"
  value       = var.service_account_name
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore apps reference in their ExternalSecret (null if not created)"
  value       = var.create_cluster_secret_store ? var.cluster_secret_store_name : null
}
