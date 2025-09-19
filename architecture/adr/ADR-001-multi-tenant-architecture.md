# ADR-001: Multi-tenant Architecture

**Status**: Accepted  
**Date**: 2024-01-01  
**Deciders**: Architecture Team  
**Technical Story**: Design tenant isolation strategy for shop management system

## Context

We need to support multiple shops (tenants) in a single system while ensuring:
- Strong data isolation between tenants
- Cost efficiency at scale
- Operational simplicity
- Performance consistency
- Compliance with data protection regulations

## Decision Drivers

* **Cost Efficiency**: Database and infrastructure costs should not scale linearly with tenant count
* **Data Security**: Absolute data isolation between tenants is mandatory
* **Scalability**: System must handle 10,000+ shops efficiently  
* **Operational Simplicity**: Minimize management overhead
* **Performance**: Query performance should not degrade significantly with tenant count
* **Compliance**: Meet data residency and isolation requirements

## Options Considered

### Option 1: Database Per Tenant
**Description**: Each tenant gets their own dedicated PostgreSQL database

**Pros**:
- Complete data isolation
- Independent scaling per tenant
- Easier backup/restore per tenant
- No noisy neighbor issues

**Cons**:
- High infrastructure costs ($500+/month per tenant)
- Complex connection management
- Operational overhead (monitoring, updates, maintenance)
- Resource waste for small tenants

**Cost Analysis**: $500/month × 10,000 tenants = $5,000,000/month

### Option 2: Schema Per Tenant  
**Description**: Single database with dedicated schema per tenant

**Pros**:
- Good data isolation
- Shared infrastructure costs
- Easier cross-tenant analytics
- Single connection pool

**Cons**:
- PostgreSQL schema limits (~1000 schemas practical)
- Complex schema management
- Migration complexity
- Query routing complexity

**Cost Analysis**: ~$2,000/month for large database instance

### Option 3: Shared Database with Row Level Security (RLS)
**Description**: Single database with tenant_id column and RLS policies

**Pros**:
- Cost efficient - single database
- Strong security with RLS policies
- Simple connection management
- Easy cross-tenant operations
- Excellent PostgreSQL RLS support

**Cons**:
- Potential noisy neighbor issues
- More complex query patterns
- Risk of RLS policy mistakes
- Single point of failure

**Cost Analysis**: ~$500-2000/month depending on scale

### Option 4: Application-Level Isolation
**Description**: Handle tenant isolation entirely in application code

**Pros**:
- Maximum flexibility
- No database-level complexity
- Easy to implement initially

**Cons**:
- High security risk
- Prone to developer errors
- Complex query logic
- No database-level enforcement

## Decision

**Chosen Option**: **Option 3 - Shared Database with Row Level Security (RLS)**

### Rationale

1. **Cost Effectiveness**: Single database instance vs. thousands of separate databases
2. **Security**: PostgreSQL RLS provides database-level enforcement
3. **Scalability**: Proven to scale to millions of rows with proper indexing
4. **Operational Simplicity**: Single database to monitor, backup, and maintain
5. **Performance**: Modern PostgreSQL handles RLS efficiently with proper indexing

### Implementation Details

```sql
-- Tenant isolation policy example
CREATE POLICY tenant_isolation ON shops
    FOR ALL TO application_user
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- Enable RLS on all tenant tables
ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
-- ... etc for all tenant tables
```

## Consequences

### Positive Consequences

* **Dramatic Cost Savings**: $5M/month → $2K/month for database infrastructure
* **Operational Simplicity**: Single database to manage instead of thousands
* **Strong Security**: Database-enforced tenant isolation via RLS
* **Performance**: Excellent query performance with proper tenant_id indexing
* **Flexibility**: Easy to add cross-tenant features when needed

### Negative Consequences  

* **Complexity**: Application must always set tenant context correctly
* **Risk**: RLS policy mistakes could leak data between tenants
* **Performance**: Some queries may be more complex due to RLS overhead
* **Single Point of Failure**: Database outage affects all tenants

### Mitigation Strategies

1. **Automated Testing**: Comprehensive RLS policy testing in CI/CD
2. **Code Reviews**: Mandatory review for all tenant-related code
3. **Monitoring**: Real-time monitoring for cross-tenant data access
4. **High Availability**: Aurora cluster with automatic failover
5. **Backup Strategy**: Point-in-time recovery with 30-day retention

## Compliance Considerations

* **GDPR**: Tenant data can be isolated and deleted per tenant_id
* **SOX**: Audit trails maintained per tenant with immutable logs
* **PCI DSS**: Payment data isolated using RLS + additional encryption
* **Data Residency**: All tenant data in single compliant region

## Monitoring & Validation

### Success Metrics
- Zero cross-tenant data leaks
- Query performance within 200ms 95th percentile
- Database costs under $3,000/month at 10K tenants
- RLS policy coverage 100% on tenant tables

### Monitoring
- Custom CloudWatch metrics for tenant access patterns
- Automated alerts for potential RLS violations
- Performance monitoring per tenant
- Regular security audits of RLS policies

## Related Decisions

* ADR-002: Database Technology Choice (PostgreSQL)
* ADR-003: Authentication Strategy (affects tenant context)
* ADR-004: API Design (tenant routing strategy)

## References

* [PostgreSQL Row Level Security Documentation](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
* [Multi-tenant SaaS Architecture Patterns](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-isolation.html)
* [RLS Performance Best Practices](https://www.postgresql.org/docs/current/sql-createpolicy.html)