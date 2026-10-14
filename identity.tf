data "aws_caller_identity" "current" {}

output "aws_account_id" {
  description = "AWS account used by this Terraform configuration."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_ig_id" {
  description = "AWS internet gateway ID"
  value       = aws_internet_gateway.lab.id
}

output "aws_rt_id" {
  description = "AWS route table id"
  value       = aws_route_table.app.id
}

output "aws_route" {
  description = "Destination CIDR for the internet route."
  value       = aws_route.internet.destination_cidr_block
}

output "aws_subnet_cidr" {
  description = "Application subnet IPv4 CIDR."
  value       = aws_subnet.app.cidr_block
}

