#########################################
# gj-lab ASG (1대 동결 + 고정 AMI)
#########################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# ===== 변수 =====
variable "vpc_id" {
  type    = string
  default = "vpc-009884452bcbdb7b7"
}

variable "public_subnet_ids" {
  type = list(string)
  default = [
    "subnet-02f862538546caf3e",
    "subnet-043862d181e3189a3"
  ]
}

variable "ami_id" {
  description = "이미 만들어둔 AMI ID"
  type        = string
  default     = "ami-0a71e3eb8b23101ed" # ✅ Ubuntu 24.04 (공식)
}

# ===== Security Groups =====
resource "aws_security_group" "alb_sg" {
  name        = "gj-lab-alb-sg"
  description = "ALB 80/443"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj-lab-alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "gj-lab-app-sg"
  description = "App 8080 + SSH"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj-lab-app-sg" }
}

# ===== IAM (EC2 → SSM 접근) =====
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_role" {
  name               = "gj-lab-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "gj-lab-app-profile"
  role = aws_iam_role.app_role.name
}

# ===== Launch Template =====
resource "aws_launch_template" "lt" {
  name_prefix   = "gj-lab-lt-"
  image_id      = var.ami_id
  instance_type = "t3.micro"
  key_name      = "gj-kor-aiot" # ✅ SSH 키

  iam_instance_profile {
    name = aws_iam_instance_profile.app_profile.name
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "gj-lab-ec2"
      Project = "gj-lab"
    }
  }
}

# ===== Target Group + ALB + Listener =====
resource "aws_lb_target_group" "tg" {
  name        = "gj-lab-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    matcher             = "200-499"
    interval            = 60
    unhealthy_threshold = 5
    healthy_threshold   = 2
    timeout             = 10
  }
}

resource "aws_lb" "alb" {
  name               = "gj-lab-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ===== Auto Scaling Group (1대 유지 + 교체 없음) =====
resource "aws_autoscaling_group" "asg" {
  name                = "gj-lab-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1
  health_check_type   = "EC2"
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Default" # ✅ 항상 기본 버전
  }

  protect_from_scale_in = true # ✅ 삭제 방지

  lifecycle {
    ignore_changes = [
      desired_capacity,
      launch_template,
    ]
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      instance_warmup        = 300
    }
    triggers = [] # ✅ 변경에도 교체 없음
  }

  tag {
    key                 = "Project"
    value               = "gj-lab"
    propagate_at_launch = true
  }
}

# ===== 출력 =====
output "alb_dns" {
  value = aws_lb.alb.dns_name
}
