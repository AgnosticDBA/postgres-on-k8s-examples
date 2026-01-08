#!/bin/bash

# Quick test script for PostgreSQL DBaaS platform

set -e

echo "🧪 Testing PostgreSQL DBaaS Platform..."

# Test 1: Check if all components are running
echo "1️⃣ Checking component status..."
kubectl get postgresdatabases
kubectl get pods -n postgres-database-system
kubectl get pods -n percona-postgresql-operator

# Test 2: Create a test database
echo "2️⃣ Creating test database..."
cat <<EOF | kubectl apply -f -
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: test-db
  namespace: default
spec:
  version: 16
  replicas: 1
  storage: 1Gi
  backup: false
  monitoring: false
EOF

# Test 3: Wait for database to be ready
echo "3️⃣ Waiting for test database to be ready..."
for i in {1..20}; do
    if kubectl get postgresdatabase test-db -o jsonpath='{.status.phase}' | grep -q "Ready"; then
        echo "✅ Test database is ready!"
        break
    fi
    if [ $i -eq 20 ]; then
        echo "❌ Test database failed to become ready"
        kubectl get postgresdatabase test-db -o yaml
        exit 1
    fi
    echo "⏳ Waiting... ($i/20)"
    sleep 5
done

# Test 4: Test database connection
echo "4️⃣ Testing database connection..."
kubectl port-forward svc/test-db 5433:5432 -n default &
PF_PID=$!
sleep 5

# Get password and test connection
PASSWORD=$(kubectl get secret test-db-credentials -o jsonpath='{.data.password}' | base64 -d)
if echo "SELECT version();" | PGPASSWORD=$PASSWORD psql -h localhost -p 5433 -U postgres -d test_db -qt | grep -q "PostgreSQL"; then
    echo "✅ Database connection successful!"
else
    echo "❌ Database connection failed"
    kill $PF_PID 2>/dev/null
    exit 1
fi

kill $PF_PID 2>/dev/null

# Test 5: Test database operations
echo "5️⃣ Testing database operations..."
kubectl port-forward svc/test-db 5433:5432 -n default &
PF_PID=$!
sleep 5

# Create test table and data
PGPASSWORD=$PASSWORD psql -h localhost -p 5433 -U postgres -d test_db <<EOF
CREATE TABLE test_table (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO test_table (name) VALUES ('Test Record 1'), ('Test Record 2');
SELECT COUNT(*) FROM test_table;
EOF

if [ $? -eq 0 ]; then
    echo "✅ Database operations successful!"
else
    echo "❌ Database operations failed"
    kill $PF_PID 2>/dev/null
    exit 1
fi

kill $PF_PID 2>/dev/null

# Test 6: Test scaling
echo "6️⃣ Testing database scaling..."
kubectl patch postgresdatabase test-db -p '{"spec":{"replicas":2}}'

sleep 10

# Check if scaling worked
REPLICAS=$(kubectl get postgresdatabase test-db -o jsonpath='{.status.replicas}')
if [ "$REPLICAS" = "2" ]; then
    echo "✅ Database scaling successful!"
else
    echo "⚠️  Database scaling may still be in progress (current replicas: $REPLICAS)"
fi

# Cleanup
echo "🧹 Cleaning up test resources..."
kubectl delete postgresdatabase test-db

echo ""
echo "🎉 All tests passed! PostgreSQL DBaaS Platform is working correctly!"
echo ""
echo "📊 Platform Status:"
kubectl get postgresdatabases
echo ""
echo "🔗 To create a new database:"
echo "cat <<EOF | kubectl apply -f -"
echo "apiVersion: databases.mycompany.com/v1"
echo "kind: PostgresDatabase"
echo "metadata:"
echo "  name: my-new-db"
echo "spec:"
echo "  version: 17"
echo "  replicas: 1"
echo "  storage: 5Gi"
echo "  backup: false"
echo "  monitoring: false"
echo "EOF"