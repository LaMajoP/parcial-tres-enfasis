aws_region                = "us-east-2"
owner                     = "LaMajoP"
github_repository         = "LaMajoP/parcial-tres-enfasis"
eks_access_principal_arns = ["arn:aws:iam::000000000000:role/aegisvolt-local-deployer"]
availability_zones        = ["us-east-2a", "us-east-2b"]
vpc_cidrs                 = { dev = "10.40.0.0/16", test = "10.41.0.0/16", prod = "10.42.0.0/16" }
enable_private_api        = false
internal_nlb_arn          = null
internal_nlb_dns_name     = null
lab_profile               = true
