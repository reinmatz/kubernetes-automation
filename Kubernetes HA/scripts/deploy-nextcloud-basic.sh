#!/bin/bash
#
# Deploy Nextcloud - Stufe 1 (Basis-Installation)
# Deployt eine funktionierende Nextcloud mit MariaDB
#
# Verwendung: ./deploy-nextcloud-basic.sh
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguration
NAMESPACE="nextcloud-prod"
MANIFESTS_DIR="../manifests/nextcloud"

# Funktionen
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    # Cluster-Verbindung
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    # StorageClass
    if ! kubectl get storageclass &> /dev/null; then
        log_error "No StorageClass found. Please configure storage first."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"

    if kubectl get namespace $NAMESPACE &> /dev/null; then
        log_warning "Namespace $NAMESPACE already exists"
    else
        kubectl apply -f "$MANIFESTS_DIR/00-namespace.yaml"
        log_success "Namespace created"
    fi
}

create_secrets() {
    log_info "Creating secrets..."

    if kubectl get secret nextcloud-db -n $NAMESPACE &> /dev/null; then
        log_warning "Secret 'nextcloud-db' already exists. Skipping."
        return
    fi

    echo ""
    echo "Please enter a secure database password (or press Enter for auto-generation):"
    read -s -p "Database Password: " DB_PASSWORD
    echo

    if [ -z "$DB_PASSWORD" ]; then
        log_info "Generating random password..."
        DB_PASSWORD=$(openssl rand -base64 32)
        log_success "Password generated: $DB_PASSWORD"
        echo "⚠️  IMPORTANT: Save this password securely!"
    fi

    kubectl create secret generic nextcloud-db \
        --namespace $NAMESPACE \
        --from-literal=MYSQL_ROOT_PASSWORD=$DB_PASSWORD \
        --from-literal=MYSQL_PASSWORD=$DB_PASSWORD \
        --from-literal=MYSQL_DATABASE=nextcloud \
        --from-literal=MYSQL_USER=nextcloud \
        --from-literal=MYSQL_HOST=mariadb

    log_success "Secrets created"
}

deploy_storage() {
    log_info "Deploying storage (PVCs)..."
    kubectl apply -f "$MANIFESTS_DIR/02-storage.yaml"
    log_success "Storage configured"
}

deploy_mariadb() {
    log_info "Deploying MariaDB StatefulSet..."
    kubectl apply -f "$MANIFESTS_DIR/03-mariadb-statefulset.yaml"
    kubectl apply -f "$MANIFESTS_DIR/04-mariadb-service.yaml"

    log_info "Waiting for MariaDB to be ready..."
    kubectl wait --for=condition=ready pod -l app=mariadb -n $NAMESPACE --timeout=300s

    log_success "MariaDB deployed and ready"
}

deploy_nextcloud() {
    log_info "Deploying Nextcloud..."
    kubectl apply -f "$MANIFESTS_DIR/05-nextcloud-deployment.yaml"
    kubectl apply -f "$MANIFESTS_DIR/06-nextcloud-service.yaml"

    log_info "Waiting for Nextcloud to be ready (this may take 2-3 minutes)..."
    kubectl wait --for=condition=ready pod -l app=nextcloud -n $NAMESPACE --timeout=600s

    log_success "Nextcloud deployed and ready"
}

show_status() {
    echo ""
    echo "========================================="
    echo "   Nextcloud Deployment Status"
    echo "========================================="
    echo ""

    log_info "Pods:"
    kubectl get pods -n $NAMESPACE

    echo ""
    log_info "Services:"
    kubectl get services -n $NAMESPACE

    echo ""
    log_info "PVCs:"
    kubectl get pvc -n $NAMESPACE

    echo ""
}

show_access_info() {
    echo "========================================="
    echo "   Access Information"
    echo "========================================="
    echo ""

    # LoadBalancer IP
    EXTERNAL_IP=$(kubectl get service nextcloud -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$EXTERNAL_IP" ]; then
        log_success "Nextcloud is accessible at: http://$EXTERNAL_IP"
    else
        log_warning "LoadBalancer IP not yet assigned. Use port-forwarding:"
        echo ""
        echo "  kubectl port-forward -n $NAMESPACE service/nextcloud 8080:80"
        echo ""
        echo "  Then access: http://localhost:8080"
    fi

    echo ""
    echo "Initial Setup:"
    echo "  - Create admin account in web interface"
    echo "  - Install recommended apps"
    echo ""
    log_warning "Remember to save your database password securely!"
    echo ""
}

# Main
main() {
    echo ""
    echo "========================================="
    echo "   Nextcloud Basic Deployment (Stufe 1)"
    echo "========================================="
    echo ""

    check_prerequisites
    create_namespace
    create_secrets
    deploy_storage
    deploy_mariadb
    deploy_nextcloud
    show_status
    show_access_info

    log_success "Deployment completed successfully! 🎉"
    echo ""
}

# Trap errors
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Run
main
