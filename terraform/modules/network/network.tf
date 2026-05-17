# VPC & Networking
resource "aws_vpc" "main_vpc" {
  # 10.0.X.X → These two belong to the VPC. You cannot change them in your subnets.
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Internet Gateway
resource "aws_internet_gateway" "main_internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main_internet_gateway"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat_eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "main_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_a.id

  tags = {
    Name = "main_nat_gateway"
  }

  depends_on = [aws_internet_gateway.main_internet_gateway]
}

# Public Subnet A
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet A"
  }
}

# Public Subnet B
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-3b"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet B"
  }
}

# Private Subnet A
resource "aws_subnet" "private_subnet_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = false
  tags = {
    Name = "Private Subnet A"
  }
}

# Private Subnet B
resource "aws_subnet" "private_subnet_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "eu-west-3b"
  map_public_ip_on_launch = false
  tags = {
    Name = "Private Subnet B"
  }
}

# Routing Table for Public Subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_internet_gateway.id
  }

  tags = {
    Name = "public_route_table"
  }
}

# Routing Table for Private Subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_nat_gateway.id
  }

  tags = {
    Name = "private_route_table"
  }
}

# Associate Public Subnets with the Public Route Table
resource "aws_route_table_association" "public_subnet_a_assoc" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b_assoc" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate Private Subnets with the Private Route Table
resource "aws_route_table_association" "private_subnet_a_assoc" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_b_assoc" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Group for EC2 Instances
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2_security_group"
  description = "Allow SSH inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name = "ec2_security_group"
  }
}

# Rules for EC2 Security Group
resource "aws_vpc_security_group_ingress_rule" "allow_http_from_alb" {
  security_group_id = aws_security_group.ec2_security_group.id
  description       = "Allow HTTP inbound traffic from ALB"

  # Reference the Security Group ID of the ALB
  referenced_security_group_id = aws_security_group.alb_security_group.id

  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

# We will use SSM Session Manager instead of SSH for admin access
# Allowing SSH port 22, needs Bastion Host in the public subnet 
# and you have to allow the Bastion IP in the sg above
# resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
#   security_group_id = aws_security_group.ec2_security_group.id
#   description       = "Allow SSH inbound traffic from IPv4"
#   from_port         = 22
#   ip_protocol       = "tcp"
#   to_port           = 22
#   cidr_ipv4         = aws_vpc.main_vpc.cidr_block
# OR 
#   cidr_ipv4         = "0.0.0.0/0"
# }

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound_ec2" {
  security_group_id = aws_security_group.ec2_security_group.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Security Group for ALB
resource "aws_security_group" "alb_security_group" {
  name        = "alb_security_group"
  description = "Allow HTTP inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name = "alb_security_group"
  }
}

# Rules for ALB Security Group
resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4_alb" {
  security_group_id = aws_security_group.alb_security_group.id
  description       = "Allow HTTP inbound traffic from IPv4"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4_alb" {
  security_group_id = aws_security_group.alb_security_group.id
  description       = "Allow HTTPS inbound traffic from IPv4"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound_alb" {
  security_group_id = aws_security_group.alb_security_group.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Application Load Balancer
resource "aws_lb" "app_load_balancer" {
  name               = "app_load_balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_security_group.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
   
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  # access_logs {
  #   bucket  = aws_s3_bucket.lb_logs.id
  #   prefix  = "app_load_balancer"
  #   enabled = true
  # }
}

# Target Group for ALB
resource "aws_lb_target_group" "app_load_balancer_target_group" {
  name     = "app_load_balancer_target_group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id
  target_type = "instance"

  health_check {
    enabled             = true
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 3
  }
}

# Listener for ALB to forward traffic to the target group
resource "aws_lb_listener" "app_load_balancer_listener" {
  load_balancer_arn  = aws_lb.app_load_balancer.arn
  port               = "80"
  protocol           = "HTTP"

  # OR (One listener by protocol, comment the above)
  # port             = "443"
  # protocol         = "HTTPS"
  # ssl_policy       = "ELBSecurityPolicy-2016-08"
  # certificate_arn  = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_load_balancer_target_group.arn
  }
}
