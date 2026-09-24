variable "name" {
  description = "Name prefix for all resources, e.g. client-a-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: lowercase letters, digits, hyphens."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block, e.g. 10.0.0.0/16"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "az_count" {
  description = "How many AZs to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "exclude_zone_ids" {
  description = "AZ IDs to skip, e.g. [\"use1-az3\"] where EKS has no control plane"
  type        = list(string)
  default     = []
}

# ---- Subnet sizing: cidrsubnet(vpc_cidr, newbits, index) ----
# Defaults give the M0 plan for a /16: private /20s at index 0..2, isolated /24s at 48..50.

variable "private_subnet_newbits" {
  description = "Bits added to the VPC prefix for private subnets (/16 + 4 = /20)"
  type        = number
  default     = 4
}

variable "isolated_subnet_newbits" {
  description = "Bits added to the VPC prefix for isolated subnets (/16 + 8 = /24)"
  type        = number
  default     = 8
}

variable "isolated_subnet_offset" {
  description = "First cidrsubnet index for isolated subnets (48 -> 10.0.48.0/24 in a 10.0.0.0/16)"
  type        = number
  default     = 48
}

# ---- DNS ----

variable "enable_dns_support" {
  description = "Enable the Amazon DNS resolver (needed for VPC endpoint private DNS)"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Give instances DNS hostnames (needed for VPC endpoint private DNS)"
  type        = bool
  default     = true
}

# ---- Tags ----

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for private subnets only, e.g. kubernetes.io/role/internal-elb"
  type        = map(string)
  default     = {}
}

variable "isolated_subnet_tags" {
  description = "Extra tags for isolated subnets only"
  type        = map(string)
  default     = {}
}
