# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **Kubernetes High-Availability (HA) Cluster** documentation and automation repository focused on on-premise Debian 12 deployments. It contains comprehensive guides for manual installation, Ansible automation, and GitOps workflows using Flux CD.

### Core Purpose
- Manual HA Kubernetes cluster setup (educational)
- Production-ready Ansible automation for cluster deployment
- GitOps integration with Flux CD and GitHub Actions
- Complete monitoring, logging, and security extensions

### Technology Stack
- **OS**: Debian 11/12
- **Kubernetes**: v1.28+ (kubeadm)
- **Container Runtime**: containerd
- **CNI**: Flannel
- **Load Balancer**: MetalLB
- **Ingress**: Nginx Ingress Controller
- **Monitoring**: Prometheus + Grafana
- **Logging**: Loki + Promtail
- **Security**: Cert-Manager
- **GitOps**: Flux CD v2
- **IaC**: Ansible

## Repository Structure

```
/files/
├── 01_Kubernetes_HA_Manual_Installation.md    # Step-by-step manual setup guide
├── 02_Kubernetes_HA_Ansible_Automation.md     # Ansible automation guide
├── 03_Kubernetes_HA_GitOps_Setup.md           # GitOps with Flux CD
├── README_Ansible_Guide.md                     # Quick start Ansible guide
├── COMPLETE_SOLUTION_OVERVIEW.md              # Overview of all three parts
├── Kubernetes_Kurszusammenfassung.md          # German course summary
│
├── bootstrap.sh                                # One-liner automation setup script
├── site_playbook.yml                          # Main Ansible playbook (cluster + extensions)
├── extensions_playbook.yml                    # Extensions deployment playbook
├── inventory_hosts.yml                        # Ansible inventory template
│
├── flux_examples.yaml                         # Flux CD configuration examples
├── github_workflows.md                        # GitHub Actions CI/CD workflows
└── gitops_cheatsheet.md                       # Quick reference for GitOps operations
```

## Architecture Overview

### Cluster Topology (Default Configuration)
```
Control Planes (HA):
├─ k8s-cp1: 192.168.100.10 (4CPU/8GB) - First control plane
├─ k8s-cp2: 192.168.100.11 (4CPU/8GB)
└─ k8s-cp3: 192.168.100.12 (4CPU/8GB)

Worker Nodes:
├─ k8s-w1: 192.168.100.20 (8CPU/16GB)
└─ k8s-w2: 192.168.100.21 (8CPU/16GB)

Load Balancer (Optional):
└─ k8s-lb: 192.168.100.100 (Virtual IP)

Network Configuration:
├─ Pod Network: 10.244.0.0/16 (Flannel)
├─ Service CIDR: 10.96.0.0/12
└─ MetalLB Range: 192.168.100.200-210
```

### Component Architecture

**Cluster Foundation:**
- HA Control Plane with 3 nodes + etcd cluster
- kubeadm for cluster initialization
- Flannel CNI for pod networking
- Local Path Provisioner for storage

**Extensions:**
- MetalLB for LoadBalancer services (external IPs)
- Nginx Ingress Controller for HTTP/HTTPS routing
- Prometheus + Grafana for metrics and dashboards
- Loki + Promtail for log aggregation
- Cert-Manager for automated TLS certificate management
- Flux CD for GitOps-based deployments

## Common Commands

### Ansible Automation

```bash
# Bootstrap environment (one-time setup)
bash files/bootstrap.sh

# Deploy complete cluster (cluster + all extensions)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v

# Deploy only Kubernetes cluster (no extensions)
ansible-playbook -i inventory/hosts.yml playbooks/cluster.yml -v

# Deploy only extensions (monitoring, logging, ingress, etc.)
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -v

# Dry-run mode (check what would change)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check -v

# Deploy specific extensions only
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t "monitoring,logging" -v

# Validate playbook syntax
ansible-playbook --syntax-check playbooks/site.yml

# Test SSH connectivity to all nodes
ansible -i inventory/hosts.yml all -m ping

# Run with extra verbosity (debugging)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vvv

# Limit execution to specific hosts
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit "k8s-cp1" -v

# Start at specific task (resume after failure)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --start-at-task "Initialize first Control Plane" -v
```

### Kubernetes Operations

```bash
# SSH to first control plane node
ssh debian@192.168.100.10

# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info

# Check storage
kubectl get storageclasses
kubectl get pvc -A

# Check services and endpoints
kubectl get services -A
kubectl get endpoints -A

# Check ingress
kubectl get ingressclasses.networking.k8s.io
kubectl get ingress -A

# View cluster events
kubectl get events --sort-by='.lastTimestamp'

# Check monitoring stack
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Check logging stack
kubectl get pods -n loki
kubectl logs -n loki -f deployment/loki

# Check Flux GitOps
flux get all
flux logs --follow
kubectl get gitrepositories -A
kubectl get kustomizations -A
```

### Testing and Verification

```bash
# Test storage provisioning
kubectl create pvc test-pvc --storageclass=local-path
kubectl get pvc
kubectl delete pvc test-pvc

# Test load balancer
kubectl create service loadbalancer test-lb --tcp=80:8080
kubectl get svc test-lb  # Should show external IP from MetalLB range
kubectl delete svc test-lb

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Check API server health
kubectl get --raw /healthz
kubectl get --raw /readyz
```

## Development Workflow

### Three-Part Approach

This repository follows a progressive learning path:

1. **Part 1 - Manual Installation** (`01_Kubernetes_HA_Manual_Installation.md`)
   - Understand how Kubernetes components work
   - Manual step-by-step setup (~90-120 minutes)
   - Best for learning and troubleshooting

2. **Part 2 - Ansible Automation** (`02_Kubernetes_HA_Ansible_Automation.md`)
   - Infrastructure as Code (IaC) approach
   - Automated deployment (~50-70 minutes)
   - Production-ready and repeatable
   - Main files: `bootstrap.sh`, `site_playbook.yml`, `inventory_hosts.yml`

3. **Part 3 - GitOps Integration** (`03_Kubernetes_HA_GitOps_Setup.md`)
   - Flux CD for continuous deployment
   - Git as single source of truth
   - Multi-environment support (dev/staging/prod)
   - Files: `flux_examples.yaml`, `github_workflows.md`, `gitops_cheatsheet.md`

### Customizing the Deployment

**Inventory Configuration** (`ansible/inventory/hosts.yml`):
- Define node IPs and hostnames
- Set cluster name and domain
- Configure network CIDRs
- Enable/disable extensions
- Set monitoring retention periods
- Configure Grafana credentials

**Key Variables to Customize**:
```yaml
kubernetes_version: "1.28.0"
cluster_name: "k8s-cluster-prod"
api_server_endpoint: "192.168.100.100:6443"
metallb_ip_range: "192.168.100.200-192.168.100.210"
prometheus_enabled: true
grafana_admin_password: "ChangeMe123!"
flux_enabled: false  # Enable when GitHub repo ready
```

### Extending the Cluster

To add new extensions or modify existing ones:
1. Create or modify roles in `ansible/roles/`
2. Update `extensions_playbook.yml` with new tasks
3. Add configuration variables to `inventory/group_vars/all.yml`
4. Test with dry-run: `ansible-playbook --check`
5. Deploy: `ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml`

## Important Configuration Files

- **`inventory_hosts.yml`**: Complete Ansible inventory template with all configurable variables
- **`site_playbook.yml`**: Main playbook that orchestrates cluster and extension deployment
- **`bootstrap.sh`**: Automated environment setup (installs Ansible, creates SSH keys, validates connectivity)
- **`flux_examples.yaml`**: Ready-to-use Flux CD manifests (GitRepository, Kustomization, HelmRelease)
- **`github_workflows.md`**: CI/CD pipeline definitions for GitHub Actions

## Network Architecture

### Port Requirements

**Control Plane Nodes**:
- 6443: Kubernetes API Server
- 2379-2380: etcd server/peer communication
- 10250: kubelet API
- 10251: kube-scheduler
- 10252: kube-controller-manager

**Worker Nodes**:
- 10250: kubelet API
- 30000-32767: NodePort Services

### IP Ranges (Default)
- **Node Network**: 192.168.100.0/24
- **Pod Network**: 10.244.0.0/16 (Flannel)
- **Service Network**: 10.96.0.0/12
- **MetalLB Pool**: 192.168.100.200-210

## Troubleshooting

### Common Issues

**SSH Connection Failures**:
```bash
# Verify SSH key exists
ls -l ~/.ssh/k8s_cluster

# Copy SSH key to nodes
for ip in 10 11 12 20 21; do
  ssh-copy-id -i ~/.ssh/k8s_cluster debian@192.168.100.${ip}
done

# Test connectivity
ansible -i inventory/hosts.yml all -m ping
```

**Nodes NotReady After Deployment**:
```bash
# Check kubelet status
ssh debian@192.168.100.10
sudo journalctl -u kubelet -n 100 -f

# Check CNI plugin (Flannel)
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel
```

**Extension Deployment Issues**:
```bash
# Check Helm releases
helm list -A

# Debug specific extension
kubectl describe deployment prometheus -n monitoring
kubectl logs -n monitoring -l app=prometheus --all-containers

# Reinstall extension
helm uninstall prometheus -n monitoring
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t monitoring
```

## Deployment Timeline

Typical deployment duration for automated installation:

| Phase | Duration |
|-------|----------|
| Pre-flight checks | 2-3 min |
| Common setup (all nodes) | 10-15 min |
| Control Plane 1 init | 5-10 min |
| CP 2 & 3 join | 4-6 min |
| Worker nodes join | 3-5 min |
| Flannel CNI | 2-3 min |
| Storage provisioner | 1-2 min |
| MetalLB | 2-3 min |
| Nginx Ingress | 3-5 min |
| Cert-Manager | 2-3 min |
| Monitoring (Prometheus/Grafana) | 10-15 min |
| Logging (Loki) | 3-5 min |
| Flux bootstrap (optional) | 2-3 min |
| **TOTAL** | **~50-70 min** |

## Key Concepts

### High Availability (HA)
- Always use 3 control plane nodes (never 2 due to etcd quorum requirements)
- etcd cluster runs on control plane nodes
- API server endpoint can be a VIP, load balancer, or DNS round-robin
- Worker nodes can be scaled independently

### Idempotency
Ansible playbooks are idempotent - safe to run multiple times. Subsequent runs should show "changed: 0" if cluster is already in desired state.

### GitOps Workflow
1. Commit manifests to Git repository
2. Flux CD detects changes
3. Automatically applies to cluster
4. Continuous reconciliation (default: every 10 minutes)

## File References

When working with this repository, note that kubectl history and examples are available in:
- `history.txt`: Contains kubectl command history with common operations
- `WSL Tab-Completion.txt`: Tab completion setup instructions

The `files/` directory contains all documentation and automation scripts. The main working directory for Ansible operations should be `ansible/` (created by `bootstrap.sh`).
