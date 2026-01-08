#!/bin/bash

# PostgreSQL DBaaS Development Setup Script
# For MacBook Air M4 (24GB RAM)

set -e

echo "🚀 Setting up PostgreSQL DBaaS Development Environment..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed. Aborting."; exit 1; }
command -v kind >/dev/null 2>&1 || { echo "❌ kind is required but not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ helm is required but not installed. Aborting."; exit 1; }

echo "✅ Prerequisites check passed"

# Create Kind cluster
echo "📦 Creating Kind cluster..."
if kind get clusters | grep -q "postgres-dbaas"; then
    echo "ℹ️  Kind cluster 'postgres-dbaas' already exists"
else
    kind create cluster --name postgres-dbaas --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
    echo "✅ Kind cluster created"
fi

# Install Percona Operator
echo "🔧 Installing Percona PostgreSQL Operator..."
kubectl apply --server-side -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/main/deploy/bundle.yaml

# Wait for operator to be ready
echo "⏳ Waiting for Percona operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/percona-postgresql-operator -n default || {
    echo "❌ Percona operator failed to become ready"
    kubectl get pods -n default
    exit 1
}

# Deploy PostgresDatabase CRD
echo "📋 Deploying PostgresDatabase CRD..."
kubectl apply -f https://raw.githubusercontent.com/AgnosticDBA/postgres-database/main/deploy/crd-postgres-database.yaml

# Build and deploy controller
echo "🏗️  Building and deploying postgres-database-controller..."

# Clone controller repo if not present
if [ ! -d "../postgres-database-controller" ]; then
    echo "📥 Cloning postgres-database-controller..."
    cd ..
    git clone https://github.com/AgnosticDBA/postgres-database-controller.git
    cd postgres-on-k8s-examples
fi

# Build controller image
echo "🔨 Building controller image..."
cd ../postgres-database-controller

# Detect platform and build accordingly
if [[ "$(uname -m)" == "arm64" ]]; then
    echo "🍎 Building for ARM64 (Apple Silicon)..."
    # Update Dockerfile for ARM64
    sed -i.bak 's/GOARCH=amd64/GOARCH=arm64/' Dockerfile
    docker build -t postgres-database-controller:latest .
    # Restore Dockerfile
    mv Dockerfile.bak Dockerfile
else
    echo "🖥️ Building for AMD64 (Intel/CI)..."
    docker build -t postgres-database-controller:latest .
fi

# Load image into Kind cluster
echo "📦 Loading image into Kind cluster..."
kind load docker-image postgres-database-controller:latest --name postgres-dbaas

# Deploy controller
echo "🚀 Deploying controller..."
kubectl apply -f deploy/controller.yaml

# Wait for controller to be ready
echo "⏳ Waiting for postgres-database-controller to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/postgres-database-controller -n postgres-database-system || {
    echo "❌ postgres-database-controller failed to become ready"
    kubectl get pods -n postgres-database-system
    exit 1
}

cd ../postgres-on-k8s-examples

# Create example PostgresDatabase
echo "🗄️  Creating example PostgresDatabase..."
cat <<EOF | kubectl apply -f -
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: example-db
  namespace: default
spec:
  version: 17
  replicas: 1
  storage: 5Gi
  backup: false
  monitoring: false
EOF

# Wait for database to be ready
echo "⏳ Waiting for example database to be ready..."
for i in {1..30}; do
    if kubectl get postgresdatabase example-db -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Ready"; then
        echo "✅ Example database is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Example database failed to become ready"
        kubectl get postgresdatabase example-db -o yaml
        exit 1
    fi
    echo "⏳ Waiting for database... ($i/30)"
    sleep 10
done

# Show connection information
echo ""
echo "🎉 PostgreSQL DBaaS Development Environment is ready!"
echo ""
echo "📊 Status:"
kubectl get postgresdatabases.databases.mycompany.com
kubectl get pods -n postgres-database-system
kubectl get pods -n percona-postgresql-operator
echo ""
echo "🔗 To connect to the example database:"
echo "kubectl port-forward svc/example-db 5432:5432 &"
echo "PGPASSWORD=\$(kubectl get secret example-db-postgres-secret -o jsonpath='{.data.password}' | base64 -d) psql -h localhost -U postgres -d example_db"
echo ""
echo "📖 See DEVELOPER_GUIDE.md for more information"