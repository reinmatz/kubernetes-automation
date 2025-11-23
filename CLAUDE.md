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
/
├── CLAUDE.md                                   # This file - Claude Code guidance
│
├── Kubernetes HA/                              # Main project directory
│   ├── manifests/                              # Kubernetes manifests
│   │   ├── ansible/                            # Ansible container deployment
│   │   │   ├── 01-namespace.yaml
│   │   │   ├── 02-serviceaccount-rbac.yaml
│   │   │   ├── 04-deployment.yaml
│   │   │   └── 06-ansible-runner-custom.yaml
│   │   └── nextcloud/                          # Nextcloud HA deployment
│   │       ├── 05-nextcloud-deployment.yaml
│   │       ├── 07-ingress.yaml
│   │       └── 08-tls-certificate.yaml
│   │
│   ├── scripts/                                # Helper scripts
│   │   ├── ansible-k8s.sh                      # Ansible container helper
│   │   └── backup-nextcloud.sh                 # Nextcloud backup script
│   │
│   ├── k8s_extensions_playbook.yml             # Extensions deployment (Cert-Manager, Monitoring, Loki)
│   ├── k8s_networking_playbook.yml             # Networking deployment (Nginx Ingress)
│   ├── grafana-certificate-dashboard.json      # Grafana dashboard for cert monitoring
│   │
│   └── Documentation/                          # Generated documentation
│       ├── FINAL_SUMMARY.md                    # Complete project summary
│       ├── ALL_EXTENSIONS_DEPLOYED.md          # Extensions deployment guide
│       ├── NEXTCLOUD_TLS_AUTO_RENEWAL.md       # TLS auto-renewal documentation
│       ├── GRAFANA_SETUP_GUIDE.md              # Grafana setup guide
│       ├── ANSIBLE_QUICKSTART.md               # Ansible container quickstart
│       └── DEPLOYMENT_SUCCESS.md               # Deployment details
│
└── files/                                      # Legacy Ansible automation (for on-premise HA clusters)
    ├── 01_Kubernetes_HA_Manual_Installation.md
    ├── 02_Kubernetes_HA_Ansible_Automation.md
    ├── 03_Kubernetes_HA_GitOps_Setup.md
    ├── bootstrap.sh
    ├── site_playbook.yml
    └── inventory_hosts.yml
```

## Architecture Overview

### Current Docker Desktop Setup (Production-Ready)

The repository contains a fully functional production-ready setup for Docker Desktop Kubernetes:

```
Deployed Components:
├─ ansible (namespace)
│  └─ Ansible Container (kubectl + Helm + Python kubernetes)
│     - Deployment: ansible-k8s (2/2 Running)
│     - Tools: kubectl, helm, ansible-playbook
│     - Purpose: Infrastructure automation from within cluster
│
├─ cert-manager (namespace)
│  ├─ cert-manager (3/3 Running)
│  ├─ cert-manager-cainjector (1/1 Running)
│  ├─ cert-manager-webhook (1/1 Running)
│  └─ ClusterIssuers:
│     ├─ selfsigned (Ready)
│     ├─ letsencrypt-staging
│     └─ letsencrypt-prod
│
├─ monitoring (namespace)
│  ├─ Prometheus (2/2 Running) - Metrics collection
│  ├─ Grafana (3/3 Running) - Dashboards (Port 3000)
│  ├─ AlertManager (2/2 Running)
│  ├─ Kube-State-Metrics (1/1 Running)
│  └─ Prometheus-Operator (1/1 Running)
│
├─ loki (namespace)
│  ├─ Loki (1/1 Running) - Log aggregation
│  └─ Promtail (1/1 Running) - Log collection
│
├─ ingress-nginx (namespace)
│  └─ Ingress Controller (1/1 Running)
│     - NodePort: 80:30209/TCP, 443:31896/TCP
│     - TLS: Enabled with cert-manager integration
│
└─ nextcloud-prod (namespace)
   ├─ Nextcloud (3/3 Running) - High Availability
   ├─ MariaDB (1/1 Running)
   ├─ LoadBalancer Service: http://localhost
   ├─ Ingress: https://nextcloud.home16.local:31896
   └─ TLS Certificate:
      - Auto-created by cert-manager
      - Auto-renewal: 30 days before expiry
      - CN: nextcloud.home16.local

Access URLs:
├─ Nextcloud HTTPS: https://nextcloud.home16.local:31896
├─ Nextcloud HTTP:  http://localhost
└─ Grafana:         http://localhost:3000 (admin / ChangeMe123!)
```

### Cluster Topology (On-Premise HA Configuration)

For traditional on-premise high-availability clusters:

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

### Ansible in Kubernetes Container

The project now uses Ansible running as a container inside Kubernetes for automation:

```bash
# Access Ansible container shell
./scripts/ansible-k8s.sh shell

# Run ansible commands
./scripts/ansible-k8s.sh ansible localhost -m ping

# Run kubectl from Ansible container
./scripts/ansible-k8s.sh kubectl get nodes

# Deploy extensions via Ansible
kubectl exec -n ansible deployment/ansible-k8s -- sh -c \
  "cd /ansible && unset KUBECONFIG && ansible-playbook playbooks/k8s_extensions.yml -t cert-manager"

# Deploy specific extensions
kubectl exec -n ansible deployment/ansible-k8s -- sh -c \
  "cd /ansible && unset KUBECONFIG && ansible-playbook playbooks/k8s_extensions.yml -t monitoring"

kubectl exec -n ansible deployment/ansible-k8s -- sh -c \
  "cd /ansible && unset KUBECONFIG && ansible-playbook playbooks/k8s_extensions.yml -t logging"

kubectl exec -n ansible deployment/ansible-k8s -- sh -c \
  "cd /ansible && unset KUBECONFIG && ansible-playbook playbooks/k8s_networking.yml -t nginx"

# Check Ansible container logs
./scripts/ansible-k8s.sh logs

# Check Ansible container status
./scripts/ansible-k8s.sh status
```

### Legacy Ansible Automation (On-Premise HA Clusters)

For traditional on-premise HA cluster deployments:

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

# Deploy specific extensions only
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t "monitoring,logging" -v
```

### Kubernetes Operations

```bash
# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info

# Check all namespaces
kubectl get pods -A | grep -v kube-system

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

# Check Ansible container
kubectl get pods -n ansible
kubectl logs -n ansible deployment/ansible-k8s

# Check monitoring stack
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Access: http://localhost:3000 (admin / ChangeMe123!)

# Check logging stack
kubectl get pods -n loki
kubectl logs -n loki -f deployment/loki

# Check Cert-Manager
kubectl get pods -n cert-manager
kubectl get clusterissuers
kubectl get certificates -A

# Check Nextcloud with TLS
kubectl get pods -n nextcloud-prod
kubectl get ingress -n nextcloud-prod
kubectl get certificate -n nextcloud-prod
# Access: https://nextcloud.home16.local:31896

# Check Flux GitOps (if enabled)
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

### Docker Desktop / Ansible Container Issues

**Ansible Container Not Starting**:
```bash
# Check pod status
kubectl get pods -n ansible

# Check logs
kubectl logs -n ansible deployment/ansible-k8s

# Check events
kubectl describe pod -n ansible -l app=ansible-k8s

# Restart deployment
kubectl rollout restart deployment/ansible-k8s -n ansible
```

**Ingress Controller Pending (Insufficient Memory)**:
```bash
# Check pod status
kubectl get pods -n ingress-nginx

# Describe pod to see resource issues
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/component=controller

# Solution: Increase Docker Desktop memory to 6-8GB
# Docker Desktop → Settings → Resources → Memory

# After increasing memory, delete pending pod
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller

# Verify it starts
kubectl get pods -n ingress-nginx -w
```

**HTTPS/TLS Certificate Issues**:
```bash
# Check certificate status
kubectl get certificate -A
kubectl describe certificate nextcloud-tls -n nextcloud-prod

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check certificate secret
kubectl get secret nextcloud-tls-secret -n nextcloud-prod

# View certificate details
kubectl get secret nextcloud-tls-secret -n nextcloud-prod -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -text

# Force certificate renewal (delete and recreate)
kubectl delete certificate nextcloud-tls -n nextcloud-prod
kubectl apply -f "Kubernetes HA/manifests/nextcloud/08-tls-certificate.yaml"
```

**Nextcloud HTTPS Redirect Issues**:
```bash
# Configure Nextcloud to use HTTPS protocol
kubectl exec -n nextcloud-prod deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ config:system:set overwriteprotocol --value='https'"

# Set correct host with port
kubectl exec -n nextcloud-prod deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ config:system:set overwritehost --value='nextcloud.home16.local:31896'"

# Configure trusted domains
kubectl exec -n nextcloud-prod deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ config:system:set trusted_domains 0 --value=localhost"

kubectl exec -n nextcloud-prod deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ config:system:set trusted_domains 1 --value=nextcloud.home16.local"
```

**Ingress 404 Errors**:
```bash
# Check ingress configuration
kubectl get ingress -A
kubectl describe ingress nextcloud -n nextcloud-prod

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50

# Verify service endpoints exist
kubectl get endpoints -n nextcloud-prod

# Delete old conflicting ingress resources
kubectl get ingress -A
kubectl delete namespace <old-namespace>
```

### On-Premise HA Cluster Issues

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

### Current Docker Desktop Setup Files

The `Kubernetes HA/` directory contains the current production-ready setup:
- `manifests/ansible/`: Ansible container deployment manifests
- `manifests/nextcloud/`: Nextcloud HA with TLS certificate
- `scripts/ansible-k8s.sh`: Helper script for Ansible container operations
- `k8s_extensions_playbook.yml`: Ansible playbook for extensions (Cert-Manager, Monitoring, Loki)
- `k8s_networking_playbook.yml`: Ansible playbook for networking (Nginx Ingress)
- `grafana-certificate-dashboard.json`: Grafana dashboard for certificate monitoring
- Documentation files: `FINAL_SUMMARY.md`, `ALL_EXTENSIONS_DEPLOYED.md`, etc.

### Legacy On-Premise Setup Files

The `files/` directory contains all documentation and automation scripts for traditional on-premise HA clusters. The main working directory for Ansible operations should be `ansible/` (created by `bootstrap.sh`).

## Current Production Setup Summary

**Environment**: Docker Desktop Kubernetes (macOS)
**Total Pods Running**: 18+
**Total Namespaces**: 6 (ansible, cert-manager, monitoring, loki, ingress-nginx, nextcloud-prod)
**Deployment Method**: Ansible running as container in Kubernetes
**Automation Level**: 100% (Infrastructure as Code)

**Key Features**:
- ✅ Ansible container with kubectl, Helm, and Python kubernetes modules
- ✅ Automatic TLS certificate management with cert-manager
- ✅ TLS auto-renewal 30 days before expiry
- ✅ Full monitoring stack (Prometheus + Grafana)
- ✅ Centralized logging (Loki + Promtail)
- ✅ Nginx Ingress Controller with HTTPS
- ✅ Nextcloud High Availability (3 replicas)
- ✅ Production-ready configuration

**Access Points**:
- Nextcloud HTTPS: `https://nextcloud.home16.local:31896`
- Nextcloud HTTP: `http://localhost`
- Grafana: `http://localhost:3000` (admin / ChangeMe123!)

**Documentation**:
All deployment steps, troubleshooting guides, and configuration details are documented in:
- `Kubernetes HA/FINAL_SUMMARY.md` - Complete overview
- `Kubernetes HA/ALL_EXTENSIONS_DEPLOYED.md` - Extensions guide
- `Kubernetes HA/NEXTCLOUD_TLS_AUTO_RENEWAL.md` - TLS certificate details
- `Kubernetes HA/GRAFANA_SETUP_GUIDE.md` - Monitoring setup
- `Kubernetes HA/ANSIBLE_QUICKSTART.md` - Ansible container guide
