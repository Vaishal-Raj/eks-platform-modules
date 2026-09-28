output "security_group_ids" {
  value = module.security_groups.security_group_ids
}

output "alb_standin_security_group_id" {
  value = aws_security_group.alb_standin.id
}

output "vpce_standin_security_group_id" {
  value = aws_security_group.vpce_standin.id
}
