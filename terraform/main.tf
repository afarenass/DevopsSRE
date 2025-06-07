terraform {
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/70332319/terraform/state/default"
    lock_address   = "https://gitlab.com/api/v4/projects/70332319/terraform/state/default/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/70332319/terraform/state/default/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    username       = "gitlab-ci-token"
  }
}

provider "aws" {
  region = var.region
}

# Vpc Configuration

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support  = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-b"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_elasticache_subnet_group" "elasticache" {
  name       = "main-elasticache-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "elasticache-subnet-group"
  }
}

resource "aws_security_group" "db" {
  name        = "db-sg"
  description = "Allow DB access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Solo tu VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "main-db-subnet-group"
  }
}

resource "aws_security_group" "elasticache_sg" {
  name        = "elasticache-sg"
  description = "Allow access to ElastiCache"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Ajusta según necesidad
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elasticache-sg"
  }
}

resource "aws_docdb_subnet_group" "main" {
  name       = "main-docdb-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "main-docdb-subnet-group"
  }
}

resource "aws_security_group" "docdb" {
  name        = "docdb-sg"
  description = "Allow DocumentDB access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Solo tu VPC, ajusta si es necesario
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docdb-sg"
  }
}


# S3
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.s3_bucket_name
}

# Rds Instance

resource "aws_db_instance" "app_db" {
  identifier         = var.db_identifier
  engine             = "mysql"
  instance_class     = "db.t3.micro"
  username           = var.db_username
  password           = var.db_password
  allocated_storage  = 20
  skip_final_snapshot = true
  publicly_accessible = false
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id] 
}

# ElasticCache

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "salus-redis"
  description = "Redis for Salus"
  engine                        = "redis"
  engine_version                = "7.0"
  node_type                     = "cache.t3.micro"
  num_cache_clusters         = 2
  automatic_failover_enabled    = true
  subnet_group_name             = aws_elasticache_subnet_group.elasticache.name
  security_group_ids            = [aws_security_group.elasticache_sg.id]
  parameter_group_name          = "default.redis7"
  port                          = 6379
  multi_az_enabled              = true

  tags = {
    Name = "salus-redis"
  }
}


# DocumentDB

resource "aws_docdb_cluster" "main" {
  cluster_identifier      = "salus-docdb"
  engine                 = "docdb"
  master_username        = var.docdb_username
  master_password        = var.docdb_password
  db_subnet_group_name   = aws_docdb_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.docdb.id]
  skip_final_snapshot    = true

  tags = {
    Name = "salus-docdb"
  }
}

resource "aws_docdb_cluster_instance" "main" {
  count              = 1
  identifier         = "salus-docdb-instance-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = "db.t3.medium"
  engine             = "docdb"
}


# Api Gateway

resource "aws_api_gateway_rest_api" "salus_api" {
  name        = "salus-api"
  description = "API Gateway para Salus"
}

# API Gateway Resource (ejemplo: /salud)
resource "aws_api_gateway_resource" "salud" {
  rest_api_id = aws_api_gateway_rest_api.salus_api.id
  parent_id   = aws_api_gateway_rest_api.salus_api.root_resource_id
  path_part   = "salud"
}

# API Gateway Method (GET /salud)
resource "aws_api_gateway_method" "get_salud" {
  rest_api_id   = aws_api_gateway_rest_api.salus_api.id
  resource_id   = aws_api_gateway_resource.salud.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration (Mock example)
resource "aws_api_gateway_integration" "get_salud_mock" {
  rest_api_id = aws_api_gateway_rest_api.salus_api.id
  resource_id = aws_api_gateway_resource.salud.id
  http_method = aws_api_gateway_method.get_salud.http_method
  type        = "MOCK"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "salus_api_deployment" {
  depends_on = [aws_api_gateway_integration.get_salud_mock]
  rest_api_id = aws_api_gateway_rest_api.salus_api.id
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.salus_api.id
  deployment_id = aws_api_gateway_deployment.salus_api_deployment.id
  stage_name    = "prod"
}
