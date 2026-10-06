output "cluster_name" {
  description = "Cluster name (eks-node-group, eks-addons, kubectl)"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "Cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL (kubernetes/helm providers)"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate of the API server (kubernetes/helm providers)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version running"
  value       = aws_eks_cluster.this.version
}

output "platform_version" {
  description = "EKS platform version (eks.N)"
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_security_group_id" {
  description = "Security group EKS created for the control plane and managed nodes"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_role_arn" {
  description = "IAM role of the control plane"
  value       = aws_iam_role.cluster.arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (https://oidc.eks...)"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA trust policies (irsa-role module), or null"
  value       = one(aws_iam_openid_connect_provider.this[*].arn)
}

output "oidc_provider" {
  description = "Issuer without https:// (used in IRSA condition keys: <this>:sub, <this>:aud)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "log_group_name" {
  description = "Control plane log group, or null if logging is off"
  value       = one(aws_cloudwatch_log_group.this[*].name)
}
