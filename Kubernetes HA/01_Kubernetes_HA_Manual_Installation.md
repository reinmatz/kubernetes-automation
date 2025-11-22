# Kubernetes HA Cluster - Manual Installation (Schritt-für-Schritt)

**Zielumgebung:** On-Premise VMs, Debian 12, High-Availability Setup  
**Kubernetes Version:** 1.28+ (aktuell stable)  
**Container Runtime:** containerd

---

## Inhaltsverzeichnis

1. [Netzwerk-Planung & Voraussetzungen](#1-netzwerk-planung--voraussetzungen)
2. [VM-Vorbereitung](#2-vm-vorbereitung)
3. [Basis-Setup auf allen Nodes](#3-basis-setup-auf-allen-nodes)
4. [Control Plane Bootstrap](#4-control-plane-bootstrap)
5. [Worker Nodes konfigurieren](#5-worker-nodes-konfigurieren)
6. [HA Load Balancer (optional intern)](#6-ha-load-balancer-optional-intern)
7. [Netzwerk-Plugin (Flannel)](#7-netzwerk-plugin-flannel)
8. [Storage (Local Path Provisioner)](#8-storage-local-path-provisioner)
9. [MetalLB (External Load Balancer)](#9-metallb-external-load-balancer)
10. [Nginx Ingress Controller](#10-nginx-ingress-controller)
11. [Monitoring (Prometheus + Grafana)](#11-monitoring-prometheus--grafana)
12. [Logging (Loki + Promtail)](#12-logging-loki--promtail)
13. [Cert-Manager (HTTPS/TLS)](#13-cert-manager-httpstls)
14. [Flux CD (GitOps)](#14-flux-cd-gitops)
15. [Troubleshooting & Verification](#15-troubleshooting--verification)

---

## 1. Netzwerk-Planung & Voraussetzungen

### Infrastruktur-Übersicht

```
┌─────────────────────────────────────────────────────────┐
│                  Cluster Topology                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Control Plane (HA):                                    │
│  ├─ k8s-cp1: 192.168.100.10 (4CPU/8GB)                │
│  ├─ k8s-cp2: 192.168.100.11 (4CPU/8GB)                │
│  └─ k8s-cp3: 192.168.100.12 (4CPU/8GB)                │
│                                                         │
│  Worker Nodes:                                          │
│  ├─ k8s-w1: 192.168.100.20 (8CPU/16GB)                │
│  └─ k8s-w2: 192.168.100.21 (8CPU/16GB)                │
│                                                         │
│  Load Balancer (Virtual):                               │
│  └─ k8s-lb: 192.168.100.100 (2CPU/4GB) - Optional     │
│                                                         │
│  Pod Network Range: 10.244.0.0/16 (Flannel)            │
│  Service CIDR: 10.96.0.0/12 (default)                  │
│  MetalLB Range: 192.168.100.200-210 (External IPs)    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Netzwerk-Anforderungen

- **Alle Nodes** müssen sich gegenseitig sehen können (L3-Konnektivität)
- **Ports offen** (siehe unten)
- **DNS-Auflösung** für alle Hostnames (oder /etc/hosts)
- **Keine Firewall-Blocking** zwischen Nodes (oder Regeln öffnen)

### Erforderliche Ports

#### Control Plane Nodes

| Port | Protokoll | Beschreibung |
|------|-----------|-------------|
| 6443 | TCP | Kubernetes API |
| 2379-2380 | TCP | etcd Server / Peer |
| 10250 | TCP | kubelet API |
| 10251 | TCP | kube-scheduler |
| 10252 | TCP | kube-controller-manager |
| 10255 | TCP | Read-only kubelet API |

#### Worker Nodes

| Port | Protokoll | Beschreibung |
|------|-----------|-------------|
| 10250 | TCP | kubelet API |
| 10255 | TCP | Read-only kubelet API |
| 30000-32767 | TCP/UDP | NodePort Services |

### Systemanforderungen

**Pro Node (Minimum):**
- CPU: 2 Cores (besser 4+)
- RAM: 2GB (besser 8GB+)
- Disk: 20GB (besser 50GB+)
- OS: Debian 11/12 (aktuell)

**Für Production HA:**
- 3 Control Plane Nodes (nie 2!)
- 2-5 Worker Nodes
- Dedicated Load Balancer (HAProxy/Keepalived oder externe HW)

---

## 2. VM-Vorbereitung

### 2.1 Debian Installation (alle VMs)

Installiere Debian 12 Bookworm mit folgenden Settings:

```bash
# Während Installation:
- Hostname: k8s-cp1, k8s-cp2, k8s-cp3, k8s-w1, k8s-w2
- Domain: cluster.local (oder deine Domain)
- IP-Adressen: Statisch (siehe oben)
- Standard-Software: SSH Server, keine GUI
```

### 2.2 Basis-Netzwerk-Konfiguration

**Auf k8s-cp1 (192.168.100.10):**

```bash
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.100.10/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
        search: [cluster.local]
EOF

sudo netplan apply
```

**Auf k8s-cp2 (192.168.100.11):**

```bash
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.100.11/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
        search: [cluster.local]
EOF

sudo netplan apply
```

**Auf k8s-cp3 (192.168.100.12):**

```bash
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.100.12/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
        search: [cluster.local]
EOF

sudo netplan apply
```

**Auf k8s-w1 (192.168.100.20) und k8s-w2 (192.168.100.21):**

Analog anpassen.

### 2.3 Hosts-Datei aktualisieren

**Auf ALLEN VMs:**

```bash
sudo tee -a /etc/hosts << 'EOF'

# Kubernetes Cluster
192.168.100.10   k8s-cp1.cluster.local   k8s-cp1
192.168.100.11   k8s-cp2.cluster.local   k8s-cp2
192.168.100.12   k8s-cp3.cluster.local   k8s-cp3
192.168.100.20   k8s-w1.cluster.local    k8s-w1
192.168.100.21   k8s-w2.cluster.local    k8s-w2
192.168.100.100  k8s-lb.cluster.local    k8s-lb
EOF
```

### 2.4 SSH Key-basierte Authentifizierung (optional aber recommended)

Auf deinem lokalen Rechner:

```bash
# SSH-Key generieren (falls noch nicht vorhanden)
ssh-keygen -t ed25519 -f ~/.ssh/k8s_cluster -C "kubernetes@cluster"

# Keys zu allen Nodes kopieren
for node in 10 11 12 20 21; do
  ssh-copy-id -i ~/.ssh/k8s_cluster debian@192.168.100.${node}
done
```

### 2.5 SSH-Config für leichteren Zugriff

```bash
# ~/.ssh/config auf deinem Rechner
cat >> ~/.ssh/config << 'EOF'
Host k8s-cp1
  HostName 192.168.100.10
  User debian
  IdentityFile ~/.ssh/k8s_cluster

Host k8s-cp2
  HostName 192.168.100.11
  User debian
  IdentityFile ~/.ssh/k8s_cluster

Host k8s-cp3
  HostName 192.168.100.12
  User debian
  IdentityFile ~/.ssh/k8s_cluster

Host k8s-w1
  HostName 192.168.100.20
  User debian
  IdentityFile ~/.ssh/k8s_cluster

Host k8s-w2
  HostName 192.168.100.21
  User debian
  IdentityFile ~/.ssh/k8s_cluster
EOF
```

Jetzt kannst du mit `ssh k8s-cp1` direkt verbinden!

---

## 3. Basis-Setup auf allen Nodes

Führe diesen Block auf **ALLEN 5 Nodes** aus (k8s-cp1, cp2, cp3, w1, w2).

### 3.1 System-Updates & Kernel-Module

```bash
sudo apt update && sudo apt upgrade -y

# Module laden
sudo modprobe overlay
sudo modprobe br_netfilter

# Persistent machen
cat << 'EOF' | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF

# Sysctl-Einstellungen
cat << 'EOF' | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

### 3.2 containerd Installation & Konfiguration

```bash
# Abhängigkeiten
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Docker GPG Key
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Docker Repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

# containerd Installation
sudo apt install -y containerd.io

# Default Config generieren
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# SystemdCgroup aktivieren (wichtig für cgroup v2)
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml

# containerd starten
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd

# Verify
sudo systemctl status containerd
```

### 3.3 Kubernetes Binaries

```bash
# GPG Key für Kubernetes
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg

# Kubernetes Repository
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update

# kubeadm, kubelet, kubectl installieren
sudo apt install -y kubeadm kubelet kubectl

# Hold (damit bei apt upgrade nicht auto-updated wird)
sudo apt-mark hold kubeadm kubelet kubectl

# kubelet systemd preset
sudo mkdir -p /etc/systemd/system/kubelet.service.d
```

### 3.4 Swap deaktivieren (WICHTIG!)

```bash
# Swap ausschalten
sudo swapoff -a

# Persistent - swap aus fstab entfernen
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Verify
free -h  # Swap sollte 0 sein
```

### 3.5 Firewall (UFW) - Falls aktiviert

```bash
# Falls UFW läuft, Ports öffnen:

# Auf Control Plane Nodes:
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 6443/tcp    # API Server
sudo ufw allow 2379/tcp    # etcd client
sudo ufw allow 2380/tcp    # etcd peer
sudo ufw allow 10250/tcp   # kubelet
sudo ufw allow 10251/tcp   # kube-scheduler
sudo ufw allow 10252/tcp   # kube-controller-manager

# Auf Worker Nodes:
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 10250/tcp   # kubelet
sudo ufw allow 30000:32767/tcp  # NodePort

# Alle Nodes
sudo ufw enable
```

### 3.6 Verify auf allen Nodes

```bash
# 1. Kernel-Module
lsmod | grep -E "overlay|br_netfilter"

# 2. containerd läuft?
sudo systemctl is-active containerd

# 3. kubelet bereit?
sudo systemctl status kubelet  # Sollte inaktiv sein (normal bis Control Plane ready)

# 4. Netzwerk-Ping Test
ping -c 3 192.168.100.10  # Test zu anderen Nodes

# 5. Swap deaktiviert?
free -h | grep Swap  # Sollte 0B sein
```

---

## 4. Control Plane Bootstrap

Jetzt initialisieren wir die HA Control Plane mit **kubeadm init**.

### 4.1 Erster Control Plane Node (k8s-cp1)

```bash
# SSH zu k8s-cp1
ssh k8s-cp1

# kubeadm init ausführen
sudo kubeadm init \
  --control-plane-endpoint "192.168.100.100:6443" \
  --kubernetes-version "v1.28.0" \
  --pod-network-cidr "10.244.0.0/16" \
  --service-cidr "10.96.0.0/12" \
  --upload-certs \
  --apiserver-advertise-address "192.168.100.10"
```

**Output speichern!** Du brauchst die Tokens später.

```bash
# Nach erfolgreichem init:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes  # Sollte k8s-cp1 zeigen (NotReady bis Networking aktiv)
```

### 4.2 Token für andere Control Planes generieren

Falls du die Tokens vom init nicht mehr hast:

```bash
# Auf k8s-cp1
sudo kubeadm token create --print-join-command --certificate-key=$(sudo kubeadm init phase upload-certs --upload-certs | grep -oP '(?<=Saving certificate key to secret.).*' || echo "")
```

Alternativ:

```bash
# Neue Tokens generieren
CONTROL_PLANE_TOKEN=$(sudo kubeadm token create --ttl=2h | head -1)
CERTIFICATE_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -1)

echo "Control Plane Join Command:"
echo "kubeadm join 192.168.100.100:6443 --token ${CONTROL_PLANE_TOKEN} --discovery-token-ca-cert-hash sha256:$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //') --control-plane --certificate-key ${CERTIFICATE_KEY}"
```

### 4.3 Zweiter Control Plane Node (k8s-cp2)

```bash
ssh k8s-cp2

# Token-Command von oben (aus 4.2) ausführen, z.B.:
sudo kubeadm join 192.168.100.100:6443 \
  --token abc123.def456 \
  --discovery-token-ca-cert-hash sha256:abcdef1234567890 \
  --control-plane \
  --certificate-key 1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p

# kubeconfig vorbereiten
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 4.4 Dritter Control Plane Node (k8s-cp3)

Gleich wie 4.3

```bash
ssh k8s-cp3

# Token-Command ausführen
sudo kubeadm join 192.168.100.100:6443 \
  --token abc123.def456 \
  --discovery-token-ca-cert-hash sha256:abcdef1234567890 \
  --control-plane \
  --certificate-key 1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p

# kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 4.5 Verify Control Plane

```bash
# Von jedem Control Plane Node aus
kubectl get nodes
kubectl get pods -A

# Sollte zeigen:
# NAME      STATUS   ROLES           AGE
# k8s-cp1   NotReady control-plane   2m
# k8s-cp2   NotReady control-plane   1m
# k8s-cp3   NotReady control-plane   50s

# Status "NotReady" bis Netzwerk-Plugin aktiv (nächster Schritt)
```

---

## 5. Worker Nodes konfigurieren

### 5.1 Worker Node Join Command generieren

**Auf einem Control Plane Node (z.B. k8s-cp1):**

```bash
# Falls noch Token vorhanden
WORKER_TOKEN=$(sudo kubeadm token create --ttl=2h)
DISCOVERY_TOKEN_CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

echo "Worker Join Command:"
echo "kubeadm join 192.168.100.100:6443 --token ${WORKER_TOKEN} --discovery-token-ca-cert-hash sha256:${DISCOVERY_TOKEN_CA_CERT_HASH}"
```

### 5.2 Worker Nodes joinen

**Auf k8s-w1:**

```bash
ssh k8s-w1

# Token-Command ausführen (ohne --control-plane!)
sudo kubeadm join 192.168.100.100:6443 \
  --token abc123.def456 \
  --discovery-token-ca-cert-hash sha256:abcdef1234567890
```

**Auf k8s-w2:**

```bash
ssh k8s-w2

# Gleicher Command
sudo kubeadm join 192.168.100.100:6443 \
  --token abc123.def456 \
  --discovery-token-ca-cert-hash sha256:abcdef1234567890
```

### 5.3 Verify

```bash
# Auf einem Control Plane Node
kubectl get nodes

# Output sollte zeigen (NotReady bis Networking):
# NAME      STATUS   ROLES           AGE
# k8s-cp1   NotReady control-plane   5m
# k8s-cp2   NotReady control-plane   4m
# k8s-cp3   NotReady control-plane   3m
# k8s-w1    NotReady <none>          1m
# k8s-w2    NotReady <none>          1m
```

---

## 6. HA Load Balancer (optional intern)

### 6.1 Szenario A: HAProxy + Keepalived (auf separater VM)

Falls du eine dedizierte LB-VM hast (k8s-lb @ 192.168.100.100):

```bash
ssh k8s-lb

# Abhängigkeiten
sudo apt install -y haproxy keepalived

# HAProxy config
sudo tee /etc/haproxy/haproxy.cfg << 'EOF'
global
    log stdout local0
    maxconn 2048
    daemon
    default-mode http
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend kubernetes-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-api

backend kubernetes-api
    mode tcp
    option tcplog
    balance roundrobin
    server k8s-cp1 192.168.100.10:6443 check fall 3 rise 2
    server k8s-cp2 192.168.100.11:6443 check fall 3 rise 2
    server k8s-cp3 192.168.100.12:6443 check fall 3 rise 2
EOF

sudo systemctl restart haproxy

# Keepalived config (für failover - optional)
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
vrrp_script check_haproxy {
    script "/usr/lib/keepalived/check_haproxy.sh"
    interval 2
    weight -2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    virtual_ipaddress {
        192.168.100.100/24
    }
    track_script {
        check_haproxy
    }
}
EOF

sudo systemctl enable keepalived haproxy
sudo systemctl restart keepalived haproxy
```

### 6.2 Szenario B: Nur auf einem CP Node (einfacher)

Falls keine separate LB-VM:

```bash
# Für Tests: einfach auf k8s-cp1 machen
# IP 192.168.100.100 ist dann logisch (kein failover)
# In Production: Szenario A verwenden!

# Loopback-Interface für VIP
sudo ip addr add 192.168.100.100/32 dev lo
# Persistent:
echo "auto lo:1
iface lo:1 inet static
  address 192.168.100.100
  netmask 255.255.255.255" | sudo tee -a /etc/network/interfaces
```

---

## 7. Netzwerk-Plugin (Flannel)

Jetzt installieren wir Flannel als Pod Network Plugin. **Auf einem Control Plane Node ausführen:**

```bash
ssh k8s-cp1

# Flannel Manifest deployen
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Verify - warten bis alle Pods Running sind
kubectl get pods -n kube-flannel-cfg -w

# Nach ~2 Minuten sollten Nodes zu "Ready" wechseln
kubectl get nodes
# NAME      STATUS   ROLES           AGE
# k8s-cp1   Ready    control-plane   10m
# k8s-cp2   Ready    control-plane   8m
# ...
```

---

## 8. Storage (Local Path Provisioner)

Für Dev/Test: Local Path Provisioner (nicht für Production!).

```bash
# Local Path Provisioner installieren
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Verify
kubectl get storageclasses
# NAME                   PROVISIONER             RECLAIMPOLICY
# local-path (default)   rancher.io/local-path   Delete

# Optional: Als Default setzen
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**Auf allen Worker Nodes lokale Paths erstellen:**

```bash
# Auf k8s-w1 und k8s-w2
sudo mkdir -p /opt/local-path-provisioner
sudo chmod 777 /opt/local-path-provisioner
```

---

## 9. MetalLB (External Load Balancer)

Für externe Load Balancing (NodePort → external IP).

```bash
# MetalLB Namespace
kubectl create namespace metallb-system

# MetalLB installieren
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml

# Warten bis Pods Running
kubectl get pods -n metallb-system -w

# IPAddressPool konfigurieren
kubectl apply -f - << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.100.200-192.168.100.210

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF

# Verify
kubectl get ipaddresspool -n metallb-system
```

---

## 10. Nginx Ingress Controller

```bash
# Helm Repository hinzufügen (Voraussetzung: helm installiert)
# Falls Helm noch nicht vorhanden:
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Nginx Repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Nginx Ingress installieren
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.metrics.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set controller.podAnnotations."prometheus\.io/port"="10254"

# Verify
kubectl get svc -n ingress-nginx
# NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP       PORT(S)
# ingress-nginx-controller   LoadBalancer   10.96.123.1   192.168.100.200   80:30000/TCP,443:30443/TCP

# External-IP sollte von MetalLB zugewiesen werden
kubectl get ingress -A
```

---

## 11. Monitoring (Prometheus + Grafana)

### 11.1 Prometheus Stack (kube-prometheus-stack)

```bash
# Helm Repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Namespace
kubectl create namespace monitoring

# kube-prometheus-stack installieren (alles: Prometheus, Grafana, AlertManager)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values - << 'EOF'
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

grafana:
  adminPassword: admin123  # ÄNDERN in Production!
  persistence:
    enabled: true
    size: 5Gi
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-kube-prometheus-prometheus:9090

alertmanager:
  enabled: true
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: 'null'
    receivers:
      - name: 'null'
EOF

# Verify
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
```

### 11.2 Grafana Access

```bash
# Port-Forward zu Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Browser: http://localhost:3000
# Login: admin / admin123
```

### 11.3 Ingress für Prometheus & Grafana (optional)

```bash
kubectl apply -f - << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.cluster.local
    - grafana.cluster.local
    secretName: monitoring-tls
  rules:
  - host: prometheus.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-kube-prometheus-prometheus
            port:
              number: 9090
  - host: grafana.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-grafana
            port:
              number: 80
EOF
```

---

## 12. Logging (Loki + Promtail)

### 12.1 Loki Stack installieren

```bash
# Repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Namespace
kubectl create namespace loki

# Loki + Promtail installieren
helm install loki grafana/loki-stack \
  --namespace loki \
  --values - << 'EOF'
loki:
  persistence:
    enabled: true
    size: 10Gi
  
promtail:
  enabled: true
  config:
    clients:
      - url: http://loki:3100/loki/api/v1/push

grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Loki
          type: loki
          url: http://loki:3100
          access: proxy
          isDefault: false
EOF

# Verify
kubectl get pods -n loki
kubectl get pvc -n loki
```

### 12.2 Loki zu Grafana hinzufügen

1. Grafana öffnen (http://localhost:3000)
2. Configuration → Data Sources → Add
3. Name: Loki
4. URL: http://loki:3100
5. Save & Test

---

## 13. Cert-Manager (HTTPS/TLS)

```bash
# Helm Repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# CRDs installieren
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.crds.yaml

# cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace

# ClusterIssuer für Let's Encrypt (selbstsigniert für internal use)
kubectl apply -f - << 'EOF'
apiVersion: cert-manager.io/v1
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

---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF

# Verify
kubectl get clusterissuer
```

---

## 14. Flux CD (GitOps)

### 14.1 Flux Installation

```bash
# Flux CLI installieren
curl -s https://fluxcd.io/install.sh | sudo bash

# Oder via Homebrew/Apt (je nach distro)
sudo apt-get install -y flux

# Verify
flux --version
```

### 14.2 GitHub Repository vorbereiten

1. Auf GitHub neues Repo erstellen: `k8s-cluster-config`
2. Repo clonen:

```bash
git clone https://github.com/YOUR_USER/k8s-cluster-config.git
cd k8s-cluster-config

# Struktur erstellen
mkdir -p clusters/dev-test/apps
mkdir -p clusters/dev-test/infrastructure
touch clusters/dev-test/apps/.keep
touch clusters/dev-test/infrastructure/.keep

git add .
git commit -m "Initial structure"
git push
```

### 14.3 Flux Bootstrap

```bash
# GitHub Token generieren:
# 1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
# 2. Neuen Token erstellen mit: repo, read:org

export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
export GITHUB_USER=YOUR_USER
export GITHUB_REPO=k8s-cluster-config

# Flux Bootstrap (erzeugt automatisch Manifests)
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=clusters/dev-test \
  --personal \
  --token-auth

# Verify
flux check
kubectl get pods -n flux-system
```

### 14.4 Erste Anwendung via GitOps

```bash
# In deinem Repo, z.B. apps/my-app.yaml
cat > clusters/dev-test/apps/my-app.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-config
  namespace: default
data:
  message: "Hello from GitOps!"
EOF

# Git Push
git add .
git commit -m "Add my-app"
git push

# Flux wird das automatisch deployen (sync frequency ~10 Sekunden default)
kubectl get configmap
```

---

## 15. Troubleshooting & Verification

### 15.1 Cluster Health Check

```bash
# 1. Nodes Status
kubectl get nodes -o wide

# 2. Alle Pods (auch system)
kubectl get pods -A

# 3. System Pods Details
kubectl describe nodes k8s-cp1

# 4. etcd Status (nur auf CP Nodes)
sudo systemctl status etcd

# 5. API Server Logs
sudo journalctl -u kubelet -f

# 6. Network Connectivity Test
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Im Container:
# ping -c 3 kubernetes.default  # Should work
# nslookup kubernetes.default   # Should resolve
# exit
```

### 15.2 Component Health

```bash
# Control Plane Components
kubectl get componentstatuses

# Sollte zeigen:
# NAME                 STATUS   MESSAGE
# scheduler            Healthy  ok
# controller-manager   Healthy  ok
# etcd-0               Healthy  ok
```

### 15.3 Storage Check

```bash
# Storage Classes
kubectl get storageclasses

# Test PVC erstellen
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# PVC sollte Bound sein
kubectl get pvc

# Cleanup
kubectl delete pvc test-pvc
```

### 15.4 Load Balancer Test

```bash
# Test Service mit LoadBalancer
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: test-lb
spec:
  type: LoadBalancer
  selector:
    app: test
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 8080
EOF

# EXTERNAL-IP sollte von MetalLB sein
kubectl get svc test-lb

# Cleanup
kubectl delete service test-lb
kubectl delete deployment test-app
```

### 15.5 Ingress Test

```bash
# Test Ingress
kubectl apply -f - << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: test.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-lb
            port:
              number: 80
EOF

# Hosts-Datei anpassen (lokal auf Zugriffs-Rechner):
# 192.168.100.200 test.cluster.local

# Test
curl http://test.cluster.local

# Cleanup
kubectl delete ingress test-ingress
```

### 15.6 Häufige Fehler

| Problem | Diagnose | Lösung |
|---------|----------|--------|
| Nodes NotReady | `kubectl describe node <name>` | Flannel/CNI Plugin nicht aktiv |
| Pods Pending | `kubectl describe pod <pod>` | Storage/Resource nicht verfügbar |
| etcd Unhealthy | `sudo systemctl status etcd` | CP Node disk full oder network issue |
| API Server unreachable | `curl -k https://192.168.100.100:6443` | Load Balancer down oder Firewall |
| ImagePullBackOff | `kubectl describe pod <pod>` | Image nicht abrufbar, Registry credentials |

---

## Checkliste für Produktive Installation

- [ ] 3 Control Plane Nodes deployed und healthy
- [ ] 2+ Worker Nodes deployed und healthy
- [ ] Load Balancer (HAProxy) aktiv und getestet
- [ ] Flannel/CNI Plugin aktiv (alle Nodes Ready)
- [ ] Storage Class deployed und getestet
- [ ] MetalLB deployed und IPs vergeben
- [ ] Nginx Ingress Controller deployed
- [ ] Monitoring (Prometheus+Grafana) aktiv
- [ ] Logging (Loki+Promtail) aktiv
- [ ] Cert-Manager deployed
- [ ] Flux CD Bootstrap abgeschlossen
- [ ] GitHub Repo mit Cluster-Config verknüpft
- [ ] RBAC Policies konfiguriert
- [ ] Network Policies definiert
- [ ] Backup-Strategie (etcd + Velero) implementiert
- [ ] Disaster Recovery Test durchgeführt

---

## Nächste Schritte

1. **Teil 2 lesen:** Automatisierte Installation mit Ansible
2. **Teil 3 lesen:** GitOps & GitHub Integration erweitern
3. **SecurityHardening:** RBAC, Network Policies, Pod Security Standards
4. **Backup:** Velero für etcd/PV Backups installieren
5. **Scaling:** Auto-Scaling mit Cluster Autoscaler

---

**Fertig?** Kontrolliere mit der Checkliste und melde dich bei Issues!

