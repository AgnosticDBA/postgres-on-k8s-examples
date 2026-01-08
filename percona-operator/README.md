# Percona PostgreSQL Operator Examples

This directory contains comprehensive examples for using the [Percona PostgreSQL Operator](https://www.percona.com/doc/kubernetes-operator-for-postgresql/) to deploy and manage PostgreSQL clusters on Kubernetes.

## 🎯 **About Percona PostgreSQL Operator**

Percona PostgreSQL Operator provides enterprise-grade PostgreSQL management with focus on reliability, performance, and comprehensive monitoring. It includes:

- 🔄 **High Availability** - Automated failover with Patroni
- 💾 **Backup & Recovery** - pgBackRest with storage integration
- 📊 **Monitoring** - Percona Monitoring and Management (PMM)
- 🔒 **Security** - Built-in security best practices
- 🚀 **Scaling** - Horizontal scaling with read replicas

## 📁 **Directory Structure**

```
percona-operator/
├── k8s/
│   ├── cluster/                    # PostgreSQL cluster configurations
│   │   ├── postgrescluster.yaml    # Main cluster definition
│   │   └── init-scripts.yaml      # Database initialization scripts
│   └── microservice/              # Application deployment
│       ├── deployment.yaml        # Microservice deployment
│       └── monitoring.yaml        # Monitoring configurations
├── scripts/
│   └── setup-demo.sh             # Automated demo setup
└── docs/
    ├── operator-features.md       # Feature overview
    ├── pmm-setup.md             # PMM monitoring setup
    └── backup-restore.md         # Backup and restore guide
```

## 🚀 **Quick Start**

### **Prerequisites**

- Kubernetes cluster (v1.25+)
- kubectl configured
- Helm 3.0+
- StorageClass configured

### **1. Install Percona PostgreSQL Operator**

```bash
# Using Helm (recommended)
helm repo add percona https://percona.github.io/percona-helm-charts/
helm repo update

helm install pgo percona/pgo \
  --namespace postgres-operator-system \
  --create-namespace

# Using kubectl
kubectl apply -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/main/deploy/bundle.yaml
```

### **2. Deploy Demo Environment**

```bash
# Clone repository
git clone https://github.com/your-org/postgres-on-k8s-examples.git
cd postgres-on-k8s-examples/percona-operator

# Run automated setup
./scripts/setup-demo.sh
```

### **3. Verify Deployment**

```bash
# Check cluster status
kubectl get postgrescluster -n postgres-demo

# Check pods
kubectl get pods -n postgres-demo

# Test database connection
kubectl port-forward -n postgres-demo svc/hippo-primary 5432:5432 &
PGPASSWORD="example-password" psql -h localhost -U postgres -d demo_app -c "SELECT COUNT(*) FROM users;"

# Test microservice
kubectl port-forward -n postgres-demo svc/demo-microservice-nodeport 8080:8080 &
curl http://localhost:8080/health
```

## 🏗️ **Architecture**

### **PostgreSQL Cluster Configuration**

The demo cluster (`hippo`) includes:

- **1 Instance**: Primary PostgreSQL 16 instance
- **2 Repositories**: pgBackRest backup repositories
- **pgBouncer**: Connection pooling enabled
- **Monitoring**: pgMonitor integration
- **Storage**: 1Gi persistent volumes

```yaml
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: hippo
spec:
  postgresVersion: 16
  instances:
    - name: instance1
      dataVolumeClaimSpec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
  backups:
    pgbackrest:
      repos:
      - name: repo1
        volume:
          volumeClaimSpec:
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 1Gi
  proxy:
    pgBouncer: {}
  monitoring:
    pgmonitor:
      enabled: true
```

### **Database Initialization**

- **ConfigMap**: Initialization scripts stored as ConfigMap
- **Sidecar**: Automatic database initialization
- **Schema**: Common task management schema
- **Sample Data**: Realistic test data

### **Microservice Integration**

- **Primary Service**: `hippo-primary` for writes
- **pgBouncer Service**: `hippo-pgbouncer` for connection pooling
- **Health Checks**: Application and database health monitoring
- **Autoscaling**: Horizontal pod autoscaling based on CPU/memory

## 🎛️ **Key Features**

### **High Availability**

```bash
# Monitor cluster status
kubectl get postgrescluster hippo -n postgres-demo -o wide

# View Patroni status
kubectl exec -it hippo-instance1-xxxx -n postgres-demo -- patronictl list

# Check replication
kubectl exec -it hippo-instance1-xxxx -n postgres-demo -- psql -c "SELECT * FROM pg_stat_replication;"
```

### **Backup & Recovery**

```bash
# Create manual backup
kubectl create -f - <<EOF
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresBackup
metadata:
  name: manual-backup-$(date +%Y%m%d-%H%M%S)
  namespace: postgres-demo
spec:
  pgCluster: hippo
EOF

# View backups
kubectl get postgresbackup -n postgres-demo --sort-by=.metadata.creationTimestamp

# Restore from backup (cluster recreation)
kubectl delete postgrescluster hippo -n postgres-demo
# Then recreate cluster with same name and backup configuration
```

### **Monitoring with PMM**

```bash
# Deploy PMM Server
helm repo add percona https://percona.github.io/percona-helm-charts/
helm install pmm-server percona/pmm-server \
  --namespace pmm \
  --create-namespace

# Configure cluster for PMM monitoring
kubectl patch postgrescluster hippo -n postgres-demo --type='merge' -p='{"spec":{"pmm":{"enabled":true,"image":"percona/pmm-client:2.40.0","secret":"hippo-pmm-secret","serverHost":"pmm-server.pmm.svc"}}}'
```

## 🔧 **Configuration Options**

### **PostgreSQL Parameters**

```yaml
spec:
  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"
      work_mem: "4MB"
      maintenance_work_mem: "64MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
```

### **Connection Pooling**

```yaml
spec:
  proxy:
    pgBouncer:
      image: perconalab/percona-postgresql-operator:main-ppg16-pgbouncer
      replicas: 2
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi
```

### **Backup Configuration**

```yaml
spec:
  backups:
    pgbackrest:
      image: perconalab/percona-postgresql-operator:main-ppg16-pgbackrest
      manual:
        repoName: repo1
        options:
         - --type=full
      repos:
      - name: repo1
        schedules:
          full: "0 0 * * 6"
          diff: "0 0 * * 1-5"
          incr: "0 * * * *"
        volume:
          volumeClaimSpec:
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 1Gi
```

## 📊 **Monitoring Setup**

### **Prometheus Integration**

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: hippo-metrics
  namespace: postgres-demo
spec:
  selector:
    matchLabels:
      postgres-operator.crunchydata.com/cluster: hippo
  endpoints:
  - port: exporter
```

### **Grafana Dashboards**

Percona provides pre-built dashboards:

```bash
# Import dashboards
kubectl apply -f https://raw.githubusercontent.com/percona/grafana-dashboards/postgres/postgres-overview.json
```

## 🚨 **Troubleshooting**

### **Common Issues**

1. **Pod Pending**: Check storage class and resource requests
2. **Connection Issues**: Verify service names and pgBouncer configuration
3. **Backup Failures**: Check pgBackRest configuration and storage

### **Debug Commands**

```bash
# Check cluster status
kubectl describe postgrescluster hippo -n postgres-demo

# View pod logs
kubectl logs -n postgres-demo hippo-instance1-xxxx

# Check Patroni status
kubectl exec -it hippo-instance1-xxxx -n postgres-demo -- patronictl list

# View pgBackRest status
kubectl exec -it hippo-instance1-xxxx -n postgres-demo -- pgbackrest info
```

### **Recovery Procedures**

```bash
# View available backups
kubectl get postgresbackup -n postgres-demo

# Restore from specific backup
kubectl patch postgrescluster hippo -n postgres-demo -p='{"spec":{"bootstrap":{"pgbackrest":{"repoName":"repo1","options":["--type=full","--set=20240108-120000F"]}}}'
```

## 🏗️ **Advanced Topics**

### **Read Replicas**

```yaml
spec:
  instances:
    - name: instance1
      replicas: 2
      dataVolumeClaimSpec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

### **Custom Extensions**

```yaml
spec:
  postgresql:
    parameters:
      shared_preload_libraries: "pg_stat_statements,auto_explain"
  patroni:
    bootstrap:
      initdb:
        database: demo_app
        owner: demo_app_user
        secret:
          name: hippo-pguser-demo-app-user
```

### **Security Hardening**

```yaml
spec:
  port: 5432
  syncReplicaElectionConstraint:
    enabled: true
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: database
          operator: In
          values:
          - postgres
```

## 🔄 **Migration from Other Operators**

### **From CloudNativePG**

```bash
# Export data from CloudNativePG cluster
kubectl exec -it cloudnative-pod -- pg_dump demo_app > demo_app.sql

# Import into Percona cluster
kubectl exec -it hippo-instance1-xxxx -n postgres-demo -- psql demo_app < demo_app.sql
```

### **From Vanilla PostgreSQL**

Similar process - export data using pg_dump and import into new cluster.

## 📚 **Resources**

- [Percona PostgreSQL Operator Documentation](https://www.percona.com/doc/kubernetes-operator-for-postgresql/)
- [Percona Community Forums](https://forums.percona.com/)
- [Percona Support](https://www.percona.com/services/support)
- [Percona Training](https://www.percona.com/services/training)

## 🤝 **Contributing**

To contribute Percona examples:

1. Create feature branch
2. Add or modify examples
3. Test with Percona operator
4. Update documentation
5. Submit pull request

---

**Next Steps:**
- 📖 [Operator Features Guide](docs/operator-features.md)
- 📊 [PMM Monitoring Setup](docs/pmm-setup.md)
- 💾 [Backup & Restore Guide](docs/backup-restore.md)
- 🚨 [Troubleshooting Guide](docs/troubleshooting.md)