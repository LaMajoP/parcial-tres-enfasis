output "repository_urls" { value = { for component, repository in aws_ecr_repository.this : component => repository.repository_url } }
