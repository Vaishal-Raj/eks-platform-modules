output "web_acl_arn" {
  value = module.waf.web_acl_arn
}

output "capacity" {
  value = module.waf.capacity
}

output "rule_names" {
  value = module.waf.rule_names
}

output "log_group_name" {
  value = module.waf.log_group_name
}
