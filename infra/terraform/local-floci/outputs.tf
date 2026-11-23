output "environment" { value = terraform.workspace }
output "dynamodb_tables" { value = module.dynamodb.table_names }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "local_deployer_role_arn" { value = try(aws_iam_role.local_deployer[0].arn, null) }
output "vpc_id" { value = module.network.vpc_id }
