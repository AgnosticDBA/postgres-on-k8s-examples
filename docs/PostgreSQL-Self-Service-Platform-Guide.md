# PostgreSQL Self-Service Platform: Complete Setup Guide (ARM64 Compatible)

## 🎯 Platform Overview

This platform provides developers with a **simple 8-line YAML** interface to create PostgreSQL databases, automatically handling the complexity of Percona operator configuration underneath.

### Architecture
```
┌─────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│ PostgresDatabase │───▶│ Platform Controller │───▶│ PerconaPGCluster │
│ (8 lines YAML)  │    │ (Abstracts complexity)│    │ (50+ lines YAML) │
└─────────────────┘    └─────────────────────┘    └──────────────────┘
```

---

## Prerequisites

```bash
# Check you're on minikube
kubectl config current-context
# Should output: minikube

# Verify minikube is running
minikube status

# Verify you have 8GB+ RAM allocated
minikube ssh -- free -h
```

---

## Step 1: Fresh Minikube with 8GB RAM

```bash
# Delete old minikube
minikube delete

# Create new minikube with sufficient resources (ARM64 native)
minikube start --cpus=4 --memory=8192 --disk-size=50g

# Verify
kubectl cluster-info
kubectl get nodes
```

---

## Step 2: Deploy Percona Operator (Foundation)

```bash
# Create namespace
kubectl create namespace percona-postgresql-operator

# Deploy operator using official bundle (includes all required CRDs and permissions)
kubectl apply --server-side -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/v2.8.2/deploy/bundle.yaml \
  -n percona-postgresql-operator

# Verify operator is running
kubectl get pods -n percona-postgresql-operator
```

---

## Step 3: Deploy PostgresDatabase CRD & Controller

```bash
# Deploy the CRD (simple developer interface)
kubectl apply -f postgres-database/deploy/crd-postgres-database.yaml

# Build and deploy controller
cd postgres-database-controller
docker build -t postgres-database-controller:latest .
minikube image load postgres-database-controller:latest

# Update deployment to use local image
sed -i.bak 's|agnosticdba/postgres-database-controller:latest|postgres-database-controller:latest|' deploy.yaml

kubectl apply -f deploy.yaml
cd ..

# Wait for controller to be ready
kubectl wait --for=condition=available --timeout=180s deployment/postgres-database-controller -n postgres-database-system
```

---

## Step 4: Create Your First Database (8-Line Magic!)

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

# Watch it being created automatically
kubectl get postgresdatabases -w
```

**Expected output:**
```
NAME       PHASE     REPLICAS   ENDPOINT              AGE
my-app-db  Ready     3/3        my-app-db.default.svc   2m
```

---

## Step 5: Connect to Your Database

```bash
# Get connection details
kubectl get postgresdatabase my-app-db -o yaml

# Port-forward to connect
kubectl port-forward svc/my-app-db 5432:5432 &

# Get password and connect
POSTGRES_PASSWORD=$(kubectl get secret my-app-db-credentials -o jsonpath='{.data.password}' | base64 -d)
psql -h localhost -U postgres -d my_app_db -c "SELECT version();"

# Kill port forward when done
pkill -f "kubectl port-forward"
```

---

## Step 6: Advanced Examples

### Development Database (Minimal Resources)
```yaml
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: dev-db
spec:
  version: 17
  replicas: 1
  storage: 5Gi
  backup: false
  monitoring: false
```

### High-Performance Database
```yaml
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: perf-db
spec:
  version: 17
  replicas: 5
  storage: 100Gi
  backup: true
  backupRetention: "30d"
  monitoring: true
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

### Legacy PostgreSQL 15
```yaml
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: legacy-db
spec:
  version: 15
  replicas: 3
  storage: 50Gi
  backup: true
  monitoring: true
```

---

## Step 7: Platform Management

### Scale Database
```bash
# Scale from 1 to 3 replicas for high availability
kubectl patch postgresdatabase my-app-db -p '{"spec":{"replicas":3}}'

# Watch scaling happen
kubectl get postgresdatabases -w
```

### Enable Backups
```bash
# Enable automated backups
kubectl patch postgresdatabase my-app-db -p '{"spec":{"backup":true}}'
```

### Upgrade PostgreSQL Version
```bash
# Upgrade from PostgreSQL 16 to 17
kubectl patch postgresdatabase my-app-db -p '{"spec":{"version":17}}'
```

### Monitor Resources
```bash
# Check database status and resources
kubectl get postgresdatabases -o wide

# Check underlying Percona cluster
kubectl get perconapgclusters

# View controller logs
kubectl logs -n postgres-database-system deployment/postgres-database-controller
```

---

## Step 8: Testing & Validation

### Automated Test
```bash
# Run the platform test script
./scripts/test-platform.sh
```

### Manual Testing
```bash
# Create test database
cat <<EOF | kubectl apply -f -
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: test-db
spec:
  version: 17
  replicas: 1
  storage: 1Gi
  backup: false
  monitoring: false
EOF

# Wait for ready status
kubectl wait --for=condition=ready postgresdatabase/test-db --timeout=300s

# Test connection and operations
kubectl port-forward svc/test-db 5433:5432 &
POSTGRES_PASSWORD=$(kubectl get secret test-db-credentials -o jsonpath='{.data.password}' | base64 -d)

# Create table and insert data
PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -p 5433 -U postgres -d test_db <<EOF
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100)
);

INSERT INTO users (name, email) VALUES 
    ('Alice', 'alice@example.com'),
    ('Bob', 'bob@example.com');

SELECT COUNT(*) FROM users;
EOF

# Cleanup
kubectl delete postgresdatabase test-db
pkill -f "kubectl port-forward"
```

---

## Step 9: Comparison: Before vs After

### ❌ **Before (Direct Percona Operator)**
```yaml
# 50+ lines of complex configuration
apiVersion: pgv2.percona.com/v2
kind: PerconaPGCluster
metadata:
  name: my-app-db
spec:
  crVersion: 2.8.2
  image: docker.io/percona/percona-distribution-postgresql:17.7-2
  postgresVersion: 17
  instances:
  - name: instance1
    replicas: 3
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 1
          podAffinityTerm:
            labelSelector:
              matchLabels:
                postgres-operator.crunchydata.com/data: postgres
            topologyKey: kubernetes.io/hostname
    dataVolumeClaimSpec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 10Gi
      storageClassName: standard
  proxy:
    pgBouncer:
      replicas: 3
      image: docker.io/percona/percona-pgbouncer:1.25.0-1
      affinity: # ... complex configuration
  backups:
    pgbackrest:
      image: docker.io/percona/percona-pgbackrest:2.57.0-1
      repos: [{name: "repo1"}]
  pmm:
    enabled: true
    image: docker.io/percona/pmm-client:3.5.0
    serverHost: monitoring-service
  # ... 30+ more lines
```

### ✅ **After (PostgresDatabase CRD)**
```yaml
# 8 lines - simple and developer-friendly!
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: my-app-db
spec:
  version: 17
  replicas: 3
  storage: 10Gi
  backup: true
  monitoring: true
```

---

## Step 10: Production Best Practices

### Resource Management
```yaml
# Production configuration with proper resource limits
spec:
  version: 17
  replicas: 3
  storage: 100Gi
  backup: true
  backupRetention: "30d"
  monitoring: true
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi
```

### Security Configuration
```yaml
# Enable security features
metadata:
  name: secure-db
  annotations:
    databases.mycompany.com/security-level: "high"
spec:
  version: 17
  replicas: 3
  storage: 50Gi
  backup: true
  monitoring: true
  # Security is automatically configured by controller
```

### Multi-Environment Setup
```bash
# Development
kubectl apply -f configs/dev-database.yaml

# Staging  
kubectl apply -f configs/staging-database.yaml

# Production
kubectl apply -f configs/prod-database.yaml
```

---

## Troubleshooting

### Database Stuck in "Creating" Phase
```bash
# Check controller logs
kubectl logs -n postgres-database-system deployment/postgres-database-controller

# Check underlying Percona cluster
kubectl get perconapgclusters
kubectl describe perconapgcluster my-app-db
```

### Connection Issues
```bash
# Verify service exists
kubectl get svc my-app-db

# Check pod status
kubectl get pods -l pg-cluster=my-app-db

# Test connectivity
kubectl exec -it deployment/my-app-db -- psql -c "SELECT version();"
```

### Resource Issues
```bash
# Check resource usage
kubectl top pods -l pg-cluster=my-app-db

# Verify PVCs
kubectl get pvc -l pg-cluster=my-app-db
```

---

## Migration from Direct Percona Operator

If you have existing PerconaPGCluster resources:

```bash
# 1. Export existing configuration
kubectl get perconapgcluster existing-db -o yaml > existing-db.yaml

# 2. Create PostgresDatabase equivalent
cat <<EOF | kubectl apply -f -
apiVersion: databases.mycompany.com/v1
kind: PostgresDatabase
metadata:
  name: existing-db
spec:
  version: 17
  replicas: 3
  storage: 100Gi
  backup: true
  monitoring: true
EOF

# 3. Migrate data (if needed)
kubectl exec -it existing-db-instance1-0 -- pg_dump existing_db > backup.sql
kubectl exec -it new-db-instance1-0 -- psql existing_db < backup.sql

# 4. Delete old cluster
kubectl delete perconapgcluster existing-db
```

---

## Final Checklist

- [ ] Minikube running with 8GB RAM, 4 CPUs
- [ ] Percona Operator deployed via bundle.yaml
- [ ] PostgresDatabase CRD deployed
- [ ] postgres-database-controller running
- [ ] Test database created successfully
- [ ] Database connection works via psql
- [ ] Scaling operations work
- [ ] Backup configuration works
- [ ] All pods running without errors

**When all checkmarks complete: You have a working, developer-friendly PostgreSQL platform!** 🎉

---

## Next Steps

1. **Set up CI/CD integration** - Add database creation to your deployment pipelines
2. **Configure monitoring** - Enable PMM for production databases  
3. **Set up backup policies** - Configure S3 backup storage
4. **Create database templates** - Standardize configurations for different environments
5. **Team training** - Educate developers on the 8-line database creation process

---

## Key Benefits Achieved

✅ **Developer Simplicity**: 8 lines vs 50+ lines of YAML  
✅ **ARM64 Compatible**: Works on Apple Silicon  
✅ **Production Ready**: Built on proven Percona operator  
✅ **Automated Best Practices**: HA, backups, monitoring included  
✅ **GitOps Friendly**: Declarative configuration  
✅ **Resource Efficient**: Optimized for M4 MacBook Air