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

# Deploy controller
echo "🏗️  Deploying postgres-database-controller..."

# Create controller namespace and service account
kubectl create namespace postgres-database-system --dry-run=client -o yaml | kubectl apply -f -

# Deploy controller using published image
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-database-controller
  namespace: postgres-database-system
  labels:
    app: postgres-database-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-database-controller
  template:
    metadata:
      labels:
        app: postgres-database-controller
    spec:
      serviceAccountName: postgres-database-controller
      containers:
      - name: controller
        image: ghcr.io/agnosticdba/postgres-database-controller:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Create service account and RBAC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-database-controller
  namespace: postgres-database-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: postgres-database-controller
rules:
- apiGroups: ["databases.mycompany.com"]
  resources: ["postgresdatabases", "postgresdatabases/status", "postgresdatabases/finalizers"]
  verbs: ["*"]
- apiGroups: ["pgv2.percona.com", "postgres-operator.crunchydata.com"]
  resources: ["perconapgclusters", "postgresclusters"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: postgres-database-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: postgres-database-controller
subjects:
- kind: ServiceAccount
  name: postgres-database-controller
  namespace: postgres-database-system
EOF

# Wait for controller to be ready
echo "⏳ Waiting for postgres-database-controller to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/postgres-database-controller -n postgres-database-system || {
    echo "❌ postgres-database-controller failed to become ready"
    kubectl get pods -n postgres-database-system
    exit 1
}

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
echo "PGPASSWORD=\$(kubectl get secret example-db-credentials -o jsonpath='{.data.password}' | base64 -d) psql -h localhost -U postgres -d example_db"
echo ""
echo "📖 See DEVELOPER_GUIDE.md for more information"