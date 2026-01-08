# PostgreSQL DBaaS Developer Guide

A comprehensive guide for developers to easily deploy and manage PostgreSQL databases on Kubernetes using our DBaaS solution.

## 🎯 Overview

This PostgreSQL Database-as-a-Service (DBaaS) platform provides developers with a simple, self-service way to deploy PostgreSQL databases on Kubernetes without needing to understand complex operator configurations.

### Architecture

```
┌─────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│ PostgresDatabase │───▶│ Platform Controller │───▶│ PerconaPGCluster │
│ (8 lines YAML)  │    │ (Abstracts complexity)│    │ (50+ lines YAML) │
└─────────────────┘    └─────────────────────┘    └──────────────────┘
```

### Repository Structure

```
postgres-dbaas/
├── postgres-database/                    # CRD definition & examples
├── postgres-database-controller/          # Go operator controller
├── postgres-on-k8s-examples/              # Complete deployment examples
└── percona-postgresql-operator/           # Underlying operator (can be installed from upstream)
```

## 🚀 Quick Start for MacBook Air M4 (24GB RAM)

### Prerequisites

```bash
# Install required tools
brew install docker kubectl helm kind

# Verify installation
docker --version
kubectl version --client
helm version
kind version
```

### Option 1: Self-Service Platform (Recommended)

**Perfect for developers who want simplicity**

#### 1. Set up Local Kubernetes

```bash
# Create local cluster with Kind
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

# Install Percona Operator
kubectl apply --server-side -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/main/deploy/bundle.yaml

# Wait for operator to be ready
kubectl wait --for=condition=available --timeout=300s deployment/percona-postgresql-operator
```

#### 2. Deploy PostgresDatabase CRD

```bash
# Deploy the CRD
cd postgres-database
kubectl apply -f deploy/crd-postgres-database.yaml
cd ..
```

#### 3. Deploy Controller

```bash
# Build and deploy controller
cd postgres-database-controller
docker build -t postgres-database-controller:latest .
kind load docker-image postgres-database-controller:latest

# Update deployment to use local image
sed -i.bak 's|agnosticdba/postgres-database-controller:latest|postgres-database-controller:latest|' deploy.yaml

kubectl apply -f deploy.yaml
```

#### 4. Create Your First Database

```bash
# Create a production-ready database with just 8 lines!
cat <<EOF | kubectl apply -f -
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: my-app-db
  namespace: default
spec:
  version: 17
  replicas: 3
  storage: 10Gi
  backup: true
  monitoring: true
EOF

# Watch it being created
kubectl get postgresdatabases -w
```

#### 5. Connect to Your Database

```bash
# Get connection details
kubectl get postgresdatabase my-app-db -o yaml

# Port-forward to connect
kubectl port-forward svc/my-app-db 5432:5432 &

# Connect with psql
PGPASSWORD=$(kubectl get secret my-app-db-credentials -o jsonpath='{.data.password}' | base64 -d) \
psql -h localhost -U postgres -d my_app_db
```

### Option 2: Direct Operator Usage

**For developers who want more control**

#### 1. Deploy CloudNativePG Operator (Alternative)

```bash
# Install CloudNativePG (lighter alternative)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

# Deploy example cluster
cd ../postgres-on-k8s-examples/cloudnativepg-operator
kubectl apply -f k8s/cluster/postgresql-cluster.yaml
```

#### 2. Deploy Percona Operator Examples

```bash
# Use Percona operator directly
cd ../postgres-on-k8s-examples/percona-operator
kubectl apply -f k8s/cluster/postgrescluster.yaml
```

## 📊 Resource Requirements for MacBook Air M4

### Development Environment

| Component | CPU | Memory | Storage | Description |
|-----------|-----|---------|---------|-------------|
| Kind Cluster | 2 cores | 4GB | 20GB | Base Kubernetes |
| Percona Operator | 200m | 512Mi | 1Gi | Operator pod |
| PostgresDatabase (3 replicas) | 600m | 1.5Gi | 30Gi | HA database |
| Controller | 100m | 256Mi | 100Mi | Platform controller |
| **Total** | **1.1 cores** | **2.3Gi** | **32Gi** | **Full platform** |

### Recommended Configuration

```yaml
# For development on M4 MacBook Air
spec:
  version: 17
  replicas: 1          # Start with 1 replica for development
  storage: 10Gi        # Reasonable for development
  backup: false        # Disable backups to save resources
  monitoring: false    # Disable monitoring for development
  resources:
    requests:
      cpu: 100m        # Low CPU for development
      memory: 256Mi    # Low memory for development
```

## 🛠️ Development Workflow

### 1. Database Creation

```bash
# Create database for your microservice
kubectl apply -f - <<EOF
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: user-service-db
  labels:
    app: user-service
    env: development
spec:
  version: 16
  replicas: 1
  storage: 5Gi
  backup: false
  monitoring: false
EOF
```

### 2. Application Integration

```yaml
# Example deployment for your application
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
spec:
  template:
    spec:
      containers:
      - name: user-service
        image: your-app:latest
        env:
        - name: DATABASE_URL
          value: "postgresql://postgres:$(POSTGRES_PASSWORD)@user-service-db:5432/user_service"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: user-service-db-credentials
              key: password
```

### 3. Database Operations

```bash
# Scale database for load testing
kubectl patch postgresdatabase user-service-db -p '{"spec":{"replicas":3}}'

# Enable backups for production
kubectl patch postgresdatabase user-service-db -p '{"spec":{"backup":true}}'

# Upgrade PostgreSQL version
kubectl patch postgresdatabase user-service-db -p '{"spec":{"version":17}}'
```

### 4. Monitoring and Debugging

```bash
# Check database status
kubectl get postgresdatabase user-service-db -o wide

# View underlying cluster
kubectl get perconapgclusters

# Check logs
kubectl logs -l app.kubernetes.io/name=postgres-database-controller

# Connect to database for debugging
kubectl exec -it deployment/user-service -- psql \$DATABASE_URL
```

## 🎛️ Advanced Configuration

### Custom Resource Definitions

The platform supports these PostgreSQL versions:
- PostgreSQL 13 (EOL December 2025)
- PostgreSQL 14 (EOL November 2027) 
- PostgreSQL 15 (EOL November 2029)
- PostgreSQL 16 (EOL November 2031)
- PostgreSQL 17 (EOL November 2033)

### Production Configuration

```yaml
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: production-db
  namespace: production
spec:
  version: 16
  replicas: 3              # HA with primary + 2 replicas
  storage: 100Gi           # Production storage
  backup: true             # Enable automated backups
  backupRetention: "30d"   # 30-day backup retention
  monitoring: true        # Enable PMM monitoring
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi
```

### Performance Tuning

```yaml
# For high-performance workloads
spec:
  version: 17
  replicas: 5
  storage: 500Gi
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi
  # Custom PostgreSQL parameters
  postgresqlParameters:
    max_connections: "500"
    shared_buffers: "2GB"
    effective_cache_size: "6GB"
    maintenance_work_mem: "512MB"
```

## 🔄 CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Database
on:
  push:
    paths: ['database/**']

jobs:
  deploy-db:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Configure kubectl
      uses: azure/k8s-set-context@v1
      with:
        method: kubeconfig
        kubeconfig: ${{ secrets.KUBE_CONFIG }}
    
    - name: Deploy database
      run: |
        kubectl apply -f database/postgres-database.yaml
        kubectl wait --for=condition=ready postgresdatabase/app-db
```

### Database Migration

```bash
# Run migrations as part of deployment
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  template:
    spec:
      containers:
      - name: migration
        image: migrate/migrate
        command: ["migrate", "-path", "/migrations", "-database", "\$DATABASE_URL", "up"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-db-credentials
              key: url
      restartPolicy: OnFailure
EOF
```

## 🧪 Testing Strategies

### Unit Testing

```bash
# Test controller locally
cd postgres-database-controller
go test ./...

# Test with envtest
make test
```

### Integration Testing

```bash
# Deploy test databases
kubectl apply -f postgres-database/deploy/test-postgres-database.yaml

# Run integration tests
./scripts/test-platform.sh
```

### Performance Testing

```bash
# Deploy performance test database
kubectl apply -f - <<EOF
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: perf-test
spec:
  version: 17
  replicas: 3
  storage: 50Gi
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
EOF

# Run pgbench
kubectl exec -it perf-test-1 -- pgbench -i -s 1000 postgres
```

## 🚨 Troubleshooting

### Common Issues

1. **Database stuck in "Creating" state**
   ```bash
   kubectl get postgresdatabase my-db -o yaml
   kubectl logs -l app.kubernetes.io/name=postgres-database-controller
   ```

2. **Connection refused**
   ```bash
   kubectl get svc my-db
   kubectl get pods -l postgres-operator.crunchydata.com/cluster=my-db
   ```

3. **Storage issues**
   ```bash
   kubectl get pvc
   kubectl describe pvc my-db-data
   ```

### Debug Commands

```bash
# Check all platform components
kubectl get postgresdatabases,perconapgclusters
kubectl get pods -l app.kubernetes.io/part-of=postgres-dbaas

# Port-forward for direct access
kubectl port-forward svc/my-db 5432:5432

# Check controller events
kubectl get events --field-selector involvedObject.name=postgres-database-controller
```

## 📚 Learning Resources

### Documentation
- [Percona Operator Documentation](https://docs.percona.com/percona-operator-for-postgresql/)
- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Kubernetes PostgreSQL Patterns](https://kubernetes.io/docs/concepts/workloads/pods/)

### Community
- [Percona Forums](https://forums.percona.com/)
- [CloudNativePG Slack](https://cloudnative-pg.io/community/)
- [Kubernetes PostgreSQL SIG](https://github.com/kubernetes-sigs/postgres-operator)

### Examples
- [Microservice Integration](postgres-on-k8s-examples/common/microservice/)
- [Backup and Restore](postgres-on-k8s-examples/common/backup-restore/)
- [Monitoring Setup](postgres-on-k8s-examples/common/monitoring/)

## 🗺️ Roadmap

### Q1 2025
- [ ] Multi-region support
- [ ] Automated scaling based on metrics
- [ ] Database cloning for dev/test environments

### Q2 2025  
- [ ] GraphQL API for database management
- [ ] Integration with popular ORMs
- [ ] Performance analytics dashboard

### Q3 2025
- [ ] Support for PostgreSQL extensions
- [ ] Read replica management
- [ ] Cost optimization features

## 🤝 Contributing

We welcome contributions! See the contributing guidelines in each repository:

1. **Fork** the repository
2. **Create** a feature branch
3. **Make** your changes
4. **Test** thoroughly
5. **Submit** a pull request

### Development Setup

```bash
# You're already in the postgres-dbaas directory with all repositories
# Set up development environment (automated)
./scripts/setup-dev.sh

# Or run manual setup (see guide above)
```

### Quick Test

```bash
# Test the platform after setup
./scripts/test-platform.sh
```

## 📄 License

All repositories are licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

---

**Need help?** 
- Check our [troubleshooting guide](docs/troubleshooting.md)
- Join our [community discussions](https://github.com/AgnosticDBA/discussions)
- Open an [issue](https://github.com/AgnosticDBA/issues) for bugs or feature requests

**Happy coding! 🚀**