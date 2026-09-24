output "vpc_id" {
  value = module.network.vpc_id
}

output "vpce_security_group_id" {
  value = module.vpc_endpoints.security_group_id
}

output "interface_endpoint_ids" {
  value = module.vpc_endpoints.interface_endpoint_ids
}

output "s3_endpoint_id" {
  value = module.vpc_endpoints.s3_endpoint_id
}