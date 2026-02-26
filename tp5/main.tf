terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  profile = var.profile
  region  = var.region
}

# ─── Security Group ALB ────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "tp5-alb-sg"
  description = "ALB public HTTP 80"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "tp5-alb-sg"
    Project    = "AWS-TP"
    Owner      = "ops-student"
    Env        = "dev"
    CostCenter = "TP-Cloud"
  }
}

# ─── Security Group instances ASG ─────────────────────────────────────────
resource "aws_security_group" "app" {
  name        = "tp5-app-sg"
  description = "App - HTTP depuis ALB uniquement"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "tp5-app-sg"
    Project    = "AWS-TP"
    Owner      = "ops-student"
    Env        = "dev"
    CostCenter = "TP-Cloud"
  }
}

# ─── Target Group ─────────────────────────────────────────────────────────
resource "aws_lb_target_group" "tp5" {
  name     = "tp5-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name    = "tp5-tg"
    Project = "AWS-TP"
  }
}

# ─── ALB ──────────────────────────────────────────────────────────────────
resource "aws_lb" "tp5" {
  name               = "tp5-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [var.pub1, var.pub2]

  tags = {
    Name       = "tp5-alb"
    Project    = "AWS-TP"
    Owner      = "ops-student"
    Env        = "dev"
    CostCenter = "TP-Cloud"
  }
}

# ─── Listener ALB ─────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.tp5.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tp5.arn
  }
}

# ─── Launch Template ──────────────────────────────────────────────────────
resource "aws_launch_template" "tp5" {
  name_prefix   = "tp5-lt-"
  image_id      = var.ami_id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = var.instance_profile
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  user_data = base64encode(<<-SCRIPT
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>TP5 - $(hostname) - $(date)</h1>" > /usr/share/nginx/html/index.html
  SCRIPT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name       = "tp5-asg-instance"
      Project    = "AWS-TP"
      Owner      = "ops-student"
      Env        = "dev"
      CostCenter = "TP-Cloud"
    }
  }

  tags = {
    Name    = "tp5-lt"
    Project = "AWS-TP"
  }
}

# ─── NAT Gateway (temporaire pour bootstrap nginx) ────────────────────────
/*resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name    = "tp5-eip-nat"
    Project = "AWS-TP"
  }
}

resource "aws_nat_gateway" "tp5" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.pub1

  tags = {
    Name    = "tp5-nat"
    Project = "AWS-TP"
  }

  depends_on = [aws_eip.nat]
}

resource "aws_route" "private_nat" {
  route_table_id         = var.priv_rt
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.tp5.id

  depends_on = [aws_nat_gateway.tp5]
}*/

# ─── Auto Scaling Group ───────────────────────────────────────────────────
resource "aws_autoscaling_group" "tp5" {
  name                      = "tp5-asg"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = [var.priv1, var.priv2]
  target_group_arns         = [aws_lb_target_group.tp5.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.tp5.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "tp5-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "AWS-TP"
    propagate_at_launch = true
  }

#  depends_on = [aws_nat_gateway.tp5]
}
