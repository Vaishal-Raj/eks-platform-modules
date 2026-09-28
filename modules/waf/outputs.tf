output "web_acl_arn" {
  description = "Web ACL ARN (CloudFront's web_acl_id argument takes this ARN)"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "Web ACL ID"
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Web ACL name"
  value       = aws_wafv2_web_acl.this.name
}

output "capacity" {
  description = "WCU used by this web ACL (1500 included; more costs extra)"
  value       = aws_wafv2_web_acl.this.capacity
}

output "rule_names" {
  description = "Names of all rules in the web ACL"
  value       = [for r in aws_wafv2_web_acl.this.rule : r.name]
}

output "log_group_name" {
  description = "WAF log group name, or null if logging is disabled"
  value       = one(aws_cloudwatch_log_group.this[*].name)
}
