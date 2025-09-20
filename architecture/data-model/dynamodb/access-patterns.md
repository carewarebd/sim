# DynamoDB Single Table Design - Access Patterns Analysis

## Overview
This document analyzes all access patterns from the PostgreSQL shop management system to design an optimal DynamoDB single table structure.

## Entity Relationship Analysis from PostgreSQL Schema

### Core Entities:
1. **Tenants** - SaaS tenants (shops/organizations)
2. **Users** - System users with roles
3. **Shops** - Physical/virtual store locations
4. **Categories** - Hierarchical product categories
5. **Products** - Product catalog with variants
6. **Orders** - Customer orders and transactions
7. **Order Items** - Individual line items in orders
8. **Payments** - Payment transactions
9. **Inventory Transactions** - Stock movement audit trail
10. **Customers** - Customer profiles
11. **Notifications** - System notifications

## Access Patterns Analysis (Priority Order)

### 🔥 **CRITICAL - High Frequency (100+ req/min)**

#### AP1: Get Product Details by ID
**Use Case**: Product detail pages, inventory lookups
**Query**: `SELECT * FROM products WHERE tenant_id = ? AND id = ?`
**Frequency**: 200+ req/min
**DynamoDB Pattern**: Direct item lookup

#### AP2: List Products by Tenant (with filters)
**Use Case**: Product catalog, shop inventory dashboard
**Query**: `SELECT * FROM products WHERE tenant_id = ? AND is_active = true AND category_id = ? ORDER BY name LIMIT 50`
**Frequency**: 150+ req/min
**DynamoDB Pattern**: Query with GSI

#### AP3: Product Search by Name/Description
**Use Case**: Search functionality, autocomplete
**Query**: `SELECT * FROM products WHERE tenant_id = ? AND (name ILIKE '%?%' OR description ILIKE '%?%')`
**Frequency**: 100+ req/min
**DynamoDB Pattern**: GSI query with begins_with or full-text search integration

#### AP4: Get Order Details with Items
**Use Case**: Order management, customer service
**Query**: `SELECT o.*, oi.* FROM orders o LEFT JOIN order_items oi ON o.id = oi.order_id WHERE o.tenant_id = ? AND o.id = ?`
**Frequency**: 120+ req/min
**DynamoDB Pattern**: Query with SK prefix

#### AP5: List Recent Orders by Tenant
**Use Case**: Dashboard, order management
**Query**: `SELECT * FROM orders WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 20`
**Frequency**: 80+ req/min
**DynamoDB Pattern**: GSI query with reverse timestamp

### 🚨 **HIGH - Medium-High Frequency (50-100 req/min)**

#### AP6: Get User Profile with Permissions
**Use Case**: Authentication, authorization
**Query**: `SELECT * FROM users WHERE tenant_id = ? AND email = ?`
**Frequency**: 80+ req/min
**DynamoDB Pattern**: GSI query

#### AP7: Inventory Status by Product
**Use Case**: Stock management, low stock alerts
**Query**: `SELECT * FROM products WHERE tenant_id = ? AND stock_quantity <= min_stock_level`
**Frequency**: 60+ req/min
**DynamoDB Pattern**: GSI with filter expression

#### AP8: Customer Order History
**Use Case**: Customer service, order tracking
**Query**: `SELECT * FROM orders WHERE tenant_id = ? AND customer_email = ? ORDER BY created_at DESC`
**Frequency**: 50+ req/min
**DynamoDB Pattern**: GSI query

#### AP9: Shop Product Catalog
**Use Case**: Shop-specific inventory
**Query**: `SELECT * FROM products WHERE tenant_id = ? AND shop_id = ? AND is_active = true`
**Frequency**: 70+ req/min
**DynamoDB Pattern**: GSI query

#### AP10: Category Hierarchy Navigation
**Use Case**: Navigation menus, category browsing
**Query**: `SELECT * FROM categories WHERE tenant_id = ? AND parent_id = ? ORDER BY sort_order`
**Frequency**: 40+ req/min
**DynamoDB Pattern**: Query with SK prefix

### ⚠️ **MEDIUM - Regular Access (10-50 req/min)**

#### AP11: Sales Analytics by Date Range
**Use Case**: Dashboard analytics, reports
**Query**: `SELECT DATE(created_at), SUM(total_amount) FROM orders WHERE tenant_id = ? AND created_at BETWEEN ? AND ? GROUP BY DATE(created_at)`
**Frequency**: 20+ req/min
**DynamoDB Pattern**: GSI query with aggregation in application

#### AP12: Top Selling Products
**Use Case**: Analytics dashboard, inventory planning
**Query**: `SELECT p.name, SUM(oi.quantity) FROM products p JOIN order_items oi ON p.id = oi.product_id WHERE p.tenant_id = ? GROUP BY p.id ORDER BY SUM(oi.quantity) DESC`
**Frequency**: 15+ req/min
**DynamoDB Pattern**: Complex query requiring application-level aggregation

#### AP13: Payment Transaction Lookup
**Use Case**: Financial reconciliation, refunds
**Query**: `SELECT * FROM payments WHERE tenant_id = ? AND order_id = ?`
**Frequency**: 30+ req/min
**DynamoDB Pattern**: Query with SK prefix

#### AP14: Inventory Transaction History
**Use Case**: Audit trail, stock movement tracking
**Query**: `SELECT * FROM inventory_transactions WHERE tenant_id = ? AND product_id = ? ORDER BY created_at DESC`
**Frequency**: 25+ req/min
**DynamoDB Pattern**: Query with SK prefix

#### AP15: User Management by Tenant
**Use Case**: Admin user management
**Query**: `SELECT * FROM users WHERE tenant_id = ? AND role = ? AND status = 'active'`
**Frequency**: 10+ req/min
**DynamoDB Pattern**: GSI query with filter expression

### 📊 **LOW - Occasional Access (< 10 req/min)**

#### AP16: Tenant Configuration Lookup
**Use Case**: System configuration, feature flags
**Query**: `SELECT * FROM tenants WHERE id = ?`
**Frequency**: 5+ req/min
**DynamoDB Pattern**: Direct item lookup

#### AP17: Customer Profile Management
**Use Case**: Customer management, marketing
**Query**: `SELECT * FROM customers WHERE tenant_id = ? AND email = ?`
**Frequency**: 8+ req/min
**DynamoDB Pattern**: GSI query

#### AP18: Notification Management
**Use Case**: Alert system, user notifications
**Query**: `SELECT * FROM notifications WHERE tenant_id = ? AND user_id = ? AND is_read = false ORDER BY created_at DESC`
**Frequency**: 12+ req/min
**DynamoDB Pattern**: GSI query

## Summary Statistics

- **Total Access Patterns**: 18
- **Critical (>100 req/min)**: 5 patterns (28%)
- **High (50-100 req/min)**: 5 patterns (28%) 
- **Medium (10-50 req/min)**: 6 patterns (33%)
- **Low (<10 req/min)**: 2 patterns (11%)

## Key Design Considerations

1. **Multi-tenancy**: All patterns start with tenant_id - perfect for partition key
2. **Hierarchical Data**: Products->Categories, Orders->OrderItems require composite keys
3. **Time-based Queries**: Many patterns need created_at sorting - requires GSI
4. **Search Patterns**: Product search needs special handling (ElasticSearch integration?)
5. **Analytics**: Several aggregation patterns need application-level processing
6. **User Management**: Email-based lookups need GSI
7. **Real-time Data**: Inventory and order status need consistent reads

## Next Steps

Based on this analysis, the single table design will need:
- **1 Main Table** with composite PK/SK structure
- **4-5 Global Secondary Indexes** for different access patterns
- **Strategic denormalization** for frequently accessed related data
- **Application-level aggregation** for complex analytics
- **Potential ElasticSearch integration** for full-text search