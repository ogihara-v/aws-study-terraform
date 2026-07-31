#---------------------プロバイダー設定------------------------
terraform {
  required_version = ">= 1.0.0" # ver1.0.0以上の環境に対応

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" #ver5.0以上を指定
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# EC2用の最新Amazon Linux 2023 AMIを動的取得
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
#---------------------プロバイダー設定------------------------

#---------------------ネットワーク基盤------------------------
# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

# パブリックサブネット(ALB・EC2用)
resource "aws_subnet" "publicsubnet_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet-1a"
  }
}

# パブリックサブネット
resource "aws_subnet" "publicsubnet_1c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet-1c"
  }
}

# プライベートサブネット（RDS用）
resource "aws_subnet" "privatesubnet_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.project_name}-private-subnet-1a"
  }
}

# プライベートサブネット（RDS冗長化）
resource "aws_subnet" "privatesubnet_1c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.project_name}-private-subnet-1c"
  }
}

# ルートテーブルの作成(宛先：0.0.0.0/0, 送信先：IGW)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-route-table"
  }
}

# パブリックサブネット化(IGWへの経路を持つルートテーブルを紐づけ)
resource "aws_route_table_association" "public_rt_assoc_1a" {
  subnet_id      = aws_subnet.publicsubnet_1a.id
  route_table_id = aws_route_table.public_rt.id
}

# ALBを配置する「1c」もネットに繋がるように関連付け
resource "aws_route_table_association" "public_rt_assoc_1c" {
  subnet_id      = aws_subnet.publicsubnet_1c.id
  route_table_id = aws_route_table.public_rt.id
}

#---------------------ネットワーク基盤------------------------

#---------------------セキュリティグループ------------------------
# EC2のセキュリティグループ
resource "aws_security_group" "ec2_sg" {
  name   = "${var.project_name}-ec2-sg"
  vpc_id = aws_vpc.main.id
}

# インバウンドルール：8080はALBのSGからのみ許可
resource "aws_vpc_security_group_ingress_rule" "web_port" {
  security_group_id = aws_security_group.ec2_sg.id
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  #cidr_ipv4 = var.my_ip →ALB作成のため不要になる
  referenced_security_group_id = aws_security_group.alb_sg.id
}

# インバウンドルール：SSHは管理者のIPのみ許可
resource "aws_vpc_security_group_ingress_rule" "web_ssh" {
  security_group_id = aws_security_group.ec2_sg.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip
}

# アウトバウンドルール：外向けの通信は全て許可
resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.ec2_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# RDSセキュリティグループ
resource "aws_security_group" "rds_sg" {
  name   = "${var.project_name}-rds-sg"
  vpc_id = aws_vpc.main.id
}

# インバウンドルール：MySQL通信はEC2のSGからのみ許可
resource "aws_vpc_security_group_ingress_rule" "rds_mysql" {
  security_group_id            = aws_security_group.rds_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ec2_sg.id
}

# アウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ALBセキュリティグループ
resource "aws_security_group" "alb_sg" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.main.id
}

# インバウンドルール(HTTP、インターネットから許可)
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# アウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
#---------------------セキュリティグループ------------------------

#---------------------アプリ層------------------------
# EC2
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  subnet_id              = aws_subnet.publicsubnet_1a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags = {
    Name = "${var.project_name}-web"
  }
}
#---------------------アプリ層------------------------

#---------------------ロードバランサー層------------------------
resource "aws_alb" "main" {
  name               = "${var.project_name}-elb"
  load_balancer_type = "application" # ALBと指定
  internal           = false
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [
    aws_subnet.publicsubnet_1a.id,
    aws_subnet.publicsubnet_1c.id,
  ]

  tags = {
    Name = "${var.project_name}-elb"
  }
}

resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-elb-tg"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
  port        = 8080
  protocol    = "HTTP"

  health_check {
    protocol            = "HTTP"
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-elb-tg"
  }
}

# EC2をターゲットグループに登録
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.web.id
  port             = 8080
}

# ELBリスナー
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_alb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
#---------------------ロードバランサー層------------------------

#---------------------データベース層------------------------
# DBサブネットグループ
resource "aws_db_subnet_group" "main" {
  name = "${var.project_name}-rds-subnet-group"
  subnet_ids = [
    aws_subnet.privatesubnet_1a.id,
    aws_subnet.privatesubnet_1c.id,
  ]

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

# RDS
resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-rds"
  allocated_storage      = 20
  instance_class         = "db.t4g.micro"
  port                   = 3306
  storage_type           = "gp3"
  engine                 = "mysql"
  db_name                = "awsstudy"
  username               = var.db_user
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  backup_retention_period = 1
  backup_window           = "12:00-13:00"
  maintenance_window      = "sun:18:00-sun:19:00"

  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  publicly_accessible         = false
  multi_az                    = false
  deletion_protection         = false
  skip_final_snapshot         = true
}
#---------------------データベース層------------------------

#---------------------アラーム通知設定------------------------
resource "aws_sns_topic" "alarm_topic" {
  name = "${var.project_name}-alarm-topic"

  tags = {
    Name = "${var.project_name}-alarm-topic"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "EC2-CPU-Alarm"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    InstanceId = aws_instance.web.id
  }

  alarm_actions      = [aws_sns_topic.alarm_topic.arn]
  treat_missing_data = "breaching"
}
#---------------------アラーム通知設定------------------------

#---------------------WAF設定------------------------
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "awsStudyACL"
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "commonRules"
    }
  }
}

resource "aws_cloudwatch_log_group" "waf_log" {
  name              = "aws-waf-logs-study"
  retention_in_days = 7
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_log.arn]
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_alb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
#---------------------WAF設定------------------------