#!/bin/bash

# Demo setup script for PostgreSQL Operator examples
# This script sets up a complete demo environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="postgres-demo"
CLUSTER_NAME="hippo"
MICROSERVICE_NAME="demo-microservice"

echo -e "${BLUE}🚀 PostgreSQL Operator Demo Setup${NC}"
echo "=================================="

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
    
    # Check if PostgreSQL operator is installed
    if ! kubectl get crd postgresclusters.postgres-operator.crunchydata.com &> /dev/null; then
        print_warning "PostgreSQL operator CRD not found. Installing operator..."
        install_operator
    fi
    
    print_status "Prerequisites check completed"
}

# Install PostgreSQL operator
install_operator() {
    print_info "Installing PostgreSQL operator..."
    
    # Add operator helm repository
    helm repo add pgo https://percona.github.io/percona-helm-charts/
    helm repo update
    
    # Install operator
    helm install pgo pgo/pgo \
        --namespace postgres-operator-system \
        --create-namespace \
        --wait
    
    print_status "PostgreSQL operator installed"
}

# Create namespace
create_namespace() {
    print_info "Creating namespace: $NAMESPACE"
    
    kubectl apply -f examples/k8s/namespace.yaml
    
    print_status "Namespace created"
}

# Deploy PostgreSQL cluster
deploy_postgres_cluster() {
    print_info "Deploying PostgreSQL cluster: $CLUSTER_NAME"
    
    # Apply cluster configuration
    kubectl apply -f examples/k8s/cluster/
    
    # Wait for cluster to be ready
    print_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=ready --timeout=600s postgrescluster/$CLUSTER_NAME -n $NAMESPACE
    
    print_status "PostgreSQL cluster deployed and ready"
}

# Initialize database
initialize_database() {
    print_info "Initializing database with schema and sample data..."
    
    # Wait for primary pod to be ready
    PRIMARY_POD=$(kubectl get pods -n $NAMESPACE -l postgres-operator.crunchydata.com/role=primary -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$PRIMARY_POD" ]; then
        print_error "Primary pod not found"
        exit 1
    fi
    
    print_info "Primary pod: $PRIMARY_POD"
    
    # Wait for pod to be ready
    kubectl wait --for=condition=ready --timeout=300s pod/$PRIMARY_POD -n $NAMESPACE
    
    # Copy initialization scripts
    kubectl cp examples/database/ $NAMESPACE/$PRIMARY_POD:/tmp/
    
    # Execute initialization scripts
    kubectl exec -n $NAMESPACE $PRIMARY_POD -- psql -d postgres -f /tmp/schema.sql
    kubectl exec -n $NAMESPACE $PRIMARY_POD -- psql -d demo_app -f /tmp/sample-data.sql
    
    print_status "Database initialized"
}

# Build and deploy microservice
deploy_microservice() {
    print_info "Building and deploying microservice..."
    
    # Check if Docker is available
    if command -v docker &> /dev/null; then
        print_info "Building Docker image locally..."
        
        # Build image
        docker build -t $MICROSERVICE_NAME:latest examples/microservice/
        
        # Load image into kind cluster if using kind
        if kubectl cluster-info --context kind-* &> /dev/null; then
            kind load docker-image $MICROSERVICE_NAME:latest
            print_info "Image loaded into kind cluster"
        fi
        
        # Update deployment to use local image
        sed -i.bak "s|ghcr.io/your-org/demo-microservice:latest|$MICROSERVICE_NAME:latest|g" examples/k8s/microservice/deployment.yaml
    else
        print_warning "Docker not found. Using pre-built image (may not work)"
    fi
    
    # Deploy microservice
    kubectl apply -f examples/k8s/microservice/
    
    # Wait for deployment to be ready
    print_info "Waiting for microservice to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/$MICROSERVICE_NAME -n $NAMESPACE
    
    print_status "Microservice deployed and ready"
}

# Verify deployment
verify_deployment() {
    print_info "Verifying deployment..."
    
    # Check PostgreSQL cluster
    kubectl get postgrescluster -n $NAMESPACE
    echo ""
    
    # Check pods
    kubectl get pods -n $NAMESPACE
    echo ""
    
    # Check services
    kubectl get svc -n $NAMESPACE
    echo ""
    
    # Test database connection
    print_info "Testing database connection..."
    PRIMARY_SERVICE=$(kubectl get postgrescluster $CLUSTER_NAME -n $NAMESPACE -o jsonpath='{.status.primaryService}')
    
    # Port-forward and test
    kubectl port-forward -n $NAMESPACE svc/$PRIMARY_SERVICE 5432:5432 &
    PF_PID=$!
    sleep 5
    
    if PGPASSWORD="example-password" psql -h localhost -U postgres -d demo_app -c "SELECT COUNT(*) FROM users;" &> /dev/null; then
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

# Show access information
show_access_info() {
    print_info "Access Information"
    echo "===================="
    
    # PostgreSQL connection
    PRIMARY_SERVICE=$(kubectl get postgrescluster $CLUSTER_NAME -n $NAMESPACE -o jsonpath='{.status.primaryService}')
    echo -e "${BLUE}PostgreSQL:${NC}"
    echo "  Service: $PRIMARY_SERVICE"
    echo "  Database: demo_app"
    echo "  User: demo_app_user"
    echo ""
    
    # Microservice access
    echo -e "${BLUE}Microservice:${NC}"
    echo "  Service: $MICROSERVICE_NAME"
    echo "  NodePort: http://localhost:30080"
    echo "  API: http://localhost:8080/api"
    echo ""
    
    # Port-forward commands
    echo -e "${BLUE}Port-forward commands:${NC}"
    echo "  PostgreSQL: kubectl port-forward -n $NAMESPACE svc/$PRIMARY_SERVICE 5432:5432"
    echo "  Microservice: kubectl port-forward -n $NAMESPACE svc/$MICROSERVICE_NAME-nodeport 8080:8080"
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
    
    print_status "Cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT

# Main execution
main() {
    print_info "Starting PostgreSQL Operator demo setup..."
    
    check_prerequisites
    create_namespace
    deploy_postgres_cluster
    initialize_database
    deploy_microservice
    verify_deployment
    show_access_info
    
    print_status "Demo setup completed successfully! 🎉"
    echo ""
    print_info "Use the commands above to access the demo applications."
}

# Run main function
main "$@"