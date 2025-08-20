provider "aws" {
  region = var.aws_region

   default_tags {
    tags = {
      Environment = var.environment
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.main.id

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

resource "aws_instance" "ecs_instance" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.ecs_sg.name]
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = "my-app-bucket"
  acl    = "private"
}

resource "aws_db_instance" "db" {
  engine            = "mysql"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  username          = var.username
  password          = var.password
  publicly_accessible = true
}

resource "aws_efs_file_system" "shared_fs" {
  creation_token = "my-product"

  tags = {
    Name = "MyProduct"
  }
}

resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"
}

resource "aws_ecs_task_definition" "my_task" {
  family                   = "my-task"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"

  container_definitions = <<DEFINITION
  [
    {
      "name": "my-container",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ]
    }
  ]
  DEFINITION
}

resource "aws_cloudfront_distribution" "s3_distribution" {

  count = var.environment == "prod" ? 1 : 0

  origin {
    domain_name              = aws_s3_bucket.app_bucket.bucket_regional_domain_name
    origin_id                = "s3-app-bucket"
  }

  enabled             = true
  default_root_object = "index.html"
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-app-bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = var.environment
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}