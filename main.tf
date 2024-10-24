terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucketmartinz"
    key            = "terraform/state/gitmartinz.tfstate"

    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
  }
}


provider "aws" {
  region = var.aws_region  # Define the AWS region
}

resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "my_vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public_subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.private_subnet_cidr_block
  availability_zone = "us-east-1a"
  tags = {
    Name = "private_subnet"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.private_subnet_2_cidr_block
  availability_zone = "us-east-1b"
  tags = {
    Name = "private_subnet_2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "my_igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public_route_table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_elastic_beanstalk_application" "my_app" {
  name        = "my_app"
  description = "Elastic Beanstalk application"
}

resource "random_string" "db_username" {
  length  = 16
  special = false
}

resource "random_string" "db_password" {
  length           = 32
  special          = true
  override_special = "_%+=~"
}

resource "aws_kms_key" "db_kms_key" {
  description = "KMS key for RDS credentials encryption"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "rds_credentials9"
  description = "Database credentials for RDS"
  kms_key_id  = aws_kms_key.db_kms_key.arn
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = random_string.db_username.result
    password = random_string.db_password.result
  })
}

resource "aws_iam_role" "elastic_beanstalk_role" {
  name = "my-elastic-beanstalk-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
        Effect    = "Allow"
        Sid       = ""
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "elastic_beanstalk_web_policy_attachment" {
  name       = "my-elastic-beanstalk-web-attachment"
  roles      = [aws_iam_role.elastic_beanstalk_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_instance_profile" {
  name = "my-elastic-beanstalk-instance-profile"
  role = aws_iam_role.elastic_beanstalk_role.name
}

resource "aws_elastic_beanstalk_environment" "my-env" {
  application        = aws_elastic_beanstalk_application.my_app.name
  name               = "my-env"
  solution_stack_name = "64bit Amazon Linux 2 v5.9.6 running Node.js 16"
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "1"
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = aws_subnet.public_subnet.id
  }
}

resource "aws_security_group" "eb_sg" {
  name        = "eb_security_group"
  description = "Elastic Beanstalk security group"
  vpc_id      = aws_vpc.my_vpc.id
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
}

resource "aws_db_subnet_group" "my_db_subnet_group" {
  name       = "my_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]
  tags = {
    Name = "my_db_subnet_group"
  }
}

resource "aws_security_group" "my_rds_sg" {
  vpc_id = aws_vpc.my_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_subnet.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "my_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_subnet_group_name = aws_db_subnet_group.my_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.my_rds_sg.id]
  username             = random_string.db_username.result
  password             = random_string.db_password.result
  skip_final_snapshot  = true
  tags = {
    Name = "my_rds_instance"
  }
}
