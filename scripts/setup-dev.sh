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

# Skip controller deployment for now (controller needs to be built separately)
echo "🏗️  Controller deployment skipped - CRD is available for manual testing"
echo "ℹ️  To deploy the controller manually:"
echo "   cd ../postgres-database-controller"
echo "   docker build -t postgres-database-controller:latest ."
echo "   kind load docker-image postgres-database-controller:latest"
echo "   kubectl apply -f deploy.yaml"

# Show status
echo ""
echo "🎉 PostgreSQL DBaaS Development Environment is ready!"
echo ""
echo "📊 Status:"
echo "Percona PostgreSQL Operator:"
kubectl get pods -n percona-postgresql-operator
echo ""
echo "ℹ️  CRD is deployed and ready for controller testing"
echo ""
echo "🔧 Next steps:"
echo "   1. Build and deploy the postgres-database-controller"
echo "   2. Create PostgresDatabase resources to test the controller"
echo ""
echo "📖 See DEVELOPER_GUIDE.md for more information"