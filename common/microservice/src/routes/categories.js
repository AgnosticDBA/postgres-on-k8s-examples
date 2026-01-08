const express = require('express');
const Joi = require('joi');

const router = express.Router();

const categorySchema = Joi.object({
  name: Joi.string().min(1).max(50).required(),
  color: Joi.string().pattern(/^#[0-9A-Fa-f]{6}$/).default('#007bff')
});

// GET /api/categories - Get all categories
router.get('/', async (req, res) => {
  try {
    const result = await req.db.query(`
      SELECT c.id, c.name, c.color, c.created_at,
             COUNT(tc.task_id) as task_count
      FROM categories c
      LEFT JOIN task_categories tc ON c.id = tc.category_id
      GROUP BY c.id, c.name, c.color, c.created_at
      ORDER BY c.name
    `);
    
    res.json({ categories: result.rows });
  } catch (error) {
    console.error('Error fetching categories:', error);
    res.status(500).json({ error: 'Failed to fetch categories' });
  }
});

// GET /api/categories/:id - Get category by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await req.db.query(`
      SELECT c.id, c.name, c.color, c.created_at,
             COUNT(tc.task_id) as task_count
      FROM categories c
      LEFT JOIN task_categories tc ON c.id = tc.category_id
      WHERE c.id = $1
      GROUP BY c.id, c.name, c.color, c.created_at
    `, [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Category not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching category:', error);
    res.status(500).json({ error: 'Failed to fetch category' });
  }
});

// POST /api/categories - Create new category
router.post('/', async (req, res) => {
  try {
    const { error, value } = categorySchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    
    const { name, color } = value;
    
    const result = await req.db.query(
      'INSERT INTO categories (name, color) VALUES ($1, $2) RETURNING id, name, color, created_at',
      [name, color]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating category:', error);
    
    if (error.code === '23505') {
      return res.status(409).json({ error: 'Category name already exists' });
    }
    
    res.status(500).json({ error: 'Failed to create category' });
  }
});

// PUT /api/categories/:id - Update category
router.put('/:id', async (req, res) => {
  try {
    const { error, value } = categorySchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    
    const { id } = req.params;
    const { name, color } = value;
    
    const result = await req.db.query(
      'UPDATE categories SET name = $1, color = $2 WHERE id = $3 RETURNING id, name, color, created_at',
      [name, color, id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Category not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating category:', error);
    
    if (error.code === '23505') {
      return res.status(409).json({ error: 'Category name already exists' });
    }
    
    res.status(500).json({ error: 'Failed to update category' });
  }
});

// DELETE /api/categories/:id - Delete category
router.delete('/:id', async (req, res) => {
  const client = await req.db.connect();
  
  try {
    const { id } = req.params;
    
    await client.query('BEGIN');
    
    // Check if category exists
    const categoryCheck = await client.query('SELECT id FROM categories WHERE id = $1', [id]);
    if (categoryCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Category not found' });
    }
    
    // Check if category is being used by tasks
    const usageCheck = await client.query(
      'SELECT COUNT(*) FROM task_categories WHERE category_id = $1',
      [id]
    );
    
    if (parseInt(usageCheck.rows[0].count) > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ 
        error: 'Cannot delete category',
        message: 'Category is being used by tasks. Remove it from all tasks first.'
      });
    }
    
    // Delete category
    await client.query('DELETE FROM categories WHERE id = $1', [id]);
    
    await client.query('COMMIT');
    
    res.status(204).send();
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error deleting category:', error);
    res.status(500).json({ error: 'Failed to delete category' });
  } finally {
    client.release();
  }
});

// GET /api/categories/:id/tasks - Get tasks in category
router.get('/:id/tasks', async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 10, status } = req.query;
    const offset = (page - 1) * limit;
    
    // Check if category exists
    const categoryCheck = await req.db.query('SELECT id FROM categories WHERE id = $1', [id]);
    if (categoryCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Category not found' });
    }
    
    let query = `
      SELECT t.id, t.title, t.description, t.status, t.priority, t.due_date,
             t.created_at, t.updated_at, t.user_id,
             u.username as user_username
      FROM tasks t
      JOIN users u ON t.user_id = u.id
      JOIN task_categories tc ON t.id = tc.task_id
      WHERE tc.category_id = $1
    `;
    const params = [id];
    
    if (status) {
      query += ' AND t.status = $2';
      params.push(status);
    }
    
    query += ` ORDER BY t.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);
    
    const [tasks, countResult] = await Promise.all([
      req.db.query(query, params),
      req.db.query(
        'SELECT COUNT(*) FROM tasks t JOIN task_categories tc ON t.id = tc.task_id WHERE tc.category_id = $1' + 
        (status ? ' AND t.status = $2' : ''),
        status ? [id, status] : [id]
      )
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
    console.error('Error fetching category tasks:', error);
    res.status(500).json({ error: 'Failed to fetch category tasks' });
  }
});

module.exports = router;