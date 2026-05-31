# Output the VPC name
output "vpc_name" {
    value = var.vpc_name
}

# Output the VPC ID
output "vpc_id" {
    value = aws_vpc.main.id
}

# Output the list of public subnet IDs
output "public_subnet_ids" {
    value = aws_subnet.public[*].id
}

# Output the list of private subnet IDs
output "private_subnet_ids" {
    value = aws_subnet.private[*].id
}