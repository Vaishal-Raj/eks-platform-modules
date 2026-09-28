output "alb_arn" {
  description = "ALB ARN (the cloudfront module's VPC origin points here)"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Internal DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB"
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB security group ID (the cloudfront module adds the inbound rule here)"
  value       = aws_security_group.this.id
}

output "listener_arn" {
  description = "HTTP listener ARN"
  value       = aws_lb_listener.http.arn
}

output "listener_port" {
  description = "HTTP listener port"
  value       = aws_lb_listener.http.port
}

output "target_group_arn" {
  description = "Empty IP target group ARN for EKS, or null if not created"
  value       = one(aws_lb_target_group.this[*].arn)
}

# alb_arn, security_group_id and listener_port are exactly what the cloudfront module will need.
