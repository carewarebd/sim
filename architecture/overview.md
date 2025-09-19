# System Architecture Overview

## High-Level Architecture

This shop management system follows a modern microservices-oriented architecture deployed on AWS, designed for multi-tenancy, scalability, and cost-effectiveness.

### Core Principles

1. **Multi-tenant shared schema**: Single database with tenant isolation via row-level security (RLS)
2. **Event-driven architecture**: Asynchronous processing using SQS/SNS for scalability
3. **Caching strategy**: Multi-layer caching with Redis and CloudFront CDN
4. **Separation of concerns**: Distinct services for core business logic, search, and file storage
5. **Security-first**: JWT-based authentication, encryption at rest/transit, and VPC isolation

## System Components

### Frontend Layer
- **React SPA**: Single-page application with TypeScript and Tailwind CSS
- **CloudFront CDN**: Global content delivery with custom domain support
- **S3 Static Hosting**: Frontend assets served from S3 with CloudFront caching

### API Gateway & Authentication
- **Application Load Balancer**: SSL termination and traffic routing
- **AWS Cognito**: User authentication and JWT token management
- **API Gateway**: Rate limiting, request/response transformation
- **WAF**: Web application firewall for DDoS protection

### Application Layer  
- **ECS Fargate**: Container orchestration for API services
- **Auto Scaling Groups**: Horizontal scaling based on CPU/memory metrics
- **Lambda Functions**: Event-driven processing for notifications and background tasks

### Data Layer
- **PostgreSQL (Aurora)**: Primary transactional database with read replicas
- **OpenSearch**: Product search and analytics with geospatial capabilities  
- **Redis (ElastiCache)**: Session storage, API caching, and pub/sub messaging
- **S3**: Object storage for product images, invoices, and backups

### Integration Layer
- **SQS**: Message queues for async processing (orders, notifications)
- **SNS**: Push notifications and email/SMS alerts
- **EventBridge**: Event routing and workflow orchestration

## Data Flow Architecture

### 1. User Authentication Flow
```
User → CloudFront → ALB → API Gateway → Cognito → JWT Token → Client Storage
```

### 2. Product Management Flow  
```
User → Create/Update Product → API → PostgreSQL → CDC → OpenSearch Index
                             ↓
                      S3 (Image Upload via Presigned URL)
```

### 3. Order Processing Flow
```
Customer → Place Order → API → PostgreSQL → SQS → Lambda → SNS → Shop Owner Notification
                              ↓
                         Order Status Updates → WebSocket → Real-time UI Updates
```

### 4. Search & Discovery Flow
```
User → Search Query → API → OpenSearch → Filtered Results → PostgreSQL (Product Details)
                           ↓
                    Geospatial Query (Nearby Shops) → PostGIS Extension
```

### 5. Reporting & Analytics Flow
```
Daily Batch → Lambda → PostgreSQL → Materialized Views Refresh → Redis Cache → API → Dashboard
```

## Technology Stack Rationale

### Database Selection: PostgreSQL (Aurora)
- **ACID compliance** for financial transactions
- **JSON/JSONB support** for flexible product attributes
- **PostGIS extension** for geospatial queries (nearby shops)
- **Row-level security** for multi-tenant isolation
- **Mature ecosystem** with excellent AWS integration

### Search Engine: Amazon OpenSearch
- **Full-text search** with relevance scoring
- **Faceted filtering** (category, price range, availability)
- **Geospatial search** for location-based queries
- **Analytics capabilities** for business insights
- **Managed service** reduces operational overhead

### Caching Strategy: Multi-layer
- **CloudFront**: Static content (images, CSS, JS) - 24hr TTL
- **Redis**: API responses, session data - 1hr TTL
- **Application cache**: In-memory caching for frequent queries - 5min TTL

### Container Orchestration: ECS Fargate
- **Serverless containers** eliminate EC2 management
- **Auto-scaling** based on metrics and scheduled scaling
- **Cost-effective** compared to EKS for moderate workloads
- **Integrated monitoring** with CloudWatch

## Multi-Tenancy Architecture

### Shared Schema with RLS Approach

**Advantages:**
- **Cost-effective**: Single database instance serves all tenants
- **Easier maintenance**: Schema changes deploy once across all tenants  
- **Resource sharing**: Better utilization of database connections and memory
- **Consistent performance**: All tenants benefit from database optimizations

**Implementation:**
```sql
-- All tables include tenant_id
CREATE TABLE products (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    ...
);

-- Row-level security policies
CREATE POLICY tenant_isolation ON products
    USING (tenant_id = current_setting('app.current_tenant')::UUID);
```

**Security Measures:**
- Connection-level tenant context setting
- Application-layer tenant validation
- Database views that auto-filter by tenant
- Audit logging of cross-tenant access attempts

### Alternative Approaches Considered

**Schema-per-tenant**: Rejected due to management complexity at 10,000+ tenants
**Database-per-tenant**: Rejected due to cost ($50k+/month for RDS instances)

## Scalability Design

### Horizontal Scaling Points
- **API Layer**: ECS auto-scaling (2-20 containers)
- **Database**: Read replicas (up to 15) with read/write splitting
- **Search**: OpenSearch cluster scaling (3-15 nodes)
- **Cache**: Redis cluster mode with sharding

### Vertical Scaling Limits
- **RDS Aurora**: Up to 128 vCPUs, 768GB RAM per writer instance
- **OpenSearch**: Up to 3TB storage per node, 192 GiB memory
- **ECS Tasks**: Up to 4 vCPU, 30GB memory per container

### Performance Targets
- **API Response Time**: P95 < 200ms, P99 < 500ms
- **Search Response Time**: P95 < 100ms for simple queries
- **Database Connections**: Max 1000 concurrent (connection pooling)
- **Throughput**: 200 requests/sec sustained, 400 req/sec burst

## Security Architecture

### Network Security
- **VPC**: Private subnets for database and application tiers
- **Security Groups**: Principle of least privilege access
- **NACLs**: Network-level traffic filtering
- **WAF**: Protection against common web exploits

### Data Security  
- **Encryption at Rest**: AES-256 for all storage services
- **Encryption in Transit**: TLS 1.3 for all communications
- **Secrets Management**: AWS Secrets Manager for database credentials
- **Key Management**: AWS KMS with customer-managed keys

### Application Security
- **Authentication**: OAuth 2.0 with JWT tokens
- **Authorization**: Role-based access control (RBAC)
- **Rate Limiting**: Per-user and per-tenant limits
- **Input Validation**: Comprehensive sanitization and validation

## Disaster Recovery & Backup

### Recovery Time Objective (RTO): 4 hours
### Recovery Point Objective (RPO): 1 hour

### Backup Strategy
- **PostgreSQL**: Automated backups with 7-day retention, cross-region snapshots
- **OpenSearch**: Daily snapshots to S3 with 30-day retention
- **S3**: Cross-region replication for critical business data
- **Application**: Infrastructure as Code for rapid environment recreation

### Failover Procedures
1. **Database**: Automated failover to read replica in same AZ (< 2 minutes)
2. **Cross-region**: Manual failover to disaster recovery region (< 4 hours)  
3. **Application**: ECS service replacement with health checks (< 5 minutes)
4. **DNS**: Route 53 health checks for automatic traffic routing

## Monitoring & Observability

### Key Metrics
- **Application**: Request rate, error rate, response time percentiles
- **Database**: Connection count, CPU utilization, replication lag
- **Infrastructure**: Container CPU/memory, disk space, network throughput
- **Business**: Daily active users, order volume, revenue metrics

### Alerting Thresholds
- **High Priority**: 5xx error rate > 1%, database CPU > 80%
- **Medium Priority**: Response time P95 > 500ms, disk usage > 85%
- **Low Priority**: Daily backup failures, certificate expiration warnings

### Observability Tools
- **CloudWatch**: Metrics, logs, and dashboards
- **X-Ray**: Distributed tracing for request flows
- **OpenSearch Dashboards**: Business analytics and search metrics
- **Custom Dashboards**: Grafana for detailed infrastructure monitoring

## Performance Optimization

### Database Optimizations
- **Connection Pooling**: PgBouncer with 100 max connections per service
- **Query Optimization**: Proper indexing, query plan analysis
- **Materialized Views**: Pre-computed aggregations for reports
- **Partitioning**: Large tables partitioned by date/tenant

### Caching Strategy
- **Database Query Cache**: Redis with 1-hour TTL for read-heavy queries
- **API Response Cache**: Application-level caching with cache invalidation
- **CDN Cache**: CloudFront for static content with regional edge locations
- **Browser Cache**: Aggressive caching headers for static assets

### Search Optimization
- **Index Design**: Optimized field mappings for query patterns
- **Shard Strategy**: Balanced sharding across cluster nodes
- **Query Optimization**: Filtered queries before full-text search
- **Result Caching**: Popular search results cached in Redis

---

This architecture is designed to handle the specified load of 10,000 shops and 200 requests/sec while maintaining cost-effectiveness and operational simplicity. The system can scale horizontally at multiple layers and includes comprehensive monitoring and disaster recovery capabilities.