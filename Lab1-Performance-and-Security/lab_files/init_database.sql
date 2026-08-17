-- ============================================================================
-- Students MIS Database Initialization Script (Performance & Security Lab)
-- ============================================================================
-- Creates the schema and seed data used by the Performance & Security lab.
-- Deliberately omits foreign keys and secondary indexes: the lab teaches
-- students to discover and fix the resulting performance problems.
--
-- Idempotent: safe to re-run (drops and recreates all lab objects).
-- Tested on: PostgreSQL 15 and 16
-- Run as:    sudo -u postgres psql -d studentsmis -f init_database.sql
-- ============================================================================

-- Drop existing lab objects if they exist (dependency order handled by CASCADE)
DROP TABLE IF EXISTS grades CASCADE;
DROP TABLE IF EXISTS enrollments CASCADE;
DROP TABLE IF EXISTS courses CASCADE;
DROP TABLE IF EXISTS students CASCADE;

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------
CREATE TABLE students (
    student_id    SERIAL PRIMARY KEY,
    student_name  VARCHAR(255) NOT NULL,
    email         VARCHAR(255) UNIQUE NOT NULL,
    phone         VARCHAR(50),
    address       TEXT,
    city          VARCHAR(100),
    state         VARCHAR(50),
    zip_code      VARCHAR(20),
    country       VARCHAR(100) DEFAULT 'USA',
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- NOTE: no "departments" table in Lab 1 — department is free text here,
-- mirroring how the original schema's "category" was never a real dimension
-- table either. Lab 2 introduces a real departments table.
CREATE TABLE courses (
    course_id      SERIAL PRIMARY KEY,
    course_name    VARCHAR(255) NOT NULL,
    department     VARCHAR(100),
    credit_hours   DECIMAL(4,2) NOT NULL,
    seats_available INTEGER DEFAULT 0,
    description    TEXT,
    course_code    VARCHAR(50) UNIQUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- NOTE: no foreign key on student_id — intentional for the performance demo
CREATE TABLE enrollments (
    enrollment_id    SERIAL PRIMARY KEY,
    student_id       INTEGER NOT NULL,
    enrollment_date  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR(50) DEFAULT 'active',
    tuition_amount   DECIMAL(10,2),
    notes            TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- NOTE: no foreign keys — intentional for the performance demo
CREATE TABLE grades (
    grade_id      SERIAL PRIMARY KEY,
    enrollment_id INTEGER NOT NULL,
    course_id     INTEGER NOT NULL,
    credits       INTEGER NOT NULL,
    grade_points  DECIMAL(10,2) NOT NULL,
    extra_credit  DECIMAL(5,2) DEFAULT 0
);

-- ----------------------------------------------------------------------------
-- Seed data
-- ----------------------------------------------------------------------------

-- 5,000 students. A single random draw picks the city/state pair so the
-- geography is consistent (Denver is always CO, Portland always OR, etc.).
INSERT INTO students (student_name, email, phone, address, city, state, zip_code)
SELECT
    'Student ' || gs,
    'student' || gs || '@studentsmis.edu',
    '555-' || LPAD(gs::text, 4, '0'),
    gs || ' Main Street',
    (ARRAY['Denver','Portland','Seattle','Austin'])[bucket],
    (ARRAY['CO','OR','WA','TX'])[bucket],
    LPAD((random() * 99999)::integer::text, 5, '0')
FROM (
    SELECT gs, 1 + floor(random() * 4)::int AS bucket
    FROM generate_series(1, 5000) AS gs
) AS seed;

-- 100 courses
INSERT INTO courses (course_name, department, credit_hours, seats_available, course_code)
SELECT
    'Course ' || gs,
    CASE WHEN random() < 0.25 THEN 'Computer Science'
         WHEN random() < 0.50 THEN 'Mathematics'
         WHEN random() < 0.75 THEN 'Biology'
         ELSE 'English'
    END,
    (1 + floor(random() * 4))::decimal(4,2),
    (random() * 200)::integer,
    'CRS-' || LPAD(gs::text, 6, '0')
FROM generate_series(1, 100) AS gs;

-- 20,000 enrollments spread across the last year
INSERT INTO enrollments (student_id, enrollment_date, status, tuition_amount, notes)
SELECT
    (random() * 4999 + 1)::integer,
    CURRENT_DATE - (random() * 365)::integer * INTERVAL '1 day',
    CASE WHEN random() < 0.70 THEN 'completed'
         WHEN random() < 0.90 THEN 'active'
         WHEN random() < 0.95 THEN 'pending'
         ELSE 'withdrawn'
    END,
    (random() * 1000 + 10)::decimal(10,2),
    repeat('Enrollment data padding for bloat. ', 5)
FROM generate_series(1, 20000);

-- 50,000 grade line items
INSERT INTO grades (enrollment_id, course_id, credits, grade_points)
SELECT
    (random() * 19999 + 1)::integer,
    (random() * 99 + 1)::integer,
    (random() * 5 + 1)::integer,
    (random() * 500 + 10)::decimal(10,2)
FROM generate_series(1, 50000);

-- Recompute enrollment totals for the first half of the enrollments (kept
-- partial on purpose — a full correlated UPDATE over 20k rows with no
-- indexes is slow, and half is enough for realistic data).
UPDATE enrollments e
SET tuition_amount = (
    SELECT COALESCE(SUM(credits * grade_points * (1 - extra_credit/100)), 0)
    FROM grades g
    WHERE g.enrollment_id = e.enrollment_id
)
WHERE enrollment_id <= 10000;

-- ----------------------------------------------------------------------------
-- Generate table bloat (dead tuples) for the maintenance exercises
-- ----------------------------------------------------------------------------

-- Insert 10,000 throwaway enrollments, then delete them
INSERT INTO enrollments (student_id, enrollment_date, status, tuition_amount, notes)
SELECT student_id, enrollment_date, 'deleted', tuition_amount, 'DELETED ROW FOR BLOAT'
FROM enrollments
WHERE enrollment_id <= 10000;

DELETE FROM enrollments WHERE notes = 'DELETED ROW FOR BLOAT';

-- Insert 2,500 duplicate students, then delete them
INSERT INTO students (student_name, email, phone, address, city, state, zip_code)
SELECT student_name || '_dup', 'dup_' || email, phone, address, city, state, zip_code
FROM students
WHERE student_id <= 2500;

DELETE FROM students WHERE student_name LIKE '%\_dup';

-- Widen some existing rows so the tables occupy realistic space
UPDATE students
SET address = address || ' - ' || repeat('Extra data for size. ', 3)
WHERE student_id <= 1000;

UPDATE enrollments
SET notes = notes || ' - ' || repeat('Enrollment record padding. ', 3)
WHERE enrollment_id <= 5000;

-- ----------------------------------------------------------------------------
-- Reporting function used in the performance exercises
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION slow_student_report(days_back INTEGER DEFAULT 90)
RETURNS TABLE(
    student_name VARCHAR,
    total_enrollments BIGINT,
    total_tuition     NUMERIC,
    avg_tuition       NUMERIC,
    last_enrollment   TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.student_name,
        COUNT(e.enrollment_id),
        SUM(e.tuition_amount),
        AVG(e.tuition_amount),
        MAX(e.enrollment_date)
    FROM students s
    LEFT JOIN enrollments e ON s.student_id = e.student_id
    WHERE e.enrollment_date > CURRENT_DATE - (days_back || ' days')::INTERVAL
      AND e.status = 'completed'
    GROUP BY s.student_name
    HAVING COUNT(e.enrollment_id) > 0
    ORDER BY SUM(e.tuition_amount) DESC;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Refresh planner statistics
-- ----------------------------------------------------------------------------
ANALYZE students;
ANALYZE courses;
ANALYZE enrollments;
ANALYZE grades;

-- ----------------------------------------------------------------------------
-- Summary
-- ----------------------------------------------------------------------------
SELECT 'Database initialization complete!' AS status;
SELECT (SELECT COUNT(*) FROM students)    AS students,
       (SELECT COUNT(*) FROM courses)     AS courses,
       (SELECT COUNT(*) FROM enrollments) AS enrollments,
       (SELECT COUNT(*) FROM grades)      AS grades;
