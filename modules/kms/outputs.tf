output "key_arns" {
  description = "Map of purpose -> key ARN (e.g. key_arns[\"rds\"] for the rds module's kms_key_id)"
  value       = { for k, key in aws_kms_key.this : k => key.arn }
}

output "key_ids" {
  description = "Map of purpose -> key ID"
  value       = { for k, key in aws_kms_key.this : k => key.key_id }
}

output "alias_names" {
  description = "Map of purpose -> alias name (alias/<name>-<purpose>)"
  value       = { for k, a in aws_kms_alias.this : k => a.name }
}

output "alias_arns" {
  description = "Map of purpose -> alias ARN"
  value       = { for k, a in aws_kms_alias.this : k => a.arn }
}
