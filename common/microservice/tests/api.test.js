const request = require('supertest');
const { app, pool } = require('../src/server');

describe('Health Endpoints', () => {
  afterAll(async () => {
    await pool.end();
  });

  describe('GET /health', () => {
    it('should return health status', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toHaveProperty('status', 'healthy');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('database');
    });
  });

  describe('GET /health/ready', () => {
    it('should return readiness status', async () => {
      const response = await request(app)
        .get('/health/ready')
        .expect(200);

      expect(response.body).toHaveProperty('status', 'ready');
    });
  });

  describe('GET /health/live', () => {
    it('should return liveness status', async () => {
      const response = await request(app)
        .get('/health/live')
        .expect(200);

      expect(response.body).toHaveProperty('status', 'alive');
      expect(response.body).toHaveProperty('uptime');
    });
  });
});

describe('API Endpoints', () => {
  beforeAll(async () => {
    // Setup test data
    await pool.query('BEGIN');
    await pool.query(`
      INSERT INTO users (id, username, email, password_hash) 
      VALUES ('test-user-id', 'testuser', 'test@example.com', 'hash')
      ON CONFLICT (id) DO NOTHING
    `);
    await pool.query(`
      INSERT INTO categories (id, name, color) 
      VALUES ('test-cat-id', 'Test Category', '#ff0000')
      ON CONFLICT (id) DO NOTHING
    `);
  });

  afterAll(async () => {
    await pool.query('ROLLBACK');
    await pool.end();
  });

  describe('GET /api/users', () => {
    it('should return users list', async () => {
      const response = await request(app)
        .get('/api/users')
        .expect(200);

      expect(response.body).toHaveProperty('users');
      expect(Array.isArray(response.body.users)).toBe(true);
    });
  });

  describe('GET /api/categories', () => {
    it('should return categories list', async () => {
      const response = await request(app)
        .get('/api/categories')
        .expect(200);

      expect(response.body).toHaveProperty('categories');
      expect(Array.isArray(response.body.categories)).toBe(true);
    });
  });

  describe('POST /api/users', () => {
    it('should create a new user', async () => {
      const userData = {
        username: 'newuser',
        email: 'newuser@example.com',
        password: 'password123'
      };

      const response = await request(app)
        .post('/api/users')
        .send(userData)
        .expect(201);

      expect(response.body).toHaveProperty('id');
      expect(response.body.username).toBe(userData.username);
      expect(response.body.email).toBe(userData.email);
    });

    it('should reject invalid user data', async () => {
      const invalidData = {
        username: 'ab', // too short
        email: 'invalid-email',
        password: '123' // too short
      };

      const response = await request(app)
        .post('/api/users')
        .send(invalidData)
        .expect(400);

      expect(response.body).toHaveProperty('error');
    });
  });

  describe('POST /api/tasks', () => {
    it('should create a new task', async () => {
      const taskData = {
        title: 'Test Task',
        description: 'This is a test task',
        user_id: 'test-user-id',
        status: 'pending',
        priority: 'medium'
      };

      const response = await request(app)
        .post('/api/tasks')
        .send(taskData)
        .expect(201);

      expect(response.body).toHaveProperty('id');
      expect(response.body.title).toBe(taskData.title);
      expect(response.body.user_id).toBe(taskData.user_id);
    });

    it('should reject invalid task data', async () => {
      const invalidData = {
        title: '', // empty title
        user_id: 'invalid-uuid'
      };

      const response = await request(app)
        .post('/api/tasks')
        .send(invalidData)
        .expect(400);

      expect(response.body).toHaveProperty('error');
    });
  });
});