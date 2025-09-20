# Real-Time Updates Handling

## Overview
This document addresses the critical challenge of balancing aggressive caching strategies with real-time update requirements for dashboards, inventory management, and live business operations.

## The Real-Time vs Caching Challenge

### Core Problem Statement
**Conflicting Requirements:**
- **Caching Goal:** Reduce database load, improve response times, lower costs
- **Real-Time Goal:** Provide immediate updates for stock levels, order status, and dashboard metrics
- **Business Impact:** Stale cache data can lead to overselling, poor customer experience, and incorrect business decisions

### Critical Real-Time Data Categories

#### 1. Inventory Management
**Why Real-Time is Critical:**
- Prevent overselling of products
- Accurate stock displays across multiple channels
- Real-time stock alerts for low inventory
- Coordination across multiple shops/warehouses

**Current Challenges with Caching:**
- Stock levels change with every sale/return
- Cache invalidation storms during peak sales
- Race conditions between cache updates and sales

#### 2. Order Processing
**Why Real-Time is Critical:**
- Order status updates during fulfillment
- Payment processing confirmations
- Shipping status and tracking updates
- Customer expectations for immediate feedback

#### 3. Dashboard Analytics
**Why Real-Time is Critical:**
- Business owners need current sales metrics
- Performance tracking for staff
- Real-time alerts for business anomalies
- Decision-making based on current data

## Solution Architecture

### 1. Hybrid Data Architecture Pattern

#### Separation of Concerns
```
┌─────────────────────────────────────────────────┐
│                CACHED LAYER                     │
│  (Static/Semi-Static Product Information)       │
├─────────────────────────────────────────────────┤
│ • Product descriptions, images, specifications  │
│ • Base pricing and categories                   │
│ • Reviews and ratings                          │
│ • Seller information                           │
│ • Product variants and options                 │
└─────────────────────────────────────────────────┘
                      +
┌─────────────────────────────────────────────────┐
│              REAL-TIME LAYER                    │
│         (Dynamic Business Data)                 │
├─────────────────────────────────────────────────┤
│ • Current stock levels                         │
│ • Live pricing updates                         │
│ • Order status changes                         │
│ • Payment processing status                    │
│ • Real-time analytics metrics                 │
└─────────────────────────────────────────────────┘
```

#### Implementation Strategy
```javascript
// Frontend: Hybrid data loading
class ProductService {
  async getProduct(productId) {
    // 1. Load cached base product data
    const productBase = await this.getCachedProduct(productId);
    
    // 2. Establish real-time connection for dynamic data
    const liveConnection = this.connectToLiveData(productId);
    
    // 3. Merge cached and live data
    return {
      ...productBase,
      stock: liveConnection.currentStock,
      pricing: liveConnection.currentPricing,
      availability: liveConnection.availability
    };
  }
  
  connectToLiveData(productId) {
    const socket = io('/product-updates');
    socket.emit('subscribe', { productId });
    
    return {
      currentStock: null,
      currentPricing: null,
      availability: 'unknown',
      
      onStockUpdate: (callback) => {
        socket.on(`stock:${productId}`, callback);
      },
      
      onPriceUpdate: (callback) => {
        socket.on(`price:${productId}`, callback);
      }
    };
  }
}
```

### 2. Event-Driven Real-Time Updates

#### WebSocket Architecture
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Database      │    │   Application    │    │    Frontend     │
│   Changes       │───▶│   Server         │───▶│   Real-Time     │
│                 │    │                  │    │   Updates       │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ • Stock Updates │    │ • Event Handler  │    │ • Socket.io     │
│ • Order Status  │    │ • Data Processor │    │ • UI Updates    │
│ • Price Changes │    │ • WebSocket Hub  │    │ • Notifications │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

#### Real-Time Event Implementation
```javascript
// Server-side: Real-time event handlers
class RealTimeUpdateService {
  constructor() {
    this.io = require('socket.io')(server);
    this.setupEventHandlers();
  }
  
  setupEventHandlers() {
    // Database change listeners
    this.db.on('stockUpdate', this.handleStockUpdate.bind(this));
    this.db.on('orderStatusChange', this.handleOrderUpdate.bind(this));
    this.db.on('priceChange', this.handlePriceUpdate.bind(this));
  }
  
  async handleStockUpdate(event) {
    const { productId, newStock, tenantId } = event;
    
    // Emit to all connected clients watching this product
    this.io.to(`product:${productId}`).emit('stockUpdate', {
      productId,
      stock: newStock,
      availability: newStock > 0 ? 'available' : 'out_of_stock',
      timestamp: Date.now()
    });
    
    // Also emit to tenant dashboard
    this.io.to(`tenant:${tenantId}:dashboard`).emit('inventoryAlert', {
      productId,
      stock: newStock,
      alert: newStock <= 5 ? 'low_stock' : null
    });
  }
  
  async handleOrderUpdate(event) {
    const { orderId, status, customerId, tenantId } = event;
    
    // Customer-specific update
    this.io.to(`customer:${customerId}`).emit('orderUpdate', {
      orderId,
      status,
      timestamp: Date.now()
    });
    
    // Tenant dashboard update
    this.io.to(`tenant:${tenantId}:dashboard`).emit('newOrder', {
      orderId,
      status,
      timestamp: Date.now()
    });
  }
}
```

### 3. Smart Caching with Real-Time Overlays

#### Dashboard Analytics Strategy
```javascript
// Dashboard with hybrid cached + real-time data
class DashboardService {
  async getDashboardData(tenantId) {
    // 1. Get cached base metrics (updated every 5-15 minutes)
    const baseMetrics = await this.getCachedMetrics(tenantId);
    
    // 2. Get real-time delta updates since cache timestamp
    const realtimeUpdates = await this.getRealTimeDeltas(
      tenantId, 
      baseMetrics.lastUpdated
    );
    
    // 3. Merge cached data with real-time updates
    return this.mergeMetrics(baseMetrics, realtimeUpdates);
  }
  
  async getCachedMetrics(tenantId) {
    const cacheKey = `dashboard:${tenantId}:metrics`;
    let metrics = await redis.get(cacheKey);
    
    if (!metrics) {
      // Expensive aggregation query - run in background
      metrics = await this.computeFullMetrics(tenantId);
      await redis.setex(cacheKey, 900, JSON.stringify(metrics)); // 15 min
    } else {
      metrics = JSON.parse(metrics);
    }
    
    return metrics;
  }
  
  async getRealTimeDeltas(tenantId, since) {
    // Quick queries for data changed since last cache update
    const newOrders = await db.query(`
      SELECT COUNT(*), SUM(total_amount) 
      FROM orders 
      WHERE tenant_id = $1 AND created_at > $2
    `, [tenantId, since]);
    
    const stockAlerts = await db.query(`
      SELECT product_id, stock_level 
      FROM products 
      WHERE tenant_id = $1 AND stock_level <= low_stock_threshold 
      AND updated_at > $2
    `, [tenantId, since]);
    
    return {
      newOrdersCount: newOrders[0].count,
      newRevenue: newOrders[0].sum,
      stockAlerts: stockAlerts,
      timestamp: Date.now()
    };
  }
}
```

### 4. Optimistic UI Updates with Rollback

#### Stock Level Management
```javascript
// Frontend: Optimistic updates with rollback capability
class StockManager {
  async purchaseProduct(productId, quantity) {
    // 1. Optimistically update UI immediately
    this.updateUIStock(productId, -quantity);
    this.showPendingState(productId);
    
    try {
      // 2. Submit purchase request
      const result = await api.post('/orders', {
        productId,
        quantity
      });
      
      // 3. Confirm successful purchase
      this.confirmPurchase(productId, result);
      
    } catch (error) {
      // 4. Rollback on failure
      this.rollbackStockUpdate(productId, quantity);
      this.showErrorState(productId, error);
      
      // 5. Re-sync with server state
      await this.refreshProductStock(productId);
    }
  }
  
  updateUIStock(productId, deltaQuantity) {
    const currentStock = this.getCurrentDisplayedStock(productId);
    const newStock = Math.max(0, currentStock + deltaQuantity);
    
    this.setDisplayedStock(productId, newStock);
    this.updateAvailabilityIndicator(productId, newStock > 0);
  }
  
  async rollbackStockUpdate(productId, deltaQuantity) {
    // Reverse the optimistic update
    this.updateUIStock(productId, deltaQuantity);
    this.clearPendingState(productId);
  }
}
```

## Advanced Real-Time Patterns

### 1. Event Sourcing for Audit Trail

#### Order Status Tracking
```javascript
// Event sourcing pattern for order lifecycle
class OrderEventStore {
  async trackOrderStatusChange(orderId, newStatus, metadata) {
    const event = {
      eventId: uuid(),
      orderId,
      eventType: 'ORDER_STATUS_CHANGED',
      data: {
        previousStatus: metadata.previousStatus,
        newStatus,
        changedBy: metadata.userId,
        reason: metadata.reason,
        timestamp: Date.now()
      }
    };
    
    // 1. Store event in event store
    await this.appendEvent(event);
    
    // 2. Update read model (cached data)
    await this.updateOrderReadModel(orderId, newStatus);
    
    // 3. Emit real-time update
    this.emitOrderUpdate(orderId, event);
  }
  
  async getOrderHistory(orderId) {
    // Can be cached since historical events don't change
    const cacheKey = `order_history:${orderId}`;
    let history = await redis.get(cacheKey);
    
    if (!history) {
      history = await this.getEventsForOrder(orderId);
      await redis.setex(cacheKey, 3600, JSON.stringify(history)); // 1 hour
    }
    
    return JSON.parse(history);
  }
}
```

### 2. CQRS (Command Query Responsibility Segregation)

#### Separate Read and Write Models
```javascript
// Write Model - Optimized for commands (orders, stock updates)
class WriteModel {
  async processStockUpdate(productId, delta, reason) {
    // Direct database write
    const result = await db.query(`
      UPDATE products 
      SET stock_level = stock_level + $2,
          updated_at = NOW()
      WHERE id = $1
      RETURNING stock_level
    `, [productId, delta]);
    
    // Emit event for read model updates
    await this.eventBus.emit('stock.updated', {
      productId,
      newStock: result[0].stock_level,
      delta,
      reason,
      timestamp: Date.now()
    });
  }
}

// Read Model - Optimized for queries (dashboards, reports)
class ReadModel {
  async getProductWithStock(productId) {
    // Try cache first
    const cached = await this.getCachedProduct(productId);
    
    if (cached && this.isFreshEnough(cached)) {
      return cached;
    }
    
    // Fallback to optimized read query
    const product = await this.readOnlyDb.query(`
      SELECT p.*, c.name as category_name 
      FROM products_view p 
      JOIN categories c ON p.category_id = c.id 
      WHERE p.id = $1
    `, [productId]);
    
    // Cache for future reads
    await this.cacheProduct(productId, product[0]);
    
    return product[0];
  }
}
```

### 3. Server-Sent Events (SSE) for Dashboard

#### Live Dashboard Implementation
```javascript
// Server: SSE endpoint for live dashboard
app.get('/api/dashboard/:tenantId/live', authenticateToken, (req, res) => {
  const { tenantId } = req.params;
  
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*'
  });
  
  // Send initial cached data
  const sendCachedData = async () => {
    const cachedMetrics = await getCachedDashboardMetrics(tenantId);
    res.write(`data: ${JSON.stringify(cachedMetrics)}\n\n`);
  };
  
  sendCachedData();
  
  // Set up real-time updates
  const updateInterval = setInterval(async () => {
    const realtimeMetrics = await getRealTimeMetrics(tenantId);
    res.write(`data: ${JSON.stringify(realtimeMetrics)}\n\n`);
  }, 30000); // Every 30 seconds
  
  // Listen for specific events
  const eventHandlers = {
    newOrder: (data) => res.write(`event: newOrder\ndata: ${JSON.stringify(data)}\n\n`),
    stockAlert: (data) => res.write(`event: stockAlert\ndata: ${JSON.stringify(data)}\n\n`)
  };
  
  eventBus.on(`tenant:${tenantId}:newOrder`, eventHandlers.newOrder);
  eventBus.on(`tenant:${tenantId}:stockAlert`, eventHandlers.stockAlert);
  
  // Cleanup on disconnect
  req.on('close', () => {
    clearInterval(updateInterval);
    eventBus.off(`tenant:${tenantId}:newOrder`, eventHandlers.newOrder);
    eventBus.off(`tenant:${tenantId}:stockAlert`, eventHandlers.stockAlert);
  });
});

// Client: SSE consumption
class DashboardLiveUpdates {
  constructor(tenantId) {
    this.eventSource = new EventSource(`/api/dashboard/${tenantId}/live`);
    this.setupEventHandlers();
  }
  
  setupEventHandlers() {
    this.eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.updateDashboardMetrics(data);
    };
    
    this.eventSource.addEventListener('newOrder', (event) => {
      const orderData = JSON.parse(event.data);
      this.showNewOrderNotification(orderData);
      this.incrementOrderCounter();
    });
    
    this.eventSource.addEventListener('stockAlert', (event) => {
      const alertData = JSON.parse(event.data);
      this.showStockAlert(alertData);
    });
  }
}
```

## Performance Optimization

### 1. Connection Management

#### WebSocket Connection Pooling
```javascript
class ConnectionManager {
  constructor() {
    this.connections = new Map();
    this.rooms = new Map();
    this.connectionLimits = {
      perTenant: 1000,
      perUser: 5,
      total: 10000
    };
  }
  
  addConnection(socket, userId, tenantId) {
    // Enforce connection limits
    if (this.exceedsLimits(userId, tenantId)) {
      socket.disconnect('Connection limit exceeded');
      return false;
    }
    
    // Track connection
    this.connections.set(socket.id, {
      socket,
      userId,
      tenantId,
      connectedAt: Date.now(),
      subscriptions: new Set()
    });
    
    // Add to tenant room
    socket.join(`tenant:${tenantId}`);
    
    return true;
  }
  
  subscribeToProduct(socketId, productId) {
    const connection = this.connections.get(socketId);
    if (connection) {
      connection.socket.join(`product:${productId}`);
      connection.subscriptions.add(`product:${productId}`);
    }
  }
}
```

### 2. Message Queuing for High Volume Updates

#### Redis Pub/Sub for Scalability
```javascript
class RealTimeMessageQueue {
  constructor() {
    this.publisher = redis.createClient();
    this.subscriber = redis.createClient();
    
    this.setupSubscriptions();
  }
  
  publishStockUpdate(productId, stockData) {
    const message = {
      type: 'STOCK_UPDATE',
      productId,
      data: stockData,
      timestamp: Date.now()
    };
    
    this.publisher.publish('stock-updates', JSON.stringify(message));
  }
  
  setupSubscriptions() {
    this.subscriber.subscribe('stock-updates');
    this.subscriber.on('message', (channel, message) => {
      const data = JSON.parse(message);
      
      // Distribute to connected WebSocket clients
      this.distributeUpdate(data);
    });
  }
  
  distributeUpdate(updateData) {
    const { type, productId, data } = updateData;
    
    // Send to all clients subscribed to this product
    io.to(`product:${productId}`).emit('stockUpdate', data);
    
    // Send aggregated updates to tenant dashboards
    this.updateTenantDashboards(productId, data);
  }
}
```

## Implementation Checklist

### Phase 1: Basic Real-Time Infrastructure
- [ ] Set up WebSocket server with Socket.io
- [ ] Implement basic stock level real-time updates
- [ ] Create hybrid data loading pattern
- [ ] Add optimistic UI updates with rollback

### Phase 2: Advanced Real-Time Features  
- [ ] Implement Server-Sent Events for dashboards
- [ ] Add event sourcing for audit trails
- [ ] Create CQRS pattern for read/write separation
- [ ] Set up Redis pub/sub for message distribution

### Phase 3: Performance & Scaling
- [ ] Implement connection pooling and limits
- [ ] Add message queuing for high-volume updates
- [ ] Create monitoring for real-time performance
- [ ] Optimize database queries for real-time data

### Phase 4: Advanced Features
- [ ] Add predictive caching based on real-time patterns
- [ ] Implement conflict resolution for concurrent updates
- [ ] Create advanced dashboard customization
- [ ] Add real-time analytics and reporting