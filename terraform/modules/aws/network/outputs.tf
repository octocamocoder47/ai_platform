output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_system_subnet_ids" {
  description = "Private system subnet IDs"
  value       = aws_subnet.private_system[*].id
}

output "private_gpu_subnet_ids" {
  description = "Private GPU subnet IDs"
  value       = aws_subnet.private_gpu[*].id
}

output "private_subnet_ids" {
  description = "All private subnet IDs"
  value       = concat(aws_subnet.private_system[*].id, aws_subnet.private_gpu[*].id)
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = var.enable_transit_gateway ? aws_ec2_transit_gateway.main[0].id : null
}

output "transit_gateway_arn" {
  description = "Transit Gateway ARN"
  value       = var.enable_transit_gateway ? aws_ec2_transit_gateway.main[0].arn : null
}

output "nat_eips" {
  description = "NAT Gateway EIPs"
  value       = aws_eip.nat[*].public_ip
}

output "vpc_endpoint_s3_id" {
  description = "S3 VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_interface_ids" {
  description = "Interface VPC Endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}
