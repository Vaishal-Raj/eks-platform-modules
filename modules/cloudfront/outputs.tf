output "distribution_id" {
  description = "CloudFront distribution ID (cache invalidations, console)"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Public address, e.g. d1234abcd.cloudfront.net"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "Route 53 zone ID for alias records pointing at this distribution (dns-acm module)"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "vpc_origin_id" {
  description = "CloudFront VPC origin ID"
  value       = aws_cloudfront_vpc_origin.this.id
}

output "vpc_origin_security_group_id" {
  description = "ID of AWS's CloudFront-VPCOrigins-Service-SG in the VPC (the ALB's only allowed source)"
  value       = data.aws_security_group.cloudfront_vpc_origin.id
}
