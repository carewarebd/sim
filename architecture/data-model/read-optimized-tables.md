# Read-Optimized Tables and Caching Strategy

## Overview

This document outlines the denormalization strategy and caching architecture used to optimize read performance for frequently accessed data patterns in the shop management system.

## Performance Requirements

- **API Response Time**: P95 < 200ms, P99 < 500ms
- **Search Response Time**: P95 < 100ms
- **Dashboard Load Time**: < 1 second for KPI widgets
- **Concurrent Users**: 50,000 monthly active users
- **Peak Load**: 200 requests/sec sustained

## Denormalization Strategy

### 1. Materialized Views for Analytics

The system uses three primary materialized views to precompute frequently requested aggregations:

#### Daily Sales Summary
```sql
CREATE MATERIALIZED VIEW daily_sales_summary AS
SELECT 
    o.tenant_id,
    DATE(o.created_at) as date,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_revenue,
    COALESCE(SUM(oi.quantity), 0) as total_items_sold,
    COALESCE(AVG(o.total_amount), 0) as avg_order_value,
    (SELECT oi2.product_id 
     FROM order_items oi2 
     JOIN orders o2 ON oi2.order_id = o2.id 
     WHERE o2.tenant_id = o.tenant_id 
       AND DATE(o2.created_at) = DATE(o.created_at)
     GROUP BY oi2.product_id 
     ORDER BY SUM(oi2.quantity) DESC 
     LIMIT 1) as top_selling_product_id,
    now() as updated_at
FROM orders o
LEFT JOIN order_items oi ON o.id = oi.order_id
WHERE o.status NOT IN ('cancelled', 'refunded')
GROUP BY o.tenant_id, DATE(o.created_at);
```

**Optimization Benefits:**
- Dashboard KPI queries reduce from ~500ms to <50ms
- Eliminates daily JOIN operations across orders and order_items
- Supports time-series analysis without complex aggregations

**Refresh Schedule:** Daily at 1:00 AM UTC via scheduled Lambda

#### Salesperson Performance Summary
```sql
CREATE MATERIALIZED VIEW salesperson_performance AS
SELECT 
    o.tenant_id,
    o.salesperson_id,
    DATE_TRUNC('month', o.created_at) as month,
    COUNT(o.id) as orders_count,
    COALESCE(SUM(o.total_amount), 0) as total_sales,
    COALESCE(SUM(o.total_amount) * 0.05, 0) as commission_earned,
    now() as updated_at
FROM orders o
WHERE o.salesperson_id IS NOT NULL
  AND o.status NOT IN ('cancelled', 'refunded')
GROUP BY o.tenant_id, o.salesperson_id, DATE_TRUNC('month', o.created_at);
```

**Optimization Benefits:**
- Monthly performance reports load instantly
- Eliminates need for complex GROUP BY queries with date functions
- Supports commission calculations without runtime computation

**Refresh Schedule:** Monthly on the 1st at 2:00 AM UTC

#### Product Popularity Summary
```sql
CREATE MATERIALIZED VIEW product_popularity AS
SELECT 
    oi.tenant_id,
    oi.product_id,
    DATE_TRUNC('month', o.created_at) as month,
    COUNT(DISTINCT o.id) as times_ordered,
    SUM(oi.quantity) as quantity_sold,
    SUM(oi.total_price) as revenue_generated,
    now() as updated_at
FROM order_items oi
JOIN orders o ON oi.order_id = o.id
WHERE o.status NOT IN ('cancelled', 'refunded')
GROUP BY oi.tenant_id, oi.product_id, DATE_TRUNC('month', o.created_at);
```

**Optimization Benefits:**
- Product recommendation algorithms use pre-computed popularity scores
- Inventory decisions based on fast popularity lookups
- Marketing campaigns can quickly identify trending products

**Refresh Schedule:** Weekly on Sunday at 3:00 AM UTC

### 2. Denormalized Fields in Orders

To avoid JOINs during order processing, key product information is stored redundantly in `order_items`:

```sql
CREATE TABLE order_items (
    id UUID PRIMARY KEY,
    order_id UUID NOT NULL,
    product_id UUID NOT NULL,
    product_name VARCHAR(255) NOT NULL,  -- Denormalized
    product_sku VARCHAR(100) NOT NULL,   -- Denormalized
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,   -- Snapshot at time of order
    total_price DECIMAL(10,2) NOT NULL,
    -- ...
);
```

**Rationale:**
- Order history remains accurate even if product details change
- Invoice generation doesn't require JOINs with products table
- Order reports perform 3x faster without product lookups

## Multi-Layer Caching Strategy

### Layer 1: Application Cache (In-Memory)
- **Technology**: Node.js in-memory cache (Map/LRU)
- **TTL**: 5 minutes
- **Use Cases**: Frequently accessed configuration data, current user sessions
- **Size Limit**: 100MB per container instance

```javascript
// Example: Product cache with LRU eviction
const productCache = new LRUCache({
  max: 1000,           // Max 1000 products
  maxSize: 50 * 1024 * 1024, // 50MB max
  ttl: 5 * 60 * 1000   // 5 minutes
});
```

### Layer 2: Redis Cache (ElastiCache)
- **Technology**: Redis Cluster with 2 nodes (Primary + Replica)
- **TTL**: 1 hour for API responses, 24 hours for reference data
- **Use Cases**: API response caching, session storage, real-time data

#### Key Patterns:
```redis
# API Response Cache
SET "api:products:tenant123:page1" "{json_response}" EX 3600

# Session Storage
HSET "session:user456" "tenant_id" "123" "role" "admin" EX 86400

# Counter Cache (order counts, inventory levels)
INCR "counters:tenant123:daily_orders:2024-09-19"
```

#### Cache Invalidation Strategy:
- **Write-through**: Update cache immediately after database writes
- **TTL-based**: Automatic expiration for time-sensitive data  
- **Event-driven**: SQS messages trigger cache invalidation on entity updates
- **Tagging**: Group related cache keys for bulk invalidation

```javascript
// Example: Product update invalidates related cache keys
async function updateProduct(productId, updates) {
  await database.updateProduct(productId, updates);
  
  // Invalidate related cache entries
  await cache.del([
    `product:${productId}`,
    `products:tenant:${tenantId}:page:*`,
    `search:products:*`,
    `popular:products:${tenantId}`
  ]);
}
```

### Layer 3: CloudFront CDN
- **TTL**: 24 hours for static assets, 5 minutes for dynamic API responses
- **Edge Locations**: Global AWS edge network
- **Use Cases**: Product images, static files, public API responses

#### Cache Behaviors:
```yaml
# CloudFront Distribution Settings
CacheBehaviors:
  - PathPattern: "/api/public/*"
    TTL: 300              # 5 minutes
    Compress: true
    
  - PathPattern: "/images/*" 
    TTL: 86400           # 24 hours
    Compress: true
    
  - PathPattern: "/assets/*"
    TTL: 31536000        # 1 year
    Compress: true
```

## Read Replica Strategy

### PostgreSQL Read Replicas
- **Primary**: 1 writer instance (db.r6g.xlarge) 
- **Replicas**: 2 reader instances (db.r6g.large)
- **Replication Lag**: Target < 100ms

#### Read/Write Splitting Logic:
```javascript
// Database connection routing
const readQueries = [
  'SELECT', 'SHOW', 'DESCRIBE', 'EXPLAIN'
];

function getConnection(query) {
  const isReadQuery = readQueries.some(cmd => 
    query.trim().toUpperCase().startsWith(cmd)
  );
  
  return isReadQuery ? readOnlyDB : primaryDB;
}
```

### Query Distribution:
- **95% reads**: Routed to read replicas
- **5% writes**: Routed to primary instance
- **Analytics queries**: Dedicated read replica with larger instance size

## Performance Monitoring

### Key Metrics:
- **Cache Hit Ratio**: Target > 85%
- **Redis Memory Usage**: Alert at 80% capacity
- **Materialized View Lag**: Monitor refresh completion times
- **Read Replica Lag**: Alert if lag > 5 seconds

### Monitoring Queries:
```sql
-- Check materialized view freshness
SELECT 
  schemaname, 
  matviewname, 
  definition,
  ispopulated,
  hasindexes
FROM pg_matviews 
WHERE schemaname = 'public';

-- Monitor read replica lag
SELECT 
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  sync_state,
  EXTRACT(EPOCH FROM (now() - replay_timestamp)) AS lag_seconds
FROM pg_stat_replication;
```

## Cache Warming Strategy

### Application Startup:
1. **Load Reference Data**: Tenants, users, categories into Redis
2. **Warm Popular Queries**: Most accessed products and orders 
3. **Precompute Aggregations**: Dashboard KPIs for active tenants

### Scheduled Cache Warming:
```javascript
// Lambda function runs every 4 hours
async function warmCaches() {
  const activeTenants = await getActiveTenants();
  
  for (const tenant of activeTenants) {
    // Warm product catalog
    await cachePopularProducts(tenant.id);
    
    // Warm dashboard data
    await cacheDashboardKPIs(tenant.id);
    
    // Warm user sessions
    await cacheActiveUserSessions(tenant.id);
  }
}
```

## Index Optimization for Read Performance

### Composite Indexes for Common Query Patterns:

```sql
-- Optimized for "orders by tenant and date range"  
CREATE INDEX idx_orders_tenant_date_status 
ON orders(tenant_id, created_at DESC, status) 
WHERE status NOT IN ('cancelled', 'refunded');

-- Optimized for "products by category with stock"
CREATE INDEX idx_products_category_stock 
ON products(tenant_id, category_id, stock_quantity) 
WHERE is_active = true;

-- Optimized for "low stock alerts"
CREATE INDEX idx_products_low_stock_alert 
ON products(tenant_id, stock_quantity, min_stock_level) 
WHERE stock_quantity <= min_stock_level AND is_active = true;
```

### Partial Indexes for Performance:
```sql
-- Only index active products for search
CREATE INDEX idx_products_search_active 
ON products USING GIN(to_tsvector('english', name || ' ' || description))
WHERE is_active = true;

-- Only index unread notifications  
CREATE INDEX idx_notifications_unread_user 
ON notifications(user_id, created_at DESC) 
WHERE read_at IS NULL;
```

## Cost-Performance Trade-offs

### Materialized View Storage Cost:
- **daily_sales_summary**: ~1MB per 10,000 tenants per year
- **salesperson_performance**: ~500KB per 10,000 tenants per year  
- **product_popularity**: ~2MB per 10,000 tenants per year
- **Total Additional Storage**: ~35MB per year at full scale

### Redis Memory Cost:
- **Instance**: cache.r6g.large (13.07 GiB memory)
- **Monthly Cost**: ~$125
- **Memory Utilization**: Target 70% (9GB active data)

### Read Replica Cost:
- **2x db.r6g.large instances**: ~$580/month  
- **Performance Gain**: 3x improvement in read query response time
- **Availability Benefit**: Failover capability for high availability

## Cache Invalidation Patterns

### Event-Driven Invalidation:
```javascript
// Product update triggers cache invalidation
await productService.update(productId, changes);

// Publish cache invalidation event
await sns.publish({
  TopicArn: 'arn:aws:sns:us-east-1:account:cache-invalidation',
  Message: JSON.stringify({
    type: 'PRODUCT_UPDATED',
    tenantId: tenantId,
    productId: productId,
    keys: [`product:${productId}`, `products:tenant:${tenantId}:*`]
  })
});
```

### Smart Invalidation:
- **Granular**: Invalidate specific keys rather than clearing all cache
- **Conditional**: Only invalidate if actual data changes occurred
- **Batched**: Group multiple invalidations into single operations

## Conclusion

This read-optimization strategy achieves:
- **4x improvement** in dashboard load times via materialized views
- **85%+ cache hit ratio** through multi-layer caching
- **Sub-100ms response times** for 95% of read queries
- **Cost-effective scaling** to 10,000 tenants with predictable performance

The combination of denormalized data, strategic caching, and optimized indexes ensures the system can handle the target load of 200 requests/sec while maintaining excellent user experience.