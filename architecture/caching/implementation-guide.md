# Implementation Guide

## Overview
This document provides step-by-step implementation guidelines for deploying the comprehensive caching strategy in the Shop Management System, including code examples, configuration templates, and deployment procedures.

## Prerequisites & Technology Stack

### Required Infrastructure
- **Redis Cluster:** ElastiCache with 3 master + 3 replica nodes
- **CloudFront CDN:** Global distribution with custom cache behaviors  
- **Application Load Balancer:** SSL termination and traffic routing
- **WebSocket Support:** Socket.io with Redis adapter for scaling
- **Monitoring:** CloudWatch + custom dashboards

### Required Libraries & Dependencies
```json
{
  "dependencies": {
    "redis": "^4.6.0",
    "socket.io": "^4.7.0",
    "socket.io-redis": "^6.1.0",
    "node-cache": "^5.1.2",
    "ioredis": "^5.3.0",
    "@aws-sdk/client-cloudfront": "^3.400.0",
    "express-rate-limit": "^6.8.0",
    "compression": "^1.7.4"
  },
  "devDependencies": {
    "redis-mock": "^0.56.3",
    "jest": "^29.0.0",
    "supertest": "^6.3.0"
  }
}
```

## Phase 1: Core Caching Infrastructure (Week 1-2)

### Step 1: Redis Cluster Setup

#### AWS ElastiCache Configuration
```terraform
# terraform/elasticache.tf
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "shop-management-redis"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "redis_cluster" {
  replication_group_id         = "shop-management-redis"
  description                  = "Redis cluster for shop management caching"
  
  node_type                   = "cache.r6g.large"
  port                        = 6379
  parameter_group_name        = "default.redis7"
  
  num_cache_clusters          = 6
  automatic_failover_enabled  = true
  multi_az_enabled           = true
  
  subnet_group_name          = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids         = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result
  
  snapshot_retention_limit   = 7
  snapshot_window           = "03:00-05:00"
  maintenance_window        = "sun:05:00-sun:07:00"
  
  tags = {
    Environment = var.environment
    Project     = "shop-management"
  }
}
```

#### Application Redis Connection
```javascript
// config/redis.js
const Redis = require('ioredis');

const redisConfig = {
  host: process.env.REDIS_CLUSTER_ENDPOINT,
  port: 6379,
  password: process.env.REDIS_AUTH_TOKEN,
  
  // Connection pool settings
  maxRetriesPerRequest: 3,
  retryDelayOnFailover: 100,
  enableReadyCheck: false,
  maxRetriesPerRequest: null,
  
  // Cluster configuration
  enableOfflineQueue: false,
  connectTimeout: 10000,
  commandTimeout: 5000,
  
  // Optimize for performance
  lazyConnect: true,
  keepAlive: 30000,
  
  // Retry strategy
  retryDelayOnClusterDown: 300,
  retryDelayOnFailover: 100,
  slotsRefreshTimeout: 10000
};

// Create Redis client
const redis = new Redis(redisConfig);

// Error handling
redis.on('error', (err) => {
  console.error('Redis connection error:', err);
  // Implement fallback strategy or graceful degradation
});

redis.on('connect', () => {
  console.log('Redis connected successfully');
});

module.exports = redis;
```

### Step 2: Cache Service Implementation

#### Core Cache Service
```javascript
// services/cacheService.js
class CacheService {
  constructor(redisClient) {
    this.redis = redisClient;
    this.localCache = new Map(); // In-memory fallback
    this.defaultTTL = 300; // 5 minutes
  }
  
  // Generate cache key with tenant isolation
  generateKey(tenantId, resource, identifier, modifier = null) {
    const baseKey = `{${tenantId}}:${resource}:${identifier}`;
    return modifier ? `${baseKey}:${modifier}` : baseKey;
  }
  
  // Get with fallback strategy
  async get(key, fallbackFn = null) {
    try {
      // Try Redis first
      const cached = await this.redis.get(key);
      if (cached) {
        return JSON.parse(cached);
      }
      
      // Try local memory cache
      if (this.localCache.has(key)) {
        return this.localCache.get(key);
      }
      
      // Execute fallback function if provided
      if (fallbackFn && typeof fallbackFn === 'function') {
        const data = await fallbackFn();
        await this.set(key, data); // Cache the result
        return data;
      }
      
      return null;
      
    } catch (error) {
      console.error('Cache get error:', error);
      
      // Return from local cache if Redis fails
      return this.localCache.get(key) || null;
    }
  }
  
  // Set with dual storage
  async set(key, value, ttl = this.defaultTTL) {
    const serialized = JSON.stringify(value);
    
    try {
      // Set in Redis
      await this.redis.setex(key, ttl, serialized);
      
      // Also set in local cache (shorter TTL)
      this.localCache.set(key, value);
      setTimeout(() => this.localCache.delete(key), Math.min(ttl, 300) * 1000);
      
    } catch (error) {
      console.error('Cache set error:', error);
      // At least store locally
      this.localCache.set(key, value);
    }
  }
  
  // Delete from both caches
  async delete(key) {
    try {
      await this.redis.del(key);
    } catch (error) {
      console.error('Cache delete error:', error);
    }
    
    this.localCache.delete(key);
  }
  
  // Pattern-based deletion for cache invalidation
  async deletePattern(pattern) {
    try {
      const keys = await this.redis.keys(pattern);
      if (keys.length > 0) {
        await this.redis.del(...keys);
      }
    } catch (error) {
      console.error('Cache pattern delete error:', error);
    }
  }
}

module.exports = CacheService;
```

#### Product Caching Implementation
```javascript
// services/productService.js
class ProductService {
  constructor(db, cacheService, eventEmitter) {
    this.db = db;
    this.cache = cacheService;
    this.events = eventEmitter;
  }
  
  async getProduct(productId, tenantId, includeStock = false) {
    const cacheKey = this.cache.generateKey(tenantId, 'product', productId);
    
    // Try cache first with fallback to database
    const product = await this.cache.get(cacheKey, async () => {
      return await this.fetchProductFromDB(productId, tenantId);
    });
    
    if (!product) {
      throw new Error(`Product ${productId} not found`);
    }
    
    // If stock is needed, fetch it separately (real-time)
    if (includeStock) {
      product.stock = await this.getCurrentStock(productId, tenantId);
    }
    
    return product;
  }
  
  async fetchProductFromDB(productId, tenantId) {
    const result = await this.db.query(`
      SELECT p.*, c.name as category_name, c.id as category_id
      FROM products p
      JOIN categories c ON p.category_id = c.id  
      WHERE p.id = $1 AND p.tenant_id = $2 AND p.deleted_at IS NULL
    `, [productId, tenantId]);
    
    return result[0] || null;
  }
  
  async updateProduct(productId, tenantId, updates) {
    // Update database
    const updatedProduct = await this.db.query(`
      UPDATE products 
      SET name = COALESCE($3, name),
          description = COALESCE($4, description), 
          price = COALESCE($5, price),
          updated_at = NOW()
      WHERE id = $1 AND tenant_id = $2
      RETURNING *
    `, [productId, tenantId, updates.name, updates.description, updates.price]);
    
    if (updatedProduct.length === 0) {
      throw new Error('Product not found or update failed');
    }
    
    // Update cache
    const cacheKey = this.cache.generateKey(tenantId, 'product', productId);
    await this.cache.set(cacheKey, updatedProduct[0], 900); // 15 minutes
    
    // Invalidate related caches
    await this.invalidateRelatedCaches(productId, tenantId);
    
    // Emit event for real-time updates
    this.events.emit('product.updated', {
      productId,
      tenantId,
      product: updatedProduct[0]
    });
    
    return updatedProduct[0];
  }
  
  async invalidateRelatedCaches(productId, tenantId) {
    const patterns = [
      `{${tenantId}}:products:*`,           // Product lists
      `{${tenantId}}:search:*`,             // Search results
      `marketplace:products:*`,             // Marketplace cache
      `{${tenantId}}:reports:product-popularity:*` // Reports
    ];
    
    for (const pattern of patterns) {
      await this.cache.deletePattern(pattern);
    }
  }
}
```

### Step 3: HTTP Cache Headers Implementation

#### Express Middleware for Cache Headers
```javascript
// middleware/cacheHeaders.js
const cacheHeaders = {
  // Long-term static assets
  static: (req, res, next) => {
    if (req.path.match(/\.(jpg|jpeg|png|gif|ico|css|js|woff|woff2)$/)) {
      res.set({
        'Cache-Control': 'public, max-age=31536000, immutable',
        'Expires': new Date(Date.now() + 31536000000).toUTCString()
      });
    }
    next();
  },
  
  // API responses - frequently accessed
  apiFrequent: (ttl = 300) => (req, res, next) => {
    res.set({
      'Cache-Control': `public, max-age=${ttl}, stale-while-revalidate=60`,
      'Vary': 'Accept-Encoding, Authorization'
    });
    next();
  },
  
  // API responses - user specific
  apiPrivate: (ttl = 120) => (req, res, next) => {
    res.set({
      'Cache-Control': `private, max-age=${ttl}, stale-while-revalidate=30`,
      'Vary': 'Authorization'
    });
    next();
  },
  
  // No cache - real-time data
  noCache: (req, res, next) => {
    res.set({
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0'
    });
    next();
  }
};

module.exports = cacheHeaders;
```

#### API Route Implementation with Caching
```javascript
// routes/products.js
const express = require('express');
const router = express.Router();
const cacheHeaders = require('../middleware/cacheHeaders');

// Product listing - cacheable
router.get('/', 
  cacheHeaders.apiFrequent(300), // 5 minutes
  async (req, res) => {
    try {
      const { page = 1, limit = 20, category, search } = req.query;
      const tenantId = req.user.tenantId;
      
      // Create cache key including query parameters
      const cacheKey = cache.generateKey(
        tenantId, 
        'products', 
        'list', 
        `page:${page}:limit:${limit}:category:${category}:search:${search}`
      );
      
      const products = await cache.get(cacheKey, async () => {
        return await productService.getProducts(tenantId, {
          page, limit, category, search
        });
      });
      
      res.json({
        success: true,
        data: products,
        cached: true
      });
      
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
);

// Individual product - cacheable but include real-time stock
router.get('/:id',
  cacheHeaders.apiFrequent(600), // 10 minutes
  async (req, res) => {
    try {
      const productId = req.params.id;
      const tenantId = req.user.tenantId;
      
      // Get cached product info + real-time stock
      const product = await productService.getProduct(
        productId, 
        tenantId, 
        true // include real-time stock
      );
      
      res.json({
        success: true,
        data: product
      });
      
    } catch (error) {
      res.status(404).json({ error: error.message });
    }
  }
);

// Stock levels - real-time only
router.get('/:id/stock',
  cacheHeaders.noCache,
  async (req, res) => {
    try {
      const productId = req.params.id;
      const tenantId = req.user.tenantId;
      
      const stock = await productService.getCurrentStock(productId, tenantId);
      
      res.json({
        success: true,
        data: { stock, lastUpdated: Date.now() }
      });
      
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
);
```

## Phase 2: Real-Time Integration (Week 3-4)

### Step 4: WebSocket Implementation

#### Socket.io Server Setup
```javascript
// realtime/socketServer.js
const socketIo = require('socket.io');
const redisAdapter = require('socket.io-redis');
const jwt = require('jsonwebtoken');

class SocketServer {
  constructor(server, redisClient) {
    this.io = socketIo(server, {
      cors: {
        origin: process.env.FRONTEND_URL,
        methods: ['GET', 'POST'],
        credentials: true
      },
      transports: ['websocket', 'polling']
    });
    
    // Use Redis adapter for scaling across multiple servers
    this.io.adapter(redisAdapter({
      host: process.env.REDIS_HOST,
      port: process.env.REDIS_PORT,
      auth_pass: process.env.REDIS_AUTH_TOKEN
    }));
    
    this.setupMiddleware();
    this.setupEventHandlers();
  }
  
  setupMiddleware() {
    // Authentication middleware
    this.io.use(async (socket, next) => {
      try {
        const token = socket.handshake.auth.token;
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        
        socket.userId = decoded.userId;
        socket.tenantId = decoded.tenantId;
        socket.permissions = decoded.permissions;
        
        next();
      } catch (error) {
        next(new Error('Authentication failed'));
      }
    });
    
    // Rate limiting middleware
    this.io.use(async (socket, next) => {
      // Simple rate limiting - 100 messages per minute per user
      socket.messageCount = 0;
      socket.rateLimitReset = Date.now() + 60000;
      
      next();
    });
  }
  
  setupEventHandlers() {
    this.io.on('connection', (socket) => {
      console.log(`User ${socket.userId} connected from tenant ${socket.tenantId}`);
      
      // Join tenant room for broadcasts
      socket.join(`tenant:${socket.tenantId}`);
      
      // Product subscription
      socket.on('subscribe:product', (data) => {
        const { productId } = data;
        
        if (this.isAuthorized(socket, 'products:read', productId)) {
          socket.join(`product:${productId}`);
          console.log(`User ${socket.userId} subscribed to product ${productId}`);
        }
      });
      
      // Dashboard subscription
      socket.on('subscribe:dashboard', () => {
        if (this.isAuthorized(socket, 'dashboard:read')) {
          socket.join(`dashboard:${socket.tenantId}`);
          console.log(`User ${socket.userId} subscribed to dashboard`);
        }
      });
      
      // Order tracking subscription
      socket.on('subscribe:order', (data) => {
        const { orderId } = data;
        
        if (this.isAuthorized(socket, 'orders:read', orderId)) {
          socket.join(`order:${orderId}`);
          console.log(`User ${socket.userId} subscribed to order ${orderId}`);
        }
      });
      
      // Handle disconnection
      socket.on('disconnect', (reason) => {
        console.log(`User ${socket.userId} disconnected: ${reason}`);
      });
      
      // Error handling
      socket.on('error', (error) => {
        console.error('Socket error:', error);
      });
    });
  }
  
  isAuthorized(socket, permission, resourceId = null) {
    // Implement your authorization logic
    return socket.permissions && socket.permissions.includes(permission);
  }
  
  // Methods for emitting updates
  emitStockUpdate(productId, stockData) {
    this.io.to(`product:${productId}`).emit('stock:update', {
      productId,
      ...stockData,
      timestamp: Date.now()
    });
  }
  
  emitOrderUpdate(orderId, orderData) {
    this.io.to(`order:${orderId}`).emit('order:update', {
      orderId,
      ...orderData,
      timestamp: Date.now()
    });
  }
  
  emitDashboardMetric(tenantId, metric) {
    this.io.to(`dashboard:${tenantId}`).emit('dashboard:metric', {
      ...metric,
      timestamp: Date.now()
    });
  }
}

module.exports = SocketServer;
```

#### Frontend WebSocket Client
```javascript
// frontend/services/realtimeService.js
import io from 'socket.io-client';

class RealtimeService {
  constructor() {
    this.socket = null;
    this.subscriptions = new Map();
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
  }
  
  connect(authToken) {
    this.socket = io(process.env.REACT_APP_WEBSOCKET_URL, {
      auth: { token: authToken },
      transports: ['websocket', 'polling'],
      timeout: 20000,
      forceNew: true
    });
    
    this.setupEventHandlers();
    
    return new Promise((resolve, reject) => {
      this.socket.on('connect', () => {
        console.log('Connected to real-time server');
        this.reconnectAttempts = 0;
        resolve();
      });
      
      this.socket.on('connect_error', (error) => {
        console.error('Connection failed:', error);
        reject(error);
      });
    });
  }
  
  setupEventHandlers() {
    this.socket.on('disconnect', (reason) => {
      console.log('Disconnected from real-time server:', reason);
      
      if (reason === 'io server disconnect') {
        // Server initiated disconnect - don't reconnect
        return;
      }
      
      // Auto-reconnect with exponential backoff
      this.attemptReconnect();
    });
    
    this.socket.on('reconnect', () => {
      console.log('Reconnected to real-time server');
      // Re-establish subscriptions
      this.resubscribeAll();
    });
  }
  
  // Product stock updates
  subscribeToProduct(productId, callback) {
    if (!this.socket) return;
    
    this.socket.emit('subscribe:product', { productId });
    this.socket.on('stock:update', (data) => {
      if (data.productId === productId) {
        callback(data);
      }
    });
    
    this.subscriptions.set(`product:${productId}`, callback);
  }
  
  // Dashboard updates
  subscribeToDashboard(callback) {
    if (!this.socket) return;
    
    this.socket.emit('subscribe:dashboard');
    this.socket.on('dashboard:metric', callback);
    
    this.subscriptions.set('dashboard', callback);
  }
  
  // Order tracking
  subscribeToOrder(orderId, callback) {
    if (!this.socket) return;
    
    this.socket.emit('subscribe:order', { orderId });
    this.socket.on('order:update', (data) => {
      if (data.orderId === orderId) {
        callback(data);
      }
    });
    
    this.subscriptions.set(`order:${orderId}`, callback);
  }
  
  unsubscribe(subscriptionKey) {
    this.subscriptions.delete(subscriptionKey);
  }
  
  disconnect() {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
      this.subscriptions.clear();
    }
  }
  
  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnection attempts reached');
      return;
    }
    
    const delay = Math.pow(2, this.reconnectAttempts) * 1000; // Exponential backoff
    this.reconnectAttempts++;
    
    setTimeout(() => {
      console.log(`Attempting reconnection ${this.reconnectAttempts}/${this.maxReconnectAttempts}`);
      this.socket.connect();
    }, delay);
  }
  
  resubscribeAll() {
    // Re-establish all subscriptions after reconnection
    for (const [key, callback] of this.subscriptions) {
      if (key.startsWith('product:')) {
        const productId = key.split(':')[1];
        this.subscribeToProduct(productId, callback);
      } else if (key === 'dashboard') {
        this.subscribeToDashboard(callback);
      } else if (key.startsWith('order:')) {
        const orderId = key.split(':')[1];
        this.subscribeToOrder(orderId, callback);
      }
    }
  }
}

export default new RealtimeService();
```

### Step 5: CloudFront CDN Configuration

#### Terraform CDN Setup
```terraform
# terraform/cloudfront.tf
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "ALB-${aws_lb.main.name}"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  # Default cache behavior (API responses)
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${aws_lb.main.name}"
    compress              = true
    
    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Accept", "Content-Type"]
      
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300    # 5 minutes
    max_ttl                = 3600   # 1 hour
  }
  
  # Static assets cache behavior
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${aws_lb.main.name}"
    compress              = true
    
    forwarded_values {
      query_string = false
      headers      = ["Accept-Encoding"]
      
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 31536000  # 1 year
    default_ttl            = 31536000  # 1 year
    max_ttl                = 31536000  # 1 year
  }
  
  # API products cache behavior (longer TTL)
  ordered_cache_behavior {
    path_pattern           = "/api/products*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${aws_lb.main.name}"
    compress              = true
    
    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Accept"]
      
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 600     # 10 minutes
    max_ttl                = 1800    # 30 minutes
  }
  
  # No cache for real-time endpoints
  ordered_cache_behavior {
    path_pattern           = "/api/*/stock"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${aws_lb.main.name}"
    
    forwarded_values {
      query_string = true
      headers      = ["*"]
      
      cookies {
        forward = "all"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.main.arn
    ssl_support_method  = "sni-only"
  }
  
  tags = {
    Environment = var.environment
    Project     = "shop-management"
  }
}
```

## Phase 3: Monitoring & Optimization (Week 5-6)

### Step 6: Performance Monitoring

#### Cache Performance Metrics
```javascript
// monitoring/cacheMetrics.js
const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch();

class CacheMetrics {
  constructor(cacheService) {
    this.cache = cacheService;
    this.metrics = {
      hits: 0,
      misses: 0,
      sets: 0,
      deletes: 0,
      errors: 0
    };
    
    this.startMetricsCollection();
  }
  
  recordHit() {
    this.metrics.hits++;
  }
  
  recordMiss() {
    this.metrics.misses++;
  }
  
  recordSet() {
    this.metrics.sets++;
  }
  
  recordDelete() {
    this.metrics.deletes++;
  }
  
  recordError() {
    this.metrics.errors++;
  }
  
  getHitRatio() {
    const total = this.metrics.hits + this.metrics.misses;
    return total > 0 ? (this.metrics.hits / total) * 100 : 0;
  }
  
  async publishMetrics() {
    const timestamp = new Date();
    const hitRatio = this.getHitRatio();
    
    const params = {
      Namespace: 'ShopManagement/Cache',
      MetricData: [
        {
          MetricName: 'HitRatio',
          Value: hitRatio,
          Unit: 'Percent',
          Timestamp: timestamp
        },
        {
          MetricName: 'CacheHits',
          Value: this.metrics.hits,
          Unit: 'Count',
          Timestamp: timestamp
        },
        {
          MetricName: 'CacheMisses',  
          Value: this.metrics.misses,
          Unit: 'Count',
          Timestamp: timestamp
        },
        {
          MetricName: 'CacheErrors',
          Value: this.metrics.errors,
          Unit: 'Count', 
          Timestamp: timestamp
        }
      ]
    };
    
    try {
      await cloudwatch.putMetricData(params).promise();
      
      // Reset counters after publishing
      this.resetMetrics();
      
    } catch (error) {
      console.error('Failed to publish cache metrics:', error);
    }
  }
  
  resetMetrics() {
    this.metrics = {
      hits: 0,
      misses: 0,
      sets: 0,
      deletes: 0,
      errors: 0
    };
  }
  
  startMetricsCollection() {
    // Publish metrics every minute
    setInterval(() => {
      this.publishMetrics();
    }, 60000);
  }
}

module.exports = CacheMetrics;
```

### Step 7: Health Checks & Alerts

#### Cache Health Monitoring
```javascript
// monitoring/healthCheck.js
class CacheHealthCheck {
  constructor(cacheService, socketServer) {
    this.cache = cacheService;
    this.socketServer = socketServer;
    
    this.healthStatus = {
      redis: 'unknown',
      websocket: 'unknown',
      lastCheck: null
    };
    
    this.startHealthChecks();
  }
  
  async checkRedisHealth() {
    try {
      const testKey = 'health:check';
      const testValue = Date.now().toString();
      
      // Test set operation
      await this.cache.set(testKey, testValue, 60);
      
      // Test get operation  
      const retrieved = await this.cache.get(testKey);
      
      // Test delete operation
      await this.cache.delete(testKey);
      
      if (retrieved === testValue) {
        this.healthStatus.redis = 'healthy';
        return true;
      } else {
        this.healthStatus.redis = 'degraded';
        return false;
      }
      
    } catch (error) {
      console.error('Redis health check failed:', error);
      this.healthStatus.redis = 'unhealthy';
      return false;
    }
  }
  
  checkWebSocketHealth() {
    try {
      const connectedClients = this.socketServer.io.sockets.sockets.size;
      
      if (connectedClients >= 0) {
        this.healthStatus.websocket = 'healthy';
        return true;
      } else {
        this.healthStatus.websocket = 'unhealthy';
        return false;
      }
      
    } catch (error) {
      console.error('WebSocket health check failed:', error);
      this.healthStatus.websocket = 'unhealthy';
      return false;
    }
  }
  
  async performHealthCheck() {
    const redisHealthy = await this.checkRedisHealth();
    const websocketHealthy = this.checkWebSocketHealth();
    
    this.healthStatus.lastCheck = new Date();
    
    // Send alerts if unhealthy
    if (!redisHealthy) {
      await this.sendAlert('Redis cache is unhealthy');
    }
    
    if (!websocketHealthy) {
      await this.sendAlert('WebSocket server is unhealthy');
    }
    
    return {
      ...this.healthStatus,
      overall: redisHealthy && websocketHealthy ? 'healthy' : 'unhealthy'
    };
  }
  
  async sendAlert(message) {
    // Implement your alerting mechanism (email, Slack, etc.)
    console.error(`ALERT: ${message}`);
    
    // Example: Send to CloudWatch Alarms
    const params = {
      Namespace: 'ShopManagement/HealthChecks',
      MetricData: [{
        MetricName: 'ServiceUnhealthy',
        Value: 1,
        Unit: 'Count',
        Timestamp: new Date()
      }]
    };
    
    // await cloudwatch.putMetricData(params).promise();
  }
  
  startHealthChecks() {
    // Run health check every 30 seconds
    setInterval(() => {
      this.performHealthCheck();
    }, 30000);
  }
  
  // Express endpoint for health status
  getHealthEndpoint() {
    return async (req, res) => {
      const health = await this.performHealthCheck();
      
      res.status(health.overall === 'healthy' ? 200 : 503).json(health);
    };
  }
}

module.exports = CacheHealthCheck;
```

## Deployment & Configuration

### Environment Configuration
```bash
# .env.production
# Redis Configuration
REDIS_CLUSTER_ENDPOINT=shop-management-redis.cache.amazonaws.com
REDIS_AUTH_TOKEN=your-secure-redis-password
REDIS_PORT=6379

# WebSocket Configuration  
WEBSOCKET_PORT=3001
WEBSOCKET_REDIS_ADAPTER=true

# Cache TTL Settings (in seconds)
CACHE_TTL_SHORT=300      # 5 minutes
CACHE_TTL_MEDIUM=1800    # 30 minutes  
CACHE_TTL_LONG=3600      # 1 hour

# Monitoring
CLOUDWATCH_NAMESPACE=ShopManagement/Cache
ENABLE_METRICS=true
METRICS_INTERVAL=60000

# Rate Limiting
RATE_LIMIT_WINDOW=60000  # 1 minute
RATE_LIMIT_MAX=100       # requests per window
```

### Docker Configuration
```dockerfile
# Dockerfile
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001
USER nodejs

# Expose ports
EXPOSE 3000 3001

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["npm", "start"]
```

### Kubernetes Deployment
```yaml
# k8s/cache-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-management-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: shop-management-api
  template:
    metadata:
      labels:
        app: shop-management-api
    spec:
      containers:
      - name: api
        image: shop-management-api:latest
        ports:
        - containerPort: 3000
        - containerPort: 3001
        env:
        - name: REDIS_CLUSTER_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: redis-config
              key: endpoint
        - name: REDIS_AUTH_TOKEN
          valueFrom:
            secretKeyRef:
              name: redis-config
              key: auth-token
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
```

## Testing Strategy

### Cache Testing
```javascript
// tests/cache.test.js
const CacheService = require('../services/cacheService');
const redis = require('redis-mock');

describe('CacheService', () => {
  let cacheService;
  
  beforeEach(() => {
    const mockRedis = redis.createClient();
    cacheService = new CacheService(mockRedis);
  });
  
  test('should cache and retrieve data correctly', async () => {
    const key = 'test:key';
    const data = { id: 1, name: 'Test Product' };
    
    await cacheService.set(key, data);
    const retrieved = await cacheService.get(key);
    
    expect(retrieved).toEqual(data);
  });
  
  test('should handle cache miss with fallback', async () => {
    const key = 'missing:key';
    const fallbackData = { id: 2, name: 'Fallback Product' };
    
    const result = await cacheService.get(key, async () => {
      return fallbackData;
    });
    
    expect(result).toEqual(fallbackData);
    
    // Should now be cached
    const cached = await cacheService.get(key);
    expect(cached).toEqual(fallbackData);
  });
  
  test('should generate proper tenant-isolated keys', () => {
    const tenantId = 'tenant123';
    const resource = 'product';
    const identifier = 'prod456';
    
    const key = cacheService.generateKey(tenantId, resource, identifier);
    
    expect(key).toBe('{tenant123}:product:prod456');
  });
});
```

### WebSocket Testing
```javascript
// tests/websocket.test.js
const Client = require('socket.io-client');
const server = require('../server');

describe('WebSocket Real-time Updates', () => {
  let clientSocket;
  let serverSocket;
  
  beforeAll((done) => {
    server.listen(() => {
      const port = server.address().port;
      clientSocket = new Client(`http://localhost:${port}`, {
        auth: { token: 'test-jwt-token' }
      });
      
      server.on('connection', (socket) => {
        serverSocket = socket;
      });
      
      clientSocket.on('connect', done);
    });
  });
  
  afterAll(() => {
    server.close();
    clientSocket.close();
  });
  
  test('should receive stock updates', (done) => {
    const productId = 'test-product-123';
    const stockData = { stock: 10, availability: 'available' };
    
    clientSocket.emit('subscribe:product', { productId });
    
    clientSocket.on('stock:update', (data) => {
      expect(data.productId).toBe(productId);
      expect(data.stock).toBe(stockData.stock);
      done();
    });
    
    // Simulate stock update from server
    serverSocket.emit('stock:update', {
      productId,
      ...stockData,
      timestamp: Date.now()
    });
  });
});
```

## Maintenance & Troubleshooting

### Common Issues & Solutions

#### Cache Miss Storm
**Problem:** Sudden spike in cache misses causing database overload
**Solution:**
```javascript
// Implement circuit breaker pattern
class CircuitBreaker {
  constructor(threshold = 5, timeout = 60000) {
    this.failureThreshold = threshold;
    this.timeout = timeout;
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
  }
  
  async execute(operation) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }
    
    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  onSuccess() {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }
  
  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.failureThreshold) {
      this.state = 'OPEN';
    }
  }
}
```

#### Memory Leaks in Local Cache
**Problem:** In-memory cache growing indefinitely
**Solution:**
```javascript
// Implement LRU cache with size limits
const LRU = require('lru-cache');

const localCache = new LRU({
  max: 10000,    // Maximum number of items
  maxAge: 300000, // 5 minutes
  updateAgeOnGet: true,
  stale: true
});
```

### Performance Optimization Checklist

- [ ] **Redis Configuration**
  - [ ] Enable compression for large values
  - [ ] Configure appropriate eviction policy
  - [ ] Set up monitoring for memory usage
  - [ ] Implement connection pooling

- [ ] **WebSocket Optimization**
  - [ ] Use Redis adapter for horizontal scaling
  - [ ] Implement connection limits per tenant
  - [ ] Add message rate limiting
  - [ ] Monitor connection stability

- [ ] **CDN Configuration**
  - [ ] Optimize cache behaviors by content type
  - [ ] Configure proper TTLs for different endpoints
  - [ ] Enable compression for all cacheable content
  - [ ] Set up cache invalidation workflows

- [ ] **Monitoring & Alerting**
  - [ ] Set up cache hit ratio monitoring
  - [ ] Configure alerts for performance degradation
  - [ ] Monitor real-time connection health
  - [ ] Track cache invalidation patterns

This implementation guide provides a complete foundation for deploying the caching strategy. Start with Phase 1 for immediate performance benefits, then gradually implement the advanced real-time features in subsequent phases.