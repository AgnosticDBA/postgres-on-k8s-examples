-- Sample database schema for demo application
-- This file creates tables and initial data for a simple task management system

-- Create database if it doesn't exist
CREATE DATABASE IF NOT EXISTS demo_app;

-- Connect to the demo database
\c demo_app;

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create tasks table
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed')),
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    color VARCHAR(7) DEFAULT '#007bff',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create task_categories junction table
CREATE TABLE IF NOT EXISTS task_categories (
    task_id INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
    category_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, category_id)
);

-- Insert sample data
INSERT INTO users (username, email) VALUES 
    ('john_doe', 'john@example.com'),
    ('jane_smith', 'jane@example.com'),
    ('bob_wilson', 'bob@example.com')
ON CONFLICT (username) DO NOTHING;

INSERT INTO categories (name, color) VALUES 
    ('Work', '#dc3545'),
    ('Personal', '#28a745'),
    ('Shopping', '#ffc107'),
    ('Health', '#17a2b8')
ON CONFLICT (name) DO NOTHING;

INSERT INTO tasks (title, description, status, user_id) VALUES 
    ('Complete project proposal', 'Finish the Q4 project proposal document', 'in_progress', 1),
    ('Buy groceries', 'Milk, eggs, bread, and vegetables', 'pending', 2),
    ('Gym workout', 'Upper body strength training', 'completed', 3),
    ('Team meeting', 'Weekly sync with the development team', 'pending', 1),
    ('Code review', 'Review pull requests from team members', 'in_progress', 2)
ON CONFLICT DO NOTHING;

-- Assign categories to tasks
INSERT INTO task_categories (task_id, category_id) VALUES 
    (1, 1), (2, 3), (3, 4), (4, 1), (5, 1)
ON CONFLICT DO NOTHING;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at);

-- Create a view for task summaries
CREATE OR REPLACE VIEW task_summary AS
SELECT 
    t.id,
    t.title,
    t.status,
    u.username,
    ARRAY_AGG(c.name) as categories,
    t.created_at
FROM tasks t
JOIN users u ON t.user_id = u.id
LEFT JOIN task_categories tc ON t.id = tc.task_id
LEFT JOIN categories c ON tc.category_id = c.id
GROUP BY t.id, t.title, t.status, u.username, t.created_at
ORDER BY t.created_at DESC;

-- Grant permissions to the demo user
CREATE USER IF NOT EXISTS demo_user WITH PASSWORD 'demo_password';
GRANT CONNECT ON DATABASE demo_app TO demo_user;
GRANT USAGE ON SCHEMA public TO demo_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO demo_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO demo_user;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO demo_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO demo_user;