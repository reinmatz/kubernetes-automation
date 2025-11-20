#!/bin/bash
# Kubernetes HA Cluster Automation - Bootstrap Script
# Usage: bash bootstrap.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

print_header() {
  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║     Kubernetes HA Cluster Bootstrap                    ║"
  echo "║     $1"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""
}

# ===== MAIN FLOW =====

print_header "Phase 1: Environment Check"

# Check OS
if [[ ! "$OSTYPE" == "linux-gnu"* ]] && [[ ! "$OSTYPE" == "darwin"* ]]; then
  error "Unsupported OS: $OSTYPE (require Linux or macOS)"
  exit 1
fi
success "OS compatible: $OSTYPE"

# Check Python
if ! command -v python3 &> /dev/null; then
  error "Python3 not found. Install first: sudo apt install python3"
  exit 1
fi
success "Python3 found: $(python3 --version)"

# Check Git
if ! command -v git &> /dev/null; then
  error "Git not found. Install first: sudo apt install git"
  exit 1
fi
success "Git found: $(git --version)"

# ===== ANSIBLE SETUP =====

print_header "Phase 2: Install Ansible"

if command -v ansible &> /dev/null; then
  success "Ansible already installed: $(ansible --version | head -1)"
else
  info "Installing Ansible..."
  python3 -m pip install --upgrade pip > /dev/null 2>&1
  pip install ansible-core requests jinja2 > /dev/null 2>&1
  success "Ansible installed: $(ansible --version | head -1)"
fi

# ===== COLLECTIONS =====

print_header "Phase 3: Install Ansible Collections"

info "Installing required collections..."
ansible-galaxy collection install \
  community.general \
  kubernetes.core \
  ansible.posix \
  --quiet

success "Collections installed"

# ===== SSH KEY =====

print_header "Phase 4: SSH Key Configuration"

SSH_KEY_PATH="$HOME/.ssh/k8s_cluster"

if [ -f "$SSH_KEY_PATH" ]; then
  success "SSH key exists: $SSH_KEY_PATH"
else
  warning "SSH key not found. Creating..."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -C "k8s-automation" -N "" > /dev/null 2>&1
  chmod 600 "$SSH_KEY_PATH"
  success "SSH key created: $SSH_KEY_PATH"
  echo ""
  warning "Copy public key to nodes:"
  echo "  for ip in 10 11 12 20 21; do"
  echo "    ssh-copy-id -i $SSH_KEY_PATH debian@192.168.100.\${ip}"
  echo "  done"
fi

# ===== DIRECTORY STRUCTURE =====

print_header "Phase 5: Create Ansible Structure"

ANSIBLE_DIR="ansible"

if [ ! -d "$ANSIBLE_DIR" ]; then
  info "Creating ansible directory structure..."
  
  mkdir -p "$ANSIBLE_DIR"/{inventory,roles,playbooks,templates,files}
  mkdir -p "$ANSIBLE_DIR"/inventory/{group_vars,host_vars}
  
  success "Directory structure created"
else
  success "Ansible directory already exists"
fi

# ===== INVENTORY CHECK =====

print_header "Phase 6: Inventory Configuration"

INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"

if [ ! -f "$INVENTORY_FILE" ]; then
  warning "Inventory file not found!"
  echo ""
  echo "Create $INVENTORY_FILE with your node details:"
  echo ""
  echo "Example:"
  cat << 'EOF'
---
all:
  children:
    control_planes:
      hosts:
        k8s-cp1:
          ansible_host: 192.168.100.10
          node_ip: 192.168.100.10
        k8s-cp2:
          ansible_host: 192.168.100.11
          node_ip: 192.168.100.11
        k8s-cp3:
          ansible_host: 192.168.100.12
          node_ip: 192.168.100.12
    workers:
      hosts:
        k8s-w1:
          ansible_host: 192.168.100.20
          node_ip: 192.168.100.20
        k8s-w2:
          ansible_host: 192.168.100.21
          node_ip: 192.168.100.21
EOF
  echo ""
  error "Please create inventory and re-run bootstrap"
  exit 1
else
  success "Inventory file found"
fi

# ===== SSH CONNECTIVITY TEST =====

print_header "Phase 7: SSH Connectivity Test"

info "Testing connectivity to nodes..."

cd "$ANSIBLE_DIR"

UNREACHABLE=0
while IFS= read -r host; do
  if [[ "$host" =~ ^[^#]*ansible_host ]]; then
    ip=$(echo "$host" | grep -oP '(?<=ansible_host: )[^ ]*')
    if [ -n "$ip" ]; then
      if timeout 5 ssh -i "$SSH_KEY_PATH" -o "StrictHostKeyChecking=no" "debian@$ip" "echo" > /dev/null 2>&1; then
        success "$ip is reachable"
      else
        error "$ip is NOT reachable"
        UNREACHABLE=$((UNREACHABLE + 1))
      fi
    fi
  fi
done < inventory/hosts.yml

cd - > /dev/null

if [ $UNREACHABLE -gt 0 ]; then
  error "$UNREACHABLE nodes unreachable!"
  echo ""
  warning "Make sure:"
  echo "  1. VMs are powered on"
  echo "  2. Network connectivity exists"
  echo "  3. SSH keys are deployed: ssh-copy-id -i $SSH_KEY_PATH debian@<ip>"
  exit 1
fi

success "All nodes reachable!"

# ===== ANSIBLE SYNTAX CHECK =====

print_header "Phase 8: Playbook Validation"

if [ -f "$ANSIBLE_DIR/playbooks/site.yml" ]; then
  info "Validating playbook syntax..."
  if ansible-playbook --syntax-check "$ANSIBLE_DIR/playbooks/site.yml" > /dev/null 2>&1; then
    success "Playbook syntax valid"
  else
    warning "Playbook syntax errors detected"
  fi
else
  warning "Playbook not found at $ANSIBLE_DIR/playbooks/site.yml"
fi

# ===== SUMMARY =====

print_header "Phase 9: Complete!"

echo "✓ Environment ready for Kubernetes deployment"
echo ""
echo "Next steps:"
echo ""
echo "1. Review and customize inventory:"
echo "   vi $ANSIBLE_DIR/inventory/hosts.yml"
echo ""
echo "2. (Optional) Test dry-run:"
echo "   cd $ANSIBLE_DIR"
echo "   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check -v"
echo ""
echo "3. Deploy cluster (control-planes + workers):"
echo "   cd $ANSIBLE_DIR"
echo "   ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v"
echo ""
echo "4. Deploy extensions (monitoring, logging, ingress, etc):"
echo "   cd $ANSIBLE_DIR"
echo "   ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -v"
echo ""
echo "5. Verify cluster:"
echo "   ssh debian@192.168.100.10"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo ""
echo "Documentation:"
echo "   Read: ../01_Kubernetes_HA_Manual_Installation.md"
echo "   Read: ../02_Kubernetes_HA_Ansible_Automation.md"
echo ""
success "Bootstrap complete!"
