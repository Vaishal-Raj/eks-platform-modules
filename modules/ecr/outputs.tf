output "registry_url" {
  description = "Registry host, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com"
  value       = local.registry_url
}

output "repository_urls" {
  description = "Map of repo key -> image URL to push/pull (e.g. repository_urls[\"api\"])"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of repo key -> repository ARN"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_names" {
  description = "Map of repo key -> repository name (<name>/<key>)"
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}

output "pull_through_cache_urls" {
  description = "Map of cache prefix -> base URL. registry.k8s.io/pause:3.10 becomes <k8s url>/pause:3.10"
  value = {
    for prefix, r in var.pull_through_cache_rules :
    prefix => "${local.registry_url}/${prefix}"
  }
}

output "pull_through_cache_upstreams" {
  description = "Map of cache prefix -> upstream registry it mirrors"
  value       = { for prefix, r in var.pull_through_cache_rules : prefix => r.upstream_registry_url }
}

output "pull_through_cache_policy_json" {
  description = "IAM policy JSON to attach to the EKS node role so first pulls can create cache repositories (null if no cache rules)"
  value       = one(data.aws_iam_policy_document.cache_pull[*].json)
}
