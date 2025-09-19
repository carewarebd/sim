# ADR-003: Database Technology Selection

**Status**: Accepted  
**Date**: 2024-01-01  
**Deciders**: Data Architecture Team  
**Technical Story**: Choose primary database technology for shop management system

## Context

The shop management system requires a database that can:
- Handle complex relational data (products, orders, inventory, customers)
- Support ACID transactions for financial operations
- Scale to 10,000+ shops with millions of records
- Provide strong consistency for critical business operations
- Support advanced querying and analytics
- Integrate with multi-tenant architecture (Row Level Security)
- Handle geospatial data for location-based features

## Decision Drivers

* **Data Integrity**: ACID compliance for financial transactions
* **Query Complexity**: Complex joins, aggregations, and analytics
* **Scalability**: Handle growth from 1K to 100K+ users
* **Multi-tenancy**: Database-level tenant isolation support
* **Geospatial**: Location-based shop and delivery features
* **Operational Maturity**: Mature tooling, monitoring, backup/recovery
* **Cost Efficiency**: Reasonable costs at scale
* **Developer Productivity**: Familiar query language and tooling

## Options Considered

### Option 1: Amazon RDS PostgreSQL
**Description**: Managed PostgreSQL with standard features

**Pros**:
- ACID compliance and strong consistency
- Rich SQL feature set and JSON support
- Excellent multi-tenancy with Row Level Security (RLS)
- PostGIS extension for geospatial data
- Mature ecosystem and tooling
- Cost-effective for medium scale

**Cons**:
- Vertical scaling limits (limited read replicas)
- Manual sharding required for massive scale
- Single-master write bottleneck
- Backup/recovery complexity at scale

**Cost Analysis**: 
- db.r6g.large (16GB RAM): $238/month
- Read replicas: +$238/month each
- Storage: ~$23/100GB/month

### Option 2: Amazon Aurora PostgreSQL
**Description**: AWS-native PostgreSQL-compatible with enhanced features

**Pros**:
- PostgreSQL compatibility with AWS enhancements
- Automatic scaling storage (up to 128 TB)
- Up to 15 read replicas with < 10ms replication lag
- Continuous backup to S3
- Multi-AZ high availability built-in
- Better performance than standard PostgreSQL
- Global database for multi-region setup

**Cons**:
- Higher costs than standard RDS
- AWS vendor lock-in
- Some PostgreSQL extensions not supported
- Aurora-specific operational procedures

**Cost Analysis**:
- db.r6g.large: $260/month (primary)
- Read replicas: $260/month each
- I/O operations: ~$0.20/million requests
- Storage: ~$0.10/GB/month (auto-scaling)

### Option 3: Amazon DynamoDB
**Description**: Managed NoSQL database with automatic scaling

**Pros**:
- Automatic horizontal scaling
- Pay-per-request pricing model
- Single-digit millisecond latency
- Built-in security and encryption
- Global tables for multi-region
- No server management required

**Cons**:
- NoSQL limitations for complex queries
- No ACID transactions across items
- Learning curve for SQL developers
- Limited query patterns
- Expensive for large datasets
- No built-in multi-tenancy support

**Cost Analysis**:
- On-demand: $1.25/million read requests, $1.25/million write requests
- Provisioned: $0.65/RCU/month, $0.325/WCU/month
- Storage: $0.25/GB/month

### Option 4: Amazon DocumentDB (MongoDB)
**Description**: Managed document database compatible with MongoDB

**Pros**:
- Document model for flexible schemas
- Automatic scaling and high availability
- Compatible with MongoDB drivers
- JSON document storage
- Good for content management

**Cons**:
- Limited ACID transaction support
- Not ideal for relational data patterns
- Higher learning curve for SQL developers
- Limited query optimization
- More expensive than relational databases

**Cost Analysis**:
- db.r6g.large: $295/month
- Storage: $0.10/GB/month
- I/O: $0.20/million requests

### Option 5: Multi-Database Approach
**Description**: PostgreSQL for transactional data + DynamoDB for high-throughput operations

**Pros**:
- Optimize each database for specific use cases
- Best performance characteristics
- Flexible scaling strategies

**Cons**:
- Operational complexity
- Data consistency challenges
- Higher development complexity
- Multiple technologies to maintain

## Decision

**Chosen Option**: **Option 2 - Amazon Aurora PostgreSQL**

### Rationale

1. **PostgreSQL Compatibility**: Leverages existing team expertise with SQL
2. **ACID Compliance**: Essential for financial transactions and inventory management
3. **Multi-tenancy**: Excellent Row Level Security support for tenant isolation
4. **Scalability**: Aurora's enhanced scaling capabilities vs. standard RDS
5. **Performance**: 3x better performance than standard PostgreSQL
6. **High Availability**: Built-in Multi-AZ with automatic failover
7. **Operational Simplicity**: Managed service with automated backups and patching
8. **Geospatial Support**: PostGIS extension for location-based features

### Implementation Architecture

```sql
-- Database Configuration
Engine: aurora-postgresql
Engine Version: 15.4
Instance Class: db.r6g.large (baseline)
Multi-AZ: true
Read Replicas: 1 (baseline), up to 15 (scale)

-- Storage Configuration
Storage Type: Aurora (auto-scaling)
Initial Size: 10 GB
Max Size: 128 TB (auto-scaling)
Backup Retention: 30 days
Point-in-time Recovery: enabled

-- Security Configuration
Encryption at Rest: AWS KMS
Encryption in Transit: TLS 1.2
VPC Security Groups: restricted access
Parameter Groups: custom for RLS and performance
```

## Consequences

### Positive Consequences

* **Performance**: 3x throughput improvement over standard PostgreSQL
* **Scalability**: Storage auto-scales from 10GB to 128TB
* **High Availability**: 99.99% uptime with Multi-AZ deployment
* **Backup & Recovery**: Continuous backup with point-in-time recovery
* **Read Scaling**: Up to 15 read replicas for query performance
* **Operational Simplicity**: Managed patching, monitoring, and maintenance
* **Cost Predictability**: Reserved instances provide cost savings

### Negative Consequences

* **Vendor Lock-in**: Aurora-specific features tie us to AWS
* **Higher Costs**: ~10% more expensive than standard RDS PostgreSQL
* **Complexity**: Aurora-specific operational procedures and monitoring
* **Extension Limitations**: Some PostgreSQL extensions not available
* **Write Scaling**: Still limited to single-master writes

### Risk Mitigation Strategies

1. **Cost Management**: Use Reserved Instances for 25% cost savings
2. **Performance Monitoring**: CloudWatch metrics and Performance Insights
3. **Backup Testing**: Regular restore testing to ensure recovery procedures
4. **Read Replica Strategy**: Scale read replicas based on actual load patterns
5. **Connection Pooling**: Use PgBouncer to optimize connection management

## Performance Characteristics

### Expected Performance Metrics
```yaml
Write Throughput: 100,000+ transactions/minute
Read Throughput: 500,000+ queries/minute (with replicas)
Storage IOPS: Up to 100,000 IOPS (3 IOPS/GB)
Replication Lag: < 10ms to read replicas
Recovery Time: < 1 minute for failover

Connection Limits:
  db.r6g.large: ~1,600 connections
  With connection pooling: 10,000+ concurrent users
```

### Scaling Behavior
```yaml
Traffic Growth Pattern:
  Month 1-3: 1K shops, 10K users → db.r6g.large
  Month 4-6: 2.5K shops, 25K users → db.r6g.large + 1 read replica
  Month 7-12: 5K shops, 50K users → db.r6g.xlarge + 2 read replicas
  Year 2+: 10K shops, 100K users → db.r6g.2xlarge + 4 read replicas
```

## Multi-tenant Implementation

### Row Level Security (RLS) Setup
```sql
-- Enable RLS on tenant tables
ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Create tenant isolation policies
CREATE POLICY tenant_isolation ON shops
    FOR ALL TO application_user
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- Indexes optimized for tenant queries
CREATE INDEX CONCURRENTLY idx_shops_tenant_id ON shops (tenant_id);
CREATE INDEX CONCURRENTLY idx_products_tenant_id ON products (tenant_id);
```

### Connection Management
```yaml
Application Connection Strategy:
  - Connection pooling with PgBouncer
  - Set tenant context at connection level
  - Prepared statements for performance
  - Read/write splitting for read replicas

Tenant Context Setup:
  SET app.current_tenant = '<tenant_uuid>';
  -- All subsequent queries filtered by RLS
```

## Backup & Disaster Recovery

### Backup Strategy
```yaml
Automated Backups:
  Retention Period: 30 days
  Backup Window: 03:00-04:00 UTC
  Point-in-time Recovery: enabled
  Cross-region Backup: enabled for compliance

Manual Snapshots:
  Pre-deployment snapshots
  Major version upgrade snapshots
  Quarterly compliance snapshots
```

### Disaster Recovery
```yaml
RTO (Recovery Time Objective): 15 minutes
RPO (Recovery Point Objective): 5 minutes

Multi-AZ Failover: Automatic (< 60 seconds)
Cross-region Failover: Manual (< 15 minutes)
Point-in-time Recovery: < 5 minutes data loss
```

## Cost Optimization

### Reserved Instance Strategy
```yaml
1-Year Reserved Instances (No Upfront):
  Primary Instance: 25% savings
  Read Replicas: 25% savings
  Annual Savings: ~$1,500 at medium scale

3-Year Reserved Instances (Partial Upfront):
  Primary Instance: 40% savings
  Read Replicas: 40% savings
  Annual Savings: ~$2,400 at medium scale
```

### Performance Optimization
```sql
-- Materialized views for analytics
CREATE MATERIALIZED VIEW daily_sales_summary AS
SELECT tenant_id, date, SUM(total_amount) as daily_total
FROM orders 
WHERE created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY tenant_id, date;

-- Partial indexes for performance
CREATE INDEX CONCURRENTLY idx_active_products 
ON products (tenant_id, name) 
WHERE status = 'active';

-- Table partitioning for large tables
CREATE TABLE orders_2024 PARTITION OF orders
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

## Monitoring & Alerting

### Key Metrics
```yaml
Database Performance:
  - CPU Utilization < 80%
  - Database Connections < 80% of max
  - Read Latency < 20ms 95th percentile
  - Write Latency < 50ms 95th percentile

Tenant Performance:
  - Query execution time per tenant
  - Connection usage per tenant
  - Storage growth per tenant
  - RLS policy compliance
```

### Automated Alerts
```yaml
Critical Alerts:
  - Database failover events
  - Connection exhaustion (> 90%)
  - Slow query detection (> 5 seconds)
  - Backup failures

Warning Alerts:
  - High CPU utilization (> 70%)
  - Storage growth rate changes
  - Unusual query patterns
  - Read replica lag (> 100ms)
```

## Security Implementation

### Encryption
```yaml
Encryption at Rest:
  - AWS KMS customer-managed keys
  - Key rotation enabled (annual)
  - Separate keys per environment

Encryption in Transit:
  - Force SSL connections
  - TLS 1.2 minimum version
  - Certificate validation required
```

### Access Control
```yaml
Database Users:
  - application_user: RLS-enabled application access
  - readonly_user: Analytics and reporting
  - admin_user: Schema migrations and maintenance
  - monitoring_user: CloudWatch metrics collection

Network Security:
  - VPC private subnets only
  - Security groups restrict to application tier
  - No public internet access
  - VPC endpoints for AWS services
```

## Migration Strategy

### Phase 1: Setup (Month 1)
- Aurora cluster deployment
- Schema migration from development
- Connection pooling implementation
- Monitoring and alerting setup

### Phase 2: Data Migration (Month 2)
- Initial data import using AWS DMS
- RLS policy implementation and testing
- Performance tuning and optimization
- Backup and recovery testing

### Phase 3: Production Cutover (Month 3)
- Blue/green deployment
- Traffic gradual migration
- Performance validation
- Rollback procedures ready

## Success Metrics

### Performance Targets
- Query response time: < 100ms for 95% of queries
- Write throughput: Handle peak 200 requests/sec
- Read scaling: Support 10:1 read/write ratio
- Availability: 99.99% uptime (< 4.32 minutes/month downtime)

### Cost Targets
- Cost per shop per month: < $0.50
- Total database costs: < 20% of total infrastructure
- Cost predictability: ±5% monthly variance

## Related Decisions

* ADR-001: Multi-tenant Architecture (enables RLS strategy)
* ADR-004: Caching Strategy (reduces database load)
* ADR-006: Authentication Strategy (affects connection management)

## References

* [Amazon Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
* [PostgreSQL Row Level Security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
* [Aurora Performance Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)