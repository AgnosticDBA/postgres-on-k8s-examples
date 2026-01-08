const express = require('express');

const router = express.Router();

// GET /health - Basic health check
router.get('/', async (req, res) => {
  try {
    // Check database connection
    const dbCheck = await req.db.query('SELECT 1 as health_check');
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      database: 'connected',
      uptime: process.uptime()
    });
  } catch (error) {
    console.error('Health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      database: 'disconnected',
      error: error.message
    });
  }
});

// GET /health/ready - Readiness probe
router.get('/ready', async (req, res) => {
  try {
    // Check if database is ready and has required tables
    const tablesCheck = await req.db.query(`
      SELECT COUNT(*) as table_count 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name IN ('users', 'tasks', 'categories')
    `);
    
    const tableCount = parseInt(tablesCheck.rows[0].table_count);
    
    if (tableCount < 3) {
      return res.status(503).json({
        status: 'not ready',
        timestamp: new Date().toISOString(),
        reason: 'Database tables not ready',
        tables_found: tableCount
      });
    }
    
    res.json({
      status: 'ready',
      timestamp: new Date().toISOString(),
      database: 'ready',
      tables_found: tableCount
    });
  } catch (error) {
    console.error('Readiness check failed:', error);
    res.status(503).json({
      status: 'not ready',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

// GET /health/live - Liveness probe
router.get('/live', (req, res) => {
  res.json({
    status: 'alive',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    version: process.env.npm_package_version || '1.0.0'
  });
});

// GET /health/detailed - Detailed health information
router.get('/detailed', async (req, res) => {
  try {
    const [dbCheck, tableStats, connectionInfo] = await Promise.all([
      req.db.query('SELECT version() as db_version, current_database() as current_db'),
      req.db.query(`
        SELECT 
          (SELECT COUNT(*) FROM users) as users_count,
          (SELECT COUNT(*) FROM tasks) as tasks_count,
          (SELECT COUNT(*) FROM categories) as categories_count,
          (SELECT COUNT(*) FROM task_categories) as task_categories_count
      `),
      req.db.query(`
        SELECT 
          state,
          COUNT(*) as connection_count
        FROM pg_stat_activity 
        WHERE datname = current_database()
        GROUP BY state
      `)
    ]);
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      database: {
        status: 'connected',
        version: dbCheck.rows[0].db_version,
        current_database: dbCheck.rows[0].current_db,
        connections: connectionInfo.rows,
        tables: tableStats.rows[0]
      },
      application: {
        node_version: process.version,
        platform: process.platform,
        environment: process.env.NODE_ENV || 'development'
      }
    });
  } catch (error) {
    console.error('Detailed health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

module.exports = router;