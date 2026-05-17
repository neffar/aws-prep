# Search for the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

# IAM Role for EC2 for SSM
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Role Policy Attachment for SSM
# We use an AWS-managed policy so we don't have to write the rules ourselves.
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile for SSM
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Launch Template
resource "aws_launch_template" "app_launch_template" {
  name_prefix   = "app-server-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_security_group.id]
  }

  iam_instance_profile {
   name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y nginx
              systemctl enable nginx
              systemctl start nginx
              echo "<h1>Welcome to my highly secure Auto-Scaled App!</h1>" > /usr/share/nginx/html/index.html
              EOF
  )

  tags = {
    Name = "app_launch_template"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_auto_scaling_group" {
  name_prefix         = "app-asg-"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  
  vpc_zone_identifier = [
    aws_subnet.private_subnet_a.id,
    aws_subnet.private_subnet_b.id
  ]

  target_group_arns   = [aws_lb_target_group.app_load_balancer_target_group.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  launch_template {
    id       = aws_launch_template.app_launch_template.id
    version  = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Target Tracking Scaling Policy based on CPU Utilization
resource "aws_autoscaling_policy" "app_cpu_scaling_policy" {
  name                   = "app-cpu-scaling-policy"
  autoscaling_group_name = aws_autoscaling_group.app_auto_scaling_group.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70.0  # <--- The threshold (70% average CPU usage)
  }
}
