output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_instance_id" {
  value = module.rds.instance_id
}

output "engine_version_actual" {
  value = module.rds.engine_version_actual
}

output "master_username" {
  value = module.rds.master_username
}

output "master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "rds_security_group_id" {
  value = module.security_groups.rds_security_group_id
}

output "node_security_group_id" {
  value = module.security_groups.node_security_group_id
}
