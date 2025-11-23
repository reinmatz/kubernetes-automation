#!/bin/bash
#
# Backup Nextcloud - Vollständiges Backup (Datenbank + Dateien + Manifeste)
#
# Verwendung: ./backup-nextcloud.sh [backup-directory]
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
BACKUP_BASE_DIR="${1:-./backups}"
BACKUP_DIR="$BACKUP_BASE_DIR/nextcloud-$(date +%Y%m%d-%H%M%S)"

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
        log_error "kubectl not found"
        exit 1
    fi

    # Cluster-Verbindung
    if ! kubectl cluster-info dump &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Namespace exists
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "Namespace $NAMESPACE not found"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created"
}

backup_kubernetes_manifests() {
    log_info "Backing up Kubernetes manifests..."

    kubectl get all,pvc,secrets,ingress,networkpolicies,servicemonitors,cronjobs,hpa,poddisruptionbudgets \
        -n $NAMESPACE \
        -o yaml > "$BACKUP_DIR/kubernetes-manifests.yaml"

    log_success "Manifests backed up"
}

backup_secrets() {
    log_info "Backing up Secrets (separately for security)..."

    kubectl get secrets -n $NAMESPACE -o yaml > "$BACKUP_DIR/secrets.yaml"

    log_warning "Secrets backed up to: $BACKUP_DIR/secrets.yaml"
    log_warning "⚠️  This file contains sensitive data! Keep it secure!"
}

enable_maintenance_mode() {
    log_info "Enabling Nextcloud maintenance mode..."

    # Get first Nextcloud pod
    NEXTCLOUD_POD=$(kubectl get pods -n $NAMESPACE -l app=nextcloud -o jsonpath='{.items[0].metadata.name}')

    kubectl exec -n $NAMESPACE $NEXTCLOUD_POD -- \
        su -s /bin/bash www-data -c "php occ maintenance:mode --on" || {
        log_warning "Could not enable maintenance mode (Nextcloud might not be fully initialized)"
    }

    log_success "Maintenance mode enabled"
}

disable_maintenance_mode() {
    log_info "Disabling Nextcloud maintenance mode..."

    NEXTCLOUD_POD=$(kubectl get pods -n $NAMESPACE -l app=nextcloud -o jsonpath='{.items[0].metadata.name}')

    kubectl exec -n $NAMESPACE $NEXTCLOUD_POD -- \
        su -s /bin/bash www-data -c "php occ maintenance:mode --off" || {
        log_warning "Could not disable maintenance mode"
    }

    log_success "Maintenance mode disabled"
}

backup_database() {
    log_info "Backing up MariaDB database..."

    # Get database password
    DB_PASSWORD=$(kubectl get secret nextcloud-db -n $NAMESPACE -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d)

    # Create database dump
    kubectl exec -n $NAMESPACE mariadb-0 -- bash -c "
        mysqldump -u root -p$DB_PASSWORD \
            --single-transaction \
            --quick \
            --lock-tables=false \
            --routines \
            --triggers \
            --events \
            --all-databases \
            --add-drop-database \
            --add-drop-table \
            --hex-blob \
        | gzip -9
    " > "$BACKUP_DIR/database.sql.gz"

    # Verify backup
    if [ -s "$BACKUP_DIR/database.sql.gz" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_DIR/database.sql.gz" | cut -f1)
        log_success "Database backed up (Size: $BACKUP_SIZE)"
    else
        log_error "Database backup failed (file is empty)"
        exit 1
    fi
}

backup_nextcloud_files() {
    log_info "Creating PVC snapshot for Nextcloud files..."

    # Check if VolumeSnapshot is supported
    if kubectl get crd volumesnapshots.snapshot.storage.k8s.io &> /dev/null; then
        SNAPSHOT_NAME="nextcloud-data-snapshot-$(date +%Y%m%d-%H%M%S)"

        cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: nextcloud-data
EOF

        log_success "PVC snapshot created: $SNAPSHOT_NAME"
        echo "$SNAPSHOT_NAME" > "$BACKUP_DIR/volumesnapshot-name.txt"
    else
        log_warning "VolumeSnapshot not supported. Skipping file backup."
        log_warning "Consider using Velero for complete backup solution."
    fi
}

create_backup_manifest() {
    log_info "Creating backup manifest..."

    cat > "$BACKUP_DIR/BACKUP_INFO.txt" <<EOF
Nextcloud Backup Information
============================

Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Namespace: $NAMESPACE

Files in this backup:
- kubernetes-manifests.yaml: All Kubernetes resources
- secrets.yaml: Secrets (⚠️ KEEP SECURE!)
- database.sql.gz: MariaDB database dump
- volumesnapshot-name.txt: VolumeSnapshot name (if created)

Restore Instructions:
See: ../../Nextcloud_Production_Installation_Guide.md
Section: 7.2 Disaster Recovery

Cluster Info:
$(kubectl cluster-info 2>&1 | head -1)

Kubernetes Version:
$(kubectl version --short 2>&1 | grep Server)

Resources at backup time:
$(kubectl get pods,pvc -n $NAMESPACE 2>&1)
EOF

    log_success "Backup manifest created"
}

show_backup_summary() {
    echo ""
    echo "========================================="
    echo "   Backup Summary"
    echo "========================================="
    echo ""

    log_success "Backup completed successfully!"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo ""
    echo "Files:"
    ls -lh "$BACKUP_DIR"
    echo ""

    TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    log_info "Total backup size: $TOTAL_SIZE"

    echo ""
    log_warning "Security Reminder:"
    echo "  - secrets.yaml contains sensitive data"
    echo "  - database.sql.gz may contain user data"
    echo "  - Store backup securely (encrypted, off-site)"
    echo ""
}

# Main
main() {
    echo ""
    echo "========================================="
    echo "   Nextcloud Full Backup"
    echo "========================================="
    echo ""

    check_prerequisites
    create_backup_directory

    # Backup sequence
    enable_maintenance_mode
    backup_kubernetes_manifests
    backup_secrets
    backup_database
    backup_nextcloud_files
    disable_maintenance_mode

    create_backup_manifest
    show_backup_summary

    log_success "Backup process completed! 🎉"
    echo ""
}

# Trap errors
trap 'log_error "Backup failed at line $LINENO"; disable_maintenance_mode 2>/dev/null; exit 1' ERR

# Trap exit to ensure maintenance mode is disabled
trap 'disable_maintenance_mode 2>/dev/null' EXIT

# Run
main
