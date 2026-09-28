output "node_security_group_id" {
  description = "sg-node: attach to EKS worker nodes (eks module, M3)"
  value       = aws_security_group.node.id
}

output "rds_security_group_id" {
  description = "sg-rds: attach to the RDS instance (rds module), or null if not created"
  value       = one(aws_security_group.rds[*].id)
}

output "cache_security_group_id" {
  description = "sg-cache: attach to ElastiCache (M3), or null if not created"
  value       = one(aws_security_group.cache[*].id)
}

output "security_group_ids" {
  description = "All created groups by role: node, rds, cache"
  value = {
    node  = aws_security_group.node.id
    rds   = one(aws_security_group.rds[*].id)
    cache = one(aws_security_group.cache[*].id)
  }
}
