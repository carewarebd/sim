# AWS Deployment Documentation

## Table of Contents

1. [Infrastructure Overview](#infrastructure-overview)
2. [Prerequisites](#prerequisites)
3. [Terraform Configuration](#terraform-configuration)
4. [EC2 Auto Scaling Configuration](#ec2-auto-scaling-configuration)
5. [Database Setup](#database-setup)
6. [Networking Configuration](#networking-configuration)
7. [CI/CD Pipeline](#cicd-pipeline)
8. [Monitoring and Logging](#monitoring-and-logging)
9. [Security Configuration](#security-configuration)
10. [Deployment Steps](#deployment-steps)

## Infrastructure Overview

The Shop Management System is deployed on AWS using the following services:

- **EC2 Auto Scaling Group**: Scalable compute instances for the API and frontend
- **Application Load Balancer**: Request routing and SSL termination
- **RDS Aurora PostgreSQL**: Primary database with read replicas
- **ElastiCache Redis**: Caching and session storage
- **OpenSearch**: Product search and analytics
- **S3**: Static asset storage and backups
- **CloudFront**: CDN for global content delivery
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
│  │  EC2 Instances │ │  EC2 Instances │ │
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
  - EC2 Instances: 20 per region (default, can be increased)
  - Auto Scaling Groups: 200 per region (default)
  - Application Load Balancers: 50 per region (default)
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

# Install AWS Systems Manager Session Manager Plugin (for secure instance access)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

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
│   ├── ec2/               # EC2 Auto Scaling Group and ALB
│   ├── rds/               # Database configuration
│   ├── elasticache/       # Redis configuration
│   ├── opensearch/        # Search engine setup
│   ├── s3/                # Storage buckets
│   └── security/          # Security groups and IAM
├── environments/
│   ├── dev/               # Development environment
│   ├── staging/           # Staging environment
│   └── production/        # Production environment
├── scripts/
│   ├── deploy.sh          # Deployment script
│   ├── destroy.sh         # Cleanup script
│   └── user-data.sh       # EC2 instance initialization
└── packer/
    └── api-server.json    # AMI build configuration
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

# Get the latest Amazon Linux 2023 AMI
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

# EC2 Auto Scaling Module
module "ec2" {
  source = "./modules/ec2"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  security_group_ids = [module.security.ec2_security_group_id]
  
  # Load Balancer Configuration
  alb_subnet_ids         = module.vpc.public_subnet_ids
  alb_security_group_ids = [module.security.alb_security_group_id]
  
  # Auto Scaling Configuration
  instance_type    = var.instance_type
  min_size         = var.min_instances
  max_size         = var.max_instances
  desired_capacity = var.desired_instances
  
  # AMI and Launch Template
  ami_id               = var.custom_ami_id != "" ? var.custom_ami_id : data.aws_ami.amazon_linux.id
  key_pair_name        = var.key_pair_name
  enable_monitoring    = true
  
  # Application Configuration
  api_port          = var.api_port
  frontend_port     = var.frontend_port
  node_env          = var.environment
  
  # Environment Variables for User Data Script
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
  
  # Auto Scaling Policies
  scale_up_adjustment    = 1
  scale_down_adjustment  = -1
  cpu_high_threshold     = 70
  cpu_low_threshold      = 30
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
    name                   = module.ec2.alb_dns_name
    zone_id                = module.ec2.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = module.ec2.alb_dns_name
    zone_id                = module.ec2.alb_zone_id
    evaluate_target_health = true
  }
}
```

## EC2 Auto Scaling Configuration

The EC2 Auto Scaling configuration provides scalable and cost-effective compute resources for running the Shop Management System. This approach offers better cost control and operational simplicity compared to containerized deployments.

### Key Components

1. **Auto Scaling Group**: Manages the fleet of EC2 instances
2. **Launch Template**: Defines instance configuration and user data
3. **Application Load Balancer**: Distributes traffic across healthy instances
4. **Target Groups**: Health check and routing configuration
5. **CloudWatch Alarms**: Trigger scaling actions based on metrics

### EC2 Module Structure

**terraform/modules/ec2/main.tf**

```hcl
# Launch Template
resource "aws_launch_template" "app_server" {
  name_prefix   = "${var.project_name}-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  
  vpc_security_group_ids = var.security_group_ids
  
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    environment = var.node_env
    api_port    = var.api_port
    
    # Database configuration
    db_host     = var.environment_variables.DB_HOST
    db_port     = var.environment_variables.DB_PORT
    db_name     = var.environment_variables.DB_NAME
    db_username = var.environment_variables.DB_USERNAME
    db_password = var.environment_variables.DB_PASSWORD
    
    # Redis configuration
    redis_host = var.environment_variables.REDIS_HOST
    redis_port = var.environment_variables.REDIS_PORT
    
    # Application configuration
    jwt_secret = var.environment_variables.JWT_SECRET
    api_base_url = var.environment_variables.API_BASE_URL
    s3_bucket = var.environment_variables.S3_BUCKET
    s3_region = var.environment_variables.S3_REGION
  }))
  
  # IAM instance profile for AWS service access
  iam_instance_profile {
    name = aws_iam_instance_profile.app_server.name
  }
  
  monitoring {
    enabled = var.enable_monitoring
  }
  
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-app-server"
      Environment = var.environment
      Project     = var.project_name
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_servers" {
  name                = "${var.project_name}-${var.environment}-asg"
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.app_servers.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  
  launch_template {
    id      = aws_launch_template.app_server.id
    version = "$Latest"
  }
  
  # Ensure rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
  
  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-asg-instance"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# Application Load Balancer
resource "aws_lb" "app_servers" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.alb_security_group_ids
  subnets            = var.alb_subnet_ids
  
  enable_deletion_protection = var.environment == "production"
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Environment = var.environment
  }
}

# Target Group for API servers
resource "aws_lb_target_group" "app_servers" {
  name     = "${var.project_name}-${var.environment}-api-tg"
  port     = var.api_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_healthy_threshold
    interval            = var.health_check_interval
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-api-tg"
    Environment = var.environment
  }
}

# ALB Listener (HTTPS)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app_servers.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_servers.arn
  }
}

# ALB Listener (HTTP - redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_servers.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

### User Data Script

The user data script initializes each EC2 instance with the necessary software and configuration:

**terraform/modules/ec2/user-data.sh**

```bash
#!/bin/bash

# Update system
yum update -y

# Install Node.js 18
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Install PM2 process manager
npm install -g pm2

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Create application directory
mkdir -p /opt/shop-management
cd /opt/shop-management

# Create application user
useradd -r -s /bin/false shopapp
chown shopapp:shopapp /opt/shop-management

# Set environment variables
cat > /opt/shop-management/.env << EOF
NODE_ENV=${environment}
PORT=${api_port}

# Database
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USERNAME=${db_username}
DB_PASSWORD=${db_password}

# Redis
REDIS_HOST=${redis_host}
REDIS_PORT=${redis_port}

# Application
JWT_SECRET=${jwt_secret}
API_BASE_URL=${api_base_url}
S3_BUCKET=${s3_bucket}
S3_REGION=${s3_region}
EOF

# Create PM2 ecosystem file
cat > /opt/shop-management/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'shop-management-api',
    script: './dist/server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env_file: './.env',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    error_file: '/var/log/shop-management/error.log',
    out_file: '/var/log/shop-management/out.log',
    merge_logs: true,
    max_memory_restart: '1G',
    node_args: '--max-old-space-size=1024'
  }]
}
EOF

# Create log directory
mkdir -p /var/log/shop-management
chown shopapp:shopapp /var/log/shop-management

# Download and setup application code (placeholder)
# In real deployment, this would download from S3 or ECR
echo "Application code deployment would go here"

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "ShopManagement/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/shop-management/*.log",
                        "log_group_name": "/aws/ec2/shop-management/${environment}",
                        "log_stream_name": "{instance_id}-application"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Start application with PM2
su - shopapp -c "cd /opt/shop-management && pm2 start ecosystem.config.js"
su - shopapp -c "pm2 save"

# Enable PM2 to start on boot
env PATH=$PATH:/usr/bin pm2 startup systemd -u shopapp --hp /home/shopapp
systemctl enable pm2-shopapp

# Create health check endpoint script
cat > /opt/shop-management/health-check.sh << 'EOF'
#!/bin/bash
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${api_port}/health)
if [ $response -eq 200 ]; then
    exit 0
else
    exit 1
fi
EOF
chmod +x /opt/shop-management/health-check.sh
```

### Auto Scaling Policies

**terraform/modules/ec2/autoscaling.tf**

```hcl
# Scale Up Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-${var.environment}-scale-up"
  scaling_adjustment     = var.scale_up_adjustment
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_servers.name
}

# Scale Down Policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-${var.environment}-scale-down"
  scaling_adjustment     = var.scale_down_adjustment
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_servers.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_high_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_servers.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_low_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_servers.name
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

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.medium"
}

variable "custom_ami_id" {
  description = "Custom AMI ID (leave empty to use latest Amazon Linux)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for instance access"
  type        = string
}

variable "min_instances" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 2
}

variable "max_instances" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 6
}

variable "desired_instances" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
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

# Auto Scaling Configuration
variable "cpu_high_threshold" {
  description = "CPU threshold for scaling up"
  type        = number
  default     = 70
}

variable "cpu_low_threshold" {
  description = "CPU threshold for scaling down"
  type        = number
  default     = 30
}
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