output "vpc_id" {
  description = "The ID of the VPC"
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
    description = "The IDs of the public subnets"
    value = [
        aws_subnet.public_subnet_a.id,
        aws_subnet.public_subnet_b.id,
        aws_subnet.public_subnet_c.id
    ]
}

output "private_app_subnets_ids" {
    description = "The IDs of the private app subnets"
    value = [
        aws_subnet.private_app_subnet_a.id,
        aws_subnet.private_app_subnet_b.id,
        aws_subnet.private_app_subnet_c.id
    ]
}

output "private_data_subnets_ids" {
    description = "The IDs of the private data subnets"
    value = [
        aws_subnet.private_data_subnet_a.id,
        aws_subnet.private_data_subnet_b.id,
        aws_subnet.private_data_subnet_c.id
    ]
}

output "security_groups_ids" {
    description = "The IDs of the security groups"
    value = {
        alb = aws_security_group.alb_sg.id,
        app = aws_security_group.app_sg.id,
        db = aws_security_group.db_sg.id
    }
}

