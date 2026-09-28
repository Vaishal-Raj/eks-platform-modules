provider "aws" {
  region = "us-east-1" # CLOUDFRONT-scope WAF must be created here

  # Tags added by the organization's Cloud Custodian (an SCP forbids deleting them)
  ignore_tags {
    keys         = ["Owner"]
    key_prefixes = ["c7n-"]
  }

  default_tags {
    tags = {
      Project   = "poc-gvr"
      Purpose   = "module-example"
      ManagedBy = "terraform"
    }
  }
}

module "waf" {
  source = "../../modules/waf"

  name              = "waf-example"
  trusted_ip_cidrs  = ["203.0.113.10/32"] # documentation range, safe for testing
  blocked_ip_cidrs  = ["198.51.100.0/24"] # documentation range
  blocked_countries = ["KP"]

  logging = {
    enabled        = true
    retention_days = 7
  }
}
