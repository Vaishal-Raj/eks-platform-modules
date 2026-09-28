output "key_arns" {
  value = module.kms.key_arns
}

output "alias_names" {
  value = module.kms.alias_names
}

output "encrypted_log_group" {
  value = aws_cloudwatch_log_group.encrypted.name
}
