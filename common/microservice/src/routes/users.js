const express = require('express');
const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();

const userSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(50).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(6).required()
});

const updateUserSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(50),
  email: Joi.string().email()
}).min(1);

// GET /api/users - Get all users
router.get('/', async (req, res) => {
  try {
    const { page = 1, limit = 10, search } = req.query;
    const offset = (page - 1) * limit;
    
    let query = 'SELECT id, username, email, created_at, updated_at FROM users';
    let countQuery = 'SELECT COUNT(*) FROM users';
    const params = [];
    
    if (search) {
      query += ' WHERE username ILIKE $1 OR email ILIKE $1';
      countQuery += ' WHERE username ILIKE $1 OR email ILIKE $1';
      params.push(`%${search}%`);
    }
    
    query += ' ORDER BY created_at DESC LIMIT $' + (params.length + 1) + ' OFFSET $' + (params.length + 2);
    params.push(limit, offset);
    
    const [users, countResult] = await Promise.all([
      req.db.query(query, params),
      req.db.query(countQuery, search ? [`%${search}%`] : [])
    ]);
    
    const total = parseInt(countResult.rows[0].count);
    
    res.json({
      users: users.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit)
      }
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// GET /api/users/:id - Get user by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await req.db.query(
      'SELECT id, username, email, created_at, updated_at FROM users WHERE id = $1',
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching user:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// POST /api/users - Create new user
router.post('/', async (req, res) => {
  try {
    const { error, value } = userSchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    
    const { username, email, password } = value;
    const bcrypt = require('bcryptjs');
    const passwordHash = await bcrypt.hash(password, 10);
    
    const result = await req.db.query(
      'INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email, created_at, updated_at',
      [username, email, passwordHash]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating user:', error);
    
    if (error.code === '23505') {
      return res.status(409).json({ error: 'Username or email already exists' });
    }
    
    res.status(500).json({ error: 'Failed to create user' });
  }
});

// PUT /api/users/:id - Update user
router.put('/:id', async (req, res) => {
  try {
    const { error, value } = updateUserSchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    
    const { id } = req.params;
    const updates = [];
    const params = [];
    let paramIndex = 1;
    
    if (value.username) {
      updates.push(`username = $${paramIndex++}`);
      params.push(value.username);
    }
    
    if (value.email) {
      updates.push(`email = $${paramIndex++}`);
      params.push(value.email);
    }
    
    updates.push(`updated_at = CURRENT_TIMESTAMP`);
    params.push(id);
    
    const query = `UPDATE users SET ${updates.join(', ')} WHERE id = $${paramIndex} RETURNING id, username, email, created_at, updated_at`;
    
    const result = await req.db.query(query, params);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating user:', error);
    
    if (error.code === '23505') {
      return res.status(409).json({ error: 'Username or email already exists' });
    }
    
    res.status(500).json({ error: 'Failed to update user' });
  }
});

// DELETE /api/users/:id - Delete user
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await req.db.query('DELETE FROM users WHERE id = $1 RETURNING id', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.status(204).send();
  } catch (error) {
    console.error('Error deleting user:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// GET /api/users/:id/tasks - Get user's tasks
router.get('/:id/tasks', async (req, res) => {
  try {
    const { id } = req.params;
    const { status, page = 1, limit = 10 } = req.query;
    const offset = (page - 1) * limit;
    
    // Check if user exists
    const userCheck = await req.db.query('SELECT id FROM users WHERE id = $1', [id]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    let query = `
      SELECT t.id, t.title, t.description, t.status, t.priority, t.due_date, t.created_at, t.updated_at,
             ARRAY_AGG(c.name) as categories
      FROM tasks t
      LEFT JOIN task_categories tc ON t.id = tc.task_id
      LEFT JOIN categories c ON tc.category_id = c.id
      WHERE t.user_id = $1
    `;
    const params = [id];
    
    if (status) {
      query += ' AND t.status = $2';
      params.push(status);
    }
    
    query += ` GROUP BY t.id, t.title, t.description, t.status, t.priority, t.due_date, t.created_at, t.updated_at
               ORDER BY t.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);
    
    const [tasks, countResult] = await Promise.all([
      req.db.query(query, params),
      req.db.query('SELECT COUNT(*) FROM tasks WHERE user_id = $1' + (status ? ' AND status = $2' : ''), status ? [id, status] : [id])
    ]);
    
    const total = parseInt(countResult.rows[0].count);
    
    res.json({
      tasks: tasks.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit)
      }
    });
  } catch (error) {
    console.error('Error fetching user tasks:', error);
    res.status(500).json({ error: 'Failed to fetch user tasks' });
  }
});

module.exports = router;