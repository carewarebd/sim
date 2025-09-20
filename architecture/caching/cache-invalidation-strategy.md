# Cache Invalidation Strategy

## Overview
This document outlines comprehensive strategies for handling cache invalidation while maintaining real-time update requirements for dashboards, inventory, and critical business operations.

## Cache Invalidation Patterns

### 1. Time-Based Invalidation (TTL - Time To Live)

#### Short TTL (30 seconds - 5 minutes)
**Use Cases:**
- Real-time dashboard metrics with acceptable delay
- Product pricing that changes frequently
- Stock level approximations (with real-time overlay)

**Implementation:**
```
Cache-Control: max-age=300, stale-while-revalidate=60
```

**Benefits:**
- Automatic expiration reduces manual invalidation complexity
- Acceptable for near-real-time data
- Prevents indefinite stale data

#### Medium TTL (5 - 60 minutes)
**Use Cases:**
- Product catalog details (excluding stock)
- User profiles and permissions
- Category hierarchies
- Search result sets

**Implementation:**
```
Cache-Control: max-age=1800, stale-while-revalidate=300
```

#### Long TTL (1+ hours)
**Use Cases:**
- Static configuration data
- Historical reports (previous days/months)
- System settings and metadata
- Generated documents (PDFs, invoices)

### 2. Event-Driven Invalidation

#### Database Change Events
**Trigger Scenarios:**
- Product updates → Invalidate product cache + search results
- Price changes → Invalidate product + marketplace caches
- User profile updates → Invalidate user-specific caches
- Category modifications → Invalidate category + product listing caches

**Implementation with AWS:**
```
DynamoDB Streams / RDS Event Notifications 
→ Lambda Functions 
→ ElastiCache/Redis FLUSHALL or specific key deletion
→ CloudFront invalidation API calls
```

#### Application-Level Events
**Event Types:**
```json
{
  "eventType": "product.updated",
  "productId": "uuid",
  "tenantId": "uuid", 
  "affectedCaches": [
    "product:uuid",
    "products:tenant:uuid:*",
    "search:*:product:uuid",
    "marketplace:nearby:*"
  ],
  "timestamp": "2024-09-20T10:30:00Z"
}
```

### 3. Hybrid Real-Time + Cached Approach

#### Stock Level Management
**Problem:** Stock levels change constantly but need real-time accuracy

**Solution - Layered Data Architecture:**
```
├── Cached Layer (Redis): Product base information (5-15 min TTL)
│   ├── Product details, images, descriptions
│   ├── Base pricing and categories
│   └── Reviews and ratings
│
└── Real-Time Layer (WebSocket/SSE): Dynamic information
    ├── Current stock levels
    ├── Live pricing updates
    └── Availability status
```

**Frontend Implementation:**
```javascript
// Load cached product data
const productBase = await getCachedProduct(productId);

// Establish real-time connection for live data
const liveData = connectToLiveUpdates(productId);
liveData.onStockUpdate(newStock => updateUI(newStock));

// Merge cached + live data for complete view
const completeProduct = { ...productBase, stock: liveData.currentStock };
```

#### Dashboard Analytics
**Problem:** Need real-time metrics but expensive to compute constantly

**Solution - Smart Refresh Strategy:**
```
├── Background Jobs: Pre-compute metrics every 5-15 minutes
├── Cache Layer: Store computed results with short TTL
├── Real-Time Stream: Push critical updates (new orders, stock alerts)
└── User Interface: Show cached data + real-time overlays
```

## Multi-Tenant Cache Strategy

### Tenant Isolation
**Cache Key Patterns:**
```
product:{tenantId}:{productId}
products:{tenantId}:category:{categoryId}:page:{page}
user:{tenantId}:{userId}:profile
reports:{tenantId}:daily:{date}
```

### Cross-Tenant Data
**Marketplace Public Data:**
```
marketplace:products:search:{query}:{location}
marketplace:shops:nearby:{lat}:{lng}:{radius}
public:categories:hierarchy
```

**Benefits:**
- Prevents data leakage between tenants
- Allows selective invalidation per tenant
- Enables shared caching for public marketplace data

## Advanced Invalidation Strategies

### 1. Dependency-Based Invalidation

**Dependency Mapping:**
```yaml
product_update_triggers:
  - cache_keys:
    - "product:{productId}"
    - "products:{tenantId}:*"
    - "search:*:{productId}"
    - "marketplace:search:*"
    - "reports:{tenantId}:product-popularity:*"

category_update_triggers:
  - cache_keys:
    - "category:{categoryId}:*"
    - "products:{tenantId}:category:{categoryId}:*"
    - "marketplace:categories:*"
```

### 2. Gradual Cache Warming

**Strategy for High-Traffic Data:**
```
1. Detect cache miss on popular endpoint
2. Trigger background job to rebuild cache
3. Serve stale data temporarily (if available)
4. Update cache asynchronously
5. Notify other instances of new cache data
```

### 3. Cache Versioning

**For Complex Dependencies:**
```
Cache Key Format: {base_key}:v{version}:{timestamp}
Example: products:tenant123:v2:1695196800

Version Increment Triggers:
- Major schema changes
- Bulk data updates
- Configuration changes affecting display
```

## Real-Time Update Handling

### WebSocket Implementation for Critical Data

#### Stock Level Updates
```javascript
// Server-side event emission
socket.to(`product:${productId}`).emit('stockUpdate', {
  productId,
  newStock: updatedStock,
  timestamp: Date.now()
});

// Client-side handling
socket.on('stockUpdate', (data) => {
  updateProductStock(data.productId, data.newStock);
  showStockAlert(data.newStock);
});
```

#### Order Status Updates
```javascript
// Real-time order tracking
socket.to(`order:${orderId}`).emit('statusUpdate', {
  orderId,
  status: 'shipped',
  trackingNumber: 'TRK123456',
  estimatedDelivery: '2024-09-22'
});
```

### Server-Sent Events (SSE) for Dashboard

#### Live Dashboard Metrics
```javascript
// Dashboard metrics stream
app.get('/api/dashboard/live-stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive'
  });

  const interval = setInterval(() => {
    const metrics = getCurrentMetrics(req.tenantId);
    res.write(`data: ${JSON.stringify(metrics)}\n\n`);
  }, 30000); // Update every 30 seconds

  req.on('close', () => clearInterval(interval));
});
```

## Cache Consistency Strategies

### 1. Write-Through Caching
**For Critical Data:**
- Write to database first
- Update cache immediately
- Ensures consistency but higher latency

### 2. Write-Behind Caching
**For High-Performance Scenarios:**
- Write to cache first
- Asynchronous database update
- Higher performance but eventual consistency

### 3. Cache-Aside Pattern
**For Flexible Scenarios:**
- Application manages cache explicitly
- Check cache first, fallback to database
- Update cache after database writes

## Monitoring and Alerting

### Key Metrics to Track

#### Cache Performance
- Hit/Miss ratios by endpoint
- Average response times (cached vs uncached)
- Cache memory usage and eviction rates
- Invalidation frequency and patterns

#### Real-Time Performance
- WebSocket connection counts and stability
- Message delivery latency
- Real-time update success rates
- Dashboard refresh frequencies

### Alerting Thresholds
```yaml
cache_hit_ratio_low:
  threshold: < 70%
  severity: warning
  endpoints: [products, users, categories]

cache_invalidation_storm:
  threshold: > 1000 invalidations/minute
  severity: critical
  action: investigate_bulk_updates

realtime_connection_drops:
  threshold: > 10% connection drop rate
  severity: critical
  action: check_websocket_health
```

## Implementation Recommendations

### Phase 1: Foundation (Week 1-2)
1. Implement basic TTL caching for product catalog
2. Set up Redis cluster with tenant isolation
3. Configure CloudFront CDN with appropriate cache policies
4. Basic event-driven invalidation for product updates

### Phase 2: Real-Time Integration (Week 3-4)
1. WebSocket infrastructure for stock level updates
2. SSE implementation for dashboard metrics
3. Hybrid caching strategy for frequently accessed data
4. Advanced invalidation patterns

### Phase 3: Optimization (Week 5-6)
1. Cache warming strategies
2. Performance monitoring and tuning
3. Advanced dependency tracking
4. Cost optimization based on usage patterns

### Technology Stack Recommendations
- **Cache Storage:** Redis Cluster (ElastiCache)
- **CDN:** CloudFront with custom cache policies
- **Real-Time:** Socket.io + Redis adapter for scaling
- **Event System:** AWS EventBridge + Lambda
- **Monitoring:** CloudWatch + custom dashboards