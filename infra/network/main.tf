resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "atlas-fintech-network-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "eu-west-1a"
    map_public_ip_on_launch = true

    tags = {
      Name = "atlas-fintech-public-subnet-a"
    }
}

resource "aws_subnet" "public_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "eu-west-1b"
    map_public_ip_on_launch = true

    tags = {
      Name = "atlas-fintech-public-subnet-b"
    }
}

resource "aws_subnet" "public_subnet_c" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.3.0/24"
    availability_zone = "eu-west-1c"
    map_public_ip_on_launch = true

    tags = {
      Name = "atlas-fintech-public-subnet-c"
    }
}

resource "aws_subnet" "private_app_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.4.0/24"
    availability_zone = "eu-west-1a"
    map_public_ip_on_launch = false

    tags = {
      Name = "atlas-fintech-private-app-subnet-a"
    }
}

resource "aws_subnet" "private_app_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.5.0/24"
    availability_zone = "eu-west-1b"
    map_public_ip_on_launch = false

    tags = {
      Name = "atlas-fintech-private-app-subnet-b"
    }
}

resource "aws_subnet" "private_app_subnet_c" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.6.0/24"
    availability_zone = "eu-west-1c"
    map_public_ip_on_launch = false

    tags = {
      Name = "atlas-fintech-private-app-subnet-c"
    }
}

resource "aws_subnet" "private_data_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.7.0/24"
    availability_zone = "eu-west-1a"
    map_public_ip_on_launch = false

    tags = {
      Name = "atlas-fintech-private-data-subnet-a"
    }
}

resource "aws_subnet" "private_data_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.8.0/24"
    availability_zone = "eu-west-1b"
    map_public_ip_on_launch = false

    tags = {
      Name = "atlas-fintech-private-data-subnet-b"
    }
}

resource "aws_subnet" "private_data_subnet_c" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.9.0/24"
    availability_zone = "eu-west-1c"
    map_public_ip_on_launch = false

    tags = {
      Name = "atlas-fintech-private-data-subnet-c"
    }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "atlas-fintech-public-rt"
  }
}

resource "aws_eip" "eip_a" {
    domain = "vpc"

    tags = {
      Name = "atlas-fintech-nat-eip-a"
    }
}

resource "aws_eip" "eip_b" {
    domain = "vpc"

    tags = {
      Name = "atlas-fintech-nat-eip-b"
    }
}

resource "aws_eip" "eip_c" {
    domain = "vpc"

    tags = {
      Name = "atlas-fintech-nat-eip-c"
    }
}

resource "aws_nat_gateway" "nat_a" {
    allocation_id = aws_eip.eip_a.id
    subnet_id = aws_subnet.public_subnet_a.id
}

resource  "aws_nat_gateway" "nat_b" {
    allocation_id = aws_eip.eip_b.id
    subnet_id = aws_subnet.public_subnet_b.id
}

resource  "aws_nat_gateway" "nat_c" {
    allocation_id = aws_eip.eip_c.id
    subnet_id = aws_subnet.public_subnet_c.id
}

resource "aws_route_table" "private_app_rt_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }

  tags = {
    Name = "atlas-fintech-private-app-rt_a"
  }
}

resource "aws_route_table" "private_app_rt_b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }

  tags = {
    Name = "atlas-fintech-private-app-rt_b"
  }
}

resource "aws_route_table" "private_app_rt_c" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_c.id
  }

  tags = {
    Name = "atlas-fintech-private-app-rt_c"
  }
}

resource "aws_route_table_association" "public_subnet_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_c" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_app_subnet_a" {
  subnet_id      = aws_subnet.private_app_subnet_a.id
  route_table_id = aws_route_table.private_app_rt_a.id
}

resource "aws_route_table_association" "private_app_subnet_b" {
  subnet_id      = aws_subnet.private_app_subnet_b.id
  route_table_id = aws_route_table.private_app_rt_b.id
}

resource "aws_route_table_association" "private_app_subnet_c" {
  subnet_id      = aws_subnet.private_app_subnet_c.id
  route_table_id = aws_route_table.private_app_rt_c.id
}

resource "aws_route_table" "private_data_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "atlas-fintech-private-data-rt"
  }
}

resource "aws_route_table_association" "private_data_subnet_a" {
  subnet_id      = aws_subnet.private_data_subnet_a.id
  route_table_id = aws_route_table.private_data_rt.id
}

resource "aws_route_table_association" "private_data_subnet_b" {
  subnet_id      = aws_subnet.private_data_subnet_b.id
  route_table_id = aws_route_table.private_data_rt.id
}

resource "aws_route_table_association" "private_data_subnet_c" {
  subnet_id      = aws_subnet.private_data_subnet_c.id
  route_table_id = aws_route_table.private_data_rt.id
}

resource "aws_security_group" "alb_sg" {
  name        = "atlas-fintech-alb-sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.main.id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 80
    to_port     = 80
    protocol     = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
}

resource "aws_security_group" "app_sg" {
  name        = "atlas-fintech-app-sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 5432
    to_port     = 5432      
    protocol    = "tcp"
    cidr_blocks = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol     = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol     = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "atlas-fintech-db-sg"
  description = "Allow inbound traffic on port 5432"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol     = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  
 }
} 