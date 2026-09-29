output "registry_url" {
  value = module.ecr.registry_url
}

output "repository_urls" {
  value = module.ecr.repository_urls
}

output "pull_through_cache_urls" {
  value = module.ecr.pull_through_cache_urls
}

output "pull_through_cache_policy_json" {
  value = module.ecr.pull_through_cache_policy_json
}
