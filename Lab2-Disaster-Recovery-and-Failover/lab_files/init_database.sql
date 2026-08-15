-- ============================================================================
-- CarvedRock Production Database Initialization (Disaster Recovery Lab)
-- ============================================================================
-- Creates the schema and seed data for the disaster-recovery / failover lab.
--
-- Idempotent: safe to re-run — it drops and recreates every lab object, so
-- row counts are always deterministic:
--   customers = 10, products = 15, orders = 15, order_items = 21, inventory = 15
--
-- Tested on: PostgreSQL 15 and 16
-- Run as:    sudo -u postgres psql -d carvedrock_prod -f init_database.sql
-- ============================================================================

-- Drop existing lab objects (order handled by CASCADE)
DROP VIEW  IF EXISTS order_summary;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS inventory   CASCADE;
DROP TABLE IF EXISTS orders      CASCADE;
DROP TABLE IF EXISTS products    CASCADE;
DROP TABLE IF EXISTS customers   CASCADE;

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    email       VARCHAR(100) UNIQUE NOT NULL,
    phone       VARCHAR(20),
    address     TEXT,
    city        VARCHAR(50),
    state       VARCHAR(2),
    zip_code    VARCHAR(10),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    product_id     SERIAL PRIMARY KEY,
    product_name   VARCHAR(200) NOT NULL,
    category       VARCHAR(50),
    description    TEXT,
    price          DECIMAL(10,2),
    stock_quantity INTEGER DEFAULT 0,
    sku            VARCHAR(50) UNIQUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    order_id         SERIAL PRIMARY KEY,
    customer_id      INTEGER REFERENCES customers(customer_id),
    order_date       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR(20) DEFAULT 'pending',
    total_amount     DECIMAL(10,2),
    shipping_address TEXT,
    billing_address  TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
    item_id     SERIAL PRIMARY KEY,
    order_id    INTEGER REFERENCES orders(order_id),
    product_id  INTEGER REFERENCES products(product_id),
    quantity    INTEGER NOT NULL,
    unit_price  DECIMAL(10,2),
    total_price DECIMAL(10,2),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inventory (
    inventory_id       SERIAL PRIMARY KEY,
    product_id         INTEGER REFERENCES products(product_id),
    warehouse_location VARCHAR(50),
    quantity_on_hand   INTEGER DEFAULT 0,
    reorder_point      INTEGER DEFAULT 10,
    last_restocked     TIMESTAMP,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- Seed data
-- ----------------------------------------------------------------------------
INSERT INTO customers (first_name, last_name, email, phone, address, city, state, zip_code) VALUES
('John',     'Smith',    'john.smith@email.com',     '555-0101', '123 Main St',    'Denver',           'CO', '80201'),
('Sarah',    'Johnson',  'sarah.j@email.com',        '555-0102', '456 Oak Ave',    'Boulder',          'CO', '80301'),
('Michael',  'Williams', 'mwilliams@email.com',      '555-0103', '789 Pine Rd',    'Fort Collins',     'CO', '80521'),
('Emma',     'Brown',    'emma.brown@email.com',     '555-0104', '321 Elm St',     'Colorado Springs', 'CO', '80903'),
('James',    'Davis',    'jdavis@email.com',         '555-0105', '654 Maple Dr',   'Aurora',           'CO', '80011'),
('Olivia',   'Miller',   'olivia.m@email.com',       '555-0106', '987 Cedar Ln',   'Lakewood',         'CO', '80226'),
('William',  'Wilson',   'wwilson@email.com',        '555-0107', '159 Birch St',   'Thornton',         'CO', '80229'),
('Sophia',   'Moore',    'sophia.moore@email.com',   '555-0108', '753 Spruce Ave', 'Westminster',      'CO', '80031'),
('Robert',   'Taylor',   'rtaylor@email.com',        '555-0109', '852 Willow Rd',  'Arvada',           'CO', '80002'),
('Isabella', 'Anderson', 'isabella.a@email.com',     '555-0110', '951 Aspen Dr',   'Centennial',       'CO', '80112');

INSERT INTO products (product_name, category, description, price, stock_quantity, sku) VALUES
('Mountain Hiking Boots',   'Footwear',    'Durable waterproof hiking boots for rough terrain', 149.99, 50, 'MHB-001'),
('Trail Running Shoes',     'Footwear',    'Lightweight shoes for trail running',                89.99, 75, 'TRS-002'),
('Climbing Harness Pro',    'Climbing',    'Professional grade climbing harness',                79.99, 30, 'CHP-003'),
('Alpine Backpack 65L',     'Backpacks',   'Large capacity backpack for multi-day trips',       199.99, 25, 'APB-004'),
('Quick-Dry Hiking Pants',  'Apparel',     'Moisture-wicking hiking pants',                      59.99, 100,'QHP-005'),
('Thermal Base Layer Set',  'Apparel',     'Warm base layer for cold weather',                   49.99, 80, 'TBL-006'),
('GPS Navigator Pro',       'Electronics', 'Advanced GPS device for outdoor navigation',        299.99, 15, 'GPS-007'),
('Camping Tent 4-Person',   'Camping',     'Weather-resistant tent for 4 people',               249.99, 20, 'CT4-008'),
('Sleeping Bag Zero',       'Camping',     'Zero-degree rated sleeping bag',                    129.99, 40, 'SBZ-009'),
('Portable Water Filter',   'Accessories', 'Compact water filtration system',                    39.99, 60, 'PWF-010'),
('Trekking Poles Carbon',   'Accessories', 'Lightweight carbon fiber trekking poles',            99.99, 35, 'TPC-011'),
('Rock Climbing Rope 60m',  'Climbing',    'Dynamic climbing rope 60 meters',                   189.99, 20, 'RCR-012'),
('Headlamp LED Pro',        'Electronics', 'High-power LED headlamp',                            44.99, 70, 'HLP-013'),
('Camping Stove Compact',   'Camping',     'Portable camping stove with fuel',                   54.99, 45, 'CSC-014'),
('First Aid Kit Complete',  'Safety',      'Comprehensive outdoor first aid kit',                34.99, 90, 'FAK-015');

INSERT INTO orders (customer_id, order_date, status, total_amount, shipping_address) VALUES
(1,  CURRENT_TIMESTAMP - INTERVAL '30 days', 'completed',  449.97, '123 Main St, Denver, CO 80201'),
(2,  CURRENT_TIMESTAMP - INTERVAL '25 days', 'completed',  289.98, '456 Oak Ave, Boulder, CO 80301'),
(3,  CURRENT_TIMESTAMP - INTERVAL '20 days', 'completed',  159.98, '789 Pine Rd, Fort Collins, CO 80521'),
(4,  CURRENT_TIMESTAMP - INTERVAL '18 days', 'shipped',    399.98, '321 Elm St, Colorado Springs, CO 80903'),
(5,  CURRENT_TIMESTAMP - INTERVAL '15 days', 'completed',  249.99, '654 Maple Dr, Aurora, CO 80011'),
(1,  CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed',  189.99, '123 Main St, Denver, CO 80201'),
(6,  CURRENT_TIMESTAMP - INTERVAL '12 days', 'processing',  99.99, '987 Cedar Ln, Lakewood, CO 80226'),
(7,  CURRENT_TIMESTAMP - INTERVAL '10 days', 'completed',  549.96, '159 Birch St, Thornton, CO 80229'),
(8,  CURRENT_TIMESTAMP - INTERVAL '8 days',  'shipped',    129.99, '753 Spruce Ave, Westminster, CO 80031'),
(9,  CURRENT_TIMESTAMP - INTERVAL '5 days',  'processing',  79.99, '852 Willow Rd, Arvada, CO 80002'),
(10, CURRENT_TIMESTAMP - INTERVAL '3 days',  'pending',     44.99, '951 Aspen Dr, Centennial, CO 80112'),
(2,  CURRENT_TIMESTAMP - INTERVAL '2 days',  'pending',    299.99, '456 Oak Ave, Boulder, CO 80301'),
(3,  CURRENT_TIMESTAMP - INTERVAL '1 day',   'pending',    189.98, '789 Pine Rd, Fort Collins, CO 80521'),
(4,  CURRENT_TIMESTAMP - INTERVAL '6 hours', 'pending',    349.97, '321 Elm St, Colorado Springs, CO 80903'),
(5,  CURRENT_TIMESTAMP - INTERVAL '2 hours', 'pending',     99.98, '654 Maple Dr, Aurora, CO 80011');

INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price) VALUES
(1,  1,  2, 149.99, 299.98),
(1,  3,  1,  79.99,  79.99),
(1,  10, 2,  39.99,  79.98),
(2,  2,  2,  89.99, 179.98),
(2,  6,  2,  49.99,  99.98),
(3,  5,  2,  59.99, 119.98),
(3,  10, 1,  39.99,  39.99),
(4,  4,  1, 199.99, 199.99),
(4,  9,  1, 129.99, 129.99),
(4,  11, 1,  99.99,  99.99),
(5,  8,  1, 249.99, 249.99),
(6,  12, 1, 189.99, 189.99),
(7,  11, 1,  99.99,  99.99),
(8,  1,  2, 149.99, 299.98),
(8,  8,  1, 249.99, 249.99),
(9,  9,  1, 129.99, 129.99),
(10, 3,  1,  79.99,  79.99),
(11, 13, 1,  44.99,  44.99),
(12, 7,  1, 299.99, 299.99),
(13, 2,  1,  89.99,  89.99),
(13, 11, 1,  99.99,  99.99);

INSERT INTO inventory (product_id, warehouse_location, quantity_on_hand, reorder_point, last_restocked) VALUES
(1,  'Denver-A1',  50, 20, CURRENT_TIMESTAMP - INTERVAL '5 days'),
(2,  'Denver-A2',  75, 30, CURRENT_TIMESTAMP - INTERVAL '3 days'),
(3,  'Denver-B1',  30, 15, CURRENT_TIMESTAMP - INTERVAL '7 days'),
(4,  'Denver-B2',  25, 10, CURRENT_TIMESTAMP - INTERVAL '10 days'),
(5,  'Denver-C1', 100, 40, CURRENT_TIMESTAMP - INTERVAL '2 days'),
(6,  'Denver-C2',  80, 35, CURRENT_TIMESTAMP - INTERVAL '4 days'),
(7,  'Boulder-A1', 15,  5, CURRENT_TIMESTAMP - INTERVAL '15 days'),
(8,  'Boulder-A2', 20,  8, CURRENT_TIMESTAMP - INTERVAL '12 days'),
(9,  'Boulder-B1', 40, 15, CURRENT_TIMESTAMP - INTERVAL '6 days'),
(10, 'Boulder-B2', 60, 25, CURRENT_TIMESTAMP - INTERVAL '8 days'),
(11, 'Boulder-C1', 35, 15, CURRENT_TIMESTAMP - INTERVAL '9 days'),
(12, 'Springs-A1', 20,  8, CURRENT_TIMESTAMP - INTERVAL '11 days'),
(13, 'Springs-A2', 70, 30, CURRENT_TIMESTAMP - INTERVAL '1 day'),
(14, 'Springs-B1', 45, 20, CURRENT_TIMESTAMP - INTERVAL '13 days'),
(15, 'Springs-B2', 90, 40, CURRENT_TIMESTAMP - INTERVAL '14 days');

-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------
CREATE INDEX idx_orders_customer_id     ON orders(customer_id);
CREATE INDEX idx_orders_order_date      ON orders(order_date);
CREATE INDEX idx_order_items_order_id   ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_inventory_product_id   ON inventory(product_id);
CREATE INDEX idx_products_category      ON products(category);

-- ----------------------------------------------------------------------------
-- Reporting view
-- ----------------------------------------------------------------------------
CREATE VIEW order_summary AS
SELECT
    o.order_id,
    o.order_date,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email,
    o.status,
    o.total_amount,
    COUNT(oi.item_id) AS item_count,
    SUM(oi.quantity)  AS total_items
FROM orders o
JOIN customers c        ON o.customer_id = c.customer_id
LEFT JOIN order_items oi ON o.order_id   = oi.order_id
GROUP BY o.order_id, o.order_date, c.first_name, c.last_name,
         c.email, o.status, o.total_amount;

-- ----------------------------------------------------------------------------
-- Summary (deterministic on every run)
-- ----------------------------------------------------------------------------
SELECT 'Database initialization complete!' AS status;
SELECT (SELECT COUNT(*) FROM customers)   AS customers,
       (SELECT COUNT(*) FROM products)    AS products,
       (SELECT COUNT(*) FROM orders)      AS orders,
       (SELECT COUNT(*) FROM order_items) AS order_items,
       (SELECT COUNT(*) FROM inventory)   AS inventory;
