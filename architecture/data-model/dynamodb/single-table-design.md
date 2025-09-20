# DynamoDB Single Table Design

## Table Structure

### Main Table: `shop_management`

| Attribute | Type | Description |
|-----------|------|-------------|
| **PK** | String | Partition Key - Primary identifier |
| **SK** | String | Sort Key - Secondary identifier/timestamp |
| **GSI1PK** | String | Global Secondary Index 1 Partition Key |
| **GSI1SK** | String | Global Secondary Index 1 Sort Key |
| **GSI2PK** | String | Global Secondary Index 2 Partition Key |
| **GSI2SK** | String | Global Secondary Index 2 Sort Key |
| **GSI3PK** | String | Global Secondary Index 3 Partition Key |
| **GSI3SK** | String | Global Secondary Index 3 Sort Key |
| **GSI4PK** | String | Global Secondary Index 4 Partition Key |
| **GSI4SK** | String | Global Secondary Index 4 Sort Key |
| **entity_type** | String | Type of entity (TENANT, USER, PRODUCT, etc.) |
| **data** | Map | Entity-specific attributes |
| **created_at** | String | ISO timestamp |
| **updated_at** | String | ISO timestamp |
| **ttl** | Number | TTL for temporary records |

## Global Secondary Indexes

### GSI1: Time-based Queries (created_at sorting)
- **GSI1PK**: `TENANT#{tenant_id}#{entity_type}`
- **GSI1SK**: `{reverse_timestamp}#{entity_id}`
- **Use Cases**: Recent orders, newest products, user activity

### GSI2: Search and Filtering
- **GSI2PK**: `TENANT#{tenant_id}#{category}#{status}`
- **GSI2SK**: `{searchable_field}#{entity_id}`
- **Use Cases**: Product search, category filtering, status filtering

### GSI3: User and Email Lookups
- **GSI3PK**: `EMAIL#{email}` or `USER#{user_id}`
- **GSI3SK**: `TENANT#{tenant_id}`
- **Use Cases**: User authentication, customer lookups

### GSI4: Analytics and Aggregation
- **GSI4PK**: `ANALYTICS#{tenant_id}#{date_period}`
- **GSI4SK**: `{metric_type}#{value}`
- **Use Cases**: Sales by date, top products, inventory levels

## Entity Patterns

### 1. Tenant
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "METADATA",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#TENANT",
  "GSI1SK": "9999999999999#01234567-89ab-cdef-0123-456789abcdef",
  "entity_type": "TENANT",
  "data": {
    "name": "Acme Electronics Store",
    "slug": "acme-electronics",
    "domain": "acme.shop.com",
    "status": "active",
    "subscription_plan": "premium",
    "settings": {}
  },
  "created_at": "2024-01-01T00:00:00Z"
}
```

### 2. User
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "USER#11111111-2222-3333-4444-555555555555",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#USER",
  "GSI1SK": "9999999999999#11111111-2222-3333-4444-555555555555",
  "GSI3PK": "EMAIL#john.doe@example.com",
  "GSI3SK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "entity_type": "USER",
  "data": {
    "email": "john.doe@example.com",
    "name": "John Doe",
    "role": "admin",
    "status": "active",
    "cognito_sub": "us-east-1:12345678-1234-1234-1234-123456789012",
    "phone": "+1-555-123-4567"
  },
  "created_at": "2024-01-01T10:00:00Z"
}
```

### 3. Category
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "CATEGORY#22222222-3333-4444-5555-666666666666",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#CATEGORY",
  "GSI1SK": "9999999999999#22222222-3333-4444-5555-666666666666",
  "GSI2PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#CATEGORY#active",
  "GSI2SK": "electronics#22222222-3333-4444-5555-666666666666",
  "entity_type": "CATEGORY",
  "data": {
    "name": "Electronics",
    "slug": "electronics",
    "description": "Electronic devices and accessories",
    "parent_id": null,
    "sort_order": 1,
    "is_active": true
  },
  "created_at": "2024-01-01T12:00:00Z"
}
```

### 4. Product
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "PRODUCT#33333333-4444-5555-6666-777777777777",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#PRODUCT",
  "GSI1SK": "1704067200#33333333-4444-5555-6666-777777777777",
  "GSI2PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#22222222-3333-4444-5555-666666666666#active",
  "GSI2SK": "wireless headphones#33333333-4444-5555-6666-777777777777",
  "GSI4PK": "ANALYTICS#01234567-89ab-cdef-0123-456789abcdef#STOCK",
  "GSI4SK": "LOW#0005#33333333-4444-5555-6666-777777777777",
  "entity_type": "PRODUCT",
  "data": {
    "name": "Wireless Bluetooth Headphones",
    "slug": "wireless-bluetooth-headphones",
    "sku": "WBH-001",
    "description": "High-quality wireless headphones with noise cancellation",
    "category_id": "22222222-3333-4444-5555-666666666666",
    "price": 299.99,
    "cost": 150.00,
    "currency": "USD",
    "stock_quantity": 5,
    "min_stock_level": 10,
    "max_stock_level": 100,
    "is_active": true,
    "is_featured": true,
    "in_stock": true,
    "allow_backorder": false,
    "tags": ["wireless", "bluetooth", "headphones", "audio"],
    "attributes": {
      "color": "Black",
      "brand": "TechBrand",
      "model": "TB-WH-2024"
    },
    "images": [
      "https://images.example.com/wbh-001-1.jpg",
      "https://images.example.com/wbh-001-2.jpg"
    ]
  },
  "created_at": "2024-01-01T15:00:00Z"
}
```

### 5. Order
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "ORDER#44444444-5555-6666-7777-888888888888",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#ORDER",
  "GSI1SK": "1704067200#44444444-5555-6666-7777-888888888888",
  "GSI3PK": "EMAIL#customer@example.com",
  "GSI3SK": "ORDER#1704067200#44444444-5555-6666-7777-888888888888",
  "GSI4PK": "ANALYTICS#01234567-89ab-cdef-0123-456789abcdef#2024-01-01",
  "GSI4SK": "SALES#299.99#44444444-5555-6666-7777-888888888888",
  "entity_type": "ORDER",
  "data": {
    "order_number": "ORD-2024-001",
    "customer_email": "customer@example.com",
    "customer_name": "Jane Smith",
    "customer_phone": "+1-555-987-6543",
    "status": "confirmed",
    "payment_status": "completed",
    "order_type": "sale",
    "subtotal": 299.99,
    "tax_amount": 24.00,
    "discount_amount": 0.00,
    "shipping_amount": 9.99,
    "total_amount": 333.98,
    "currency": "USD",
    "delivery_method": "shipping",
    "delivery_address": {
      "street": "123 Main St",
      "city": "New York",
      "state": "NY",
      "zip": "10001",
      "country": "US"
    },
    "notes": "Leave at front door",
    "metadata": {}
  },
  "created_at": "2024-01-01T16:00:00Z"
}
```

### 6. Order Item
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "ORDER#44444444-5555-6666-7777-888888888888#ITEM#001",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#ORDER_ITEM",
  "GSI1SK": "1704067200#44444444-5555-6666-7777-888888888888#001",
  "GSI4PK": "PRODUCT#33333333-4444-5555-6666-777777777777",
  "GSI4SK": "SOLD#2024-01-01#1",
  "entity_type": "ORDER_ITEM",
  "data": {
    "order_id": "44444444-5555-6666-7777-888888888888",
    "product_id": "33333333-4444-5555-6666-777777777777",
    "product_name": "Wireless Bluetooth Headphones",
    "product_sku": "WBH-001",
    "quantity": 1,
    "unit_price": 299.99,
    "total_price": 299.99,
    "currency": "USD"
  },
  "created_at": "2024-01-01T16:00:00Z"
}
```

### 7. Payment
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "ORDER#44444444-5555-6666-7777-888888888888#PAYMENT#001",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#PAYMENT",
  "GSI1SK": "1704067200#55555555-6666-7777-8888-999999999999",
  "entity_type": "PAYMENT",
  "data": {
    "order_id": "44444444-5555-6666-7777-888888888888",
    "amount": 333.98,
    "currency": "USD",
    "status": "completed",
    "payment_method": "card",
    "payment_gateway": "stripe",
    "transaction_id": "pi_1234567890",
    "reference_number": "PAY-2024-001"
  },
  "created_at": "2024-01-01T16:05:00Z"
}
```

### 8. Inventory Transaction
```json
{
  "PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef",
  "SK": "PRODUCT#33333333-4444-5555-6666-777777777777#INVENTORY#1704067200001",
  "GSI1PK": "TENANT#01234567-89ab-cdef-0123-456789abcdef#INVENTORY",
  "GSI1SK": "1704067200#66666666-7777-8888-9999-aaaaaaaaaaaa",
  "entity_type": "INVENTORY_TRANSACTION",
  "data": {
    "product_id": "33333333-4444-5555-6666-777777777777",
    "transaction_type": "stock_out",
    "quantity": -1,
    "previous_quantity": 6,
    "new_quantity": 5,
    "unit_cost": 150.00,
    "total_cost": -150.00,
    "reference_number": "ORD-2024-001",
    "notes": "Order fulfillment"
  },
  "created_at": "2024-01-01T16:00:00Z"
}
```

## Query Examples for Each Access Pattern

### AP1: Get Product Details by ID
```javascript
// Direct item lookup - fastest possible query
const params = {
  TableName: 'shop_management',
  Key: {
    PK: 'TENANT#01234567-89ab-cdef-0123-456789abcdef',
    SK: 'PRODUCT#33333333-4444-5555-6666-777777777777'
  }
};
// Performance: ~1ms, Cost: 0.5 RCU
```

### AP2: List Products by Tenant (with filters)
```javascript
// GSI2 Query with filter expression
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI2-index',
  KeyConditionExpression: 'GSI2PK = :pk',
  FilterExpression: '#data.#price BETWEEN :min_price AND :max_price',
  ExpressionAttributeNames: {
    '#data': 'data',
    '#price': 'price'
  },
  ExpressionAttributeValues: {
    ':pk': 'TENANT#01234567-89ab-cdef-0123-456789abcdef#22222222-3333-4444-5555-666666666666#active',
    ':min_price': 100,
    ':max_price': 500
  },
  Limit: 50
};
// Performance: ~3-5ms, Cost: 2-5 RCU
```

### AP3: Product Search by Name/Description
```javascript
// GSI2 Query with begins_with for prefix search
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI2-index',
  KeyConditionExpression: 'GSI2PK = :pk AND begins_with(GSI2SK, :search_term)',
  ExpressionAttributeValues: {
    ':pk': 'TENANT#01234567-89ab-cdef-0123-456789abcdef#SEARCH#active',
    ':search_term': 'wireless'
  },
  Limit: 20
};
// Performance: ~2-4ms, Cost: 1-3 RCU
// Note: For full-text search, integrate with Amazon OpenSearch
```

### AP4: Get Order Details with Items
```javascript
// Query all items with same PK and SK prefix
const params = {
  TableName: 'shop_management',
  KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
  ExpressionAttributeValues: {
    ':pk': 'TENANT#01234567-89ab-cdef-0123-456789abcdef',
    ':sk': 'ORDER#44444444-5555-6666-7777-888888888888'
  }
};
// Returns: Order + OrderItems + Payments in single query
// Performance: ~2-3ms, Cost: 1-2 RCU
```

### AP5: List Recent Orders by Tenant
```javascript
// GSI1 Query with reverse timestamp sorting
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI1-index',
  KeyConditionExpression: 'GSI1PK = :pk',
  ExpressionAttributeValues: {
    ':pk': 'TENANT#01234567-89ab-cdef-0123-456789abcdef#ORDER'
  },
  ScanIndexForward: true, // GSI1SK has reverse timestamp
  Limit: 20
};
// Performance: ~3-5ms, Cost: 1-3 RCU
```

### AP6: Get User Profile with Permissions
```javascript
// GSI3 Query by email
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI3-index',
  KeyConditionExpression: 'GSI3PK = :email AND GSI3SK = :tenant',
  ExpressionAttributeValues: {
    ':email': 'EMAIL#john.doe@example.com',
    ':tenant': 'TENANT#01234567-89ab-cdef-0123-456789abcdef'
  }
};
// Performance: ~2-3ms, Cost: 1 RCU
```

### AP7: Inventory Status by Product (Low Stock Alerts)
```javascript
// GSI4 Query for analytics/stock levels
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI4-index',
  KeyConditionExpression: 'GSI4PK = :pk AND begins_with(GSI4SK, :status)',
  ExpressionAttributeValues: {
    ':pk': 'ANALYTICS#01234567-89ab-cdef-0123-456789abcdef#STOCK',
    ':status': 'LOW#'
  }
};
// Performance: ~3-5ms, Cost: 1-3 RCU
```

### AP8: Customer Order History
```javascript
// GSI3 Query by customer email
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI3-index',
  KeyConditionExpression: 'GSI3PK = :email AND begins_with(GSI3SK, :prefix)',
  ExpressionAttributeValues: {
    ':email': 'EMAIL#customer@example.com',
    ':prefix': 'ORDER#'
  },
  ScanIndexForward: false // Latest first
};
// Performance: ~2-4ms, Cost: 1-2 RCU
```

### AP11: Sales Analytics by Date Range
```javascript
// GSI4 Query with date range
const params = {
  TableName: 'shop_management',
  IndexName: 'GSI4-index',
  KeyConditionExpression: 'GSI4PK = :pk AND begins_with(GSI4SK, :sales)',
  FilterExpression: '#created_at BETWEEN :start_date AND :end_date',
  ExpressionAttributeNames: {
    '#created_at': 'created_at'
  },
  ExpressionAttributeValues: {
    ':pk': 'ANALYTICS#01234567-89ab-cdef-0123-456789abcdef#2024-01-01',
    ':sales': 'SALES#',
    ':start_date': '2024-01-01T00:00:00Z',
    ':end_date': '2024-01-31T23:59:59Z'
  }
};
// Performance: ~5-10ms, Cost: 3-8 RCU
// Note: Aggregation done in application layer
```

## Key Design Decisions

### 1. **Composite Partition Keys**
- All entities scoped by `TENANT#` for perfect multi-tenancy
- Hierarchical relationships maintained through SK structure
- Related entities co-located for single-query access

### 2. **Reverse Timestamp Strategy**
- GSI1SK uses `9999999999999 - timestamp` for latest-first sorting
- Enables efficient "recent items" queries
- Consistent with DynamoDB best practices

### 3. **Denormalization Strategy**
- Product names/SKUs duplicated in order items for fast display
- Category information embedded where frequently accessed
- Trade-off: Storage for read performance

### 4. **Search Optimization**
- GSI2SK includes searchable terms for prefix matching
- Full-text search requires Amazon OpenSearch integration
- Balanced approach between cost and functionality

### 5. **Analytics Support**
- GSI4 designed for aggregation queries
- Date-based partitioning for time-series data
- Application-level aggregation for complex metrics

## Scaling Considerations

### Write Patterns
- Partition key distribution ensures even write load
- Hot partitions avoided through UUID distribution
- Time-based keys spread across partitions

### Read Patterns
- Most queries use KeyConditionExpression (efficient)
- Minimal FilterExpression usage to reduce costs
- Consistent reads only where necessary

### Storage Efficiency
- Strategic denormalization balances storage vs. query performance
- TTL used for temporary/cache-like records
- Compressed JSON for complex attributes

This single table design efficiently handles all identified access patterns while maintaining strong consistency, optimal performance, and cost-effectiveness.