# Database Performance Analysis: Most Frequent Queries

## Overview
Analysis of the most frequent queries in the shop management system and their estimated performance based on the current PostgreSQL schema design with proper indexing.

## Performance Assumptions
- **Database**: PostgreSQL 14+ with proper maintenance
- **Hardware**: Modern SSD storage, 16GB RAM, 4-core CPU
- **Data Volume**: 
  - 1,000 tenants
  - 10,000 shops
  - 100,000 products
  - 1,000,000 orders
  - 5,000,000 order_items
  - 10,000,000 inventory_transactions

## Top 20 Most Frequent Queries & Performance Analysis

### 1. **Product Listing with Filters** (HIGH FREQUENCY)
```sql
-- Get products for a specific tenant/shop with filters
SELECT p.*, c.name as category_name
FROM products p
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.tenant_id = $1 
  AND p.is_active = true
  AND p.category_id = $2
  AND p.price BETWEEN $3 AND $4
ORDER BY p.name
LIMIT 50 OFFSET $5;
```
**Estimated Performance**: **2-5ms**
- ✅ Uses: `idx_products_tenant_id`, `idx_products_category_id`, `idx_products_is_active`, `idx_products_price`
- ✅ Covering index potential for tenant_id + is_active + category_id
- ⚠️ **CONCERN**: ORDER BY p.name not indexed - could be slow with large datasets

**Optimization Needed**:
```sql
CREATE INDEX idx_products_tenant_active_category_name 
ON products(tenant_id, is_active, category_id, name);
```

### 2. **Product Search** (HIGH FREQUENCY)
```sql
-- Full-text search across products
SELECT p.*, c.name as category_name,
       ts_rank(to_tsvector('english', p.name || ' ' || COALESCE(p.description, '')), 
                plainto_tsquery('english', $2)) as rank
FROM products p
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.tenant_id = $1 
  AND p.is_active = true
  AND to_tsvector('english', p.name || ' ' || COALESCE(p.description, '')) 
      @@ plainto_tsquery('english', $2)
ORDER BY rank DESC, p.name
LIMIT 20;
```
**Estimated Performance**: **5-15ms**
- ❌ **MAJOR CONCERN**: No full-text search index exists in current schema
- ❌ Function-based search will be very slow (100ms+)

**Critical Optimization Needed**:
```sql
-- Add tsvector column for search
ALTER TABLE products ADD COLUMN search_vector tsvector;
CREATE INDEX idx_products_search_vector ON products USING GIN(search_vector);
```

### 3. **Order Details Lookup** (HIGH FREQUENCY)
```sql
-- Get order with items for order management
SELECT o.*, oi.*, p.name as product_name
FROM orders o
LEFT JOIN order_items oi ON o.id = oi.order_id
LEFT JOIN products p ON oi.product_id = p.id
WHERE o.tenant_id = $1 AND o.id = $2;
```
**Estimated Performance**: **1-3ms**
- ✅ Uses: `idx_orders_tenant_id` (PRIMARY lookup)
- ✅ Uses: `idx_order_items_order_id`
- ✅ Excellent performance for single order lookup

### 4. **Shop Inventory Status** (HIGH FREQUENCY)
```sql
-- Get current stock levels for shop dashboard
SELECT p.id, p.name, p.sku, p.quantity_in_stock, p.low_stock_threshold,
       CASE 
         WHEN p.quantity_in_stock = 0 THEN 'OUT_OF_STOCK'
         WHEN p.quantity_in_stock <= p.low_stock_threshold THEN 'LOW_STOCK'
         ELSE 'IN_STOCK'
       END as stock_status
FROM products p
WHERE p.tenant_id = $1 
  AND p.is_active = true
  AND p.track_quantity = true
ORDER BY p.quantity_in_stock ASC, p.name;
```
**Estimated Performance**: **10-25ms**
- ⚠️ **CONCERN**: No index on track_quantity
- ⚠️ **CONCERN**: ORDER BY quantity_in_stock, name not optimized

**Optimization Needed**:
```sql
CREATE INDEX idx_products_inventory_status 
ON products(tenant_id, is_active, track_quantity, quantity_in_stock, name);
```

### 5. **Recent Orders Dashboard** (HIGH FREQUENCY)
```sql
-- Get recent orders for shop dashboard
SELECT o.id, o.order_number, o.customer_email, o.total_amount, 
       o.status, o.created_at
FROM orders o
WHERE o.tenant_id = $1 
  AND o.shop_id = $2
  AND o.created_at >= NOW() - INTERVAL '7 days'
ORDER BY o.created_at DESC
LIMIT 20;
```
**Estimated Performance**: **2-5ms**
- ✅ Uses: `idx_orders_tenant_id`, `idx_orders_shop_id`
- ✅ Good performance with proper composite index

### 6. **Low Stock Alerts** (MEDIUM FREQUENCY)
```sql
-- Get products with low stock for alerts
SELECT p.id, p.name, p.sku, p.quantity_in_stock, p.low_stock_threshold
FROM products p
WHERE p.tenant_id = $1
  AND p.is_active = true
  AND p.track_quantity = true
  AND p.quantity_in_stock <= p.low_stock_threshold;
```
**Estimated Performance**: **5-15ms**
- ❌ **CONCERN**: Uses `idx_products_low_stock` but may not be selective enough
- ⚠️ Complex WHERE clause with multiple conditions

**Current Index**: `idx_products_low_stock (tenant_id, quantity_in_stock, low_stock_threshold)`
**Status**: ✅ Adequate but could be improved

### 7. **Customer Order History** (MEDIUM FREQUENCY)
```sql
-- Get customer's order history
SELECT o.id, o.order_number, o.total_amount, o.status, o.created_at
FROM orders o
WHERE o.tenant_id = $1 
  AND o.customer_email = $2
ORDER BY o.created_at DESC
LIMIT 10;
```
**Estimated Performance**: **2-8ms**
- ✅ Uses: `idx_orders_customer_email`
- ✅ Good performance for email-based lookup

### 8. **Sales Analytics - Daily Summary** (MEDIUM FREQUENCY)
```sql
-- Get daily sales for analytics dashboard
SELECT DATE(o.created_at) as sale_date,
       COUNT(*) as order_count,
       SUM(o.total_amount) as total_revenue,
       AVG(o.total_amount) as avg_order_value
FROM orders o
WHERE o.tenant_id = $1 
  AND o.shop_id = $2
  AND o.status IN ('delivered', 'completed')
  AND o.created_at >= $3 
  AND o.created_at <= $4
GROUP BY DATE(o.created_at)
ORDER BY sale_date DESC;
```
**Estimated Performance**: **10-50ms**
- ⚠️ **CONCERN**: Aggregation query over potentially large dataset
- ⚠️ No specific index for analytics queries

**Optimization Needed**:
```sql
CREATE INDEX idx_orders_analytics 
ON orders(tenant_id, shop_id, status, created_at);
```

### 9. **Category Product Count** (MEDIUM FREQUENCY)
```sql
-- Get product counts per category for navigation
SELECT c.id, c.name, COUNT(p.id) as product_count
FROM categories c
LEFT JOIN products p ON c.id = p.category_id 
  AND p.is_active = true 
  AND p.tenant_id = $1
WHERE c.tenant_id = $1 
  AND c.is_active = true
GROUP BY c.id, c.name
ORDER BY c.sort_order, c.name;
```
**Estimated Performance**: **5-15ms**
- ✅ Uses existing indexes effectively
- ✅ Good performance for category navigation

### 10. **Product Variant Lookup** (MEDIUM FREQUENCY)
```sql
-- Get product with variants for detail page
SELECT p.*, pv.id as variant_id, pv.sku as variant_sku, 
       pv.price as variant_price, pv.quantity_in_stock as variant_stock
FROM products p
LEFT JOIN product_variants pv ON p.id = pv.product_id
WHERE p.tenant_id = $1 
  AND p.slug = $2 
  AND p.is_active = true;
```
**Estimated Performance**: **1-3ms**
- ✅ Uses: `unique_tenant_slug` index
- ✅ Excellent performance for product detail pages

## Performance Issues Identified

### 🚨 **Critical Issues**
1. **No Full-Text Search Index**: Product search will be extremely slow (100ms+)
2. **Missing Covering Indexes**: Many queries require index-only scans
3. **Analytics Queries Not Optimized**: Aggregation queries may be slow

### ⚠️ **Moderate Issues**
1. **Order By Clauses**: Many sorts not supported by indexes
2. **Complex WHERE Clauses**: Some multi-condition queries not optimized
3. **Missing Composite Indexes**: Several query patterns need specific indexes

### ✅ **Well Optimized**
1. **Single Record Lookups**: Primary key and unique constraints work well
2. **Basic Foreign Key Navigation**: Existing indexes support these well
3. **Tenant Isolation**: All queries properly scoped to tenant_id

## Recommended Index Optimizations

### **Immediate Priority (Critical)**
```sql
-- Full-text search optimization
ALTER TABLE products ADD COLUMN search_vector tsvector;
CREATE INDEX idx_products_search_vector ON products USING GIN(search_vector);

-- Trigger to maintain search vector
CREATE OR REPLACE FUNCTION update_product_search_vector()
RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    to_tsvector('english', COALESCE(NEW.name, '') || ' ' || 
                          COALESCE(NEW.description, '') || ' ' ||
                          COALESCE(NEW.sku, ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_product_search_vector_trigger
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION update_product_search_vector();
```

### **High Priority**
```sql
-- Product listing optimization
CREATE INDEX idx_products_tenant_active_category_name 
ON products(tenant_id, is_active, category_id, name);

-- Inventory status optimization
CREATE INDEX idx_products_inventory_status 
ON products(tenant_id, is_active, track_quantity, quantity_in_stock, name);

-- Analytics optimization
CREATE INDEX idx_orders_analytics 
ON orders(tenant_id, shop_id, status, created_at);
```

### **Medium Priority**
```sql
-- Order date range queries
CREATE INDEX idx_orders_date_range 
ON orders(tenant_id, created_at, status);

-- Product pricing queries
CREATE INDEX idx_products_price_range 
ON products(tenant_id, is_active, price);
```

## Expected Performance After Optimization

| Query Type | Current | After Optimization |
|------------|---------|-------------------|
| Product Search | 100ms+ | 5-15ms |
| Product Listing | 5-10ms | 2-5ms |
| Inventory Status | 25ms | 8-12ms |
| Order Analytics | 50ms+ | 15-30ms |
| Single Lookups | 1-3ms | 1-3ms ✅ |

## Monitoring Recommendations

1. **Enable Query Logging**: Log queries > 10ms
2. **Use pg_stat_statements**: Track query performance
3. **Monitor Index Usage**: Ensure new indexes are being used
4. **Regular EXPLAIN ANALYZE**: Validate query plans
5. **Connection Pooling**: Use PgBouncer for connection management

## Scaling Considerations

For larger datasets (10M+ products, 100M+ orders):
1. **Partitioning**: Partition orders and analytics tables by date
2. **Read Replicas**: Use read replicas for analytics queries
3. **Materialized Views**: Pre-compute common aggregations
4. **Caching**: Implement Redis for frequently accessed data