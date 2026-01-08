#!/bin/bash

# CloudNativePG Demo Setup Script
# This script sets up a complete demo environment using CloudNativePG operator

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="postgres-demo"
CLUSTER_NAME="hippo-cluster"
MICROSERVICE_NAME="demo-microservice"

echo -e "${BLUE}🐘 CloudNativePG Demo Setup${NC}"
echo "==============================="

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    
    # Check if CloudNativePG operator is installed
    if ! kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
        print_warning "CloudNativePG operator CRD not found. Installing operator..."
        install_operator
    fi
    
    print_status "Prerequisites check completed"
}

# Install CloudNativePG operator
install_operator() {
    print_info "Installing CloudNativePG operator..."
    
    # Install using kubectl (official method)
    kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
    
    # Wait for operator to be ready
    print_info "Waiting for operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/cnpg-controller-manager -n cnpg-system
    
    print_status "CloudNativePG operator installed"
}

# Create namespace
create_namespace() {
    print_info "Creating namespace: $NAMESPACE"
    
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    print_status "Namespace created"
}

# Deploy PostgreSQL cluster
deploy_postgres_cluster() {
    print_info "Deploying PostgreSQL cluster: $CLUSTER_NAME"
    
    # Apply cluster configuration
    kubectl apply -f k8s/cluster/
    
    # Wait for cluster to be ready
    print_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready --timeout=600s cluster/$CLUSTER_NAME -n $NAMESPACE
    
    # Wait for all instances to be ready
    kubectl wait --for=condition=Ready --timeout=300s pod -l cnpg.io/podRole=instance -n $NAMESPACE
    
    print_status "PostgreSQL cluster deployed and ready"
}

# Initialize database
initialize_database() {
    print_info "Initializing database with schema and sample data..."
    
    # Wait for database to be fully ready
    print_info "Checking database readiness..."
    kubectl wait --for=condition=Complete --timeout=300s job/database-init -n $NAMESPACE
    
    # Verify initialization
    INIT_POD=$(kubectl get pods -n $NAMESPACE -l app=database-init -o jsonpath='{.items[0].metadata.name}')
    
    if kubectl logs -n $NAMESPACE $INIT_POD | grep -q "Database initialization completed"; then
        print_status "Database initialization completed successfully"
    else
        print_error "Database initialization failed"
        kubectl logs -n $NAMESPACE $INIT_POD
        exit 1
    fi
}

# Build and deploy microservice
deploy_microservice() {
    print_info "Building and deploying microservice..."
    
    # Update environment variables for CloudNativePG
    sed -i.bak "s|hippo-primary.postgres-demo.svc|hippo-cluster-rw.postgres-demo.svc|g" ../../common/microservice/src/server.js
    
    # Check if Docker is available
    if command -v docker &> /dev/null; then
        print_info "Building Docker image locally..."
        
        # Build image
        docker build -t $MICROSERVICE_NAME:latest ../../common/microservice/
        
        # Load image into kind cluster if using kind
        if kubectl cluster-info --context kind-* &> /dev/null; then
            kind load docker-image $MICROSERVICE_NAME:latest
            print_info "Image loaded into kind cluster"
        fi
        
        # Update deployment to use local image
        sed -i.bak2 "s|ghcr.io/your-org/demo-microservice:latest|$MICROSERVICE_NAME:latest|g" k8s/microservice/deployment.yaml
    else
        print_warning "Docker not found. Using pre-built image (may not work)"
    fi
    
    # Deploy microservice
    kubectl apply -f k8s/microservice/
    
    # Wait for deployment to be ready
    print_info "Waiting for microservice to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/$MICROSERVICE_NAME -n $NAMESPACE
    
    print_status "Microservice deployed and ready"
}

# Verify deployment
verify_deployment() {
    print_info "Verifying deployment..."
    
    # Check PostgreSQL cluster
    kubectl get cluster -n $NAMESPACE
    echo ""
    
    # Check pods
    kubectl get pods -n $NAMESPACE
    echo ""
    
    # Check services
    kubectl get svc -n $NAMESPACE
    echo ""
    
    # Test database connection
    print_info "Testing database connection..."
    
    # Port-forward and test
    kubectl port-forward -n $NAMESPACE svc/hippo-cluster-rw 5432:5432 &
    PF_PID=$!
    sleep 5
    
    if PGPASSWORD="secure_password_123" psql -h localhost -U postgres -d demo_app -c "SELECT COUNT(*) FROM users;" &> /dev/null; then
        print_status "Database connection successful"
    else
        print_error "Database connection failed"
    fi
    
    kill $PF_PID 2>/dev/null || true
    
    # Test microservice
    print_info "Testing microservice endpoints..."
    
    # Port-forward to microservice
    kubectl port-forward -n $NAMESPACE svc/$MICROSERVICE_NAME-nodeport 8080:8080 &
    MF_PID=$!
    sleep 5
    
    if curl -f http://localhost:8080/health &> /dev/null; then
        print_status "Microservice health check successful"
    else
        print_error "Microservice health check failed"
    fi
    
    if curl -f http://localhost:8080/api/users &> /dev/null; then
        print_status "Microservice API test successful"
    else
        print_error "Microservice API test failed"
    fi
    
    kill $MF_PID 2>/dev/null || true
}

# Show CloudNativePG specific information
show_cloudnativepg_info() {
    print_info "CloudNativePG Specific Information"
    echo "===================================="
    
    # Show cluster status
    echo -e "${BLUE}Cluster Status:${NC}"
    kubectl get cluster -n $NAMESPACE -o wide
    echo ""
    
    # Show instances
    echo -e "${BLUE}Cluster Instances:${NC}"
    kubectl get pods -n $NAMESPACE -l cnpg.io/podRole=instance -o wide
    echo ""
    
    # Show read-write service
    echo -e "${BLUE}Connection Information:${NC}"
    echo "  Read-Write Service: hippo-cluster-rw.$NAMESPACE.svc.local"
    echo "  Read-Only Service: hippo-cluster-ro.$NAMESPACE.svc.local"
    echo "  Database: demo_app"
    echo "  User: demo_app_user"
    echo ""
    
    # Show backup information
    echo -e "${BLUE}Backup Status:${NC}"
    kubectl get backup -n $NAMESPACE --sort-by=.metadata.creationTimestamp || echo "  No backups yet"
    echo ""
    
    # Show scheduled backups
    echo -e "${BLUE}Scheduled Backups:${NC}"
    kubectl get scheduledbackup -n $NAMESPACE || echo "  No scheduled backups configured"
    echo ""
}

# Show access information
show_access_info() {
    print_info "Access Information"
    echo "===================="
    
    show_cloudnativepg_info
    
    # Microservice access
    echo -e "${BLUE}Microservice:${NC}"
    echo "  Service: $MICROSERVICE_NAME"
    echo "  NodePort: http://localhost:30080"
    echo "  API: http://localhost:8080/api"
    echo ""
    
    # Port-forward commands
    echo -e "${BLUE}Port-forward commands:${NC}"
    echo "  PostgreSQL (RW): kubectl port-forward -n $NAMESPACE svc/hippo-cluster-rw 5432:5432"
    echo "  PostgreSQL (RO): kubectl port-forward -n $NAMESPACE svc/hippo-cluster-ro 5432:5432"
    echo "  Microservice: kubectl port-forward -n $NAMESPACE svc/$MICROSERVICE_NAME-nodeport 8080:8080"
    echo ""
    
    # CloudNativePG specific commands
    echo -e "${BLUE}CloudNativePG Commands:${NC}"
    echo "  View cluster status: kubectl get cluster $CLUSTER_NAME -n $NAMESPACE -o yaml"
    echo "  Create backup: kubectl create backup backup-$(date +%Y%m%d) --cluster=$CLUSTER_NAME -n $NAMESPACE"
    echo "  View backups: kubectl get backup -n $NAMESPACE"
    echo "  Failover: kubectl patch cluster $CLUSTER_NAME -n $NAMESPACE -p '{\"spec\":{\"instances\":4}}'"
    echo ""
    
    # Example API calls
    echo -e "${BLUE}Example API calls:${NC}"
    echo "  curl http://localhost:8080/health"
    echo "  curl http://localhost:8080/api/users"
    echo "  curl http://localhost:8080/api/tasks"
    echo "  curl http://localhost:8080/api/categories"
}

# Cleanup function
cleanup() {
    print_warning "Cleaning up..."
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Restore original files
    if [ -f ../../common/microservice/src/server.js.bak ]; then
        mv ../../common/microservice/src/server.js.bak ../../common/microservice/src/server.js
    fi
    
    print_status "Cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT

# Main execution
main() {
    print_info "Starting CloudNativePG demo setup..."
    
    check_prerequisites
    create_namespace
    deploy_postgres_cluster
    initialize_database
    deploy_microservice
    verify_deployment
    show_access_info
    
    print_status "CloudNativePG demo setup completed successfully! 🎉"
    echo ""
    print_info "Use the commands above to access the demo applications."
    print_info "Check out the CloudNativePG-specific commands for advanced operations."
}

# Run main function
main "$@"