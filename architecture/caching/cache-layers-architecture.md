# Cache Layers Architecture

## Overview
This document defines the multi-layer caching architecture for the Shop Management System, leveraging different cache types and technologies to optimize performance across all system components.

## Cache Layer Hierarchy

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT LAYER                         │
├─────────────────────────────────────────────────────────┤
│ • Browser Cache (HTTP headers)                          │
│ • Service Worker Cache (Progressive Web App)            │
│ • Local Storage (user preferences, temp data)           │
│ • Session Storage (temporary UI state)                  │
└─────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────┐
│                      CDN LAYER                          │
├─────────────────────────────────────────────────────────┤
│ • CloudFront Edge Locations (Global)                    │
│ • Static Assets (Images, CSS, JS, Fonts)                │
│ • API Response Caching (Selected Endpoints)             │
│ • Geographic Distribution                               │
└─────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────┐
│                 LOAD BALANCER LAYER                     │
├─────────────────────────────────────────────────────────┤
│ • Application Load Balancer (ALB)                       │
│ • Connection pooling                                    │
│ • Health check caching                                 │
└─────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────┐
│                 APPLICATION LAYER                       │
├─────────────────────────────────────────────────────────┤
│ • Redis Cluster (Primary Cache)                         │
│ • In-Memory Cache (Node.js applications)                │
│ • Session Store                                         │
│ • API Response Cache                                    │
└─────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────┐
│                   DATABASE LAYER                        │
├─────────────────────────────────────────────────────────┤
│ • PostgreSQL Query Result Cache                         │
│ • Connection Pool Caching                              │
│ • Prepared Statement Cache                             │
│ • OpenSearch Result Cache                              │
└─────────────────────────────────────────────────────────┘
```

## Layer Specifications

### 1. Client Layer Caching

#### Browser HTTP Cache
**Configuration:**
```http
# Static Assets (1 year)
Cache-Control: public, max-age=31536000, immutable

# API Responses - Frequently Accessed Data
Cache-Control: public, max-age=300, stale-while-revalidate=60

# API Responses - User-Specific Data  
Cache-Control: private, max-age=120, stale-while-revalidate=30

# No Cache - Real-time Data
Cache-Control: no-cache, no-store, must-revalidate
```

**Use Cases:**
- Product catalog images and thumbnails
- User interface assets (CSS, JavaScript, fonts)
- API responses for product listings
- User profile data (private caching)

#### Service Worker Cache (PWA)
**Implementation Strategy:**
```javascript
// Cache Strategy Implementation
const CACHE_NAME = 'shop-management-v1';
const CACHE_STRATEGIES = {
  static: 'CacheFirst',          // Images, CSS, JS
  api: 'StaleWhileRevalidate',   // API responses  
  realtime: 'NetworkOnly'        // Stock levels, orders
};

// Product catalog pre-caching
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll([
        '/api/products?page=1&limit=20',
        '/api/categories',
        '/api/user-profile'
      ]))
  );
});
```

**Benefits:**
- Offline functionality for browsing products
- Instant loading for frequently accessed data
- Reduced server load for repeat visits

#### Local Storage Strategy
**Data Types:**
```javascript
// User Preferences (Long-term)
localStorage.setItem('userPreferences', JSON.stringify({
  theme: 'dark',
  language: 'en',
  currency: 'USD',
  itemsPerPage: 20
}));

// Recently Viewed Products (Session-based)
sessionStorage.setItem('recentProducts', JSON.stringify([
  { id: 'uuid1', timestamp: Date.now() },
  { id: 'uuid2', timestamp: Date.now() }
]));
```

### 2. CDN Layer (CloudFront)

#### Cache Behaviors Configuration
```yaml
# Static Assets Behavior
static-assets:
  path_pattern: "/assets/*"
  compress: true
  cache_policy:
    ttl: 31536000  # 1 year
    query_strings: ignore
    headers: [Accept-Encoding]

# API Responses Behavior  
api-responses:
  path_pattern: "/api/products*"
  cache_policy:
    ttl: 300  # 5 minutes
    query_strings: all
    headers: [Authorization, Accept]
    
# Dynamic Content (No Cache)
dynamic-content:
  path_pattern: "/api/orders*"
  cache_policy:
    ttl: 0
    query_strings: all
    headers: all
```

#### Geographic Distribution
**Edge Locations Strategy:**
- **Primary Regions:** US East, US West, EU West, Asia Pacific
- **Secondary Regions:** South America, Middle East, Africa
- **Origin Shield:** Enabled for reduced origin load

**Performance Targets:**
- Static assets: < 100ms response time globally
- Cached API responses: < 200ms response time
- Cache hit ratio: > 90% for static content, > 70% for API responses

### 3. Application Layer Caching

#### Redis Cluster Configuration
**Cluster Topology:**
```yaml
redis_cluster:
  nodes: 6  # 3 masters, 3 replicas
  instance_type: cache.r6g.large
  availability_zones: [us-east-1a, us-east-1b, us-east-1c]
  
  memory_optimization:
    maxmemory_policy: allkeys-lru
    maxmemory: 3.5gb_per_node
    
  persistence:
    rdb_backup: enabled
    backup_retention: 7_days
```

**Cache Patterns Implementation:**

##### Cache-Aside Pattern
```javascript
// Product retrieval with cache-aside
async function getProduct(productId, tenantId) {
  const cacheKey = `product:${tenantId}:${productId}`;
  
  // Try cache first
  let product = await redis.get(cacheKey);
  if (product) {
    return JSON.parse(product);
  }
  
  // Fallback to database
  product = await db.query('SELECT * FROM products WHERE id = $1 AND tenant_id = $2', 
                          [productId, tenantId]);
  
  // Store in cache for future requests
  await redis.setex(cacheKey, 900, JSON.stringify(product)); // 15 min TTL
  
  return product;
}
```

##### Write-Through Pattern
```javascript
// Product update with write-through caching
async function updateProduct(productId, tenantId, updates) {
  // Update database first
  const updatedProduct = await db.query(
    'UPDATE products SET ... WHERE id = $1 AND tenant_id = $2 RETURNING *',
    [productId, tenantId]
  );
  
  // Update cache immediately
  const cacheKey = `product:${tenantId}:${productId}`;
  await redis.setex(cacheKey, 900, JSON.stringify(updatedProduct));
  
  // Invalidate related caches
  await invalidateRelatedCaches(productId, tenantId);
  
  return updatedProduct;
}
```

#### In-Memory Application Cache
**Node.js Memory Cache:**
```javascript
const NodeCache = require('node-cache');

// Configuration-specific cache (long TTL)
const configCache = new NodeCache({ 
  stdTTL: 3600,    // 1 hour
  checkperiod: 600  // Check for expired keys every 10 minutes
});

// User session cache (medium TTL)
const sessionCache = new NodeCache({ 
  stdTTL: 1800,     // 30 minutes
  maxKeys: 10000    // Limit memory usage
});

// API response cache (short TTL)
const apiCache = new NodeCache({
  stdTTL: 300,      // 5 minutes
  maxKeys: 50000
});
```

### 4. Database Layer Caching

#### PostgreSQL Query Caching
**Configuration Optimization:**
```postgresql
-- Query cache configuration
shared_preload_libraries = 'pg_stat_statements'
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 256MB

-- Query result caching
SET enable_seqscan = off;  -- Force index usage where possible
SET random_page_cost = 1.1; -- SSD optimization
```

**Prepared Statement Caching:**
```javascript
// Connection pool with prepared statement cache
const pool = new Pool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  max: 20, // Maximum connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
  
  // Enable prepared statement caching
  statement_timeout: 30000,
  query_timeout: 30000,
  options: '-c default_transaction_isolation=read committed'
});
```

#### OpenSearch Caching
**Search Result Caching:**
```json
{
  "query": {
    "bool": {
      "must": [
        {"match": {"name": "laptop"}},
        {"term": {"tenant_id": "uuid"}}
      ]
    }
  },
  "size": 20,
  "_source_excludes": ["large_description"],
  
  // Enable result caching
  "request_cache": true,
  "preference": "_local"
}
```

## Multi-Tenant Cache Isolation

### Tenant-Specific Cache Keys
**Naming Convention:**
```
Format: {service}:{tenant_id}:{resource}:{identifier}[:{modifier}]

Examples:
products:tenant123:product:uuid456
users:tenant123:profile:user789
reports:tenant123:daily_sales:2024-09-20
search:tenant123:query:laptop:page1
marketplace:public:nearby_shops:lat40.7:lng74.0
```

### Cache Partitioning Strategies

#### Redis Cluster Partitioning
```javascript
// Tenant-based hash slot distribution
function getTenantCacheKey(tenantId, resource, identifier) {
  // Ensure tenant data stays together in cluster
  return `{${tenantId}}:${resource}:${identifier}`;
}

// Usage
const productKey = getTenantCacheKey('tenant123', 'product', 'uuid456');
// Results in: {tenant123}:product:uuid456
```

#### Memory Isolation
```yaml
tenant_memory_limits:
  small_tenant: 100MB    # < 1000 products
  medium_tenant: 500MB   # 1000-10000 products  
  large_tenant: 2GB      # > 10000 products
  enterprise: 5GB        # Unlimited with monitoring
```

## Performance Monitoring

### Cache Hit Ratio Targets
```yaml
performance_targets:
  client_cache:
    static_assets: 95%
    api_responses: 85%
    
  cdn_cache:
    static_content: 90%
    api_responses: 70%
    
  application_cache:
    redis_cluster: 85%
    in_memory: 90%
    
  database_cache:
    query_cache: 80%
    connection_pool: 95%
```

### Monitoring Metrics
```javascript
// Cache performance metrics to track
const cacheMetrics = {
  hitRatio: 'cache_hits / (cache_hits + cache_misses)',
  averageResponseTime: 'avg(response_time_ms)',
  memoryUsage: 'used_memory / max_memory',
  evictionRate: 'evicted_keys_per_minute',
  connectionPoolUtilization: 'active_connections / max_connections'
};

// Alert thresholds
const alertThresholds = {
  hitRatioBelow: 70,          // %
  responseTimeAbove: 1000,    // ms
  memoryUsageAbove: 90,       // %
  evictionRateAbove: 100      // per minute
};
```

## Cost Optimization Strategies

### Cache Tier Optimization
**Cost-Benefit Analysis:**
```
Tier 1 - Hot Data (Redis): $200/month
  - Products catalog
  - User sessions  
  - Search results
  - ROI: 70% response time improvement

Tier 2 - Warm Data (Application Memory): $50/month
  - Configuration data
  - User preferences
  - Category hierarchies
  - ROI: 40% response time improvement

Tier 3 - Cold Data (Database Cache): Included in DB costs
  - Historical reports
  - Archived orders
  - Analytics data
  - ROI: 20% response time improvement
```

### Auto-Scaling Cache Resources
```yaml
redis_autoscaling:
  scale_up_triggers:
    - memory_utilization > 80%
    - cpu_utilization > 70%
    - connection_count > 80% of max
    
  scale_down_triggers:
    - memory_utilization < 40% for 15 minutes
    - cpu_utilization < 30% for 15 minutes
    
  scaling_policies:
    scale_up: add 1 node, max 10 nodes
    scale_down: remove 1 node, min 3 nodes
    cooldown_period: 300 seconds
```

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- Set up Redis cluster with basic configuration
- Implement client-side HTTP caching headers
- Configure CloudFront for static assets
- Basic cache-aside pattern for products

### Phase 2: Advanced Caching (Weeks 3-4)  
- Multi-tier cache implementation
- Tenant isolation and partitioning
- Advanced invalidation strategies
- Performance monitoring setup

### Phase 3: Optimization (Weeks 5-6)
- Auto-scaling implementation
- Cost optimization analysis
- Advanced monitoring and alerting
- Performance tuning based on metrics

### Phase 4: Real-time Integration (Weeks 7-8)
- WebSocket integration with caching
- Real-time invalidation systems
- Hybrid caching for live data
- Complete monitoring dashboard