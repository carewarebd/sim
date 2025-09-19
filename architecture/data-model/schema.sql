-- Shop Management System Database Schema
-- PostgreSQL 14+ with PostGIS extension
-- Multi-tenant architecture with Row-Level Security (RLS)

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create custom types
CREATE TYPE tenant_status AS ENUM ('active', 'suspended', 'cancelled');
CREATE TYPE user_role AS ENUM ('owner', 'admin', 'salesperson', 'viewer');
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'pending');
CREATE TYPE order_type AS ENUM ('sale', 'return', 'exchange');
CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');
CREATE TYPE payment_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'bank_transfer', 'digital_wallet', 'check');
CREATE TYPE delivery_method AS ENUM ('pickup', 'delivery', 'shipping');
CREATE TYPE invoice_status AS ENUM ('draft', 'sent', 'paid', 'overdue', 'cancelled');
CREATE TYPE inventory_transaction_type AS ENUM ('stock_in', 'stock_out', 'adjustment', 'transfer', 'return');
CREATE TYPE notification_type AS ENUM ('order_created', 'low_stock', 'payment_received', 'system_alert');

-- =====================================================
-- CORE TENANT MANAGEMENT
-- =====================================================

-- Tenants table - central tenant management
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    domain VARCHAR(255), -- for custom domains
    status tenant_status DEFAULT 'active',
    subscription_plan VARCHAR(50) DEFAULT 'basic',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    
    CONSTRAINT tenants_slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

-- Indexes for tenants
CREATE INDEX idx_tenants_status ON tenants(status);
CREATE INDEX idx_tenants_domain ON tenants(domain) WHERE domain IS NOT NULL;
CREATE INDEX idx_tenants_created_at ON tenants(created_at);

-- Users table - all system users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    cognito_sub VARCHAR(255) UNIQUE, -- AWS Cognito user ID
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),
    role user_role DEFAULT 'salesperson',
    status user_status DEFAULT 'active',
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for users
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_cognito_sub ON users(cognito_sub);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_tenant_role ON users(tenant_id, role);

-- =====================================================
-- SHOP AND LOCATION MANAGEMENT
-- =====================================================

-- Shops table - physical or virtual shop locations
CREATE TABLE shops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(2) DEFAULT 'US',
    location POINT, -- PostGIS geometry for geospatial queries
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(255),
    business_hours JSONB, -- Store opening hours by day
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for shops
CREATE INDEX idx_shops_tenant_id ON shops(tenant_id);
CREATE INDEX idx_shops_owner_id ON shops(owner_id);
CREATE INDEX idx_shops_is_active ON shops(is_active);
CREATE INDEX idx_shops_location ON shops USING GIST(location); -- Geospatial index
CREATE INDEX idx_shops_city_state ON shops(city, state);

-- =====================================================
-- PRODUCT CATALOG MANAGEMENT
-- =====================================================

-- Categories table - hierarchical product categories
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES categories(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    description TEXT,
    image_url VARCHAR(500),
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    
    UNIQUE(tenant_id, slug)
);

-- Indexes for categories
CREATE INDEX idx_categories_tenant_id ON categories(tenant_id);
CREATE INDEX idx_categories_parent_id ON categories(parent_id);
CREATE INDEX idx_categories_is_active ON categories(is_active);
CREATE INDEX idx_categories_sort_order ON categories(sort_order);

-- Products table - main product catalog
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    description TEXT,
    short_description VARCHAR(500),
    sku VARCHAR(100) NOT NULL,
    barcode VARCHAR(100),
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    cost_price DECIMAL(10,2) CHECK (cost_price >= 0),
    weight DECIMAL(8,3) CHECK (weight >= 0),
    dimensions JSONB, -- {length, width, height, unit}
    attributes JSONB DEFAULT '{}', -- Custom product attributes
    tags TEXT[],
    images JSONB DEFAULT '[]', -- Array of image URLs
    is_active BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    in_stock BOOLEAN DEFAULT true,
    stock_quantity INTEGER DEFAULT 0 CHECK (stock_quantity >= 0),
    min_stock_level INTEGER DEFAULT 0 CHECK (min_stock_level >= 0),
    max_stock_level INTEGER CHECK (max_stock_level IS NULL OR max_stock_level >= min_stock_level),
    allow_backorder BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    
    UNIQUE(tenant_id, sku),
    UNIQUE(tenant_id, slug)
);

-- Indexes for products - optimized for common queries
CREATE INDEX idx_products_tenant_id ON products(tenant_id);
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_sku ON products(tenant_id, sku);
CREATE INDEX idx_products_is_active ON products(is_active);
CREATE INDEX idx_products_in_stock ON products(in_stock);
CREATE INDEX idx_products_is_featured ON products(is_featured);
CREATE INDEX idx_products_price ON products(price);
CREATE INDEX idx_products_stock_quantity ON products(stock_quantity);
CREATE INDEX idx_products_low_stock ON products(tenant_id, stock_quantity) WHERE stock_quantity <= min_stock_level;
CREATE INDEX idx_products_name_trgm ON products USING GIN(name gin_trgm_ops); -- Full-text search
CREATE INDEX idx_products_tags ON products USING GIN(tags); -- Array search
CREATE INDEX idx_products_attributes ON products USING GIN(attributes); -- JSON search

-- =====================================================
-- INVENTORY MANAGEMENT
-- =====================================================

-- Inventory transactions - audit trail for stock changes
CREATE TABLE inventory_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    order_id UUID, -- References orders(id), added later due to circular dependency
    transaction_type inventory_transaction_type NOT NULL,
    quantity INTEGER NOT NULL,
    previous_quantity INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    unit_cost DECIMAL(10,2),
    total_cost DECIMAL(10,2),
    notes TEXT,
    reference_number VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for inventory transactions
CREATE INDEX idx_inventory_transactions_tenant_id ON inventory_transactions(tenant_id);
CREATE INDEX idx_inventory_transactions_product_id ON inventory_transactions(product_id);
CREATE INDEX idx_inventory_transactions_user_id ON inventory_transactions(user_id);
CREATE INDEX idx_inventory_transactions_order_id ON inventory_transactions(order_id);
CREATE INDEX idx_inventory_transactions_type ON inventory_transactions(transaction_type);
CREATE INDEX idx_inventory_transactions_created_at ON inventory_transactions(created_at);
CREATE INDEX idx_inventory_transactions_tenant_date ON inventory_transactions(tenant_id, created_at DESC);

-- =====================================================
-- ORDER MANAGEMENT
-- =====================================================

-- Orders table - sales orders and transactions
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES users(id) ON DELETE SET NULL, -- External customers may not have user accounts
    salesperson_id UUID REFERENCES users(id) ON DELETE SET NULL,
    order_number VARCHAR(50) NOT NULL,
    order_type order_type DEFAULT 'sale',
    status order_status DEFAULT 'pending',
    payment_status payment_status DEFAULT 'pending',
    subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount DECIMAL(10,2) DEFAULT 0 CHECK (tax_amount >= 0),
    discount_amount DECIMAL(10,2) DEFAULT 0 CHECK (discount_amount >= 0),
    shipping_amount DECIMAL(10,2) DEFAULT 0 CHECK (shipping_amount >= 0),
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    currency VARCHAR(3) DEFAULT 'USD',
    customer_email VARCHAR(255),
    customer_phone VARCHAR(20),
    customer_name VARCHAR(255),
    delivery_address JSONB,
    delivery_method delivery_method,
    delivery_date TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    
    UNIQUE(tenant_id, order_number)
);

-- Indexes for orders
CREATE INDEX idx_orders_tenant_id ON orders(tenant_id);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_salesperson_id ON orders(salesperson_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_payment_status ON orders(payment_status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX idx_orders_tenant_date ON orders(tenant_id, created_at DESC);
CREATE INDEX idx_orders_tenant_salesperson_date ON orders(tenant_id, salesperson_id, created_at DESC);

-- Order items table - line items for each order
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    product_name VARCHAR(255) NOT NULL, -- Snapshot of product name at time of order
    product_sku VARCHAR(100) NOT NULL, -- Snapshot of SKU
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    total_price DECIMAL(10,2) NOT NULL CHECK (total_price >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for order items
CREATE INDEX idx_order_items_tenant_id ON order_items(tenant_id);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);

-- =====================================================
-- PAYMENT MANAGEMENT
-- =====================================================

-- Payments table - payment transactions
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    payment_method payment_method NOT NULL,
    amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) DEFAULT 'USD',
    status payment_status DEFAULT 'pending',
    gateway_transaction_id VARCHAR(255),
    gateway_response JSONB,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for payments
CREATE INDEX idx_payments_tenant_id ON payments(tenant_id);
CREATE INDEX idx_payments_order_id ON payments(order_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_processed_at ON payments(processed_at);
CREATE INDEX idx_payments_gateway_transaction_id ON payments(gateway_transaction_id);

-- =====================================================
-- INVOICE MANAGEMENT
-- =====================================================

-- Invoices table - generated invoices
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    invoice_number VARCHAR(50) NOT NULL,
    issue_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
    due_date TIMESTAMP WITH TIME ZONE,
    status invoice_status DEFAULT 'draft',
    subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount DECIMAL(10,2) DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    pdf_url VARCHAR(500),
    sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    
    UNIQUE(tenant_id, invoice_number)
);

-- Indexes for invoices
CREATE INDEX idx_invoices_tenant_id ON invoices(tenant_id);
CREATE INDEX idx_invoices_order_id ON invoices(order_id);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_issue_date ON invoices(issue_date);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);

-- =====================================================
-- NOTIFICATION SYSTEM
-- =====================================================

-- Notifications table - system notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for notifications
CREATE INDEX idx_notifications_tenant_id ON notifications(tenant_id);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_read_at ON notifications(read_at);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(user_id, created_at DESC) WHERE read_at IS NULL;

-- =====================================================
-- AUDIT AND LOGGING
-- =====================================================

-- Audit logs table - system audit trail
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100) NOT NULL,
    resource_id UUID,
    changes JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for audit logs
CREATE INDEX idx_audit_logs_tenant_id ON audit_logs(tenant_id);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_resource_type ON audit_logs(resource_type);
CREATE INDEX idx_audit_logs_resource_id ON audit_logs(resource_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);

-- =====================================================
-- MATERIALIZED VIEWS FOR PERFORMANCE
-- =====================================================

-- Daily sales summary - pre-computed daily metrics
CREATE MATERIALIZED VIEW daily_sales_summary AS
SELECT 
    o.tenant_id,
    DATE(o.created_at) as date,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_revenue,
    COALESCE(SUM(oi.quantity), 0) as total_items_sold,
    COALESCE(AVG(o.total_amount), 0) as avg_order_value,
    -- Most popular product of the day
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

-- Unique index for materialized view
CREATE UNIQUE INDEX idx_daily_sales_summary_pk ON daily_sales_summary(tenant_id, date);
CREATE INDEX idx_daily_sales_summary_date ON daily_sales_summary(date DESC);
CREATE INDEX idx_daily_sales_summary_revenue ON daily_sales_summary(tenant_id, total_revenue DESC);

-- Salesperson performance summary
CREATE MATERIALIZED VIEW salesperson_performance AS
SELECT 
    o.tenant_id,
    o.salesperson_id,
    DATE_TRUNC('month', o.created_at) as month,
    COUNT(o.id) as orders_count,
    COALESCE(SUM(o.total_amount), 0) as total_sales,
    COALESCE(SUM(o.total_amount) * 0.05, 0) as commission_earned, -- Assuming 5% commission
    now() as updated_at
FROM orders o
WHERE o.salesperson_id IS NOT NULL
  AND o.status NOT IN ('cancelled', 'refunded')
GROUP BY o.tenant_id, o.salesperson_id, DATE_TRUNC('month', o.created_at);

-- Unique index for salesperson performance
CREATE UNIQUE INDEX idx_salesperson_performance_pk ON salesperson_performance(tenant_id, salesperson_id, month);
CREATE INDEX idx_salesperson_performance_month ON salesperson_performance(month DESC);
CREATE INDEX idx_salesperson_performance_sales ON salesperson_performance(tenant_id, total_sales DESC);

-- Product popularity summary
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

-- Unique index for product popularity
CREATE UNIQUE INDEX idx_product_popularity_pk ON product_popularity(tenant_id, product_id, month);
CREATE INDEX idx_product_popularity_month ON product_popularity(month DESC);
CREATE INDEX idx_product_popularity_quantity ON product_popularity(tenant_id, quantity_sold DESC);

-- =====================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =====================================================

-- Enable RLS on all tenant-scoped tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS policies for tenant isolation
-- Users can only see data from their own tenant
CREATE POLICY tenant_isolation_users ON users
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_shops ON shops
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_categories ON categories
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_products ON products
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_inventory_transactions ON inventory_transactions
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_orders ON orders
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_order_items ON order_items
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_payments ON payments
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_invoices ON invoices
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_notifications ON notifications
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY tenant_isolation_audit_logs ON audit_logs
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- =====================================================
-- TRIGGERS AND FUNCTIONS
-- =====================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shops_updated_at BEFORE UPDATE ON shops
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_categories_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_invoices_updated_at BEFORE UPDATE ON invoices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to automatically create inventory transaction on stock changes
CREATE OR REPLACE FUNCTION create_inventory_transaction()
RETURNS TRIGGER AS $$
BEGIN
    -- Only create transaction if stock_quantity changed
    IF OLD.stock_quantity != NEW.stock_quantity THEN
        INSERT INTO inventory_transactions (
            tenant_id, product_id, user_id, transaction_type,
            quantity, previous_quantity, new_quantity, notes
        ) VALUES (
            NEW.tenant_id,
            NEW.id,
            current_setting('app.current_user', true)::UUID, -- Set by application
            'adjustment',
            NEW.stock_quantity - OLD.stock_quantity,
            OLD.stock_quantity,
            NEW.stock_quantity,
            'Automatic inventory adjustment'
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for automatic inventory tracking
CREATE TRIGGER products_inventory_tracking AFTER UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION create_inventory_transaction();

-- Function to send low stock notifications
CREATE OR REPLACE FUNCTION check_low_stock()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if stock level dropped to or below minimum
    IF NEW.stock_quantity <= NEW.min_stock_level AND OLD.stock_quantity > OLD.min_stock_level THEN
        INSERT INTO notifications (tenant_id, user_id, type, title, message, data)
        SELECT 
            NEW.tenant_id,
            u.id,
            'low_stock',
            'Low Stock Alert',
            format('Product "%s" is running low on stock (%s remaining)', NEW.name, NEW.stock_quantity),
            json_build_object('product_id', NEW.id, 'current_stock', NEW.stock_quantity, 'min_level', NEW.min_stock_level)
        FROM users u
        WHERE u.tenant_id = NEW.tenant_id 
          AND u.role IN ('owner', 'admin')
          AND u.status = 'active';
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for low stock alerts
CREATE TRIGGER products_low_stock_alert AFTER UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION check_low_stock();

-- =====================================================
-- FUNCTIONS FOR COMMON OPERATIONS
-- =====================================================

-- Function to get nearby shops within radius (km)
CREATE OR REPLACE FUNCTION get_nearby_shops(
    search_latitude DECIMAL,
    search_longitude DECIMAL,
    radius_km INTEGER DEFAULT 10,
    limit_count INTEGER DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    tenant_id UUID,
    name VARCHAR(255),
    address TEXT,
    distance_km DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.tenant_id,
        s.name,
        s.address,
        ROUND(ST_Distance(
            ST_GeogFromText(format('POINT(%s %s)', search_longitude, search_latitude)),
            ST_GeogFromText(format('POINT(%s %s)', ST_X(s.location), ST_Y(s.location)))
        ) / 1000, 2) as distance_km
    FROM shops s
    WHERE s.is_active = true
      AND s.location IS NOT NULL
      AND ST_DWithin(
          ST_GeogFromText(format('POINT(%s %s)', search_longitude, search_latitude)),
          ST_GeogFromText(format('POINT(%s %s)', ST_X(s.location), ST_Y(s.location))),
          radius_km * 1000
      )
    ORDER BY distance_km ASC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function to refresh materialized views (to be called by scheduled job)
CREATE OR REPLACE FUNCTION refresh_analytics_views()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_sales_summary;
    REFRESH MATERIALIZED VIEW CONCURRENTLY salesperson_performance;
    REFRESH MATERIALIZED VIEW CONCURRENTLY product_popularity;
END;
$$ LANGUAGE plpgsql;

-- Add foreign key constraint after orders table creation
ALTER TABLE inventory_transactions 
ADD CONSTRAINT inventory_transactions_order_id_fkey 
FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;

-- =====================================================
-- SAMPLE DATA FOR TESTING
-- =====================================================

-- Insert a sample tenant
INSERT INTO tenants (id, name, slug, status, subscription_plan) VALUES 
('550e8400-e29b-41d4-a716-446655440000', 'Demo Shop Network', 'demo-shop', 'active', 'premium');

-- Set tenant context for sample data
SET app.current_tenant = '550e8400-e29b-41d4-a716-446655440000';

-- Insert sample users
INSERT INTO users (id, tenant_id, email, first_name, last_name, role) VALUES 
('550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440000', 'owner@demoshop.com', 'John', 'Smith', 'owner'),
('550e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440000', 'manager@demoshop.com', 'Jane', 'Doe', 'admin'),
('550e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440000', 'sales@demoshop.com', 'Mike', 'Johnson', 'salesperson');

-- Insert sample shop
INSERT INTO shops (tenant_id, owner_id, name, address, city, state, postal_code, location, phone, email) VALUES 
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'Demo Electronics Store', 
 '123 Main St', 'New York', 'NY', '10001', ST_Point(-74.0060, 40.7128), '(555) 123-4567', 'info@demoshop.com');

-- =====================================================
-- PERFORMANCE OPTIMIZATION NOTES
-- =====================================================

-- Query Examples with Index Usage:

-- 1. Find products with low stock (uses idx_products_low_stock):
-- SELECT name, stock_quantity, min_stock_level 
-- FROM products 
-- WHERE stock_quantity <= min_stock_level AND tenant_id = ?;

-- 2. Monthly sales by salesperson (uses idx_orders_tenant_salesperson_date):
-- SELECT salesperson_id, SUM(total_amount) 
-- FROM orders 
-- WHERE tenant_id = ? AND created_at >= '2024-01-01' AND created_at < '2024-02-01'
-- GROUP BY salesperson_id;

-- 3. Search products by name (uses idx_products_name_trgm):
-- SELECT name, price FROM products 
-- WHERE tenant_id = ? AND name ILIKE '%search_term%';

-- 4. Find nearby shops (uses idx_shops_location):
-- SELECT * FROM get_nearby_shops(40.7128, -74.0060, 5);

-- Materialized View Refresh Schedule:
-- - daily_sales_summary: Refresh daily at 1 AM
-- - salesperson_performance: Refresh monthly on 1st at 2 AM  
-- - product_popularity: Refresh weekly on Sunday at 3 AM

-- Connection Pooling Recommendations:
-- - Use PgBouncer with transaction pooling
-- - Max 100 connections per application server
-- - Connection timeout: 30 seconds
-- - Pool size per tenant: Calculate based on concurrent users

COMMENT ON SCHEMA public IS 'Shop Management System - Multi-tenant PostgreSQL schema with Row-Level Security';