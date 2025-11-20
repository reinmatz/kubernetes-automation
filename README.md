# Kubernetes HA Cluster - Complete Automation Solution

**Production-ready Kubernetes High-Availability cluster deployment on On-Premise infrastructure**

## Overview

This repository provides a comprehensive solution for deploying, managing, and operating Kubernetes HA clusters on on-premise Debian-based VMs. It includes detailed documentation, Ansible automation, and GitOps integration.

### What's Included

✅ **Manual Installation Guide** - Step-by-step educational approach
✅ **Ansible Automation** - Production-ready Infrastructure as Code
✅ **GitOps Integration** - Flux CD for continuous deployment
✅ **Monitoring & Logging** - Prometheus, Grafana, Loki stack
✅ **Security** - Cert-Manager, RBAC, Network Policies
✅ **CI/CD** - GitHub Actions workflows

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/kubernetes.git
cd kubernetes
```

### 2. Bootstrap Environment

```bash
# Run the bootstrap script to set up Ansible and dependencies
bash files/bootstrap.sh
```

### 3. Configure Inventory

```bash
# Copy and customize the inventory file
mkdir -p ansible/inventory
cp files/inventory_hosts.yml ansible/inventory/hosts.yml

# Edit with your node IPs and configuration
vim ansible/inventory/hosts.yml
```

### 4. Deploy Cluster

```bash
# Copy playbooks
cp files/site_playbook.yml ansible/playbooks/site.yml
cp files/extensions_playbook.yml ansible/playbooks/extensions.yml

# Deploy complete cluster (50-70 minutes)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v
```

### 5. Verify Deployment

```bash
# SSH to first control plane
ssh debian@192.168.100.10

# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A
```

## Documentation

### Core Guides

- **[Part 1: Manual Installation](files/01_Kubernetes_HA_Manual_Installation.md)** - Understand how Kubernetes works (~90-120 min)
- **[Part 2: Ansible Automation](files/02_Kubernetes_HA_Ansible_Automation.md)** - Automated deployment (~50-70 min)
- **[Part 3: GitOps Setup](files/03_Kubernetes_HA_GitOps_Setup.md)** - Flux CD integration (~30-45 min)
- **[Complete Solution Overview](files/COMPLETE_SOLUTION_OVERVIEW.md)** - Full architecture overview

### Quick References

- **[Ansible Quick Guide](files/README_Ansible_Guide.md)** - Fast Ansible reference
- **[GitOps Cheatsheet](files/gitops_cheatsheet.md)** - GitOps commands and troubleshooting
- **[GitHub Workflows](files/github_workflows.md)** - CI/CD pipeline definitions

## Architecture

### Default Cluster Topology

```
Control Planes (HA):
├─ k8s-cp1: 192.168.100.10 (4CPU/8GB)
├─ k8s-cp2: 192.168.100.11 (4CPU/8GB)
└─ k8s-cp3: 192.168.100.12 (4CPU/8GB)

Worker Nodes:
├─ k8s-w1: 192.168.100.20 (8CPU/16GB)
└─ k8s-w2: 192.168.100.21 (8CPU/16GB)

Network:
├─ Pod Network: 10.244.0.0/16 (Flannel)
├─ Service CIDR: 10.96.0.0/12
└─ MetalLB Range: 192.168.100.200-210
```

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

## Key Features

### High Availability
- 3 Control Plane nodes with etcd cluster
- Automatic failover and recovery
- Load-balanced API server access

### Automation
- One-command deployment with Ansible
- Idempotent playbooks (safe to re-run)
- Modular role-based structure
- Pre-flight validation checks

### Observability
- Prometheus metrics collection
- Grafana dashboards
- Loki log aggregation
- AlertManager integration

### GitOps Ready
- Flux CD for continuous deployment
- Git as single source of truth
- Multi-environment support
- Automated secret management with SOPS

## Common Commands

### Ansible Deployment

```bash
# Full deployment (cluster + extensions)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v

# Cluster only (no extensions)
ansible-playbook -i inventory/hosts.yml playbooks/cluster.yml -v

# Extensions only
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -v

# Dry-run mode
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check -v

# Specific extensions
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t "monitoring,logging" -v
```

### Kubernetes Operations

```bash
# Cluster health
kubectl get nodes -o wide
kubectl get pods -A

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000

# Check Flux status
flux get all
flux logs --follow
```

## Requirements

### Infrastructure
- 3-5 VMs with Debian 11/12
- Minimum: 2 CPU, 2GB RAM, 20GB disk per node
- Recommended: 4+ CPU, 8GB+ RAM, 50GB+ disk
- Network connectivity between all nodes

### Software (Local Machine)
- Ansible 2.9+
- Python 3.8+
- Git
- SSH access to all nodes

## Repository Structure

```
.
├── CLAUDE.md                      # Claude Code guidance
├── README.md                      # This file
├── files/                         # All documentation and scripts
│   ├── 01_Kubernetes_HA_Manual_Installation.md
│   ├── 02_Kubernetes_HA_Ansible_Automation.md
│   ├── 03_Kubernetes_HA_GitOps_Setup.md
│   ├── bootstrap.sh
│   ├── site_playbook.yml
│   ├── extensions_playbook.yml
│   ├── inventory_hosts.yml
│   ├── flux_examples.yaml
│   └── github_workflows.md
└── ansible/                       # Created by bootstrap.sh
    ├── inventory/
    ├── playbooks/
    └── roles/
```

## Troubleshooting

### SSH Connection Issues
```bash
# Test connectivity
ansible -i inventory/hosts.yml all -m ping

# Copy SSH key to nodes
ssh-copy-id -i ~/.ssh/k8s_cluster debian@192.168.100.10
```

### Nodes Not Ready
```bash
# Check kubelet logs
ssh debian@192.168.100.10
sudo journalctl -u kubelet -n 100 -f

# Check CNI plugin
kubectl get pods -n kube-flannel
```

### Extension Issues
```bash
# Check Helm releases
helm list -A

# Debug extension
kubectl describe deployment prometheus -n monitoring
kubectl logs -n monitoring -l app=prometheus
```

## Contributing

This is a documentation and automation repository. Contributions welcome:
- Documentation improvements
- Ansible role enhancements
- Additional extensions
- Bug fixes

## Support

- Check the comprehensive guides in `files/`
- Review troubleshooting sections in documentation
- Verify your inventory configuration
- Test with dry-run mode before deployment

## License

MIT License - Use freely for your infrastructure automation

## Acknowledgments

Built using:
- [Kubernetes Official Documentation](https://kubernetes.io/)
- [Flux CD](https://fluxcd.io/)
- [Ansible Best Practices](https://docs.ansible.com/)
- Community experience and best practices

---

**Ready to deploy?** Start with `bash files/bootstrap.sh`
