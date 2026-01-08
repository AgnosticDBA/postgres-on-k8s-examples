-- Sample data for testing and demonstration
-- This file contains realistic test data for the demo application

-- Insert sample users
INSERT INTO users (username, email, password_hash) VALUES 
    ('alice_johnson', 'alice@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6QJw/2Ej7W'),
    ('bob_smith', 'bob@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6QJw/2Ej7W'),
    ('charlie_brown', 'charlie@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6QJw/2Ej7W'),
    ('diana_prince', 'diana@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6QJw/2Ej7W'),
    ('eve_wilson', 'eve@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6QJw/2Ej7W')
ON CONFLICT (username) DO NOTHING;

-- Insert sample categories
INSERT INTO categories (name, color) VALUES 
    ('Work', '#dc3545'),
    ('Personal', '#28a745'),
    ('Shopping', '#ffc107'),
    ('Health', '#17a2b8'),
    ('Learning', '#6f42c1'),
    ('Finance', '#fd7e14'),
    ('Home', '#20c997'),
    ('Social', '#e83e8c')
ON CONFLICT (name) DO NOTHING;

-- Get user IDs and category IDs for task insertion
DO $$
DECLARE
    alice_id UUID;
    bob_id UUID;
    charlie_id UUID;
    diana_id UUID;
    eve_id UUID;
    work_id UUID;
    personal_id UUID;
    shopping_id UUID;
    health_id UUID;
    learning_id UUID;
    finance_id UUID;
    home_id UUID;
    social_id UUID;
BEGIN
    -- Get user IDs
    SELECT id INTO alice_id FROM users WHERE username = 'alice_johnson';
    SELECT id INTO bob_id FROM users WHERE username = 'bob_smith';
    SELECT id INTO charlie_id FROM users WHERE username = 'charlie_brown';
    SELECT id INTO diana_id FROM users WHERE username = 'diana_prince';
    SELECT id INTO eve_id FROM users WHERE username = 'eve_wilson';
    
    -- Get category IDs
    SELECT id INTO work_id FROM categories WHERE name = 'Work';
    SELECT id INTO personal_id FROM categories WHERE name = 'Personal';
    SELECT id INTO shopping_id FROM categories WHERE name = 'Shopping';
    SELECT id INTO health_id FROM categories WHERE name = 'Health';
    SELECT id INTO learning_id FROM categories WHERE name = 'Learning';
    SELECT id INTO finance_id FROM categories WHERE name = 'Finance';
    SELECT id INTO home_id FROM categories WHERE name = 'Home';
    SELECT id INTO social_id FROM categories WHERE name = 'Social';
    
    -- Insert sample tasks
    INSERT INTO tasks (title, description, status, priority, user_id, due_date) VALUES 
        ('Complete quarterly report', 'Finish the Q4 financial report and submit to management', 'in_progress', 'high', alice_id, CURRENT_TIMESTAMP + INTERVAL '2 days'),
        ('Buy groceries', 'Get milk, eggs, bread, vegetables, and fruits for the week', 'pending', 'medium', bob_id, CURRENT_TIMESTAMP + INTERVAL '1 day'),
        ('Gym workout', 'Upper body strength training - chest, shoulders, triceps', 'completed', 'medium', charlie_id, CURRENT_TIMESTAMP - INTERVAL '1 hour'),
        ('Study Kubernetes', 'Complete chapter 5 of Kubernetes documentation', 'in_progress', 'medium', diana_id, CURRENT_TIMESTAMP + INTERVAL '3 days'),
        ('Pay utility bills', 'Pay electricity, water, and internet bills', 'pending', 'high', eve_id, CURRENT_TIMESTAMP + INTERVAL '5 hours'),
        ('Team standup meeting', 'Daily sync with the development team', 'completed', 'low', alice_id, CURRENT_TIMESTAMP - INTERVAL '3 hours'),
        ('Read technical book', 'Continue reading "Designing Data-Intensive Applications"', 'pending', 'low', bob_id, CURRENT_TIMESTAMP + INTERVAL '1 week'),
        ('Doctor appointment', 'Annual health checkup', 'pending', 'high', charlie_id, CURRENT_TIMESTAMP + INTERVAL '1 day'),
        ('Code review', 'Review pull requests from team members', 'in_progress', 'medium', diana_id, CURRENT_TIMESTAMP + INTERVAL '4 hours'),
        ('Clean apartment', 'Deep clean living room and kitchen', 'pending', 'low', eve_id, CURRENT_TIMESTAMP + INTERVAL '2 days'),
        ('Prepare presentation', 'Create slides for client meeting', 'pending', 'urgent', alice_id, CURRENT_TIMESTAMP + INTERVAL '1 day'),
        ('Buy birthday gift', 'Get gift for friend''s birthday party', 'pending', 'medium', bob_id, CURRENT_TIMESTAMP + INTERVAL '3 days'),
        ('Yoga class', 'Evening yoga session at the community center', 'completed', 'medium', charlie_id, CURRENT_TIMESTAMP - INTERVAL '2 hours'),
        ('Update portfolio', 'Add recent projects to personal portfolio website', 'pending', 'low', diana_id, CURRENT_TIMESTAMP + INTERVAL '1 week'),
        ('Call parents', 'Weekly catch-up call with family', 'pending', 'medium', eve_id, CURRENT_TIMESTAMP + INTERVAL '2 days')
    ON CONFLICT DO NOTHING;
    
    -- Assign categories to tasks (simplified approach)
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%report%' OR t.title LIKE '%meeting%' OR t.title LIKE '%code review%'
    AND c.name = 'Work'
    ON CONFLICT DO NOTHING;
    
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%groceries%' OR t.title LIKE '%gift%'
    AND c.name = 'Shopping'
    ON CONFLICT DO NOTHING;
    
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%gym%' OR t.title LIKE '%doctor%' OR t.title LIKE '%yoga%'
    AND c.name = 'Health'
    ON CONFLICT DO NOTHING;
    
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%study%' OR t.title LIKE '%book%' OR t.title LIKE '%portfolio%'
    AND c.name = 'Learning'
    ON CONFLICT DO NOTHING;
    
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%bills%' OR t.title LIKE '%presentation%'
    AND c.name = 'Finance'
    ON CONFLICT DO NOTHING;
    
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%clean%' OR t.title LIKE '%apartment%'
    AND c.name = 'Home'
    ON CONFLICT DO NOTHING;
    
    INSERT INTO task_categories (task_id, category_id) 
    SELECT t.id, c.id 
    FROM tasks t, categories c 
    WHERE t.title LIKE '%call%' OR t.title LIKE '%parents%'
    AND c.name = 'Personal'
    ON CONFLICT DO NOTHING;
END $$;