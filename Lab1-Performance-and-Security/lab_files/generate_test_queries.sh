#!/bin/bash
# ============================================================================
# generate_test_queries.sh — run a representative workload to populate
# pg_stat_statements and the table/index statistics views.
# Usage: ./generate_test_queries.sh [database_name]   (default: carvedrock)
# Tested on: PostgreSQL 15 and 16
# ============================================================================
set -u

DB="${1:-carvedrock}"

echo "Generating test queries against '${DB}' to simulate workload..."

sudo -u postgres psql -d "${DB}" -q -v ON_ERROR_STOP=0 <<'EOF'
-- Simple counts
SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM products;

-- Join query
SELECT c.customer_name, COUNT(o.order_id)
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_name
LIMIT 100;

-- Aggregation over a date range
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(*)          AS orders,
    SUM(total_amount) AS revenue
FROM orders
WHERE order_date > CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE_TRUNC('month', order_date);

-- Subquery with HAVING
SELECT customer_name
FROM customers
WHERE customer_id IN (
    SELECT customer_id
    FROM orders
    WHERE total_amount > 500
    GROUP BY customer_id
    HAVING COUNT(*) > 5
);

-- Multi-table join with aggregation
SELECT
    p.product_name,
    p.category,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    SUM(oi.quantity)              AS total_sold
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o       ON oi.order_id  = o.order_id
WHERE o.order_date > CURRENT_DATE - INTERVAL '30 days'
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_sold DESC
LIMIT 20;

-- Correlated subquery (slow without indexes)
SELECT *
FROM orders o1
WHERE total_amount > (
    SELECT AVG(total_amount)
    FROM orders o2
    WHERE o2.customer_id = o1.customer_id
);
EOF

echo "Test queries completed."
