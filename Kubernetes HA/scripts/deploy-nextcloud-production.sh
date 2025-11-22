#!/bin/bash
#
# Deploy Nextcloud - Production (Alle Stufen)
# Deployt eine vollständige produktionsreife Nextcloud-Installation
#
# Verwendung: ./deploy-nextcloud-production.sh
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
DOMAIN="${NEXTCLOUD_DOMAIN:-nextcloud.yourdomain.com}"
EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"

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

    local ALL_GOOD=true

    # kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        ALL_GOOD=false
    fi

    # Cluster-Verbindung
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        ALL_GOOD=false
    fi

    # StorageClass
    if ! kubectl get storageclass &> /dev/null; then
        log_error "No StorageClass found"
        ALL_GOOD=false
    fi

    # Nginx Ingress Controller
    if ! kubectl get ingressclass nginx &> /dev/null; then
        log_warning "Nginx IngressClass not found. Ingress deployment will be skipped."
    fi

    # Cert-Manager
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_warning "Cert-Manager not found. TLS deployment will be skipped."
    fi

    # Prometheus Operator
    if ! kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
        log_warning "Prometheus Operator not found. Monitoring deployment will be skipped."
    fi

    if [ "$ALL_GOOD" = false ]; then
        log_error "Prerequisites check failed. Exiting."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

check_configuration() {
    log_info "Checking configuration..."

    if [ "$DOMAIN" = "nextcloud.yourdomain.com" ]; then
        log_warning "Using default domain: $DOMAIN"
        echo "Set environment variable NEXTCLOUD_DOMAIN to change:"
        echo "  export NEXTCLOUD_DOMAIN=nextcloud.example.com"
        echo ""
        read -p "Continue with default domain? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi

    if [ "$EMAIL" = "admin@example.com" ]; then
        log_warning "Using default email: $EMAIL"
        echo "Set environment variable LETSENCRYPT_EMAIL to change:"
        echo "  export LETSENCRYPT_EMAIL=yourmail@example.com"
        echo ""
    fi

    log_success "Configuration OK"
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
        echo ""
        log_success "Password generated: $DB_PASSWORD"
        echo "⚠️  IMPORTANT: Save this password securely!"
        echo ""

        # Save to file
        echo "$DB_PASSWORD" > .nextcloud-db-password
        chmod 600 .nextcloud-db-password
        log_info "Password saved to: .nextcloud-db-password"
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
    log_info "Deploying Nextcloud (3 replicas)..."

    # Update TRUSTED_DOMAINS in deployment
    sed "s/nextcloud.yourdomain.com/$DOMAIN/g" "$MANIFESTS_DIR/05-nextcloud-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "$MANIFESTS_DIR/06-nextcloud-service.yaml"

    log_info "Waiting for Nextcloud to be ready (this may take 2-3 minutes)..."
    kubectl wait --for=condition=ready pod -l app=nextcloud -n $NAMESPACE --timeout=600s

    log_success "Nextcloud deployed and ready"
}

deploy_network_policies() {
    log_info "Deploying Network Policies..."
    kubectl apply -f "$MANIFESTS_DIR/09-network-policies.yaml"
    log_success "Network Policies configured"
}

deploy_hpa() {
    log_info "Deploying Horizontal Pod Autoscaler..."

    # Check if Metrics Server is available
    if kubectl get apiservice v1beta1.metrics.k8s.io &> /dev/null; then
        kubectl apply -f "$MANIFESTS_DIR/12-hpa.yaml"
        log_success "HPA configured"
    else
        log_warning "Metrics Server not found. Skipping HPA deployment."
        log_warning "Install Metrics Server for autoscaling support."
    fi
}

deploy_ingress() {
    if ! kubectl get ingressclass nginx &> /dev/null; then
        log_warning "Nginx Ingress not available. Skipping Ingress deployment."
        return
    fi

    log_info "Deploying Ingress..."
    sed -e "s/nextcloud.yourdomain.com/$DOMAIN/g" \
        "$MANIFESTS_DIR/07-ingress.yaml" | kubectl apply -f -

    log_success "Ingress configured"
}

deploy_certificate() {
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_warning "Cert-Manager not available. Skipping Certificate deployment."
        return
    fi

    log_info "Deploying TLS Certificate..."
    sed -e "s/nextcloud.yourdomain.com/$DOMAIN/g" \
        -e "s/your-email@example.com/$EMAIL/g" \
        "$MANIFESTS_DIR/08-certificate.yaml" | kubectl apply -f -

    log_info "Waiting for certificate to be ready..."
    sleep 10
    kubectl wait --for=condition=ready certificate nextcloud-tls -n $NAMESPACE --timeout=300s || {
        log_warning "Certificate not ready yet. Check later with: kubectl get certificate -n $NAMESPACE"
    }

    log_success "Certificate configured"
}

deploy_monitoring() {
    if ! kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
        log_warning "Prometheus Operator not available. Skipping Monitoring deployment."
        return
    fi

    log_info "Deploying Monitoring (ServiceMonitor, Alerts)..."
    kubectl apply -f "$MANIFESTS_DIR/10-monitoring.yaml"
    log_success "Monitoring configured"
}

deploy_backup() {
    log_info "Deploying Backup CronJob..."
    kubectl apply -f "$MANIFESTS_DIR/11-backup-cronjob.yaml"
    log_success "Backup CronJob configured (runs daily at 2 AM)"
}

show_status() {
    echo ""
    echo "========================================="
    echo "   Nextcloud Production Status"
    echo "========================================="
    echo ""

    log_info "Pods:"
    kubectl get pods -n $NAMESPACE

    echo ""
    log_info "Services:"
    kubectl get services -n $NAMESPACE

    echo ""
    log_info "Ingress:"
    kubectl get ingress -n $NAMESPACE 2>/dev/null || echo "  No Ingress configured"

    echo ""
    log_info "PVCs:"
    kubectl get pvc -n $NAMESPACE

    echo ""
    log_info "Network Policies:"
    kubectl get networkpolicies -n $NAMESPACE

    echo ""
    log_info "HPA:"
    kubectl get hpa -n $NAMESPACE 2>/dev/null || echo "  No HPA configured"

    echo ""
}

show_access_info() {
    echo "========================================="
    echo "   Access Information"
    echo "========================================="
    echo ""

    # Ingress
    INGRESS_HOST=$(kubectl get ingress nextcloud -n $NAMESPACE -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

    if [ -n "$INGRESS_HOST" ]; then
        log_success "Nextcloud is accessible at: https://$INGRESS_HOST"
        echo ""
        echo "DNS Configuration required:"
        echo "  Add DNS record: $INGRESS_HOST → $(kubectl get ingress nextcloud -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo '<INGRESS-IP>')"
        echo ""
        echo "Or add to /etc/hosts:"
        echo "  $(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo '<INGRESS-IP>') $INGRESS_HOST"
    else
        # LoadBalancer IP
        EXTERNAL_IP=$(kubectl get service nextcloud -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [ -n "$EXTERNAL_IP" ]; then
            log_success "Nextcloud is accessible at: http://$EXTERNAL_IP"
        else
            log_warning "External IP not yet assigned. Use port-forwarding:"
            echo ""
            echo "  kubectl port-forward -n $NAMESPACE service/nextcloud 8080:80"
            echo ""
            echo "  Then access: http://localhost:8080"
        fi
    fi

    echo ""
    echo "========================================="
    echo "   Next Steps"
    echo "========================================="
    echo ""
    echo "1. Access Nextcloud web interface"
    echo "2. Create admin account"
    echo "3. Install recommended apps"
    echo "4. Configure trusted domains (if needed)"
    echo "5. Test backup: kubectl create job --from=cronjob/mariadb-backup manual-test -n $NAMESPACE"
    echo ""
    log_warning "Database password saved to: .nextcloud-db-password"
    echo ""
}

# Main
main() {
    echo ""
    echo "========================================="
    echo "   Nextcloud Production Deployment"
    echo "   (All Stages: 1, 2, 3)"
    echo "========================================="
    echo ""

    check_prerequisites
    check_configuration

    # Stufe 1: Basis
    log_info "=== Stage 1: Basic Installation ==="
    create_namespace
    create_secrets
    deploy_storage
    deploy_mariadb
    deploy_nextcloud

    # Stufe 2: Production-Ready
    log_info "=== Stage 2: Production Features ==="
    deploy_network_policies
    deploy_hpa

    # Stufe 3: Enterprise
    log_info "=== Stage 3: Enterprise Features ==="
    deploy_certificate
    deploy_ingress
    deploy_monitoring
    deploy_backup

    show_status
    show_access_info

    log_success "Production deployment completed successfully! 🎉"
    echo ""
}

# Trap errors
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Run
main
