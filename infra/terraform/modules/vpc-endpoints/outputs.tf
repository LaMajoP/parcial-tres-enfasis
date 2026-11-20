output "endpoint_security_group_id" { value = aws_security_group.endpoints.id }
output "execute_api_vpce_id" { value = aws_vpc_endpoint.interface["execute-api"].id }
