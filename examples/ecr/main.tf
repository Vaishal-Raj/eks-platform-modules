provider "aws" {
  region = "us-east-1"

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

# Customer-managed key for the app repositories (ECR uses it through a grant: via_services "ecr")
module "kms" {
  source = "../../modules/kms"

  name = "ecr-example"

  keys = {
    ecr = {
      description             = "ECR app repositories"
      via_services            = ["ecr"]
      deletion_window_in_days = 7 # throwaway test
    }
  }
}

module "ecr" {
  source = "../../modules/ecr"

  name        = "ecr-example"
  kms_key_arn = module.kms.key_arns["ecr"]

  # The demo e-commerce app: React frontend + Node.js API
  repositories = {
    frontend = { force_delete = true } # force_delete: throwaway test only
    api      = { force_delete = true }
  }

  # pull_through_cache_rules: module defaults (public.ecr.aws, registry.k8s.io, quay.io)
}
