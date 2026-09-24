variable "name" {
  description = "Name prefix for all resources, e.g. client-a-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: lowercase letters, digits, hyphens."
  }
}

variable "vpc_id" {
  description = "VPC to create the endpoints in"
  type        = string
}
variable "subnet_ids" {
  description = "Subnets for interface endpoint ENIs (one per AZ, normally the private subnets)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet."
  }
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the endpoints on HTTPS (normally the private subnet CIDRs)"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_cidrs must contain at least one valid CIDR block."
  }
}

variable "interface_services" {
  description = "AWS services to reach privately through interface endpoints"
  type        = list(string)
  default = [
    "ecr.api",              # image metadata / registry auth
    "ecr.dkr",              # image pulls
    "sts",                  # IRSA: pods swap their token for AWS credentials
    "logs",                 # Fluent Bit / CloudWatch agent
    "secretsmanager",       # External Secrets Operator
    "ec2",                  # VPC CNI + Load Balancer Controller
    "elasticloadbalancing", # Load Balancer Controller creates the ALB
  ]
}

variable "private_dns_enabled" {
  description = "Resolve the normal AWS service names to the endpoint IPs inside the VPC"
  type        = bool
  default     = true
}

variable "enable_s3_gateway" {
  description = "Create the S3 gateway endpoint (free; ECR stores image layers in S3)"
  type        = bool
  default     = true
}

variable "route_table_ids" {
  description = "Route tables that get the S3 gateway route (normally the private route table only)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}