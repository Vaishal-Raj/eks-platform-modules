output "url" {
  description = "Open this: CloudFront -> WAF -> VPC origin -> internal ALB"
  value       = "https://${module.cloudfront.domain_name}"
}

output "distribution_id" {
  value = module.cloudfront.distribution_id
}

output "alb_arn" {
  value = module.alb.alb_arn
}

output "alb_security_group_id" {
  value = module.alb.security_group_id
}

output "vpc_origin_security_group_id" {
  value = module.cloudfront.vpc_origin_security_group_id
}

output "internet_gateway_id" {
  value = module.network.internet_gateway_id
}

output "waf_capacity" {
  value = module.waf.capacity
}
