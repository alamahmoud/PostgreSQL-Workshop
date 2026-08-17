-- ============================================================================
-- Students MIS Production Database Initialization (Disaster Recovery Lab)
-- ============================================================================
-- Creates the schema and seed data for the disaster-recovery / failover lab.
--
-- Idempotent: safe to re-run — it drops and recreates every lab object, so
-- row counts are always deterministic:
--   students = 10, departments = 8, courses = 15, enrollments = 15, grades = 21
--
-- Tested on: PostgreSQL 15 and 16
-- Run as:    sudo -u postgres psql -d studentsmis_prod -f init_database.sql
-- ============================================================================

-- Drop existing lab objects (order handled by CASCADE)
DROP VIEW  IF EXISTS enrollment_summary;
DROP TABLE IF EXISTS grades      CASCADE;
DROP TABLE IF EXISTS enrollments CASCADE;
DROP TABLE IF EXISTS courses     CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS students    CASCADE;

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------
CREATE TABLE students (
    student_id  SERIAL PRIMARY KEY,
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

CREATE TABLE departments (
    department_id   SERIAL PRIMARY KEY,
    department_name VARCHAR(100) UNIQUE NOT NULL,
    building        VARCHAR(50),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE courses (
    course_id       SERIAL PRIMARY KEY,
    course_name     VARCHAR(200) NOT NULL,
    department_id   INTEGER REFERENCES departments(department_id),
    description     TEXT,
    credit_hours    DECIMAL(4,2),
    seats_available INTEGER DEFAULT 0,
    course_code     VARCHAR(50) UNIQUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE enrollments (
    enrollment_id   SERIAL PRIMARY KEY,
    student_id      INTEGER REFERENCES students(student_id),
    enrollment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status          VARCHAR(20) DEFAULT 'pending',
    tuition_amount  DECIMAL(10,2),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE grades (
    grade_id       SERIAL PRIMARY KEY,
    enrollment_id  INTEGER REFERENCES enrollments(enrollment_id),
    course_id      INTEGER REFERENCES courses(course_id),
    credits        INTEGER NOT NULL,
    grade_points   DECIMAL(10,2),
    quality_points DECIMAL(10,2),
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- Seed data
-- ----------------------------------------------------------------------------
INSERT INTO students (first_name, last_name, email, phone, address, city, state, zip_code) VALUES
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

INSERT INTO departments (department_name, building) VALUES
('Computer Science', 'Turing Hall'),
('Mathematics',      'Euler Hall'),
('Biology',          'Darwin Hall'),
('English',          'Austen Hall'),
('History',          'Herodotus Hall'),
('Physics',          'Newton Hall'),
('Chemistry',        'Curie Hall'),
('Business',         'Drucker Hall');

INSERT INTO courses (course_name, department_id, description, credit_hours, seats_available, course_code) VALUES
('Intro to Programming',      1, 'Foundations of programming and problem solving',      3.00, 50, 'CS-101'),
('Data Structures',           1, 'Core data structures and algorithm analysis',          4.00, 75, 'CS-201'),
('Calculus I',                2, 'Limits, derivatives, and integrals',                   4.00, 30, 'MA-101'),
('Linear Algebra',            2, 'Vector spaces, matrices, and linear transformations',  3.00, 25, 'MA-210'),
('General Biology',           3, 'Introduction to cellular and molecular biology',       4.00, 100,'BI-101'),
('Genetics',                  3, 'Principles of heredity and gene expression',           3.00, 80, 'BI-220'),
('World Literature',          4, 'Survey of major works across world literary traditions', 3.00, 15, 'EN-150'),
('American History',          5, 'Survey of United States history',                      3.00, 20, 'HI-110'),
('Ancient Civilizations',     5, 'Survey of early world civilizations',                  3.00, 40, 'HI-205'),
('Environmental Science',     6, 'Introduction to environmental systems and policy',     3.00, 60, 'PH-115'),
('Classical Mechanics',       6, 'Motion, forces, and energy',                           4.00, 35, 'PH-210'),
('Organic Chemistry',         7, 'Structure and reactivity of organic compounds',        4.00, 20, 'CH-220'),
('General Chemistry',         7, 'Foundations of chemical principles',                   4.00, 70, 'CH-101'),
('Principles of Marketing',   8, 'Introduction to marketing strategy and consumer behavior', 3.00, 45, 'BU-140'),
('Financial Accounting',      8, 'Foundations of financial statement preparation',       3.00, 90, 'BU-101');

INSERT INTO enrollments (student_id, enrollment_date, status, tuition_amount) VALUES
(1,  CURRENT_TIMESTAMP - INTERVAL '30 days', 'completed',    449.97),
(2,  CURRENT_TIMESTAMP - INTERVAL '25 days', 'completed',    289.98),
(3,  CURRENT_TIMESTAMP - INTERVAL '20 days', 'completed',    159.98),
(4,  CURRENT_TIMESTAMP - INTERVAL '18 days', 'active',       399.98),
(5,  CURRENT_TIMESTAMP - INTERVAL '15 days', 'completed',    249.99),
(1,  CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed',    189.99),
(6,  CURRENT_TIMESTAMP - INTERVAL '12 days', 'in_progress',   99.99),
(7,  CURRENT_TIMESTAMP - INTERVAL '10 days', 'completed',    549.96),
(8,  CURRENT_TIMESTAMP - INTERVAL '8 days',  'active',       129.99),
(9,  CURRENT_TIMESTAMP - INTERVAL '5 days',  'in_progress',   79.99),
(10, CURRENT_TIMESTAMP - INTERVAL '3 days',  'pending',       44.99),
(2,  CURRENT_TIMESTAMP - INTERVAL '2 days',  'pending',      299.99),
(3,  CURRENT_TIMESTAMP - INTERVAL '1 day',   'pending',      189.98),
(4,  CURRENT_TIMESTAMP - INTERVAL '6 hours', 'pending',      349.97),
(5,  CURRENT_TIMESTAMP - INTERVAL '2 hours', 'pending',       99.98);

INSERT INTO grades (enrollment_id, course_id, credits, grade_points, quality_points) VALUES
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

-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------
CREATE INDEX idx_enrollments_student_id      ON enrollments(student_id);
CREATE INDEX idx_enrollments_enrollment_date ON enrollments(enrollment_date);
CREATE INDEX idx_grades_enrollment_id        ON grades(enrollment_id);
CREATE INDEX idx_grades_course_id            ON grades(course_id);
CREATE INDEX idx_courses_department_id       ON courses(department_id);

-- ----------------------------------------------------------------------------
-- Reporting view
-- ----------------------------------------------------------------------------
CREATE VIEW enrollment_summary AS
SELECT
    e.enrollment_id,
    e.enrollment_date,
    s.first_name || ' ' || s.last_name AS student_name,
    s.email,
    e.status,
    e.tuition_amount,
    COUNT(g.grade_id) AS grade_count,
    SUM(g.credits)     AS total_credits
FROM enrollments e
JOIN students s     ON e.student_id = s.student_id
LEFT JOIN grades g  ON e.enrollment_id = g.enrollment_id
GROUP BY e.enrollment_id, e.enrollment_date, s.first_name, s.last_name,
         s.email, e.status, e.tuition_amount;

-- ----------------------------------------------------------------------------
-- Summary (deterministic on every run)
-- ----------------------------------------------------------------------------
SELECT 'Database initialization complete!' AS status;
SELECT (SELECT COUNT(*) FROM students)    AS students,
       (SELECT COUNT(*) FROM departments) AS departments,
       (SELECT COUNT(*) FROM courses)     AS courses,
       (SELECT COUNT(*) FROM enrollments) AS enrollments,
       (SELECT COUNT(*) FROM grades)      AS grades;
