#!/bin/bash
# ============================================================================
# generate_test_queries.sh — run a representative workload to populate
# pg_stat_statements and the table/index statistics views.
# Usage: ./generate_test_queries.sh [database_name]   (default: studentsmis)
# Tested on: PostgreSQL 15 and 16
# ============================================================================
set -u

DB="${1:-studentsmis}"

echo "Generating test queries against '${DB}' to simulate workload..."

sudo -u postgres psql -d "${DB}" -q -v ON_ERROR_STOP=0 <<'EOF'
-- Simple counts
SELECT COUNT(*) FROM students;
SELECT COUNT(*) FROM enrollments;
SELECT COUNT(*) FROM courses;

-- Join query
SELECT s.student_name, COUNT(e.enrollment_id)
FROM students s
LEFT JOIN enrollments e ON s.student_id = e.student_id
GROUP BY s.student_name
LIMIT 100;

-- Aggregation over a date range
SELECT
    DATE_TRUNC('month', enrollment_date) AS month,
    COUNT(*)              AS enrollments,
    SUM(tuition_amount)   AS revenue
FROM enrollments
WHERE enrollment_date > CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE_TRUNC('month', enrollment_date);

-- Subquery with HAVING
SELECT student_name
FROM students
WHERE student_id IN (
    SELECT student_id
    FROM enrollments
    WHERE tuition_amount > 500
    GROUP BY student_id
    HAVING COUNT(*) > 5
);

-- Multi-table join with aggregation
SELECT
    c.course_name,
    c.department,
    COUNT(DISTINCT e.student_id) AS unique_students,
    SUM(g.credits)                AS total_credits
FROM courses c
JOIN grades g       ON c.course_id = g.course_id
JOIN enrollments e  ON g.enrollment_id = e.enrollment_id
WHERE e.enrollment_date > CURRENT_DATE - INTERVAL '30 days'
GROUP BY c.course_id, c.course_name, c.department
ORDER BY total_credits DESC
LIMIT 20;

-- Correlated subquery (slow without indexes)
SELECT *
FROM enrollments e1
WHERE tuition_amount > (
    SELECT AVG(tuition_amount)
    FROM enrollments e2
    WHERE e2.student_id = e1.student_id
);
EOF

echo "Test queries completed."
