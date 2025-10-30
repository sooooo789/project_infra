
# ✅ Internet Gateway + Route Table 연결 추가
resource "aws_internet_gateway" "my_igw" {
  vpc_id = local.vpc_id
  tags = {
    Name = "gj-lab-igw"
  }
}

resource "aws_route_table" "my_rt" {
  vpc_id = local.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
  tags = {
    Name = "gj-lab-public-rt"
  }
}

resource "aws_route_table_association" "public_2a_assoc" {
  subnet_id      = aws_subnet.public_2a.id
  route_table_id = aws_route_table.my_rt.id
}

resource "aws_route_table_association" "public_2c_assoc" {
  subnet_id      = aws_subnet.public_2c.id
  route_table_id = aws_route_table.my_rt.id
}



#########################################
# gj-lab ASG (1대 동결 + 고정 AMI) - 형님 계정용 완성본
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

#########################################
# 1️⃣ 내 계정용 VPC + Subnet 자동 생성
#########################################

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name    = "gj-lab-vpc"
    Project = "gj-lab"
  }
}

resource "aws_subnet" "public_2a" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = { Name = "gj-lab-public-2a" }
}

resource "aws_subnet" "public_2c" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  tags = { Name = "gj-lab-public-2c" }
}

#########################################
# 2️⃣ 로컬 변수로 참조
#########################################
locals {
  vpc_id            = aws_vpc.my_vpc.id
  public_subnet_ids = [
    aws_subnet.public_2a.id,
    aws_subnet.public_2c.id
  ]
}

#########################################
# 3️⃣ Security Groups
#########################################

resource "aws_security_group" "alb_sg" {
  name        = "gj-lab-alb-sg"
  description = "ALB 80/443"
  vpc_id      = local.vpc_id

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
  vpc_id      = local.vpc_id

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

#########################################
# 4️⃣ IAM Role for EC2 (SSM 접근)
#########################################

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

#########################################
# 5️⃣ Launch Template (EC2)
#########################################

resource "aws_launch_template" "lt" {
  name_prefix   = "gj-lab-lt-"
  image_id      = "ami-0a71e3eb8b23101ed" # ✅ 친구의 퍼블릭 AMI
  instance_type = "t3.micro"
  key_name      = "gj-kor-aiot" # 형님 SSH 키 이름

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

#########################################
# 6️⃣ Target Group + ALB + Listener
#########################################

resource "aws_lb_target_group" "tg" {
  name        = "gj-lab-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
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
  subnets            = local.public_subnet_ids
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

#########################################
# 7️⃣ Auto Scaling Group (EC2 한 대 유지)
#########################################

resource "aws_autoscaling_group" "asg" {
  name                = "gj-lab-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1
  health_check_type   = "EC2"
  vpc_zone_identifier = local.public_subnet_ids
  target_group_arns   = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Default"
  }

  protect_from_scale_in = true

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
    triggers = []
  }

  tag {
    key                 = "Project"
    value               = "gj-lab"
    propagate_at_launch = true
  }
}

#########################################
# 8️⃣ 출력 (ALB 주소)
#########################################
output "alb_dns" {
  value = aws_lb.alb.dns_name
}
