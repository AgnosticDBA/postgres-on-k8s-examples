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
echo "⚠️  Note: Controller source code in separate repository: https://github.com/AgnosticDBA/postgres-database-controller"
echo "ℹ️  For now, we'll create a test database directly with Percona operator..."

# Skip controller build for now - controller needs to be deployed separately
echo "ℹ️  Controller deployment skipped - CRD is available for manual testing"

# Create example PostgresDatabase CR (for testing when controller is deployed)
echo "🗄️  Creating example PostgresDatabase CR (controller required to process)..."
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

echo "ℹ️  PostgresDatabase CR created - it will remain pending until the controller is deployed"

# Show status
echo ""
echo "🎉 PostgreSQL DBaaS Development Environment is ready!"
echo ""
echo "📊 Status:"
kubectl get postgresdatabases.databases.mycompany.com
kubectl get pods -n percona-postgresql-operator
echo ""
echo "ℹ️  Next steps:"
echo "   1. Deploy the postgres-database-controller to handle PostgresDatabase resources"
echo "   2. Then the example-db will be processed and become ready"
echo ""
echo "🔧 To deploy the controller:"
echo "   cd ../postgres-database-controller"
echo "   ./scripts/deploy.sh"
echo ""
echo "📖 See DEVELOPER_GUIDE.md for more information"