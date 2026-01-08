const express = require('express');
const Joi = require('joi');

const router = express.Router();

const taskSchema = Joi.object({
  title: Joi.string().min(1).max(200).required(),
  description: Joi.string().max(1000).allow(''),
  status: Joi.string().valid('pending', 'in_progress', 'completed').default('pending'),
  priority: Joi.string().valid('low', 'medium', 'high', 'urgent').default('medium'),
  user_id: Joi.string().uuid().required(),
  due_date: Joi.date().iso().allow(null),
  category_ids: Joi.array().items(Joi.string().uuid()).optional()
});

const updateTaskSchema = Joi.object({
  title: Joi.string().min(1).max(200),
  description: Joi.string().max(1000).allow(''),
  status: Joi.string().valid('pending', 'in_progress', 'completed'),
  priority: Joi.string().valid('low', 'medium', 'high', 'urgent'),
  due_date: Joi.date().iso().allow(null),
  category_ids: Joi.array().items(Joi.string().uuid()).optional()
}).min(1);

// GET /api/tasks - Get all tasks with optional filtering
router.get('/', async (req, res) => {
  try {
    const { 
      page = 1, 
      limit = 10, 
      status, 
      priority, 
      user_id, 
      category_id,
      search 
    } = req.query;
    const offset = (page - 1) * limit;
    
    let query = `
      SELECT t.id, t.title, t.description, t.status, t.priority, t.due_date, 
             t.created_at, t.updated_at, t.user_id,
             u.username as user_username,
             ARRAY_AGG(c.name) as categories
      FROM tasks t
      JOIN users u ON t.user_id = u.id
      LEFT JOIN task_categories tc ON t.id = tc.task_id
      LEFT JOIN categories c ON tc.category_id = c.id
    `;
    
    let countQuery = 'SELECT COUNT(DISTINCT t.id) FROM tasks t';
    const params = [];
    const conditions = [];
    let paramIndex = 1;
    
    if (status) {
      conditions.push(`t.status = $${paramIndex++}`);
      params.push(status);
    }
    
    if (priority) {
      conditions.push(`t.priority = $${paramIndex++}`);
      params.push(priority);
    }
    
    if (user_id) {
      conditions.push(`t.user_id = $${paramIndex++}`);
      params.push(user_id);
    }
    
    if (category_id) {
      conditions.push(`EXISTS (
        SELECT 1 FROM task_categories tc2 
        WHERE tc2.task_id = t.id AND tc2.category_id = $${paramIndex++}
      )`);
      params.push(category_id);
    }
    
    if (search) {
      conditions.push(`(t.title ILIKE $${paramIndex++} OR t.description ILIKE $${paramIndex++})`);
      params.push(`%${search}%`, `%${search}%`);
    }
    
    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
      countQuery += ' WHERE ' + conditions.join(' AND ');
    }
    
    query += ` GROUP BY t.id, t.title, t.description, t.status, t.priority, t.due_date, 
                     t.created_at, t.updated_at, t.user_id, u.username
               ORDER BY t.created_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    params.push(limit, offset);
    
    const [tasks, countResult] = await Promise.all([
      req.db.query(query, params),
      req.db.query(countQuery, params.slice(0, -2))
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
    console.error('Error fetching tasks:', error);
    res.status(500).json({ error: 'Failed to fetch tasks' });
  }
});

// GET /api/tasks/:id - Get task by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await req.db.query(`
      SELECT t.id, t.title, t.description, t.status, t.priority, t.due_date,
             t.created_at, t.updated_at, t.user_id,
             u.username as user_username,
             ARRAY_AGG(c.name) as categories
      FROM tasks t
      JOIN users u ON t.user_id = u.id
      LEFT JOIN task_categories tc ON t.id = tc.task_id
      LEFT JOIN categories c ON tc.category_id = c.id
      WHERE t.id = $1
      GROUP BY t.id, t.title, t.description, t.status, t.priority, t.due_date,
               t.created_at, t.updated_at, t.user_id, u.username
    `, [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching task:', error);
    res.status(500).json({ error: 'Failed to fetch task' });
  }
});

// POST /api/tasks - Create new task
router.post('/', async (req, res) => {
  const client = await req.db.connect();
  
  try {
    const { error, value } = taskSchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    
    const { title, description, status, priority, user_id, due_date, category_ids } = value;
    
    await client.query('BEGIN');
    
    // Check if user exists
    const userCheck = await client.query('SELECT id FROM users WHERE id = $1', [user_id]);
    if (userCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'User not found' });
    }
    
    // Insert task
    const taskResult = await client.query(`
      INSERT INTO tasks (title, description, status, priority, user_id, due_date)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id, title, description, status, priority, user_id, due_date, created_at, updated_at
    `, [title, description, status, priority, user_id, due_date]);
    
    const task = taskResult.rows[0];
    
    // Add categories if provided
    if (category_ids && category_ids.length > 0) {
      // Verify categories exist
      const categoryCheck = await client.query(
        'SELECT id FROM categories WHERE id = ANY($1)',
        [category_ids]
      );
      
      if (categoryCheck.rows.length !== category_ids.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'One or more categories not found' });
      }
      
      // Insert task-category relationships
      const categoryValues = category_ids.map(catId => `('${task.id}', '${catId}')`).join(',');
      await client.query(`
        INSERT INTO task_categories (task_id, category_id)
        VALUES ${categoryValues.replace(/\(/g, '(\'').replace(/\)/g, '\')').replace(/, /g, '\', \'')}
      `);
    }
    
    await client.query('COMMIT');
    
    // Fetch the complete task with categories
    const completeTask = await req.db.query(`
      SELECT t.id, t.title, t.description, t.status, t.priority, t.due_date,
             t.created_at, t.updated_at, t.user_id,
             u.username as user_username,
             ARRAY_AGG(c.name) as categories
      FROM tasks t
      JOIN users u ON t.user_id = u.id
      LEFT JOIN task_categories tc ON t.id = tc.task_id
      LEFT JOIN categories c ON tc.category_id = c.id
      WHERE t.id = $1
      GROUP BY t.id, t.title, t.description, t.status, t.priority, t.due_date,
               t.created_at, t.updated_at, t.user_id, u.username
    `, [task.id]);
    
    res.status(201).json(completeTask.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error creating task:', error);
    res.status(500).json({ error: 'Failed to create task' });
  } finally {
    client.release();
  }
});

// PUT /api/tasks/:id - Update task
router.put('/:id', async (req, res) => {
  const client = await req.db.connect();
  
  try {
    const { error, value } = updateTaskSchema.validate(req.body);
    
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    
    const { id } = req.params;
    const { title, description, status, priority, due_date, category_ids } = value;
    
    await client.query('BEGIN');
    
    // Check if task exists
    const taskCheck = await client.query('SELECT id FROM tasks WHERE id = $1', [id]);
    if (taskCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Task not found' });
    }
    
    // Update task
    const updates = [];
    const params = [];
    let paramIndex = 1;
    
    if (title !== undefined) {
      updates.push(`title = $${paramIndex++}`);
      params.push(title);
    }
    
    if (description !== undefined) {
      updates.push(`description = $${paramIndex++}`);
      params.push(description);
    }
    
    if (status !== undefined) {
      updates.push(`status = $${paramIndex++}`);
      params.push(status);
    }
    
    if (priority !== undefined) {
      updates.push(`priority = $${paramIndex++}`);
      params.push(priority);
    }
    
    if (due_date !== undefined) {
      updates.push(`due_date = $${paramIndex++}`);
      params.push(due_date);
    }
    
    updates.push(`updated_at = CURRENT_TIMESTAMP`);
    params.push(id);
    
    const updateQuery = `UPDATE tasks SET ${updates.join(', ')} WHERE id = $${paramIndex}`;
    await client.query(updateQuery, params);
    
    // Update categories if provided
    if (category_ids !== undefined) {
      // Remove existing categories
      await client.query('DELETE FROM task_categories WHERE task_id = $1', [id]);
      
      // Add new categories if any
      if (category_ids.length > 0) {
        // Verify categories exist
        const categoryCheck = await client.query(
          'SELECT id FROM categories WHERE id = ANY($1)',
          [category_ids]
        );
        
        if (categoryCheck.rows.length !== category_ids.length) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'One or more categories not found' });
        }
        
        // Insert task-category relationships
        const categoryValues = category_ids.map(catId => `('${id}', '${catId}')`).join(',');
        await client.query(`
          INSERT INTO task_categories (task_id, category_id)
          VALUES ${categoryValues.replace(/\(/g, '(\'').replace(/\)/g, '\')').replace(/, /g, '\', \'')}
        `);
      }
    }
    
    await client.query('COMMIT');
    
    // Fetch the updated task
    const updatedTask = await req.db.query(`
      SELECT t.id, t.title, t.description, t.status, t.priority, t.due_date,
             t.created_at, t.updated_at, t.user_id,
             u.username as user_username,
             ARRAY_AGG(c.name) as categories
      FROM tasks t
      JOIN users u ON t.user_id = u.id
      LEFT JOIN task_categories tc ON t.id = tc.task_id
      LEFT JOIN categories c ON tc.category_id = c.id
      WHERE t.id = $1
      GROUP BY t.id, t.title, t.description, t.status, t.priority, t.due_date,
               t.created_at, t.updated_at, t.user_id, u.username
    `, [id]);
    
    res.json(updatedTask.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error updating task:', error);
    res.status(500).json({ error: 'Failed to update task' });
  } finally {
    client.release();
  }
});

// DELETE /api/tasks/:id - Delete task
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await req.db.query('DELETE FROM tasks WHERE id = $1 RETURNING id', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }
    
    res.status(204).send();
  } catch (error) {
    console.error('Error deleting task:', error);
    res.status(500).json({ error: 'Failed to delete task' });
  }
});

// GET /api/tasks/stats - Get task statistics
router.get('/stats', async (req, res) => {
  try {
    const { user_id } = req.query;
    
    let userFilter = '';
    const params = [];
    
    if (user_id) {
      userFilter = 'WHERE user_id = $1';
      params.push(user_id);
    }
    
    const [statusStats, priorityStats, recentTasks] = await Promise.all([
      req.db.query(`
        SELECT status, COUNT(*) as count
        FROM tasks ${userFilter}
        GROUP BY status
        ORDER BY count DESC
      `, params),
      req.db.query(`
        SELECT priority, COUNT(*) as count
        FROM tasks ${userFilter}
        GROUP BY priority
        ORDER BY count DESC
      `, params),
      req.db.query(`
        SELECT COUNT(*) as total
        FROM tasks ${userFilter}
        WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
      `, params)
    ]);
    
    res.json({
      by_status: statusStats.rows,
      by_priority: priorityStats.rows,
      created_last_7_days: parseInt(recentTasks.rows[0].total)
    });
  } catch (error) {
    console.error('Error fetching task stats:', error);
    res.status(500).json({ error: 'Failed to fetch task statistics' });
  }
});

module.exports = router;