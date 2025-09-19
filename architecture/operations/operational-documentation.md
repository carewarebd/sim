# Operational Documentation

## Table of Contents

1. [Deployment Guide](#deployment-guide)
2. [Monitoring & Observability](#monitoring--observability)
3. [Backup & Disaster Recovery](#backup--disaster-recovery)
4. [Operational Runbooks](#operational-runbooks)
5. [Architecture Decision Records](#architecture-decision-records)
6. [Maintenance Procedures](#maintenance-procedures)

## Deployment Guide

### Prerequisites

**Required Tools & Versions**

```bash
# Development Tools
node: >= 18.0.0
npm: >= 8.0.0
docker: >= 20.10.0
terraform: >= 1.0.0
aws-cli: >= 2.0.0
kubectl: >= 1.25.0

# Verification Commands
node --version
npm --version  
docker --version
terraform version
aws --version
kubectl version --client
```

**AWS Account Setup**

```bash
# Configure AWS CLI
aws configure set region us-east-1
aws configure set output json

# Verify permissions
aws sts get-caller-identity
aws iam list-roles --query 'Roles[?contains(RoleName, `ECS`) || contains(RoleName, `RDS`)].RoleName'

# Required IAM policies
# - AmazonECS_FullAccess
# - AmazonRDS_FullAccess  
# - AmazonElastiCacheFullAccess
# - AmazonOpenSearchFullAccess
# - AmazonS3FullAccess
# - AmazonCognitoFullAccess
```

### Infrastructure Deployment

**Step 1: Deploy Core Infrastructure**

```bash
# Clone repository
git clone <repository-url>
cd shop-management

# Initialize Terraform
cd terraform/environments/production
terraform init

# Create terraform.tfvars
cat > terraform.tfvars << EOF
environment = "production"
project_name = "shop-management"
region = "us-east-1"

# Database configuration
db_instance_class = "db.r6g.large"
db_allocated_storage = 100
db_max_allocated_storage = 1000

# ECS configuration
ecs_cpu = 512
ecs_memory = 1024
desired_count = 2

# Domain configuration
domain_name = "yourdomain.com"
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
EOF

# Plan and apply infrastructure
terraform plan
terraform apply
```

**Step 2: Database Setup**

```bash
# Get RDS endpoint from Terraform output
DB_ENDPOINT=$(terraform output -raw db_endpoint)
DB_PASSWORD=$(terraform output -raw db_password)

# Connect to database
psql -h $DB_ENDPOINT -U postgres -d shop_management

# Run schema migration
psql -h $DB_ENDPOINT -U postgres -d shop_management -f ../../../architecture/schema.sql

# Verify tables created
\dt
\dp  # Check RLS policies
```

**Step 3: Application Deployment**

```bash
# Build and push Docker images
cd ../../../

# Backend API
docker build -t shop-management-api ./backend
docker tag shop-management-api:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/shop-management-api:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/shop-management-api:latest

# Frontend
docker build -t shop-management-frontend ./frontend  
docker tag shop-management-frontend:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/shop-management-frontend:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/shop-management-frontend:latest

# Update ECS service
aws ecs update-service --cluster shop-management-cluster --service shop-management-api --force-new-deployment
aws ecs update-service --cluster shop-management-cluster --service shop-management-frontend --force-new-deployment
```

### Environment-Specific Deployments

**Development Environment**

```yaml
# terraform/environments/development/terraform.tfvars
environment = "development"
db_instance_class = "db.t3.micro"
ecs_cpu = 256
ecs_memory = 512
desired_count = 1
enable_deletion_protection = false
backup_retention_period = 1
```

**Staging Environment**

```yaml
# terraform/environments/staging/terraform.tfvars  
environment = "staging"
db_instance_class = "db.r6g.medium"
ecs_cpu = 256
ecs_memory = 512
desired_count = 1
enable_deletion_protection = true
backup_retention_period = 7
```

**Production Environment**

```yaml
# terraform/environments/production/terraform.tfvars
environment = "production"
db_instance_class = "db.r6g.large" 
ecs_cpu = 512
ecs_memory = 1024
desired_count = 2
enable_deletion_protection = true
backup_retention_period = 30
multi_az = true
```

## Monitoring & Observability

### CloudWatch Configuration

**Custom Metrics**

```json
{
  "metrics": [
    {
      "metricName": "active_shops",
      "namespace": "ShopManagement/Business",
      "dimensions": [{"name": "Environment", "value": "production"}],
      "unit": "Count"
    },
    {
      "metricName": "api_response_time", 
      "namespace": "ShopManagement/Performance",
      "dimensions": [{"name": "Endpoint", "value": "*"}],
      "unit": "Milliseconds"
    },
    {
      "metricName": "database_connections",
      "namespace": "ShopManagement/Database", 
      "dimensions": [{"name": "Instance", "value": "primary"}],
      "unit": "Count"
    }
  ]
}
```

**CloudWatch Alarms**

```bash
# API Response Time Alert
aws cloudwatch put-metric-alarm \
  --alarm-name "API-High-Response-Time" \
  --alarm-description "API response time above 2 seconds" \
  --metric-name ResponseTime \
  --namespace ShopManagement/Performance \
  --statistic Average \
  --period 300 \
  --threshold 2000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:alerts

# Database Connection Alert  
aws cloudwatch put-metric-alarm \
  --alarm-name "Database-High-Connections" \
  --alarm-description "Database connections above 80%" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

**Dashboard Configuration**

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["ShopManagement/Business", "active_shops"],
          ["ShopManagement/Business", "active_users"],
          ["ShopManagement/Business", "transactions_per_hour"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Business Metrics"
      }
    },
    {
      "type": "metric", 
      "properties": {
        "metrics": [
          ["AWS/ECS", "CPUUtilization", "ServiceName", "shop-management-api"],
          ["AWS/ECS", "MemoryUtilization", "ServiceName", "shop-management-api"],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "shop-management-alb"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1", 
        "title": "Infrastructure Health"
      }
    }
  ]
}
```

### Application Logging

**Structured Logging Configuration**

```javascript
// backend/src/utils/logger.js
const winston = require('winston');
const CloudWatchLogsTransport = require('winston-aws-cloudwatch');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: {
    service: 'shop-management-api',
    environment: process.env.NODE_ENV,
    version: process.env.APP_VERSION
  },
  transports: [
    new winston.transports.Console(),
    new CloudWatchLogsTransport({
      logGroupName: '/aws/ecs/shop-management-api',
      logStreamName: `${process.env.HOSTNAME}-${Date.now()}`,
      awsRegion: 'us-east-1'
    })
  ]
});

// Usage examples
logger.info('User login successful', {
  userId: user.id,
  shopId: user.shop_id,
  ipAddress: req.ip,
  userAgent: req.get('User-Agent')
});

logger.error('Database connection failed', {
  error: error.message,
  stack: error.stack,
  query: sanitizedQuery,
  duration: elapsed
});
```

**Log Analysis Queries**

```sql
-- CloudWatch Logs Insights Queries

-- API Error Rate
fields @timestamp, @message
| filter @message like /ERROR/
| stats count(*) as error_count by bin(5m)
| sort @timestamp desc

-- Slow Database Queries  
fields @timestamp, @message
| filter @message like /query_duration/
| filter query_duration > 1000
| sort query_duration desc
| limit 100

-- User Activity Patterns
fields @timestamp, user_id, action
| filter action in ["login", "logout", "purchase"] 
| stats count(*) as activity_count by user_id, bin(1h)
| sort activity_count desc
```

### Distributed Tracing

**AWS X-Ray Configuration**

```javascript
// backend/src/middleware/tracing.js
const AWSXRay = require('aws-xray-sdk-core');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));

// Express middleware
app.use(AWSXRay.express.openSegment('shop-management-api'));

// Database tracing
AWSXRay.capturePostgreSQLConnection(pgClient);

// HTTP request tracing  
const segment = AWSXRay.getSegment();
const subsegment = segment.addNewSubsegment('external-api-call');
try {
  const response = await axios.get('https://api.example.com');
  subsegment.addMetadata('response', response.data);
} catch (error) {
  subsegment.addError(error);
} finally {
  subsegment.close();
}

app.use(AWSXRay.express.closeSegment());
```

## Backup & Disaster Recovery

### Database Backup Strategy

**Automated Backups**

```yaml
RDS Aurora Configuration:
  backup_retention_period: 30 days
  backup_window: "03:00-04:00"  # UTC
  maintenance_window: "sun:04:00-sun:05:00"  # UTC
  copy_tags_to_snapshot: true
  deletion_protection: true
  
Point-in-Time Recovery:
  enabled: true
  retention: 30 days
  granularity: 5 minutes
```

**Manual Backup Procedures**

```bash
#!/bin/bash
# scripts/backup-database.sh

DATE=$(date +%Y%m%d_%H%M%S)
DB_ENDPOINT=$(terraform output -raw db_endpoint)
BACKUP_BUCKET="shop-management-backups"

# Create manual snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier shop-management-aurora \
  --db-cluster-snapshot-identifier "manual-backup-${DATE}"

# Export schema only
pg_dump -h $DB_ENDPOINT -U postgres -s shop_management > schema_${DATE}.sql

# Upload to S3
aws s3 cp schema_${DATE}.sql s3://${BACKUP_BUCKET}/schema/

# Verify backup
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier "manual-backup-${DATE}"
```

### File Storage Backup

**S3 Cross-Region Replication**

```yaml
# terraform/modules/s3/main.tf
resource "aws_s3_bucket_replication_configuration" "backup" {
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "backup-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.backup.arn
      storage_class = "STANDARD_IA"
    }

    filter {
      prefix = "uploads/"
    }
  }
}
```

**Backup Verification Script**

```bash
#!/bin/bash
# scripts/verify-backups.sh

# Check RDS snapshots (last 7 days)
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier shop-management-aurora \
  --snapshot-type automated \
  --query 'DBClusterSnapshots[?SnapshotCreateTime>=`2024-01-01`].{ID:DBClusterSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime}' \
  --output table

# Check S3 backup bucket
aws s3 ls s3://shop-management-backups/ --recursive --human-readable --summarize

# Test backup restore (to test environment)
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier shop-management-test-restore \
  --snapshot-identifier manual-backup-20240101_120000 \
  --engine aurora-postgresql \
  --dry-run
```

### Disaster Recovery Plan

**Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)**

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| **Database Failure** | 15 minutes | 5 minutes | Aurora failover to read replica |
| **AZ Failure** | 10 minutes | 0 minutes | Multi-AZ automatic failover |
| **Region Failure** | 4 hours | 15 minutes | Cross-region backup restore |
| **Application Failure** | 5 minutes | 0 minutes | ECS auto-scaling, health checks |
| **Complete Disaster** | 24 hours | 30 minutes | Full environment rebuild |

**Disaster Recovery Procedures**

```bash
#!/bin/bash
# scripts/disaster-recovery.sh

SCENARIO=$1
BACKUP_REGION="us-west-2"

case $SCENARIO in
  "database")
    echo "Initiating database failover..."
    aws rds failover-db-cluster \
      --db-cluster-identifier shop-management-aurora \
      --target-db-instance-identifier shop-management-aurora-1
    ;;
    
  "region")
    echo "Initiating cross-region recovery..."
    cd terraform/environments/disaster-recovery
    
    # Update variables for backup region
    export TF_VAR_region=$BACKUP_REGION
    export TF_VAR_backup_restore=true
    
    terraform init
    terraform apply -auto-approve
    
    # Update DNS to point to backup region
    aws route53 change-resource-record-sets \
      --hosted-zone-id Z123456789012 \
      --change-batch file://route53-failover.json
    ;;
    
  "complete")
    echo "Initiating complete disaster recovery..."
    # Full environment rebuild from backups
    ./rebuild-environment.sh
    ;;
esac
```

### Recovery Testing

**Monthly DR Test Schedule**

```yaml
Week 1: Database Failover Test
  - Trigger manual failover
  - Verify application connectivity  
  - Measure RTO/RPO
  - Document any issues

Week 2: Application Recovery Test
  - Stop ECS services
  - Verify auto-scaling response
  - Test load balancer health checks
  - Validate monitoring alerts

Week 3: Backup Restore Test
  - Restore to test environment
  - Verify data integrity
  - Test application functionality
  - Performance validation

Week 4: Cross-Region Test  
  - Simulate region failure
  - Execute DR procedures
  - Measure recovery time
  - Update runbooks
```

## Operational Runbooks

### Common Incident Response

**High CPU Utilization**

```bash
# Investigation Steps
1. Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=shop-management-api \
  --statistics Average,Maximum \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 300

2. Review application logs
aws logs filter-log-events \
  --log-group-name /aws/ecs/shop-management-api \
  --start-time 1640995200000 \
  --filter-pattern "ERROR"

3. Scale ECS service if needed  
aws ecs update-service \
  --cluster shop-management-cluster \
  --service shop-management-api \
  --desired-count 4

4. Identify root cause
- Check for inefficient database queries
- Review memory leaks in application
- Analyze traffic patterns
```

**Database Connection Exhaustion**

```sql
-- Check current connections
SELECT count(*) as total_connections,
       state,
       application_name
FROM pg_stat_activity 
WHERE state IS NOT NULL
GROUP BY state, application_name;

-- Kill long-running queries
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity 
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
  AND query NOT LIKE '%pg_stat_activity%';

-- Temporary connection limit increase
ALTER SYSTEM SET max_connections = 200;
SELECT pg_reload_conf();
```

**API Response Time Degradation**

```bash
# 1. Check load balancer metrics
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/shop-mgmt-api/1234567890123456

# 2. Review slow query log
grep "slow query" /var/log/postgresql/postgresql.log | tail -20

# 3. Check Redis cache hit rate
redis-cli info stats | grep "cache_hit_rate\|cache_miss"

# 4. Enable detailed CloudWatch metrics
aws ecs put-cluster-capacity-providers \
  --cluster shop-management-cluster \
  --capacity-providers EC2,FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
```

### Maintenance Procedures

**Weekly Maintenance Tasks**

```bash
#!/bin/bash
# scripts/weekly-maintenance.sh

echo "Starting weekly maintenance..."

# 1. Database maintenance
psql -h $DB_ENDPOINT -U postgres -d shop_management << EOF
-- Analyze table statistics
ANALYZE;

-- Vacuum old data
VACUUM (ANALYZE, VERBOSE);

-- Check for index usage
SELECT schemaname, tablename, indexname, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE idx_tup_read = 0;
EOF

# 2. Log cleanup
aws logs delete-log-stream \
  --log-group-name /aws/ecs/shop-management-api \
  --log-stream-name $(aws logs describe-log-streams \
    --log-group-name /aws/ecs/shop-management-api \
    --query 'logStreams[?creationTime<`'$(date -d '30 days ago' +%s)'000`].logStreamName' \
    --output text)

# 3. S3 lifecycle cleanup
aws s3api put-bucket-lifecycle-configuration \
  --bucket shop-management-uploads \
  --lifecycle-configuration file://lifecycle-policy.json

# 4. Certificate renewal check
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
  --query 'Certificate.{Status:Status,NotAfter:NotAfter}'

echo "Weekly maintenance completed."
```

**Monthly Security Updates**

```bash
#!/bin/bash
# scripts/security-updates.sh

# 1. Update ECS task definitions with latest base images
docker pull node:18-alpine
docker pull postgres:15-alpine
docker pull redis:7-alpine
docker pull nginx:alpine

# 2. Rebuild application images
docker build --no-cache -t shop-management-api:latest ./backend
docker build --no-cache -t shop-management-frontend:latest ./frontend

# 3. Security scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image shop-management-api:latest

# 4. Update dependencies
cd backend && npm audit fix
cd frontend && npm audit fix

# 5. Deploy updates
aws ecs update-service \
  --cluster shop-management-cluster \
  --service shop-management-api \
  --force-new-deployment
```

## Architecture Decision Records

### ADR-001: Multi-tenant Architecture

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Need to support multiple shops in a single system while ensuring data isolation and cost efficiency.

**Decision**: Implement shared database with Row Level Security (RLS) policies for tenant isolation.

**Consequences**:
- ✅ Cost efficient - single database for all tenants
- ✅ Easier maintenance and updates
- ✅ Strong data isolation via RLS
- ❌ Potential noisy neighbor issues
- ❌ More complex query patterns

**Alternatives Considered**:
1. Database per tenant - too expensive at scale
2. Schema per tenant - management complexity
3. Application-level isolation - security concerns

### ADR-002: AWS ECS Fargate vs EC2

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Choose container orchestration platform for scalability and operational simplicity.

**Decision**: Use ECS Fargate for serverless container management.

**Consequences**:
- ✅ No server management required
- ✅ Auto-scaling based on demand
- ✅ Pay only for resources used
- ❌ Higher per-container costs
- ❌ Less control over underlying infrastructure

**Implementation**:
```yaml
# Key configuration
task_cpu: 512
task_memory: 1024
desired_count: 2
max_capacity: 10
target_cpu_utilization: 70
```

### ADR-003: PostgreSQL vs NoSQL

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Choose primary database technology for shop management data.

**Decision**: Use PostgreSQL with Aurora for ACID compliance and relational data integrity.

**Consequences**:
- ✅ Strong consistency and ACID properties
- ✅ Rich query capabilities with SQL
- ✅ Mature ecosystem and tooling
- ✅ JSON support for flexible schemas
- ❌ Potential scaling bottlenecks
- ❌ More complex horizontal scaling

### ADR-004: Authentication Strategy

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Secure user authentication and authorization system.

**Decision**: Use AWS Cognito with JWT tokens and custom RBAC.

**Consequences**:
- ✅ Managed authentication service
- ✅ Built-in security features
- ✅ OAuth/SAML integration
- ✅ Custom attributes support
- ❌ Vendor lock-in
- ❌ Limited customization options

### ADR-005: Frontend Framework

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Choose frontend technology for responsive shop management UI.

**Decision**: Use React with TypeScript and Tailwind CSS.

**Consequences**:
- ✅ Strong typing with TypeScript
- ✅ Large ecosystem and community
- ✅ Component-based architecture
- ✅ Utility-first CSS with Tailwind
- ❌ Bundle size considerations
- ❌ SEO limitations (SPA)

### ADR-006: Search Technology

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Product search and filtering capabilities across all shops.

**Decision**: Use Amazon OpenSearch for full-text search and analytics.

**Consequences**:
- ✅ Powerful search and filtering
- ✅ Analytics and aggregations
- ✅ Geospatial search support
- ✅ Managed service
- ❌ Additional infrastructure cost
- ❌ Data synchronization complexity

### ADR-007: Caching Strategy  

**Status**: Accepted  
**Date**: 2024-01-01  
**Context**: Improve application performance and reduce database load.

**Decision**: Multi-layer caching with Redis, CloudFront, and application-level caching.

**Implementation**:
```yaml
Cache Layers:
  L1: Application memory (5 minutes TTL)
  L2: Redis cluster (1 hour TTL) 
  L3: CloudFront CDN (24 hours TTL)
  L4: Database query cache
```

## Maintenance Procedures

### Database Maintenance

**Daily Tasks**
- Monitor connection counts and slow queries
- Check replication lag on read replicas  
- Review CloudWatch metrics for anomalies
- Validate backup completion

**Weekly Tasks**
- Run VACUUM and ANALYZE on large tables
- Review and optimize slow queries
- Check index usage and add missing indexes
- Update table statistics

**Monthly Tasks**
- Review and update RLS policies
- Analyze storage growth trends
- Test disaster recovery procedures
- Update database parameters if needed

### Infrastructure Maintenance

**Security Updates**
```bash
# Monthly security patch schedule
Week 1: Development environment
Week 2: Staging environment  
Week 3: Production environment (maintenance window)
Week 4: Monitoring and validation
```

**Capacity Planning**
- Monthly review of resource utilization
- Quarterly scaling projections
- Annual cost optimization review
- Performance baseline updates

**Documentation Updates**
- Keep runbooks current with infrastructure changes
- Update ADRs for architectural decisions
- Maintain disaster recovery procedures
- Review and update monitoring alerts

This comprehensive operational documentation provides everything needed to deploy, monitor, maintain, and operate the shop management system in production.