# AWS Deployment Documentation

## Table of Contents

1. [Infrastructure Overview](#infrastructure-overview)
2. [Prerequisites](#prerequisites)
3. [Terraform Configuration](#terraform-configuration)
4. [ECS Service Configuration](#ecs-service-configuration)
5. [Database Setup](#database-setup)
6. [Networking Configuration](#networking-configuration)
7. [CI/CD Pipeline](#cicd-pipeline)
8. [Monitoring and Logging](#monitoring-and-logging)
9. [Security Configuration](#security-configuration)
10. [Deployment Steps](#deployment-steps)

## Infrastructure Overview

The Shop Management System is deployed on AWS using the following services:

- **ECS Fargate**: Container orchestration for the API and frontend
- **RDS Aurora PostgreSQL**: Primary database with read replicas
- **ElastiCache Redis**: Caching and session storage
- **OpenSearch**: Product search and analytics
- **S3**: Static asset storage and backups
- **CloudFront**: CDN for global content delivery
- **Application Load Balancer**: Request routing and SSL termination
- **Route53**: DNS management
- **CloudWatch**: Monitoring and logging
- **AWS Cognito**: Authentication and user management
- **VPC**: Network isolation and security

### Architecture Diagram

```
Internet
    ↓
CloudFront CDN
    ↓
Route53 DNS
    ↓
Application Load Balancer (ALB)
    ↓
┌─────────────────────────────────────────┐
│                VPC                      │
│  ┌─────────────────┐ ┌─────────────────┐ │
│  │   Public Subnet  │ │   Public Subnet  │ │
│  │      (AZ-a)     │ │      (AZ-b)     │ │
│  │                 │ │                 │ │
│  │      ALB        │ │      ALB        │ │
│  └─────────────────┘ └─────────────────┘ │
│           │                   │         │
│  ┌─────────────────┐ ┌─────────────────┐ │
│  │ Private Subnet  │ │ Private Subnet  │ │
│  │    (AZ-a)      │ │    (AZ-b)      │ │
│  │                │ │                │ │
│  │  ECS Tasks     │ │  ECS Tasks     │ │
│  │  - API Server  │ │  - API Server  │ │
│  │  - Frontend    │ │  - Frontend    │ │
│  └─────────────────┘ └─────────────────┘ │
│           │                   │         │
│  ┌─────────────────┐ ┌─────────────────┐ │
│  │ Database Subnet │ │ Database Subnet │ │
│  │    (AZ-a)      │ │    (AZ-b)      │ │
│  │                │ │                │ │
│  │  RDS Aurora    │ │ ElastiCache    │ │
│  │  OpenSearch    │ │ OpenSearch     │ │
│  └─────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────┘
```

## Prerequisites

### Required AWS Services and Limits

- **AWS Account** with administrative access
- **Domain Name** registered and manageable in Route53
- **SSL Certificate** via AWS Certificate Manager
- **Service Limits**:
  - VPC: 5 per region (default)
  - ECS Tasks: 1000 per cluster (default)
  - RDS Instances: 40 per region (default)
  - ElastiCache Clusters: 300 per region (default)

### Local Development Tools

```bash
# Install required tools
curl -fsSL https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_darwin_amd64.zip -o terraform.zip
unzip terraform.zip && sudo mv terraform /usr/local/bin/

# Install AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Install ECS CLI
sudo curl -L "https://amazon-ecs-cli.s3.amazonaws.com/ecs-cli-darwin-amd64-latest" -o /usr/local/bin/ecs-cli
sudo chmod +x /usr/local/bin/ecs-cli

# Configure AWS credentials
aws configure
```

## Terraform Configuration

### Directory Structure

```
terraform/
├── main.tf                 # Main configuration
├── variables.tf            # Input variables
├── outputs.tf             # Output values
├── versions.tf            # Provider versions
├── modules/
│   ├── vpc/               # VPC and networking
│   ├── ecs/               # ECS cluster and services
│   ├── rds/               # Database configuration
│   ├── elasticache/       # Redis configuration
│   ├── opensearch/        # Search engine setup
│   ├── s3/                # Storage buckets
│   └── security/          # Security groups and IAM
├── environments/
│   ├── dev/               # Development environment
│   ├── staging/           # Staging environment
│   └── production/        # Production environment
└── scripts/
    ├── deploy.sh          # Deployment script
    └── destroy.sh         # Cleanup script
```

### Main Terraform Configuration

**terraform/main.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  backend "s3" {
    bucket         = "shop-management-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Random password for RDS
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Security Module
module "security" {
  source = "./modules/security"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# RDS Module
module "rds" {
  source = "./modules/rds"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids
  
  security_group_ids = [module.security.rds_security_group_id]
  
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  
  db_name     = var.db_name
  db_username = var.db_username
  db_password = random_password.db_password.result
  
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  
  enable_read_replica = var.environment == "production"
  enable_encryption   = true
}

# ElastiCache Module
module "elasticache" {
  source = "./modules/elasticache"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids
  
  security_group_ids = [module.security.elasticache_security_group_id]
  
  node_type           = var.redis_node_type
  num_cache_clusters  = var.redis_num_nodes
  engine_version      = var.redis_engine_version
  parameter_group     = var.redis_parameter_group
  
  enable_clustering = var.environment == "production"
  enable_encryption = true
}

# OpenSearch Module
module "opensearch" {
  source = "./modules/opensearch"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids
  
  security_group_ids = [module.security.opensearch_security_group_id]
  
  engine_version = var.opensearch_engine_version
  instance_type  = var.opensearch_instance_type
  instance_count = var.opensearch_instance_count
  
  ebs_enabled    = true
  ebs_volume_size = var.opensearch_ebs_volume_size
  
  enable_zone_awareness = var.environment == "production"
  enable_encryption     = true
}

# S3 Module
module "s3" {
  source = "./modules/s3"
  
  project_name = var.project_name
  environment  = var.environment
  
  enable_versioning = true
  enable_encryption = true
  
  cors_allowed_origins = var.cors_allowed_origins
  cors_allowed_methods = ["GET", "PUT", "POST", "DELETE"]
  cors_allowed_headers = ["*"]
}

# ECS Module
module "ecs" {
  source = "./modules/ecs"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  security_group_ids = [module.security.ecs_security_group_id]
  
  # Load Balancer Configuration
  alb_subnet_ids         = module.vpc.public_subnet_ids
  alb_security_group_ids = [module.security.alb_security_group_id]
  
  # Service Configuration
  api_image         = var.api_image
  frontend_image    = var.frontend_image
  api_port          = var.api_port
  frontend_port     = var.frontend_port
  
  # Scaling Configuration
  api_desired_count      = var.api_desired_count
  frontend_desired_count = var.frontend_desired_count
  api_min_capacity       = var.api_min_capacity
  api_max_capacity       = var.api_max_capacity
  
  # Environment Variables
  environment_variables = {
    # Database
    DB_HOST     = module.rds.cluster_endpoint
    DB_PORT     = "5432"
    DB_NAME     = var.db_name
    DB_USERNAME = var.db_username
    DB_PASSWORD = random_password.db_password.result
    
    # Redis
    REDIS_HOST = module.elasticache.cluster_endpoint
    REDIS_PORT = "6379"
    
    # OpenSearch
    OPENSEARCH_ENDPOINT = module.opensearch.domain_endpoint
    
    # S3
    S3_BUCKET        = module.s3.assets_bucket_name
    S3_REGION        = var.aws_region
    CLOUDFRONT_DOMAIN = module.s3.cloudfront_domain_name
    
    # Application
    NODE_ENV     = var.environment
    API_BASE_URL = "https://${var.domain_name}/api"
    
    # Authentication
    JWT_SECRET         = var.jwt_secret
    COGNITO_USER_POOL  = var.cognito_user_pool_id
    COGNITO_CLIENT_ID  = var.cognito_client_id
    
    # External Services
    SMTP_HOST     = var.smtp_host
    SMTP_PORT     = var.smtp_port
    SMTP_USERNAME = var.smtp_username
    SMTP_PASSWORD = var.smtp_password
  }
  
  # Health Check Configuration
  health_check_path               = "/health"
  health_check_healthy_threshold  = 2
  health_check_interval           = 30
  health_check_timeout            = 5
  health_check_unhealthy_threshold = 5
}

# Route53 and SSL Certificate
resource "aws_route53_zone" "main" {
  name = var.domain_name
  
  tags = {
    Name = "${var.project_name}-${var.environment}-zone"
  }
}

resource "aws_acm_certificate" "ssl" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-ssl"
  }
}

resource "aws_route53_record" "ssl_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ssl.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "ssl" {
  certificate_arn         = aws_acm_certificate.ssl.arn
  validation_record_fqdns = [for record in aws_route53_record.ssl_validation : record.fqdn]
  
  timeouts {
    create = "5m"
  }
}

# Route53 Records
resource "aws_route53_record" "main" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = true
  }
}
```

### Variables Configuration

**terraform/variables.tf**

```hcl
# General Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "shop-management"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "DevOps Team"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# Database Configuration
variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "shopmanagement"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "shopadmin"
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# Redis Configuration
variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r6g.large"
}

variable "redis_num_nodes" {
  description = "Number of Redis nodes"
  type        = number
  default     = 2
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_parameter_group" {
  description = "Redis parameter group"
  type        = string
  default     = "default.redis7"
}

# OpenSearch Configuration
variable "opensearch_engine_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.3"
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.medium.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 2
}

variable "opensearch_ebs_volume_size" {
  description = "EBS volume size for OpenSearch in GB"
  type        = number
  default     = 100
}

# ECS Configuration
variable "api_image" {
  description = "Docker image for API service"
  type        = string
}

variable "frontend_image" {
  description = "Docker image for frontend service"
  type        = string
}

variable "api_port" {
  description = "API service port"
  type        = number
  default     = 3000
}

variable "frontend_port" {
  description = "Frontend service port"
  type        = number
  default     = 80
}

variable "api_desired_count" {
  description = "Desired number of API tasks"
  type        = number
  default     = 2
}

variable "frontend_desired_count" {
  description = "Desired number of frontend tasks"
  type        = number
  default     = 2
}

variable "api_min_capacity" {
  description = "Minimum API capacity for auto scaling"
  type        = number
  default     = 2
}

variable "api_max_capacity" {
  description = "Maximum API capacity for auto scaling"
  type        = number
  default     = 10
}

# Application Configuration
variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito Client ID"
  type        = string
}

# CORS Configuration
variable "cors_allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

# Email Configuration
variable "smtp_host" {
  description = "SMTP host for email sending"
  type        = string
}

variable "smtp_port" {
  description = "SMTP port"
  type        = number
  default     = 587
}

variable "smtp_username" {
  description = "SMTP username"
  type        = string
}

variable "smtp_password" {
  description = "SMTP password"
  type        = string
  sensitive   = true
}
```

This is a comprehensive start to the AWS deployment documentation. The configuration covers the main infrastructure components with Terraform modules for VPC, security, database, caching, search, storage, and container orchestration. 

Would you like me to continue with the specific module configurations (VPC, ECS, RDS, etc.) or move to another aspect of the deployment documentation?