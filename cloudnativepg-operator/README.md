# CloudNativePG Operator Examples

This directory contains comprehensive examples for using the [CloudNativePG](https://cloudnative-pg.io/) operator to deploy and manage PostgreSQL clusters on Kubernetes.

## 🎯 **About CloudNativePG**

CloudNativePG is an open source operator designed by EDB to manage PostgreSQL workloads on Kubernetes following best practices for cloud-native environments. It provides:

- 🔄 **High Availability** - Automated failover and replication
- 💾 **Backup & Recovery** - Point-in-time recovery with Barman
- 📊 **Monitoring** - Native Prometheus metrics integration
- 🚀 **Scaling** - Read replicas and instance scaling
- 🔒 **Security** - Built-in security best practices

## 📁 **Directory Structure**

```
cloudnativepg-operator/
├── k8s/
│   ├── cluster/                    # PostgreSQL cluster configurations
│   │   ├── postgresql-cluster.yaml # Main cluster definition
│   │   ├── credentials.yaml        # Database credentials
│   │   └── init-job.yaml          # Database initialization job
│   └── microservice/              # Application deployment
│       └── deployment.yaml        # Microservice deployment
├── scripts/
│   └── setup-demo.sh             # Automated demo setup
└── docs/
    ├── operator-features.md       # Feature overview
    ├── backup-restore.md         # Backup and restore guide
    └── troubleshooting.md        # Common issues and solutions
```

## 🚀 **Quick Start**

### **Prerequisites**

- Kubernetes cluster (v1.25+)
- kubectl configured
- [Helm](https://helm.sh/) (optional)
- StorageClass configured

### **1. Install CloudNativePG Operator**

```bash
# Using kubectl (recommended)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

# Using Helm
helm repo add cloudnative-pg https://cloudnative-pg.github.io/charts
helm repo update
helm install cnpg cloudnative-pg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace
```

### **2. Deploy Demo Environment**

```bash
# Clone the repository
git clone https://github.com/your-org/postgres-on-k8s-examples.git
cd postgres-on-k8s-examples/cloudnativepg-operator

# Run the automated setup
./scripts/setup-demo.sh
```

### **3. Verify Deployment**

```bash
# Check cluster status
kubectl get cluster -n postgres-demo

# Check pods
kubectl get pods -n postgres-demo

# Test database connection
kubectl port-forward -n postgres-demo svc/hippo-cluster-rw 5432:5432 &
PGPASSWORD="secure_password_123" psql -h localhost -U postgres -d demo_app -c "SELECT COUNT(*) FROM users;"

# Test microservice
kubectl port-forward -n postgres-demo svc/demo-microservice-nodeport 8080:8080 &
curl http://localhost:8080/health
```

## 🏗️ **Architecture**

### **PostgreSQL Cluster Configuration**

The demo cluster (`hippo-cluster`) includes:

- **3 Instances**: Primary + 2 replicas for high availability
- **1Gi Storage**: Persistent volumes for data
- **Backup**: S3-compatible storage with 30-day retention
- **Monitoring**: Prometheus metrics enabled
- **Connection Pooling**: Built-in connection management

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: hippo-cluster
spec:
  instances: 3
  storage:
    size: 1Gi
  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: "s3://postgres-backups/hippo-cluster"
```

### **Database Initialization**

- **Init Job**: Automated database setup using Kubernetes Job
- **Schema**: Common task management schema
- **Sample Data**: Realistic test data for demonstration
- **Permissions**: Proper user roles and permissions

### **Microservice Integration**

- **Read-Write Service**: `hippo-cluster-rw` for writes
- **Read-Only Service**: `hippo-cluster-ro` for reads
- **Connection Failover**: Automatic primary/replica routing
- **Health Checks**: Application and database health monitoring

## 🎛️ **Key Features**

### **High Availability**

```bash
# Monitor cluster status
kubectl get cluster hippo-cluster -n postgres-demo -o wide

# View instances
kubectl get pods -n postgres-demo -l cnpg.io/podRole=instance

# Trigger failover (if needed)
kubectl patch cluster hippo-cluster -n postgres-demo -p '{"spec":{"instances":4}}'
```

### **Backup & Recovery**

```bash
# Create on-demand backup
kubectl create backup backup-$(date +%Y%m%d) --cluster=hippo-cluster -n postgres-demo

# View backups
kubectl get backup -n postgres-demo --sort-by=.metadata.creationTimestamp

# View backup details
kubectl get backup backup-20240108 -n postgres-demo -o yaml

# Restore from backup
kubectl create cluster restored-cluster \
  --from-backup=backup-20240108 \
  -n postgres-demo
```

### **Monitoring & Observability**

```bash
# View cluster metrics
kubectl exec -n postgres-demo deployment/cnpg-controller-manager -- curl localhost:8080/metrics

# View instance logs
kubectl logs -n postgres-demo hippo-cluster-1 -c postgres

# Check resource usage
kubectl top pods -n postgres-demo -l cnpg.io/podRole=instance
```

### **Scaling**

```bash
# Add read replicas
kubectl patch cluster hippo-cluster -n postgres-demo -p '{"spec":{"instances":5}}'

# Update resources
kubectl patch cluster hippo-cluster -n postgres-demo -p '{"spec":{"resources":{"requests":{"memory":"512Mi","cpu":"500m"}}}'

# Scale storage
kubectl patch cluster hippo-cluster -n postgres-demo -p '{"spec":{"storage":{"size":"2Gi"}}}'
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
      maintenance_work_mem: "64MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
```

### **Connection Management**

```yaml
spec:
  postgresql:
    pg_hba:
      - host all all 10.0.0.0/8 md5
      - host all all 172.16.0.0/12 md5
      - host all all 192.168.0.0/16 md5
```

### **Backup Configuration**

```yaml
spec:
  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: "s3://postgres-backups/hippo-cluster"
      wal:
        compression: gzip
        retention: "7d"
      data:
        compression: gzip
        jobs: 2
      s3Credentials:
        accessKeyId:
          name: backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-credentials
          key: SECRET_ACCESS_KEY
```

## 📊 **Monitoring Setup**

### **Prometheus Integration**

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: hippo-cluster-monitoring
  namespace: postgres-demo
spec:
  selector:
    matchLabels:
      cnpg.io/clusterName: hippo-cluster
  endpoints:
  - port: metrics
```

### **Grafana Dashboard**

CloudNativePG provides pre-built Grafana dashboards:

```bash
# Import dashboard
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/grafana-dashboard.yaml
```

## 🚨 **Troubleshooting**

### **Common Issues**

1. **Pod Pending**: Check storage class and resource requests
2. **Connection Issues**: Verify service names and credentials
3. **Backup Failures**: Check S3 credentials and permissions

### **Debug Commands**

```bash
# Check cluster status
kubectl describe cluster hippo-cluster -n postgres-demo

# View pod logs
kubectl logs -n postgres-demo hippo-cluster-1 -c postgres

# Check events
kubectl get events -n postgres-demo --sort-by=.metadata.creationTimestamp

# Test database connectivity
kubectl exec -it hippo-cluster-1 -n postgres-demo -- psql -c "SELECT version();"
```

### **Recovery Procedures**

```bash
# Bootstrap from backup
kubectl create cluster recovered-cluster \
  --bootstrap-from-backup backup-20240108 \
  -n postgres-demo

# Force failover
kubectl patch cluster hippo-cluster -n postgres-demo -p '{"spec":{"instances":2}}'
kubectl patch cluster hippo-cluster -n postgres-demo -p '{"spec":{"instances":3}}'
```

## 🏗️ **Advanced Topics**

### **Multi-Region Setup**

```yaml
# Configure multiple regions with object storage
spec:
  backup:
    barmanObjectStore:
      destinationPath: "s3://postgres-backups/region1/hippo-cluster"
      # Region-specific configuration
```

### **Custom Extensions**

```yaml
spec:
  postgresql:
    enableAlterSystem: true
    sharedPreloadLibraries:
      - pg_stat_statements
      - auto_explain
  monitoring:
    enabled: true
    queries:
      enabled: true
```

### **Security Hardening**

```yaml
spec:
  bootstrap:
    initdb:
      database: postgres
      owner: postgres
      secret:
        name: postgres-credentials
  externalClusters:
    - name: source-cluster
      connectionParameters:
        host: source-cluster-rw.default.svc.local
        user: postgres
        dbname: postgres
```

## 🔄 **Migration from Other Operators**

### **From Percona Operator**

```bash
# Export data from Percona cluster
kubectl exec -it percona-pod -- pg_dump demo_app > demo_app.sql

# Import into CloudNativePG cluster
kubectl exec -it hippo-cluster-1 -- psql demo_app < demo_app.sql
```

### **From CrunchyData Operator**

Similar process - export data and import into new cluster.

## 📚 **Resources**

- [CloudNativePG Documentation](https://cloudnative-pg.io/docs/current/)
- [CloudNativePG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
- [CloudNativePG Community](https://cloudnative-pg.io/community/)
- [EDB Support](https://www.enterprisedb.com/support)

## 🤝 **Contributing**

To contribute CloudNativePG examples:

1. Create feature branch
2. Add or modify examples
3. Test with CloudNativePG operator
4. Update documentation
5. Submit pull request

---

**Next Steps:**
- 📖 [Operator Features Guide](docs/operator-features.md)
- 🔄 [Backup & Restore Guide](docs/backup-restore.md)
- 🚨 [Troubleshooting Guide](docs/troubleshooting.md)
- ⚡ [Performance Tuning](docs/performance-tuning.md)