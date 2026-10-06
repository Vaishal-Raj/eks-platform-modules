output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "cluster_version" {
  value = module.eks_cluster.cluster_version
}

output "cluster_security_group_id" {
  value = module.eks_cluster.cluster_security_group_id
}

output "oidc_provider_arn" {
  value = module.eks_cluster.oidc_provider_arn
}

output "admin_principal" {
  value = data.aws_iam_session_context.current.issuer_arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks_cluster.cluster_name}"
}
