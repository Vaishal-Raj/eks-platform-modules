variable "name" {
  description = "Name prefix, e.g. client-a-dev (max 28 chars: ALB and target group names are limited to 32)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,28}$", var.name))
    error_message = "name must be 3-28 chars: lowercase letters, digits, hyphens."
  }
}

variable "vpc_id" {
  description = "VPC the ALB lives in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the ALB (at least 2, in different AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An ALB needs at least 2 subnets in different AZs."
  }
}

variable "listener_port" {
  description = "Port the HTTP listener accepts traffic on"
  type        = number
  default     = 80
}

variable "fixed_response" {
  description = "What the listener returns by default (until traffic is forwarded to the target group)"
  type = object({
    status_code  = optional(string, "200")
    content_type = optional(string, "text/plain")
    message_body = optional(string)
  })
  default = {}
}

variable "create_target_group" {
  description = "Create an empty IP target group, ready for EKS pods (Load Balancer Controller TargetGroupBinding)"
  type        = bool
  default     = true
}

variable "target_port" {
  description = "Port the targets (pods) listen on"
  type        = number
  default     = 8080
}

variable "health_check" {
  description = "Target group health check"
  type = object({
    path                = optional(string, "/")
    matcher             = optional(string, "200-399")
    interval            = optional(number, 15)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}


variable "target_egress_cidrs" {
  description = "Where the ALB may send traffic on target_port (normally the private subnet CIDRs, where pods live)"
  type        = list(string)
  default     = []
}

variable "idle_timeout" {
  description = "Seconds a connection may be idle"
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Block deletion of the ALB (turn on for prod)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}