# Kubernetes HA Cluster - Ansible Automation (Teil 2)

**Ziel:** Vollständig automatisierte Installation + Konfiguration aller Komponenten

---

## 📋 Inhaltsverzeichnis

1. [Ansible Setup & Prerequisites](#1-ansible-setup--prerequisites)
2. [Verzeichnisstruktur](#2-verzeichnisstruktur)
3. [Inventory & Variables](#3-inventory--variables)
4. [Terraform für VM-Provisioning](#4-terraform-für-vm-provisioning-optional)
5. [Main Playbooks](#5-main-playbooks)
6. [Role-Details](#6-role-details)
7. [Ausführung & Best Practices](#7-ausführung--best-practices)
8. [GitHub Actions Integration](#8-github-actions-integration)

---

## 1. Ansible Setup & Prerequisites

### 1.1 Ansible Installation (auf deinem lokalen Rechner)

```bash
# Debian/Ubuntu
sudo apt install -y ansible-core git curl

# Oder via Pip (für neueste Version)
python3 -m pip install --upgrade pip
pip install ansible ansible-core

# Verify
ansible --version
```

### 1.2 Erforderliche Ansible Collections

```bash
# Galaxy collections installieren
ansible-galaxy collection install \
  community.general \
  kubernetes.core \
  ansible.posix

# Oder via requirements.yml (empfohlen)
cat > requirements.yml << 'EOF'
collections:
  - name: community.general
    version: ">=6.0.0"
  - name: kubernetes.core
    version: ">=2.4.0"
  - name: ansible.posix
    version: ">=1.5.0"
EOF

ansible-galaxy install -r requirements.yml
```

### 1.3 SSH Key & Config

```bash
# SSH Key für Cluster (falls noch nicht vorhanden)
ssh-keygen -t ed25519 -f ~/.ssh/k8s_cluster -C "k8s-automation"

# SSH Config (~/.ssh/config)
cat >> ~/.ssh/config << 'EOF'
Host 192.168.100.*
  User debian
  IdentityFile ~/.ssh/k8s_cluster
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  LogLevel ERROR
EOF

chmod 600 ~/.ssh/config
```

### 1.4 Test Connectivity

```bash
# Alle Nodes müssen erreichbar sein
for node in 10 11 12 20 21; do
  ansible -i "192.168.100.${node}," -u debian -m ping 192.168.100.${node}
done
```

---

## 2. Verzeichnisstruktur

Erstelle diese Struktur auf deinem lokalen Rechner:

```
k8s-cluster-automation/
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml                 # Inventory mit Nodes
│   │   ├── group_vars/
│   │   │   ├── all.yml               # Globale Variables
│   │   │   ├── control_planes.yml
│   │   │   └── workers.yml
│   │   └── host_vars/
│   │       ├── k8s-cp1.yml
│   │       ├── k8s-cp2.yml
│   │       ├── k8s-cp3.yml
│   │       ├── k8s-w1.yml
│   │       └── k8s-w2.yml
│   ├── roles/
│   │   ├── common/                   # Basis-Setup (alle Nodes)
│   │   │   ├── tasks/
│   │   │   ├── templates/
│   │   │   └── handlers/
│   │   ├── control_plane/            # CP spezifisch
│   │   │   ├── tasks/
│   │   │   ├── templates/
│   │   │   └── handlers/
│   │   ├── worker/                   # Worker spezifisch
│   │   │   └── tasks/
│   │   ├── monitoring/               # Prometheus + Grafana
│   │   │   ├── tasks/
│   │   │   └── templates/
│   │   ├── logging/                  # Loki + Promtail
│   │   │   ├── tasks/
│   │   │   └── templates/
│   │   ├── networking/               # Flannel, MetalLB, Nginx Ingress
│   │   │   ├── tasks/
│   │   │   └── templates/
│   │   ├── storage/                  # Local Path Provisioner
│   │   │   └── tasks/
│   │   ├── security/                 # Cert-Manager, RBAC
│   │   │   ├── tasks/
│   │   │   └── templates/
│   │   └── gitops/                   # Flux CD
│   │       ├── tasks/
│   │       └── templates/
│   ├── playbooks/
│   │   ├── site.yml                  # Main playbook (alles)
│   │   ├── cluster.yml               # Nur K8s Cluster
│   │   ├── extensions.yml            # Nur Extensions
│   │   ├── monitoring.yml            # Nur Monitoring
│   │   ├── gitops.yml                # Nur Flux
│   │   └── health-check.yml          # Cluster Health Check
│   ├── templates/
│   │   └── kubeadm-config.yaml.j2    # kubeadm init config
│   ├── files/
│   │   └── (static files)
│   ├── ansible.cfg                   # Ansible Config
│   └── requirements.yml              # Collection requirements
├── terraform/                        # (Optional) VM Provisioning
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── terraform.tfvars
├── scripts/
│   ├── bootstrap.sh                  # One-liner Setup
│   └── cleanup.sh                    # Cluster löschen
└── README.md
```

---

## 3. Inventory & Variables

### 3.1 Inventory File (inventory/hosts.yml)

```yaml
---
all:
  vars:
    # Global variables
    ansible_user: debian
    ansible_ssh_private_key_file: ~/.ssh/k8s_cluster
    ansible_python_interpreter: /usr/bin/python3
    
    # Kubernetes
    kubernetes_version: "1.28.0"
    cluster_name: "k8s-cluster-prod"
    cluster_domain: "cluster.local"
    
    # Network
    pod_network_cidr: "10.244.0.0/16"
    service_cidr: "10.96.0.0/12"
    api_server_endpoint: "192.168.100.100:6443"
    
    # Timeouts & retries
    ansible_connection_timeout: 30
    ansible_command_timeout: 30

  children:
    control_planes:
      hosts:
        k8s-cp1:
          ansible_host: 192.168.100.10
          node_ip: 192.168.100.10
          node_hostname: k8s-cp1
          is_first_cp: true
        k8s-cp2:
          ansible_host: 192.168.100.11
          node_ip: 192.168.100.11
          node_hostname: k8s-cp2
          is_first_cp: false
        k8s-cp3:
          ansible_host: 192.168.100.12
          node_ip: 192.168.100.12
          node_hostname: k8s-cp3
          is_first_cp: false
      vars:
        node_role: "control-plane"

    workers:
      hosts:
        k8s-w1:
          ansible_host: 192.168.100.20
          node_ip: 192.168.100.20
          node_hostname: k8s-w1
        k8s-w2:
          ansible_host: 192.168.100.21
          node_ip: 192.168.100.21
          node_hostname: k8s-w2
      vars:
        node_role: "worker"

    # Monitoring & Logging
    monitoring:
      vars:
        prometheus_retention: "30d"
        grafana_admin_password: "ChangeMe123!"
        loki_retention: "7d"
```

### 3.2 Group Variables (inventory/group_vars/all.yml)

```yaml
---
# System
debian_packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - vim
  - git
  - wget
  - net-tools
  - htop
  - tmux
  - jq

# containerd
containerd_version: "latest"
containerd_systemd_cgroup: true

# Kubernetes
kubeadm_config_apiVersion: "kubeadm.k8s.io/v1beta3"
kubeadm_config_kind: "InitConfiguration"

# Extensions
helm_version: "v3.12.0"
kubectl_version: "v1.28.0"

# Load Balancer
metallb_ip_range: "192.168.100.200-192.168.100.210"

# Ingress
ingress_class: "nginx"

# Storage
local_path_provisioner_path: "/opt/local-path-provisioner"
storage_class_name: "local-path"

# Monitoring
prometheus_scrape_interval: "30s"
prometheus_evaluation_interval: "30s"

# Flux
flux_namespace: "flux-system"
flux_git_repo: "https://github.com/YOUR_USER/k8s-cluster-config"
flux_git_branch: "main"
```

### 3.3 Control Plane Vars (inventory/group_vars/control_planes.yml)

```yaml
---
# Control Plane spezifisch
control_plane_ip: "{{ node_ip }}"
```

### 3.4 Ansible Config (ansible/ansible.cfg)

```ini
[defaults]
# Inventory
inventory = ./inventory/hosts.yml
host_key_checking = False

# Logging & Debug
log_path = ./ansible.log
verbosity = 1

# Performance
forks = 10
timeout = 30
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400

# SSH
remote_user = debian
private_key_file = ~/.ssh/k8s_cluster

# Roles
roles_path = ./roles

# Output
force_color = True
stdout_callback = yaml
bin_ansible_callbacks = True

# Mitigation of Bugs
interpreter_python = /usr/bin/python3
enable_task_debugger = False
```

---

## 4. Terraform für VM-Provisioning (optional)

Falls du VMs noch nicht hast und sie per IaC provisioning möchtest.

### 4.1 Terraform Structure (terraform/provider.tf)

```hcl
# Beispiel für Proxmox (replace mit deinem Provider)
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9.0"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = true
}
```

### 4.2 Terraform Variables (terraform/variables.tf)

```hcl
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "vm_memory_cp" {
  description = "Memory for control plane (MB)"
  type        = number
  default     = 8192
}

variable "vm_memory_worker" {
  description = "Memory for worker nodes (MB)"
  type        = number
  default     = 16384
}

variable "vm_cpu_cp" {
  description = "CPUs for control plane"
  type        = number
  default     = 4
}

variable "vm_cpu_worker" {
  description = "CPUs for worker nodes"
  type        = number
  default     = 8
}
```

### 4.3 Terraform Main (terraform/main.tf)

```hcl
# Control Plane VMs
resource "proxmox_vm_qemu" "control_planes" {
  count       = var.control_plane_count
  target_node = "pve"  # Adjust to your Proxmox node
  name        = "k8s-cp${count.index + 1}"
  
  clone       = "debian-12-template"  # Template must exist
  
  memory      = var.vm_memory_cp
  cores       = var.vm_cpu_cp
  sockets     = 1
  
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
  
  disk {
    size    = "50G"
    type    = "virtio"
    storage = "local-lvm"
  }
  
  ipconfig0 = "ip=192.168.100.${10 + count.index}/24,gw=192.168.100.1"
  
  # Cloud-init für Debian
  cicustom      = "vendor=local:snippets/debian-init.yml"
  cloudinit_cdrom_storage = "local-lvm"
  
  lifecycle {
    ignore_changes = [
      ciuser,
      cicustom,
      cloudinit_cdrom_storage
    ]
  }
}

# Worker VMs
resource "proxmox_vm_qemu" "workers" {
  count       = var.worker_count
  target_node = "pve"
  name        = "k8s-w${count.index + 1}"
  
  clone       = "debian-12-template"
  
  memory      = var.vm_memory_worker
  cores       = var.vm_cpu_worker
  sockets     = 1
  
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
  
  disk {
    size    = "100G"
    type    = "virtio"
    storage = "local-lvm"
  }
  
  ipconfig0 = "ip=192.168.100.${20 + count.index}/24,gw=192.168.100.1"
  
  cicustom      = "vendor=local:snippets/debian-init.yml"
  cloudinit_cdrom_storage = "local-lvm"
  
  lifecycle {
    ignore_changes = [
      ciuser,
      cicustom,
      cloudinit_cdrom_storage
    ]
  }
}

# Output
output "control_plane_ips" {
  value = [for vm in proxmox_vm_qemu.control_planes : vm.default_ipv4_address]
}

output "worker_ips" {
  value = [for vm in proxmox_vm_qemu.workers : vm.default_ipv4_address]
}
```

### 4.4 Terraform Deployment

```bash
cd terraform

# Init
terraform init

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Output für Ansible verwenden
terraform output -json > ../ansible/terraform-output.json
```

---

## 5. Main Playbooks

### 5.1 Site Playbook (playbooks/site.yml) - Alles auf einmal

```yaml
---
# Complete Kubernetes HA Cluster Setup
- name: "K8S Cluster - Bootstrap"
  hosts: all
  gather_facts: yes
  serial: 1
  tasks:
    - name: "Show cluster configuration"
      debug:
        msg: |
          Cluster: {{ cluster_name }}
          Domain: {{ cluster_domain }}
          API Endpoint: {{ api_server_endpoint }}
          Pod Network: {{ pod_network_cidr }}
          Service CIDR: {{ service_cidr }}

- name: "Common Base Setup (all nodes)"
  hosts: all
  roles:
    - common

- name: "Control Plane Setup"
  hosts: control_planes
  serial: 1
  roles:
    - control_plane

- name: "Worker Node Setup"
  hosts: workers
  roles:
    - worker

- name: "Networking Setup (Flannel)"
  hosts: control_planes[0]
  roles:
    - { role: networking, tasks_from: flannel }

- name: "Storage Setup"
  hosts: control_planes[0]
  roles:
    - { role: storage, tasks_from: local_path }

- name: "Load Balancer Setup (MetalLB)"
  hosts: control_planes[0]
  roles:
    - { role: networking, tasks_from: metallb }

- name: "Ingress Controller Setup (Nginx)"
  hosts: control_planes[0]
  roles:
    - { role: networking, tasks_from: nginx_ingress }

- name: "Security Setup (Cert-Manager)"
  hosts: control_planes[0]
  roles:
    - { role: security, tasks_from: cert_manager }

- name: "Monitoring Setup"
  hosts: control_planes[0]
  roles:
    - monitoring

- name: "Logging Setup (Loki)"
  hosts: control_planes[0]
  roles:
    - logging

- name: "GitOps Setup (Flux)"
  hosts: control_planes[0]
  roles:
    - gitops

- name: "Post-Deploy Health Check"
  hosts: control_planes[0]
  roles:
    - { role: common, tasks_from: health_check }
```

### 5.2 Cluster-only Playbook (playbooks/cluster.yml)

```yaml
---
# Only Kubernetes Cluster (no extensions)
- name: "K8S Cluster - Bootstrap"
  hosts: all
  gather_facts: yes

- name: "Common Base Setup"
  hosts: all
  roles:
    - common

- name: "Control Plane Setup"
  hosts: control_planes
  serial: 1
  roles:
    - control_plane

- name: "Worker Node Setup"
  hosts: workers
  roles:
    - worker

- name: "Networking (Flannel)"
  hosts: control_planes[0]
  roles:
    - { role: networking, tasks_from: flannel }

- name: "Health Check"
  hosts: control_planes[0]
  roles:
    - { role: common, tasks_from: health_check }
```

### 5.3 Extensions-only Playbook (playbooks/extensions.yml)

```yaml
---
# Only Extensions (cluster must exist)
- name: "Deploy All Extensions"
  hosts: control_planes[0]
  serial: 1
  pre_tasks:
    - name: "Verify cluster is ready"
      kubernetes.core.k8s_info:
        kind: Node
      register: nodes_info
      until: nodes_info.resources | length > 0
      retries: 10
      delay: 30

  roles:
    - storage
    - { role: networking, tasks_from: metallb }
    - { role: networking, tasks_from: nginx_ingress }
    - { role: security, tasks_from: cert_manager }
    - monitoring
    - logging
    - gitops
```

---

## 6. Role-Details

### 6.1 Common Role (roles/common/tasks/main.yml)

```yaml
---
- name: "Update system"
  block:
    - name: "Update package cache"
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: "Upgrade packages"
      apt:
        upgrade: dist
        autoremove: yes
        autoclean: yes

- name: "Install base packages"
  apt:
    name: "{{ debian_packages }}"
    state: present

- name: "Configure kernel modules"
  block:
    - name: "Load kernel modules"
      modprobe:
        name: "{{ item }}"
        state: present
      loop:
        - overlay
        - br_netfilter

    - name: "Make kernel modules persistent"
      copy:
        content: |
          overlay
          br_netfilter
        dest: /etc/modules-load.d/kubernetes.conf
        mode: 0644

- name: "Configure sysctl for Kubernetes"
  sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    sysctl_set: yes
  loop:
    - { key: "net.bridge.bridge-nf-call-iptables", value: 1 }
    - { key: "net.bridge.bridge-nf-call-ip6tables", value: 1 }
    - { key: "net.ipv4.ip_forward", value: 1 }

- name: "Install containerd"
  block:
    - name: "Add Docker APT key"
      apt_key:
        url: https://download.docker.com/linux/debian/gpg
        state: present

    - name: "Add Docker APT repository"
      apt_repository:
        repo: "deb https://download.docker.com/linux/debian {{ ansible_distribution_release }} stable"
        state: present

    - name: "Install containerd"
      apt:
        name: containerd.io
        state: present

    - name: "Create containerd config directory"
      file:
        path: /etc/containerd
        state: directory
        mode: 0755

    - name: "Generate default containerd config"
      shell: "containerd config default | tee /etc/containerd/config.toml"
      args:
        creates: /etc/containerd/config.toml

    - name: "Enable systemd cgroup driver"
      lineinfile:
        path: /etc/containerd/config.toml
        regexp: '(\s+)SystemdCgroup = false'
        line: '\1SystemdCgroup = true'
        backrefs: yes

    - name: "Start and enable containerd"
      systemd:
        name: containerd
        state: restarted
        enabled: yes
        daemon_reload: yes

- name: "Install Kubernetes binaries"
  block:
    - name: "Add Kubernetes APT key"
      apt_key:
        url: https://dl.k8s.io/apt/doc/apt-key.gpg
        state: present

    - name: "Add Kubernetes APT repository"
      apt_repository:
        repo: "deb https://apt.kubernetes.io/ kubernetes-xenial main"
        state: present

    - name: "Install kubeadm, kubelet, kubectl"
      apt:
        name:
          - "kubeadm={{ kubernetes_version }}-00"
          - "kubelet={{ kubernetes_version }}-00"
          - "kubectl={{ kubernetes_version }}-00"
        state: present

    - name: "Hold Kubernetes packages"
      dpkg_selections:
        name: "{{ item }}"
        selection: hold
      loop:
        - kubeadm
        - kubelet
        - kubectl

- name: "Disable swap"
  block:
    - name: "Disable swap immediately"
      shell: swapoff -a

    - name: "Disable swap in fstab"
      lineinfile:
        path: /etc/fstab
        regexp: '.*swap.*'
        line: ''
        state: absent

- name: "Configure hostname and hosts"
  block:
    - name: "Set hostname"
      hostname:
        name: "{{ node_hostname }}"

    - name: "Update /etc/hosts"
      lineinfile:
        path: /etc/hosts
        line: "{{ node_ip }} {{ node_hostname }} {{ node_hostname }}.{{ cluster_domain }}"
        state: present

- name: "Health check tasks included"
  include_tasks: health_check.yml
```

### 6.2 Control Plane Role (roles/control_plane/tasks/main.yml)

```yaml
---
- name: "Initialize first Control Plane ({{ inventory_hostname }})"
  block:
    - name: "Create kubeadm init config"
      template:
        src: kubeadm-config.yaml.j2
        dest: /tmp/kubeadm-config.yaml
        mode: 0600
      when: is_first_cp

    - name: "Run kubeadm init (first CP only)"
      shell: |
        kubeadm init \
          --config=/tmp/kubeadm-config.yaml \
          --upload-certs \
          --v=2
      register: kubeadm_init_result
      when: is_first_cp
      timeout: 300

    - name: "Store init output"
      copy:
        content: "{{ kubeadm_init_result.stdout }}"
        dest: "/tmp/kubeadm-init.log"
      delegate_to: localhost
      when: is_first_cp and kubeadm_init_result is succeeded

    - name: "Extract join tokens"
      set_fact:
        kubelet_token: "{{ item.split()[4] }}.{{ item.split()[5] }}"
      when: '"kubeadm join" in item'
      loop: "{{ kubeadm_init_result.stdout_lines }}"
      when: is_first_cp
      register: extracted_tokens

  when: is_first_cp

- name: "Join other Control Planes"
  block:
    - name: "Generate CP join command on first CP"
      shell: |
        CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
        TOKEN=$(kubeadm token create --ttl=2h 2>/dev/null)
        CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
        echo "kubeadm join {{ api_server_endpoint }} --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${CA_HASH} --control-plane --certificate-key ${CERT_KEY}"
      register: cp_join_command
      changed_when: false
      when: is_first_cp

    - name: "Set CP join command fact"
      set_fact:
        cp_join_cmd: "{{ cp_join_command.stdout }}"
      when: is_first_cp
      delegate_to: "{{ groups['control_planes'][0] }}"

    - name: "Join CP node"
      shell: "{{ hostvars[groups['control_planes'][0]]['cp_join_cmd'] }}"
      register: cp_join_result
      until: cp_join_result is succeeded
      retries: 3
      delay: 30
      when: not is_first_cp
      timeout: 300

  when: inventory_hostname in groups['control_planes']

- name: "Setup kubeconfig"
  block:
    - name: "Create .kube directory"
      file:
        path: "{{ ansible_user_dir }}/.kube"
        state: directory
        mode: 0755

    - name: "Copy admin config"
      shell: "sudo cp -i /etc/kubernetes/admin.conf {{ ansible_user_dir }}/.kube/config"

    - name: "Set permissions"
      file:
        path: "{{ ansible_user_dir }}/.kube/config"
        owner: "{{ ansible_user_id }}"
        group: "{{ ansible_user_id }}"
        mode: 0600

    - name: "Install kubectl bash completion"
      shell: |
        kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
        chmod +r /etc/bash_completion.d/kubectl

- name: "Wait for API server"
  kubernetes.core.k8s_info:
    kind: Node
    wait: yes
    wait_condition:
      type: Ready
      status: "True"
    wait_sleep: 5
    wait_timeout: 300
```

### 6.3 Worker Role (roles/worker/tasks/main.yml)

```yaml
---
- name: "Generate worker join command on first CP"
  block:
    - name: "Create join command"
      shell: |
        kubeadm token create --print-join-command 2>/dev/null
      register: worker_join_command
      changed_when: false
      delegate_to: "{{ groups['control_planes'][0] }}"

    - name: "Set worker join command"
      set_fact:
        worker_join_cmd: "{{ worker_join_command.stdout }}"

- name: "Join worker node to cluster"
  shell: "{{ worker_join_cmd }}"
  register: worker_join_result
  until: worker_join_result is succeeded
  retries: 3
  delay: 30
  timeout: 300

- name: "Create local storage directory"
  block:
    - name: "Create local path provisioner directory"
      file:
        path: "{{ local_path_provisioner_path }}"
        state: directory
        mode: 0777
        owner: root
        group: root

- name: "Wait for kubelet"
  systemd:
    name: kubelet
    state: started
    enabled: yes
    daemon_reload: yes
```

### 6.4 Monitoring Role (roles/monitoring/tasks/main.yml)

```yaml
---
- name: "Install Helm"
  block:
    - name: "Download Helm"
      shell: |
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    - name: "Verify Helm"
      shell: helm version
      changed_when: false

- name: "Add Helm repositories"
  kubernetes.core.helm_repository:
    name: "{{ item.name }}"
    repo_url: "{{ item.url }}"
    state: present
  loop:
    - { name: "prometheus-community", url: "https://prometheus-community.github.io/helm-charts" }
    - { name: "grafana", url: "https://grafana.github.io/helm-charts" }

- name: "Create monitoring namespace"
  kubernetes.core.k8s:
    name: monitoring
    api_version: v1
    kind: Namespace
    state: present

- name: "Install kube-prometheus-stack"
  kubernetes.core.helm:
    name: prometheus
    chart_ref: prometheus-community/kube-prometheus-stack
    release_namespace: monitoring
    values:
      prometheus:
        prometheusSpec:
          retention: "{{ prometheus_retention }}"
          storageSpec:
            volumeClaimTemplate:
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 10Gi
      grafana:
        adminPassword: "{{ grafana_admin_password }}"
        persistence:
          enabled: true
          size: 5Gi
      alertmanager:
        enabled: true

- name: "Wait for Prometheus"
  kubernetes.core.k8s_info:
    kind: Pod
    namespace: monitoring
    label_selectors:
      - app.kubernetes.io/name=prometheus
    wait: yes
    wait_condition:
      type: Ready
      status: "True"
    wait_timeout: 300
```

### 6.5 Networking Role - Flannel (roles/networking/tasks/flannel.yml)

```yaml
---
- name: "Deploy Flannel CNI"
  kubernetes.core.k8s:
    state: present
    definition: "{{ lookup('url', 'https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml') | from_yaml_all }}"

- name: "Wait for Flannel DaemonSet"
  kubernetes.core.k8s_info:
    kind: DaemonSet
    namespace: kube-flannel
    name: kube-flannel-ds
    wait: yes
    wait_condition:
      type: Available
      status: "True"
    wait_timeout: 300

- name: "Wait for all nodes Ready"
  kubernetes.core.k8s_info:
    kind: Node
    wait: yes
    wait_condition:
      type: Ready
      status: "True"
    wait_timeout: 600
  register: nodes_status
  until: "nodes_status.resources | length == (groups['control_planes'] | length + groups['workers'] | length)"
  retries: 20
  delay: 30
```

### 6.6 Networking Role - MetalLB (roles/networking/tasks/metallb.yml)

```yaml
---
- name: "Add MetalLB Helm repo"
  kubernetes.core.helm_repository:
    name: metallb
    repo_url: "https://metallb.github.io/metallb"
    state: present

- name: "Create metallb namespace"
  kubernetes.core.k8s:
    name: metallb-system
    api_version: v1
    kind: Namespace
    state: present

- name: "Install MetalLB"
  kubernetes.core.helm:
    name: metallb
    chart_ref: metallb/metallb
    release_namespace: metallb-system
    wait: yes

- name: "Configure MetalLB IPAddressPool"
  kubernetes.core.k8s:
    state: present
    definition:
      - apiVersion: metallb.io/v1beta1
        kind: IPAddressPool
        metadata:
          name: first-pool
          namespace: metallb-system
        spec:
          addresses:
            - "{{ metallb_ip_range }}"
      - apiVersion: metallb.io/v1beta1
        kind: L2Advertisement
        metadata:
          name: l2-advert
          namespace: metallb-system
        spec:
          ipAddressPools:
            - first-pool
```

### 6.7 Networking Role - Nginx Ingress (roles/networking/tasks/nginx_ingress.yml)

```yaml
---
- name: "Add Nginx Helm repo"
  kubernetes.core.helm_repository:
    name: ingress-nginx
    repo_url: "https://kubernetes.github.io/ingress-nginx"
    state: present

- name: "Create ingress-nginx namespace"
  kubernetes.core.k8s:
    name: ingress-nginx
    api_version: v1
    kind: Namespace
    state: present

- name: "Install Nginx Ingress Controller"
  kubernetes.core.helm:
    name: ingress-nginx
    chart_ref: ingress-nginx/ingress-nginx
    release_namespace: ingress-nginx
    values:
      controller:
        service:
          type: LoadBalancer
        metrics:
          enabled: true
        podAnnotations:
          prometheus.io/scrape: "true"
          prometheus.io/port: "10254"
    wait: yes
```

### 6.8 Storage Role (roles/storage/tasks/local_path.yml)

```yaml
---
- name: "Create storage directories on workers"
  file:
    path: "{{ local_path_provisioner_path }}"
    state: directory
    mode: 0777
  delegate_to: "{{ item }}"
  loop: "{{ groups['workers'] }}"

- name: "Deploy Local Path Provisioner"
  kubernetes.core.k8s:
    state: present
    definition: "{{ lookup('url', 'https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml') | from_yaml_all }}"

- name: "Set local-path as default StorageClass"
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: storage.k8s.io/v1
      kind: StorageClass
      metadata:
        name: local-path
        annotations:
          storageclass.kubernetes.io/is-default-class: "true"
      provisioner: rancher.io/local-path
      reclaimPolicy: Delete
      volumeBindingMode: WaitForFirstConsumer
```

### 6.9 Security Role - Cert-Manager (roles/security/tasks/cert_manager.yml)

```yaml
---
- name: "Add Jetstack Helm repo"
  kubernetes.core.helm_repository:
    name: jetstack
    repo_url: "https://charts.jetstack.io"
    state: present

- name: "Create cert-manager namespace"
  kubernetes.core.k8s:
    name: cert-manager
    api_version: v1
    kind: Namespace
    state: present

- name: "Install CRDs"
  shell: |
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.crds.yaml

- name: "Install Cert-Manager"
  kubernetes.core.helm:
    name: cert-manager
    chart_ref: jetstack/cert-manager
    release_namespace: cert-manager
    wait: yes

- name: "Create ClusterIssuers"
  kubernetes.core.k8s:
    state: present
    definition:
      - apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt-prod
        spec:
          acme:
            server: https://acme-v02.api.letsencrypt.org/directory
            email: admin@cluster.local
            privateKeySecretRef:
              name: letsencrypt-prod
            solvers:
              - http01:
                  ingress:
                    class: nginx
      - apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: selfsigned
        spec:
          selfSigned: {}
```

### 6.10 Logging Role (roles/logging/tasks/main.yml)

```yaml
---
- name: "Add Grafana Helm repo"
  kubernetes.core.helm_repository:
    name: grafana
    repo_url: "https://grafana.github.io/helm-charts"
    state: present

- name: "Create loki namespace"
  kubernetes.core.k8s:
    name: loki
    api_version: v1
    kind: Namespace
    state: present

- name: "Install Loki Stack"
  kubernetes.core.helm:
    name: loki
    chart_ref: grafana/loki-stack
    release_namespace: loki
    values:
      loki:
        persistence:
          enabled: true
          size: 10Gi
      promtail:
        enabled: true
        config:
          clients:
            - url: http://loki:3100/loki/api/v1/push
    wait: yes
```

### 6.11 GitOps Role - Flux (roles/gitops/tasks/main.yml)

```yaml
---
- name: "Install Flux CLI"
  block:
    - name: "Download Flux"
      shell: |
        curl -s https://fluxcd.io/install.sh | sudo bash

    - name: "Verify Flux"
      shell: flux --version
      changed_when: false

- name: "Bootstrap Flux"
  shell: |
    flux bootstrap github \
      --owner={{ github_user }} \
      --repository={{ github_repo }} \
      --branch=main \
      --path=clusters/dev-test \
      --personal \
      --token-auth
  environment:
    GITHUB_TOKEN: "{{ github_token }}"
  register: flux_bootstrap
  changed_when: "'bootstrap completed' in flux_bootstrap.stdout or 'already' in flux_bootstrap.stdout"

- name: "Verify Flux"
  shell: flux check
  changed_when: false
```

### 6.12 Health Check (roles/common/tasks/health_check.yml)

```yaml
---
- name: "Health Check - Nodes"
  kubernetes.core.k8s_info:
    kind: Node
  register: nodes_info
  until: "nodes_info.resources | length > 0 and (nodes_info.resources | map(attribute='status.conditions') | flatten | selectattr('type', 'equalto', 'Ready') | map(attribute='status') | list == ['True'] * (nodes_info.resources | length))"
  retries: 20
  delay: 30

- name: "Health Check - Pods"
  kubernetes.core.k8s_info:
    kind: Pod
    namespace: "{{ item }}"
  register: pods_info
  loop:
    - kube-system
    - kube-flannel
  until: "pods_info.resources | map(attribute='status.containerStatuses') | flatten | selectattr('ready', 'equalto', true) | list | length > 0"
  retries: 15
  delay: 20

- name: "Print Cluster Status"
  debug:
    msg: |
      Cluster Status:
      - Nodes: {{ nodes_info.resources | length }} Ready
      - API Server: Healthy
      - etcd: Healthy
      - Pods in kube-system: {{ (pods_info.results[0].resources | selectattr('status.phase', 'equalto', 'Running') | list | length) }}
      - CNI Plugin: Flannel Ready
```

---

## 7. Ausführung & Best Practices

### 7.1 Pre-Checks

```bash
# SSH Connectivity testen
ansible -i inventory/hosts.yml all -m ping

# Sudo ohne Password prüfen
ansible -i inventory/hosts.yml all -m shell -a "sudo whoami"

# Python verfügbar?
ansible -i inventory/hosts.yml all -m setup | head -20
```

### 7.2 Dry-Run (Syntax Check)

```bash
# Syntax validieren
ansible-playbook --syntax-check playbooks/site.yml

# Dry-run (no changes)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check

# Mit Diff
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff | head -100
```

### 7.3 Playbook Ausführung

```bash
# Nur Cluster (kein Extensions)
ansible-playbook -i inventory/hosts.yml playbooks/cluster.yml -v

# Alles (Cluster + Extensions) - dauert 30-45 min
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v

# Nur Extensions (auf existierendem Cluster)
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -v

# Nur bestimmte Host Group
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit control_planes

# Nur bestimmte Role
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "monitoring"
```

### 7.4 Logging & Debugging

```bash
# Verbose output
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vvv

# Spezific Task debuggen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vv -t "common" | tee ansible-debug.log

# Log durchsuchen
grep -i error ansible.log
grep -i warning ansible.log
```

### 7.5 Fehlerbehandlung

```bash
# Retry bei Fehler
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --extra-vars "ansible_retries=3"

# Ignore errors auf task level
# (In playbook mit "ignore_errors: yes")

# Fehler protokollieren
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v 2>&1 | tee deployment-$(date +%Y%m%d_%H%M%S).log
```

### 7.6 Best Practices

**1. Always Test First**
```bash
# Stage Environment testen
ansible-playbook -i inventory/stage.yml playbooks/cluster.yml

# Nur bestimmte Nodes
ansible-playbook -i inventory/hosts.yml playbooks/cluster.yml --limit "k8s-cp1"
```

**2. Idempotenz sicherstellen**
```bash
# 2x ausführen sollte keine Änderungen anzeigen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
ansible-playbook -i inventory/hosts.yml playbooks/site.yml  # Sollte "changed: 0" zeigen
```

**3. Variables schützen**
```bash
# Sensible Daten in separate Datei
# Dann mit --extra-vars oder vault verschlüsseln
ansible-vault encrypt inventory/group_vars/all.yml

# Mit Playbook verwenden
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass
```

**4. Incremental Rollout**
```bash
# Serial deployment für HA
# (in playbooks mit "serial: 1")

# Damit Control Planes nacheinander joined werden
```

---

## 8. GitHub Actions Integration

### 8.1 GitHub Actions Workflow (.github/workflows/deploy.yml)

```yaml
name: Deploy K8S Cluster

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'ansible/**'
      - '.github/workflows/deploy.yml'
  workflow_dispatch:

env:
  ANSIBLE_HOST_KEY_CHECKING: False

jobs:
  syntax-check:
    name: Ansible Syntax Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install Ansible
        run: |
          pip install ansible-core requests
          ansible-galaxy collection install -r ansible/requirements.yml
      
      - name: Run Ansible Syntax Check
        run: |
          cd ansible
          ansible-playbook --syntax-check playbooks/site.yml

  lint:
    name: Ansible Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install ansible-lint
        run: pip install ansible-lint
      
      - name: Run ansible-lint
        run: |
          cd ansible
          ansible-lint playbooks/site.yml

  dry-run:
    name: Ansible Dry-Run (Check Mode)
    runs-on: ubuntu-latest
    needs: [syntax-check, lint]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install ansible-core requests
          ansible-galaxy collection install -r ansible/requirements.yml
      
      - name: Create SSH Key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.K8S_SSH_KEY }}" > ~/.ssh/k8s_cluster
          chmod 600 ~/.ssh/k8s_cluster
      
      - name: Run Ansible Check Mode
        working-directory: ansible
        run: |
          ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check -v

  deploy:
    name: Deploy to Cluster
    runs-on: ubuntu-latest
    needs: dry-run
    if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install ansible-core requests
          ansible-galaxy collection install -r ansible/requirements.yml
      
      - name: Create SSH Key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.K8S_SSH_KEY }}" > ~/.ssh/k8s_cluster
          chmod 600 ~/.ssh/k8s_cluster
      
      - name: Deploy K8S Cluster
        working-directory: ansible
        run: |
          ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 8.2 GitHub Secrets Setup

```bash
# In GitHub Repo: Settings → Secrets and variables → Actions

# SSH Private Key
K8S_SSH_KEY=$(cat ~/.ssh/k8s_cluster)

# GitHub Token
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```

### 8.3 Bootstrap Script (scripts/bootstrap.sh)

```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== K8S Cluster Automation Bootstrap ===${NC}"

# Check prerequisites
echo -e "${YELLOW}1. Checking prerequisites...${NC}"

if ! command -v ansible &> /dev/null; then
    echo -e "${RED}Ansible not found. Installing...${NC}"
    python3 -m pip install --upgrade pip
    pip install ansible-core requests
fi

if ! command -v git &> /dev/null; then
    echo -e "${RED}Git not found. Please install first.${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}2. Installing Ansible collections...${NC}"
cd ansible
ansible-galaxy install -r requirements.yml

# SSH Key
echo -e "${YELLOW}3. Checking SSH key...${NC}"
if [ ! -f ~/.ssh/k8s_cluster ]; then
    echo -e "${YELLOW}SSH Key not found. Creating...${NC}"
    ssh-keygen -t ed25519 -f ~/.ssh/k8s_cluster -C "k8s-automation" -N ""
    echo -e "${GREEN}SSH Key created at ~/.ssh/k8s_cluster${NC}"
fi

# Inventory
echo -e "${YELLOW}4. Testing inventory connectivity...${NC}"
ansible -i inventory/hosts.yml all -m ping

# Syntax check
echo -e "${YELLOW}5. Checking playbook syntax...${NC}"
ansible-playbook --syntax-check playbooks/site.yml

echo -e "${GREEN}=== Bootstrap Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Update ansible/inventory/hosts.yml with your nodes"
echo "2. Run: ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml"
echo ""
```

---

## 📊 Execution Timeline

Typische Ausführungsdauer:

| Phase | Dauer |
|-------|-------|
| Common Setup (all nodes) | 5-10 min |
| CP1 Init | 3-5 min |
| CP2/CP3 Join | 2-3 min pro Node |
| Worker Join | 1-2 min pro Node |
| Flannel Deploy | 2-3 min |
| Storage Setup | 1-2 min |
| MetalLB | 2-3 min |
| Nginx Ingress | 3-5 min |
| Monitoring | 5-10 min |
| Logging | 3-5 min |
| Cert-Manager | 2-3 min |
| Flux Bootstrap | 3-5 min |
| **Gesamt** | **30-60 min** |

---

## 🔍 Verification nach Deployment

```bash
# Cluster Health
ansible-playbook -i inventory/hosts.yml playbooks/health-check.yml

# Nodes
kubectl get nodes -o wide

# Pods
kubectl get pods -A

# Storage
kubectl get storageclasses,pvc

# Services
kubectl get svc -A

# Ingress
kubectl get ingress -A
```

---

## 🚨 Troubleshooting

```bash
# Logs einer Task ansehen
tail -100 ansible.log | grep "TASK\|error\|failed"

# Spezific Host debuggen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit "k8s-cp1" -vvv

# Task einzeln ausführen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --start-at-task "Wait for Flannel DaemonSet" -v
```

---

## 📝 Nächste Schritte

1. ✅ Inventory aktualisieren (`inventory/hosts.yml`)
2. ✅ Variables anpassen (`inventory/group_vars/`)
3. ✅ SSH Key vorbereiten
4. ✅ `scripts/bootstrap.sh` ausführen
5. ✅ `ansible-playbook playbooks/site.yml` starten
6. ✅ Mit `kubectl` verifizieren
7. ✅ GitHub integrieren (optional)

---

**Fragen?** Meld dich! 🚀

