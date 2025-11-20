# Kubernetes HA Automation - Ansible Guide

📦 **Complete Infrastructure as Code (IaC) Solution**

---

## 📋 Quick Start (3 Steps)

### 1. Bootstrap Environment

```bash
# Run bootstrap script (one-liner setup)
bash bootstrap.sh

# This will:
# ✓ Install Ansible
# ✓ Create SSH keys
# ✓ Create directory structure
# ✓ Test node connectivity
```

### 2. Customize Inventory

```bash
# Edit your nodes in ansible/inventory/hosts.yml
vim ansible/inventory/hosts.yml

# Update:
# - IP addresses (192.168.100.x)
# - Hostnames (k8s-cp1, k8s-cp2, etc)
# - Your environment details
```

### 3. Deploy Cluster

```bash
cd ansible

# DRY-RUN (check mode - no changes)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check -v

# DEPLOY (actually create cluster)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v

# Takes ~45 minutes for complete HA cluster + all extensions
```

---

## 📁 File Structure

```
project/
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml                 # YOUR NODES CONFIG
│   │   ├── group_vars/
│   │   │   └── all.yml               # Global variables
│   │   └── host_vars/                # Per-host overrides
│   │
│   ├── playbooks/
│   │   ├── site.yml                  # Complete setup (Cluster + Extensions)
│   │   ├── cluster.yml               # Only K8s cluster
│   │   └── extensions.yml            # Only monitoring/logging/etc
│   │
│   ├── roles/                        # Modular task grouping
│   │   ├── common/                   # Base setup (all nodes)
│   │   ├── control_plane/            # CP initialization
│   │   ├── worker/                   # Worker node join
│   │   ├── monitoring/               # Prometheus + Grafana
│   │   ├── logging/                  # Loki + Promtail
│   │   ├── networking/               # Flannel, MetalLB, Nginx
│   │   ├── storage/                  # Local Path Provisioner
│   │   ├── security/                 # Cert-Manager
│   │   └── gitops/                   # Flux CD
│   │
│   ├── templates/                    # Jinja2 templates
│   ├── files/                        # Static files
│   ├── ansible.cfg                   # Ansible configuration
│   └── requirements.yml              # Collection dependencies
│
├── terraform/                        # Optional: VM provisioning
├── scripts/
│   ├── bootstrap.sh                  # Setup script (you are here)
│   └── cleanup.sh                    # Tear down cluster
├── .github/
│   └── workflows/
│       └── deploy.yml                # GitHub Actions CI/CD
└── README.md                         # This file
```

---

## 🚀 Usage Examples

### Complete Installation (Cluster + Extensions)

```bash
cd ansible

# Single command deployment
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v

# Or with custom tags
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -t "cluster,monitoring" -v
```

### Cluster Only (No Extensions)

```bash
cd ansible

# Deploy just the K8s cluster
ansible-playbook -i inventory/hosts.yml playbooks/cluster.yml -v
```

### Extensions Only (On Existing Cluster)

```bash
cd ansible

# Deploy only monitoring, logging, ingress, etc
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -v

# Or specific extensions
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t "monitoring,logging" -v
```

### Dry-Run (No Changes)

```bash
cd ansible

# Check mode - see what would happen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check -v

# With detailed diff
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff | head -100
```

### Debug & Verbose Output

```bash
cd ansible

# Extra verbose (triple -v)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vvv

# Specific host only
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit "k8s-cp1" -v

# Start at specific task
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --start-at-task "Initialize first Control Plane" -v
```

### Logging & Analysis

```bash
cd ansible

# Run with logging
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v 2>&1 | tee deployment.log

# Search for errors
grep -i "error\|fail\|warn" deployment.log

# Count tasks
grep "TASK" deployment.log | wc -l
```

---

## 🔧 Configuration

### Inventory Customization (inventory/hosts.yml)

```yaml
all:
  vars:
    # Your Cluster Details
    kubernetes_version: "1.28.0"
    cluster_name: "my-cluster"
    cluster_domain: "my.cluster.local"
    
    # Network Ranges
    pod_network_cidr: "10.244.0.0/16"
    service_cidr: "10.96.0.0/12"
    api_server_endpoint: "192.168.100.100:6443"
    metallb_ip_range: "192.168.100.200-210"
    
    # Extensions to deploy
    prometheus_enabled: true
    grafana_admin_password: "SecurePassword123!"
    loki_enabled: true
    flux_enabled: false  # Enable when GitHub repo ready

  children:
    control_planes:
      hosts:
        k8s-cp1:
          ansible_host: 192.168.100.10
          is_first_cp: true
    
    workers:
      hosts:
        k8s-w1:
          ansible_host: 192.168.100.20
```

### Global Variables (inventory/group_vars/all.yml)

```yaml
---
# System
debian_packages:
  - curl
  - vim
  - git
  - jq
  # ... add more as needed

# Kubernetes
kubernetes_version: "1.28.0"

# Storage
local_path_provisioner_path: "/opt/local-path-provisioner"

# Monitoring
prometheus_retention: "30d"
prometheus_scrape_interval: "30s"

# Grafana
grafana_admin_password: "ChangeMe123!"
```

---

## 📊 Execution Timeline

Typical deployment duration:

| Phase | Time |
|-------|------|
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

---

## ✅ Verification After Deployment

```bash
# SSH to first CP node
ssh debian@192.168.100.10

# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A
kubectl get storageclasses
kubectl get services -A

# Check monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/<password>)

# Check logging
kubectl logs -n loki -f deployment/loki

# Test storage
kubectl create pvc test-pvc --image busybox
kubectl get pvc
kubectl delete pvc test-pvc

# Test load balancer
kubectl create service loadbalancer test-lb --tcp=80:8080
kubectl get svc test-lb  # Should show external IP
kubectl delete svc test-lb
```

---

## 🐛 Troubleshooting

### SSH Connection Issues

```bash
# Test SSH connectivity
ansible -i inventory/hosts.yml all -m ping

# Debug SSH connection
ssh -vvv -i ~/.ssh/k8s_cluster debian@192.168.100.10

# Copy SSH key to nodes manually
ssh-copy-id -i ~/.ssh/k8s_cluster debian@192.168.100.10
```

### Nodes Not Ready After Deployment

```bash
# SSH to CP1
ssh debian@192.168.100.10

# Check kubelet status
sudo journalctl -u kubelet -n 100 -f

# Check CNI plugin
kubectl get pods -n kube-flannel

# Check API server
kubectl get --raw /healthz
```

### Playbook Syntax Errors

```bash
cd ansible

# Validate playbook
ansible-playbook --syntax-check playbooks/site.yml

# Lint with ansible-lint
pip install ansible-lint
ansible-lint playbooks/site.yml

# Check inventory syntax
ansible-inventory -i inventory/hosts.yml --host k8s-cp1
```

### Extension Deployment Issues

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

---

## 🔄 Idempotency & Re-running

Ansible playbooks are **idempotent** - safe to run multiple times:

```bash
# Run once
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Run again - should show "changed: 0"
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Safe to re-run for fixing issues or updating
```

---

## 📝 CI/CD Integration

### GitHub Actions Workflow

Files: `.github/workflows/deploy.yml`

Automated workflow:
- ✅ Syntax check on every push
- ✅ Lint validation
- ✅ Dry-run in check mode
- ✅ Manual trigger for actual deployment

```bash
# Trigger deployment from GitHub Actions
# Push to main branch or manual workflow_dispatch
```

### Required GitHub Secrets

```bash
# Settings → Secrets and variables → Actions

K8S_SSH_KEY=<private-key-content>
GITHUB_TOKEN=<your-token>
```

---

## 🛡️ Security Best Practices

### 1. SSH Keys (Not Passwords)

```bash
# Generate strong SSH key
ssh-keygen -t ed25519 -f ~/.ssh/k8s_cluster -C "k8s-automation"

# Copy to nodes securely
ssh-copy-id -i ~/.ssh/k8s_cluster debian@<node-ip>
```

### 2. Protect Sensitive Variables

```bash
# Use Ansible Vault for passwords
ansible-vault encrypt inventory/group_vars/all.yml

# Run playbook with vault
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass
```

### 3. GitHub Secrets

```bash
# Never commit sensitive data!
# Use GitHub Secrets for:
# - SSH private keys
# - GitHub tokens
# - API credentials
# - Passwords
```

### 4. RBAC & Network Policies

After cluster deployment:

```bash
# Configure RBAC
kubectl apply -f rbac-policies.yaml

# Configure Network Policies
kubectl apply -f network-policies.yaml

# Verify
kubectl get rolebindings -A
kubectl get networkpolicies -A
```

---

## 🚀 Advanced Scenarios

### Staging vs Production

```bash
# Multiple inventories
ansible-playbook -i inventory/staging.yml playbooks/site.yml
ansible-playbook -i inventory/production.yml playbooks/site.yml
```

### Rolling Updates

```bash
# Update worker nodes one by one
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --limit "workers" \
  --serial 1 \
  -v
```

### Customize Node Groups

```bash
# Deploy only to specific nodes
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml \
  --limit "control_planes[0]" \
  -v
```

---

## 📚 Documentation

- **Part 1:** Manual step-by-step installation
  → `01_Kubernetes_HA_Manual_Installation.md`

- **Part 2:** Ansible automation (this guide)
  → `02_Kubernetes_HA_Ansible_Automation.md`

- **Part 3:** GitOps & GitHub integration
  → `03_Kubernetes_HA_GitOps_Setup.md` (coming)

---

## 🆘 Support & Troubleshooting

### Check Logs

```bash
# Ansible debug log
cat ansible.log

# Specific playbook run
grep "TASK\|error" ansible.log | head -20

# Specific host issues
grep "k8s-cp1" ansible.log
```

### Common Issues

| Issue | Solution |
|-------|----------|
| SSH timeout | Check firewall, SSH port 22 open |
| Nodes NotReady | Wait for Flannel pods, check kubelet logs |
| API unreachable | Check load balancer, API port 6443 |
| Storage pending | Check local storage paths created |
| Pods ImagePullBackOff | Network issue or missing image |

---

## 📞 Quick Reference

```bash
# SSH to nodes
ssh -i ~/.ssh/k8s_cluster debian@192.168.100.10

# Check playbook syntax
ansible-playbook --syntax-check playbooks/site.yml

# Run with verbosity
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vvv

# Dry-run (check mode)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check

# Deploy specific tag
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -t monitoring

# Limit to one host
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit k8s-cp1

# Show what changed
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --diff

# Run with extra variables
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -e "kubernetes_version=1.29.0"
```

---

## 🎯 Next Steps After Deployment

1. ✅ Verify cluster health
2. 📊 Access Grafana monitoring dashboard
3. 🔍 Check Loki logging
4. 🔐 Configure RBAC & Network Policies
5. 🌐 Deploy your applications
6. 🔄 Set up GitOps with Flux
7. 💾 Configure backups with Velero
8. 📈 Scale cluster as needed

---

## 📄 License

MIT - Use freely for your infrastructure automation

---

**Ready?** Start with: `bash bootstrap.sh`

**Questions?** Check the detailed guide: `02_Kubernetes_HA_Ansible_Automation.md`
