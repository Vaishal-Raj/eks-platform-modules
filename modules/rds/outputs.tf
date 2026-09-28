output "instance_id" {
  description = "DB instance identifier (e.g. client-a-dev-mysql)"
  value       = aws_db_instance.this.identifier
}

output "instance_arn" {
  description = "DB instance ARN"
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Writer hostname (the app writes here)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "MySQL port"
  value       = aws_db_instance.this.port
}

output "endpoint" {
  description = "Writer host:port"
  value       = aws_db_instance.this.endpoint
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master user name (the password is in Secrets Manager: master_user_secret_arn)"
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS-generated master password (External Secrets Operator reads this in M3)"
  value       = one(aws_db_instance.this.master_user_secret[*].secret_arn)
}

output "replica_address" {
  description = "Read replica hostname (read-only queries), or null if no replica"
  value       = one(aws_db_instance.replica[*].address)
}

output "engine_version_actual" {
  description = "Exact MySQL version running (e.g. 8.4.5)"
  value       = aws_db_instance.this.engine_version_actual
}

output "parameter_group_name" {
  description = "DB parameter group name"
  value       = aws_db_parameter_group.this.name
}

output "subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.this.name
}
