# Kubernetes Basis Kurs - Umfassende Zusammenfassung

## Inhaltsverzeichnis
0. [Container-Grundlagen](#0-container-grundlagen)
1. [Einführung in Kubernetes](#1-einführung-in-kubernetes)
2. [Setup & Grundkonfiguration](#2-setup--grundkonfiguration)
3. [Pods - Die kleinste Einheit](#3-pods---die-kleinste-einheit)
4. [Deployments & ReplicaSets](#4-deployments--replicasets)
5. [Services & Netzwerk](#5-services--netzwerk)
6. [Ingress Controller](#6-ingress-controller)
7. [Konfigurationsmanagement](#7-konfigurationsmanagement)
8. [Persistent Storage](#8-persistent-storage)
9. [StatefulSets](#9-statefulsets)
10. [Resource Management & Monitoring](#10-resource-management--monitoring)
11. [Health Checks & Probes](#11-health-checks--probes)
12. [Horizontal Pod Autoscaling (HPA)](#12-horizontal-pod-autoscaling-hpa)
13. [Jobs & CronJobs](#13-jobs--cronjobs)
14. [Praxisbeispiel: Nextcloud mit MariaDB](#14-praxisbeispiel-nextcloud-mit-mariadb)
15. [Backup & Restore](#15-backup--restore)
16. [kubectl Befehle - Cheat Sheet](#16-kubectl-befehle---cheat-sheet)
17. [Kubernetes Ressourcen - Vollständige Übersicht](#17-kubernetes-ressourcen---vollständige-übersicht)
18. [Best Practices](#18-best-practices)

---

## 0. Container-Grundlagen

### Evolution der Anwendungsbereitstellung

Die Art und Weise, wie wir Anwendungen bereitstellen, hat sich in den letzten Jahrzehnten grundlegend verändert:

```
┌────────────────────────────────────────────────────────────────────────┐
│                    Evolution: 1980 → 2005 → 2015                       │
└────────────────────────────────────────────────────────────────────────┘

1980er - Bare Metal                2005+ - Virtualisierung              2015+ - Container
┌─────────────────┐               ┌─────────────────┐                ┌─────────────────┐
│     APP1        │               │ ┌──────┐┌──────┐│                │ ┌────┐  ┌────┐  │
│                 │               │ │ APP1 ││ APP2 ││                │ │APP1│  │APP2│  │
│  ┌──────────┐   │               │ │  OS  ││  OS  ││                │ │Libs│  │Libs│  │
│  │Libraries │   │               │ │  HW  ││  HW  ││                │ │chro│  │    │  │
│  └──────────┘   │               │ └──────┘└──────┘│                │ │ot  │  │    │  │
│       OS        │     ═>        │  Hypervisor     │     ═>         │  Container Eng  │
│    Kernel       │               │    + VMM        │                │    OS Kernel    │
│       HW        │               │   OS Kernel     │                │       HW        │
└─────────────────┘               │       HW        │                └─────────────────┘
                                  └─────────────────┘
     Syscalls                      Syscalls                           Syscalls
```

### Containerisierung: Wie funktioniert es?

Container nutzen Linux **Kernel-Features** für Isolation:

**1. Namespaces** (Isolation)
- Jeder Container hat seine eigene isolierte Sicht auf das System
- **PID Namespace**: Eigene Prozess-IDs (Prozess 1 im Container)
- **Network Namespace**: Eigene Netzwerk-Interfaces und IP-Adressen
- **Mount Namespace**: Eigenes Dateisystem
- **UTS Namespace**: Eigener Hostname
- **IPC Namespace**: Isolierte Inter-Process Communication

**2. CGroups (Resource Management)**
- Begrenzt Ressourcen pro Container
- CPU, Memory, Disk I/O, Network
- Verhindert, dass ein Container alle Ressourcen verbraucht

**3. Secomp (System Call Filtering)**
- Kontrolliert, welche Syscalls Container machen dürfen
- Erhöht Sicherheit (z.B. verhindert Container-Breakout)

**4. SELinux / AppArmor (Mandatory Access Control)**
- Zusätzliche Sicherheitsebene
- Default bei Red Hat: SELinux

### Container vs. Virtuelle Maschinen

```
┌───────────────────────────────────────────────────────────────┐
│  Container                      Virtuelle Maschinen           │
├───────────────────────────────────────────────────────────────┤
│  ✅ Schneller Start (Sekunden)   ❌ Langsamer Start (Minuten)  │
│  ✅ Geringer Overhead             ❌ Hoher Overhead (Hypervisor)│
│  ✅ Teilen sich Kernel            ✅ Komplette Isolation        │
│  ❌ Weniger Isolation             ✅ Starke Isolation           │
│  ✅ Ideal für Microservices       ✅ Ideal für Legacy-Apps      │
└───────────────────────────────────────────────────────────────┘
```

### Container Registry

Container-Images werden in **Registries** gespeichert:

```
┌─────────────────────────────────────────────┐
│          Container Registry                 │
│                                             │
│  Öffentlich:                                │
│  • Docker Hub (hub.docker.com)              │
│  • Quay.io (Red Hat)                        │
│  • GitHub Container Registry                │
│                                             │
│  Privat:                                    │
│  • registry.redhat.io (Authentifizierung)   │
│  • Nexus / Harbor / Artifactory             │
│  • AWS ECR / Azure ACR / GCP GCR            │
└─────────────────────────────────────────────┘
```

**Pull-Befehl:**
```bash
# Von öffentlicher Registry
docker pull nginx:latest
podman pull quay.io/jfreygner/myhttpd:0.20

# Von privater Registry (mit Authentifizierung)
docker login registry.redhat.io
docker pull registry.redhat.io/rhel8/nginx:latest
```

### Kernel-Abhängigkeit und Portabilität

**Wichtig:** Container sind **abhängig von der Kernel-Architektur**:

```
┌──────────────────────────────────────────────────┐
│  Dependencies: Kernel & Architecture             │
├──────────────────────────────────────────────────┤
│                                                  │
│  ✅ Linux Container on Linux Host (same arch)    │
│  ✅ x64 Container on x64 Host                    │
│  ✅ ARM64 Container on ARM64 Host                │
│                                                  │
│  ❌ Linux Container on Windows Host              │
│     → Braucht WSL2 oder VM                      │
│  ❌ x64 Container on ARM64 Host                  │
│     → Emulation (langsam)                       │
└──────────────────────────────────────────────────┘
```

**Unterstützte Betriebssysteme (für Container Runtime):**
- **Linux**: Debian, Red Hat, SUSE, Ubuntu (native)
- **Windows**: Windows Server 2016+ (mit WSL2 für Linux-Container)
- **macOS**: Docker Desktop (nutzt VM im Hintergrund)

**Unterstützte Architekturen:**
- x64 (x86_64, amd64)
- ARM64 (aarch64) - z.B. Raspberry Pi, Apple Silicon
- ARM (32-bit)
- s390x (IBM Mainframe)

---

## 1. Einführung in Kubernetes

### Was ist Kubernetes?

Kubernetes (auch "K8s" genannt) ist eine Open-Source-Platform zur Automatisierung der Bereitstellung, Skalierung und Verwaltung von containerisierten Anwendungen. Es wurde ursprünglich von Google entwickelt und ist heute das führende Container-Orchestrierungssystem.

### Warum Orchestrierung?

**Problem ohne Orchestrierung:**
- Container manuell auf Servern verteilen
- Keine automatische Skalierung
- Kein Self-Healing bei Ausfällen
- Komplexes Netzwerk-Management
- Manuelle Updates und Rollbacks

**Lösung: Kubernetes-Orchestrierung**
- ✅ Automatische Container-Platzierung (Scheduler)
- ✅ Self-Healing (Neustart bei Abstürzen)
- ✅ Horizontal Scaling (mehr/weniger Replicas)
- ✅ Service Discovery und Load Balancing
- ✅ Rolling Updates und automatische Rollbacks
- ✅ Secret- und Configuration-Management

### Grundlegende Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Control Plane (Master)                  │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │   │
│  │  │   API    │  │   etcd   │  │   Scheduler      │  │   │
│  │  │  Server  │  │(Datenbank)│  │(Pod-Platzierung) │  │   │
│  │  └──────────┘  └──────────┘  └──────────────────┘  │   │
│  │  ┌───────────────────────────────────────────────┐  │   │
│  │  │       Controller Manager                      │  │   │
│  │  │  (überwacht Cluster-Zustand)                  │  │   │
│  │  └───────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            │                                │
│  ┌─────────────────────────┴───────────────────────────┐   │
│  │                  Worker Nodes                        │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │   │
│  │  │  Node 1      │  │  Node 2      │  │  Node 3   │ │   │
│  │  │  ┌────────┐  │  │  ┌────────┐  │  │ ┌──────┐  │ │   │
│  │  │  │ kubelet│  │  │  │ kubelet│  │  │ │kubelet│ │ │   │
│  │  │  └────────┘  │  │  └────────┘  │  │ └──────┘  │ │   │
│  │  │  ┌────────┐  │  │  ┌────────┐  │  │ ┌──────┐  │ │   │
│  │  │  │ Pods   │  │  │  │ Pods   │  │  │ │ Pods │  │ │   │
│  │  │  └────────┘  │  │  └────────┘  │  │ └──────┘  │ │   │
│  │  └──────────────┘  └──────────────┘  └───────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Control Plane (Master-Komponenten):**
- **API Server**: Zentraler Eintrittspunkt für alle Befehle (kubectl kommuniziert hierüber)
- **etcd**: Verteilte Datenbank für den Cluster-Zustand
- **Scheduler**: Entscheidet, auf welchem Node ein Pod laufen soll
- **Controller Manager**: Überwacht den Cluster und stellt sicher, dass der gewünschte Zustand erreicht wird

**Worker Nodes:**
- **kubelet**: Agent auf jedem Node, der Container startet und überwacht
- **Container Runtime**: Software zum Ausführen von Containern (z.B. containerd, Docker)
- **kube-proxy**: Netzwerk-Proxy für Service-Kommunikation

### Wichtige Konzepte

**Cluster**: Eine Sammlung von Nodes (Servern), die von Kubernetes verwaltet werden.

**Namespace**: Logische Trennung innerhalb eines Clusters. Nützlich für verschiedene Teams, Projekte oder Umgebungen (dev/test/prod).

**Context**: Kombination aus Cluster, User und Namespace. Definiert, mit welchem Cluster und Namespace kubectl arbeitet.

### Erweiterte Cluster-Architektur

**High-Availability (HA) Setup:**

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Workstation / Client                         │
│  ┌────────┐                                                          │
│  │  APP1  │    CLI (kubectl), GUI, SDK                              │
│  └────────┘                                                          │
└─────────────────────────┬────────────────────────────────────────────┘
                          │
            ┌─────────────┼─────────────┬─────────────┐
            ↓             ↓             ↓             ↓
┌──────────────────────────────────────────────────────────────────────┐
│               Master Nodes / Control Plane (HA)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │              │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │              │
│  │ │   ETCD   │←┼──┼→│   ETCD   │←┼──┼→│   ETCD   │ │ (sync)       │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │              │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │              │
│  │ │API-Server│ │  │ │API-Server│ │  │ │API-Server│ │              │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │              │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │              │
│  │ │Controller│ │  │ │Controller│ │  │ │Controller│ │              │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │              │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │              │
│  │ │Scheduler │ │  │ │Scheduler │ │  │ │Scheduler │ │              │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │              │
│  │  kubelet     │  │  kubelet     │  │  kubelet     │              │
│  │Container Eng.│  │Container Eng.│  │Container Eng.│              │
│  │      OS      │  │      OS      │  │      OS      │              │
│  │      HW      │  │      HW      │  │      HW      │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
└──────────────────────────────────────────────────────────────────────┘
                          │
            ┌─────────────┼─────────────┬─────────────┐
            ↓             ↓             ↓             ↓
┌──────────────────────────────────────────────────────────────────────┐
│         Worker Nodes / Compute Plane (Development/Production)        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │    ...       │
│  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │              │
│  │  │  APP1  │  │  │  │  APP1  │  │  │  │  APP1  │  │              │
│  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │              │
│  │  kubelet     │  │  kubelet     │  │  kubelet     │              │
│  │Container Eng.│  │Container Eng.│  │Container Eng.│              │
│  │      OS      │  │      OS      │  │      OS      │              │
│  │      HW      │  │      HW      │  │      HW      │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
└──────────────────────────────────────────────────────────────────────┘
```

**ETCD Quorum-Berechnung:**
```
Quorum = (expected_votes / 2) + 1 (round down)

Beispiel mit 3 Master Nodes:
Quorum = (3 / 2) + 1 = 2

→ Mindestens 2 von 3 Nodes müssen funktionieren
→ 1 Node kann ausfallen, Cluster bleibt funktional
```

**Wichtig für HA:**
- **Immer ungerade Anzahl** Master Nodes (3, 5, 7)
- Niemals 2 Master Nodes! (kein Quorum bei 1 Ausfall)
- 3 Nodes = optimales HA-Setup (1 Ausfall tolerierbar)
- 5 Nodes = 2 Ausfälle tolerierbar (nur für kritische Cluster)

### Kubernetes-Distributionen und Extensions

**Kubernetes Vanilla vs. Managed Distributions:**

```
┌───────────────────────────────────────────────────────────────┐
│                  Kubernetes-Distributionen                    │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  Vanilla Kubernetes (Upstream)                               │
│  • kubernetes.io                                             │
│  • Basis für alle anderen Distributionen                     │
│  • Installation: kubeadm, kubespray, kube-up                 │
│                                                               │
│  Enterprise-Distributionen (On-Premise/Hybrid):              │
│  • OpenShift (Red Hat) - Kubernetes + Developer-Tools        │
│  • Tanzu (VMware) - VMware-Integration                       │
│  • Rancher (SUSE) - Multi-Cluster Management                 │
│                                                               │
│  Managed Cloud-Services:                                     │
│  • AKS (Azure Kubernetes Service)                            │
│  • EKS (Amazon Elastic Kubernetes Service)                   │
│  • GKE (Google Kubernetes Engine)                            │
│  • OKE (Oracle Container Engine for Kubernetes)              │
│                                                               │
│  Lightweight/Edge:                                           │
│  • K3s (Rancher) - Minimal Kubernetes für IoT/Edge          │
│  • MicroK8s (Canonical) - Single-Node Kubernetes             │
│  • Kind (Kubernetes in Docker) - Lokale Entwicklung          │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**Kubernetes Extensions (Cluster-Erweiterungen):**

```
┌────────────────────────────────────────────────────────────────┐
│                    Kubernetes Extensions                       │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Networking:                                                   │
│  • SDN (Software Defined Network) - Flannel, Calico, Cilium   │
│  • Ingress Controller - Nginx, Traefik, HAProxy, Istio       │
│  • Service Mesh - Istio, Linkerd, Consul                     │
│                                                                │
│  Storage:                                                      │
│  • CSI (Container Storage Interface) Drivers                  │
│  • Rook (Cloud-Native Storage Orchestrator)                   │
│  • Longhorn (Rancher) - Distributed Block Storage            │
│                                                                │
│  Security & Access:                                           │
│  • Authentication - OIDC, LDAP, Active Directory             │
│  • RBAC (Role-Based Access Control) - Built-in              │
│  • Network Policies - Calico, Cilium                         │
│  • Pod Security Policies / Pod Security Standards            │
│                                                                │
│  Observability:                                               │
│  • Metrics - Prometheus, Datadog, New Relic                  │
│  • Logging - Fluentd, Loki, ELK Stack                        │
│  • Tracing - Jaeger, Zipkin                                  │
│  • Dashboards - Grafana, Kubernetes Dashboard                │
│                                                                │
│  CI/CD & GitOps:                                              │
│  • ArgoCD, Flux CD - GitOps Deployment                       │
│  • Tekton - Cloud-Native CI/CD Pipelines                     │
│  • Jenkins X - Kubernetes-Native Jenkins                     │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. Setup & Grundkonfiguration

### kubectl Installation & Tab-Completion

kubectl ist das Kommandozeilen-Tool für die Interaktion mit Kubernetes.

**Tab-Completion für Bash einrichten (erhöht Produktivität massiv):**

```bash
# Completion-Script generieren und speichern
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl

# Sofort aktivieren
source /etc/bash_completion.d/kubectl
```

**Was bringt Tab-Completion?**
- Befehle automatisch vervollständigen (z.B. `kubectl get po<TAB>` → `kubectl get pods`)
- Ressourcen-Namen vervollständigen (z.B. `kubectl delete pod myhttp<TAB>` → `kubectl delete pod myhttpd-xxx`)
- Optionen anzeigen (z.B. `kubectl get --<TAB><TAB>` zeigt alle Optionen)

### Kubernetes Cluster Verbindung

**Konfigurationsdatei:** `~/.kube/config`

Diese Datei enthält:
- Cluster-Informationen (API-Server-Adressen, Zertifikate)
- User-Credentials (Authentifizierung)
- Contexts (Kombination aus Cluster + User + Namespace)

**Wichtige Konfigurations-Befehle:**

```bash
# Cluster-Informationen anzeigen
kubectl config get-contexts      # Alle verfügbaren Contexts
kubectl config get-clusters      # Alle Cluster
kubectl config get-users         # Alle User

# Context wechseln (z.B. zwischen verschiedenen Clustern)
kubectl config use-context docker-desktop

# Namespace für aktuellen Context setzen (wichtig für Arbeit!)
kubectl config set-context docker-desktop --namespace mein-namespace
```

**Was sind API-Ressourcen?**

```bash
# Alle verfügbaren Ressourcen-Typen anzeigen
kubectl api-resources

# Nur Namespace-spezifische Ressourcen
kubectl api-resources --namespaced=true

# Erklärung zu einer Ressource
kubectl explain pod
kubectl explain deployment
```

### Namespaces erstellen und verwalten

Namespaces sind wie "virtuelle Cluster" innerhalb eines Clusters.

```bash
# Namespace erstellen
kubectl create namespace rma-myfirst

# Alle Namespaces anzeigen
kubectl get namespaces

# Aktuellen Context auf neuen Namespace setzen
kubectl config set-context docker-desktop --namespace rma-myfirst

# Aktuellen Context prüfen (zeigt auch Namespace)
kubectl config get-contexts
```

**Warum Namespaces?**
- **Isolation**: Ressourcen verschiedener Teams trennen
- **Quotas**: Ressourcen-Limits pro Namespace setzen
- **Organisation**: Verschiedene Umgebungen (dev/test/prod) trennen

---

## 3. Pods - Die kleinste Einheit

### Was ist ein Pod?

Ein **Pod** ist die kleinste deploybare Einheit in Kubernetes. Ein Pod kann einen oder mehrere Container enthalten, die sich:
- Denselben Netzwerk-Namespace teilen (gleiche IP-Adresse)
- Denselben Storage teilen können
- Immer auf demselben Node laufen

```
┌─────────────────────────────────┐
│           Pod                   │
│  ┌──────────┐    ┌──────────┐  │
│  │Container │    │Container │  │
│  │    A     │    │    B     │  │
│  └──────────┘    └──────────┘  │
│                                 │
│  Gemeinsame IP: 10.244.0.5     │
│  Gemeinsame Volumes            │
└─────────────────────────────────┘
```

### Pod erstellen

**Imperative Methode (schnell für Tests):**

```bash
# Pod erstellen mit Image
kubectl run myhttpd --image quay.io/jfreygner/myhttpd:0.20

# Pod-Status prüfen
kubectl get pods
kubectl get pods -o wide  # Mit zusätzlichen Infos (IP, Node)

# Alle Ressourcen anzeigen
kubectl get all
```

### Pod-Lifecycle und Verhalten

**Pod ist NICHT dauerhaft:**
- Wenn ein Pod gelöscht wird, ist er unwiederbringlich verloren
- Kubernetes startet keinen neuen Pod automatisch (dafür braucht man Deployments)

```bash
# In Pod einloggen
kubectl exec -it myhttpd -- bash

# Prozess 1 im Container killen (Container stirbt)
# Im Pod:
kill 1

# Pod wird neu gestartet (RESTARTS-Zähler erhöht sich)
kubectl get pods
```

**Pod löschen:**

```bash
kubectl delete pod myhttpd

# Pod ist komplett weg - kein automatischer Neustart!
kubectl get pods  # Liste ist leer
```

### Mit Pods arbeiten

```bash
# Logs eines Pods anzeigen
kubectl logs myhttpd
kubectl logs myhttpd -f  # Follow (Echtzeit)

# Befehl im Pod ausführen
kubectl exec myhttpd -- ls -l
kubectl exec myhttpd -- cat /etc/httpd/conf/httpd.conf

# Interaktive Shell
kubectl exec -it myhttpd -- bash

# Pod-Details anzeigen
kubectl describe pod myhttpd
```

**Wichtig:** Pods sind für direkte Verwendung nicht ideal. In der Praxis verwendet man **Deployments**!

---

## 4. Deployments & ReplicaSets

### Warum Deployments?

Deployments lösen die Probleme von einzelnen Pods:
- ✅ **Self-Healing**: Pod stirbt → neuer Pod wird automatisch erstellt
- ✅ **Skalierung**: Mehrere Replicas für Hochverfügbarkeit
- ✅ **Updates**: Rolling Updates ohne Downtime
- ✅ **Rollback**: Zurück zur vorherigen Version bei Problemen

### Architektur: Deployment → ReplicaSet → Pods

```
┌─────────────────────────────────────────────────────┐
│              Deployment (myhttpd)                   │
│  Deklariert: "Ich will 3 Replicas von myhttpd"     │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ erstellt/verwaltet
                   ↓
┌─────────────────────────────────────────────────────┐
│           ReplicaSet (myhttpd-6448bcc8d8)          │
│  Stellt sicher: Immer genau 3 Pods laufen         │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ erstellt/überwacht
                   ↓
      ┌────────────┴────────────┬────────────┐
      ↓                         ↓            ↓
┌──────────┐             ┌──────────┐   ┌──────────┐
│  Pod 1   │             │  Pod 2   │   │  Pod 3   │
│ (Running)│             │ (Running)│   │ (Running)│
└──────────┘             └──────────┘   └──────────┘
```

### Deployment erstellen

```bash
# Deployment erstellen (nicht nur Pod!)
kubectl create deployment myhttpd --image quay.io/jfreygner/myhttpd:0.20

# Status prüfen
kubectl get all
# OUTPUT zeigt:
# - Pod(s)
# - Deployment
# - ReplicaSet
```

### Skalierung

```bash
# Auf 3 Replicas skalieren
kubectl scale deployment myhttpd --replicas 3

# Prüfen
kubectl get pods
# Jetzt laufen 3 Pods mit unterschiedlichen Namen:
# myhttpd-6448bcc8d8-abc12
# myhttpd-6448bcc8d8-def34
# myhttpd-6448bcc8d8-ghi56
```

### Self-Healing testen

```bash
# Einen Pod löschen
kubectl delete pod myhttpd-6448bcc8d8-abc12

# Sofort nochmal prüfen
kubectl get pods
# Kubernetes erstellt AUTOMATISCH einen neuen Pod!
# Anzahl bleibt bei 3 (wie im Deployment definiert)
```

### Deployment bearbeiten

**Methode 1: Imperativ (schnelle Änderungen)**

```bash
# Image-Version ändern
kubectl set image deployment/myhttpd myhttpd=quay.io/jfreygner/myhttpd:0.20

# Environment-Variable setzen
kubectl set env deployment/myhttpd MY_VAR=value
```

**Methode 2: Deklarativ (empfohlen für Produktion)**

```bash
# Deployment in Editor öffnen (vi/nano)
kubectl edit deployment myhttpd

# YAML direkt bearbeiten und speichern
# Kubernetes wendet Änderungen automatisch an
```

### Rollout-Strategien

Kubernetes unterstützt **Rolling Updates** (Standard):
- Alte Pods werden schrittweise durch neue ersetzt
- Keine Downtime!

```bash
# Rollout-Historie anzeigen
kubectl rollout history deployment myhttpd

# Einzelne Revision anzeigen
kubectl rollout history deployment myhttpd --revision 1

# Zu vorheriger Version zurückkehren
kubectl rollout undo deployment myhttpd

# Zu spezifischer Revision zurückkehren
kubectl rollout undo deployment myhttpd --to-revision 1
```

---

## 5. Services & Netzwerk

### Das Problem: Pod-IPs sind nicht stabil

Pods bekommen dynamische IP-Adressen, die sich bei jedem Neustart ändern können. **Services** lösen dieses Problem, indem sie eine stabile Netzwerk-Endpoint bereitstellen.

### Service-Typen

```
┌──────────────────────────────────────────────────────┐
│  Service-Typen in Kubernetes                         │
├──────────────────────────────────────────────────────┤
│                                                      │
│  1. ClusterIP (Standard)                            │
│     - Nur innerhalb des Clusters erreichbar         │
│     - Für interne Kommunikation (z.B. DB)          │
│                                                      │
│  2. NodePort                                        │
│     - Von außen über Node-IP:Port erreichbar       │
│     - Port-Range: 30000-32767                      │
│                                                      │
│  3. LoadBalancer                                    │
│     - Externe IP-Adresse (Cloud-Provider)          │
│     - Automatische Load-Balancer Erstellung        │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Service erstellen (ClusterIP)

```bash
# Service für Deployment erstellen
kubectl expose deployment myhttpd --port 8080

# Service anzeigen
kubectl get service
# OUTPUT:
# NAME      TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
# myhttpd   ClusterIP   10.111.186.178   <none>        8080/TCP   1m

# Service-Details
kubectl describe service myhttpd
```

**Was macht dieser Service?**
- Erstellt stabile IP-Adresse (ClusterIP: 10.111.186.178)
- Alle Anfragen an diese IP werden auf die Pods verteilt (Load Balancing)
- Verwendet **Selectors** (Labels), um passende Pods zu finden

### Endpoints verstehen

```bash
# Endpoints zeigen die echten Pod-IPs
kubectl describe endpoints myhttpd
# OUTPUT:
# Endpoints: 10.1.0.11:8080,10.1.0.12:8080,10.1.0.13:8080
#            ↑ Das sind die IPs der 3 Pods!
```

```
┌─────────────────────────────────────────────────┐
│            Service (myhttpd)                    │
│        ClusterIP: 10.111.186.178:8080          │
└────────────────┬────────────────────────────────┘
                 │
                 │ Load Balancing
                 │
     ┌───────────┼───────────┬─────────────┐
     ↓           ↓           ↓             ↓
┌─────────┐ ┌─────────┐ ┌─────────┐
│ Pod 1   │ │ Pod 2   │ │ Pod 3   │
│10.1.0.11│ │10.1.0.12│ │10.1.0.13│
└─────────┘ └─────────┘ └─────────┘
```

### Service-Typen ändern

**Auf NodePort ändern (für externen Zugriff):**

```bash
# Service editieren
kubectl edit service myhttpd

# Ändere:
type: ClusterIP
# zu:
type: NodePort

# Prüfen
kubectl get service
# OUTPUT:
# NAME      TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
# myhttpd   NodePort   10.111.186.178   <none>        8080:31142/TCP   5m
#                                                            ↑
#                                                      Externer Port!
```

**Zugriff von außen:**
```bash
# Service ist erreichbar über:
curl http://<NODE-IP>:31142
# z.B.: curl http://192.168.100.10:31142
```

### Port-Forwarding für lokale Entwicklung

Für schnelles Testing ohne NodePort/Ingress:

```bash
# Port-Forwarding im Hintergrund starten
kubectl port-forward service/myhttpd 8080:8080 &

# Jetzt lokal erreichbar
curl http://localhost:8080
```

---

## 6. Ingress Controller

### Was ist Ingress?

**Problem mit Services:**
- NodePort: Unschöne Ports (30000+), keine Domain-Namen
- LoadBalancer: Jeder Service braucht eigene externe IP (teuer!)

**Lösung: Ingress**
- HTTP/HTTPS Routing basierend auf Hostnamen und Pfaden
- Eine einzige externe IP für viele Services
- SSL/TLS Terminierung

```
                    Internet
                       │
                       ↓
        ┌──────────────────────────────┐
        │      Ingress Controller      │
        │     (Nginx, Traefik, ...)    │
        │     IP: 192.168.100.200      │
        └──────────────┬───────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    Host: www.app1.local | www.app2.local
         │             │             │
         ↓             ↓             ↓
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │Service 1│   │Service 2│   │Service 3│
   └─────────┘   └─────────┘   └─────────┘
```

### Ingress Controller installieren

**Nginx Ingress Controller deployen:**

```bash
# Namespace für Ingress erstellen
mkdir -p setup/ingress
cd setup/ingress/

# Manifest herunterladen (oder aus Kurs-Materialien)
# deploy.yaml enthält alle benötigten Komponenten

# Installieren
kubectl create -f deploy.yaml

# Prüfen
kubectl get ingressclasses.networking.k8s.io
# OUTPUT:
# NAME    CONTROLLER             PARAMETERS   AGE
# nginx   k8s.io/ingress-nginx   <none>       1m

# Alle Komponenten im Namespace anzeigen
kubectl get all -n ingress-nginx
```

### Ingress Regel erstellen

```bash
# Ingress für myhttpd Service erstellen
kubectl create ingress myhttpd \
  --class nginx \
  --rule "www.myfirst.local/*=myhttpd:8080"

# Ingress anzeigen
kubectl get ingress
# OUTPUT:
# NAME      CLASS   HOSTS               ADDRESS   PORTS   AGE
# myhttpd   nginx   www.myfirst.local             80      10s
```

**Was passiert hier?**
- Alle Anfragen an `www.myfirst.local` werden an Service `myhttpd` Port `8080` weitergeleitet
- `/*` bedeutet: Alle Pfade unter dieser Domain

### Lokales Testing konfigurieren

Da `www.myfirst.local` keine echte Domain ist:

```bash
# IP-Adresse des Clusters herausfinden
ip a s

# /etc/hosts editieren
echo "172.22.84.207 www.myfirst.local" | sudo tee -a /etc/hosts

# Testen
curl www.myfirst.local
# OUTPUT: Inhalt der Webseite!
```

### Ingress für mehrere Services

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-service-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: app1.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80
  - host: app2.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 8080
```

---

## 7. Konfigurationsmanagement

### ConfigMaps - Konfigurationsdateien extern verwalten

**Problem:** Konfigurationsdateien sind im Container-Image fest eingebrannt. Änderungen erfordern neues Image.

**Lösung: ConfigMap**
- Konfiguration außerhalb des Containers speichern
- Als Datei oder Environment-Variable in Pods einbinden
- Änderungen ohne Image-Rebuild

#### ConfigMap erstellen

**Aus Datei:**

```bash
# Config-Datei aus Pod extrahieren
kubectl exec myhttpd-746766bc85-2b2k9 -- cat /etc/httpd/conf/httpd.conf > httpd.conf

# In Editor anpassen (z.B. Logging auf stderr/stdout umleiten)
code httpd.conf

# ConfigMap erstellen
kubectl create configmap myhttpd --from-file httpd.conf

# ConfigMap anzeigen
kubectl get configmaps
kubectl describe configmap myhttpd
```

#### ConfigMap in Pod einbinden

**Als Volume Mount (für Konfigurationsdateien):**

Hier verwenden wir das **oc** Tool (OpenShift Client) für erweiterte Funktionalität:

```bash
# oc Tool installieren (falls nicht vorhanden)
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.19.19/openshift-client-linux-4.19.19.tar.gz
sudo tar xf openshift-client-linux-4.19.19.tar.gz -C /usr/local/bin oc

# Tab-Completion
oc completion bash | sudo tee /etc/bash_completion.d/oc
source /etc/bash_completion.d/oc
```

**ConfigMap als Volume in Deployment einbinden:**

```bash
# ConfigMap als Datei mounten
oc set volumes deployment myhttpd \
  --add \
  --name myhttpd-conf \
  -t configmap \
  --configmap-name myhttpd \
  --mount-path /etc/httpd/conf/httpd.conf \
  --sub-path httpd.conf

# Kubernetes erstellt automatisch neue Pods mit der neuen Konfiguration!
kubectl get pods
```

**Was passiert hier?**
- `--add`: Fügt ein Volume hinzu
- `-t configmap`: Volume-Typ ist ConfigMap
- `--mount-path`: Wo die Datei im Container erscheinen soll
- `--sub-path`: Nur eine spezifische Datei aus der ConfigMap mounten (nicht ganzen Ordner überschreiben!)

#### ConfigMap aktualisieren

```bash
# Konfigurationsdatei lokal ändern
code httpd.conf

# ConfigMap aktualisieren
oc set data configmap myhttpd --from-file httpd.conf

# Pods neu starten (für manche Anwendungen notwendig)
kubectl rollout restart deployment myhttpd
```

### Secrets - Sensible Daten sicher speichern

**Secrets** sind wie ConfigMaps, aber für sensible Daten (Passwörter, API-Keys, Zertifikate).

**Wichtig:** Secrets sind Base64-kodiert, aber NICHT verschlüsselt! In Produktion zusätzliche Verschlüsselung verwenden.

#### Secret erstellen

```bash
# Namespace erstellen für MariaDB
kubectl create namespace rma-mariadb
kubectl config set-context docker-desktop --namespace rma-mariadb

# Passwort sicher eingeben (wird nicht im History gespeichert)
read -s -p 'Passwort: '

# Secret erstellen
kubectl create secret generic mymaria \
  --from-literal MARIADB_ROOT_PASSWORD=$REPLY

# Secret anzeigen (Werte sind Base64-kodiert)
kubectl get secrets
kubectl get secret mymaria -o yaml
```

#### Secret in Deployment verwenden

**Methode 1: Alle Secrets als Environment-Variablen:**

```bash
# Deployment erstellen
kubectl create deployment mymariadb --image docker.io/library/mariadb

# Alle Keys aus Secret als Env-Vars injizieren
kubectl set env deployment mymariadb --from secret/mymaria

# Prüfen
kubectl describe deployment mymariadb
```

**Methode 2: Einzelne Keys aus Secret:**

```bash
# Deployment mit kubectl edit bearbeiten
kubectl edit deployment mymariadb
```

```yaml
# Im Editor hinzufügen:
spec:
  template:
    spec:
      containers:
      - name: mariadb
        image: docker.io/library/mariadb
        env:
        - name: MARIADB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mymaria
              key: MARIADB_ROOT_PASSWORD
```

#### Secret testen

```bash
# In Container prüfen
kubectl exec mymariadb-fc666d67f-x9tcb -- env | grep MARIA
# OUTPUT:
# MARIADB_ROOT_PASSWORD=MeinGeheimesPasswort
```

### ServiceAccounts & Image Pull Secrets

**Problem:** Private Container-Registries erfordern Authentifizierung.

**Lösung: Image Pull Secret**

```bash
# Secret für Registry erstellen
kubectl create secret docker-registry redhat-registry \
  --docker-server registry.redhat.io \
  --docker-username rma \
  --docker-password $REPLY

# ServiceAccount mit Secret verknüpfen
oc secrets link default redhat-registry --for pull

# Prüfen
kubectl get serviceaccounts default -o yaml
# Secret wird automatisch für alle Pods in diesem Namespace verwendet!
```

**ServiceAccount-Struktur:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
imagePullSecrets:
- name: redhat-registry  # ← Wird automatisch hinzugefügt
```

---

## 8. Persistent Storage

### Das Problem: Container sind ephemeral

Container und Pods können jederzeit neu erstellt werden. Alle Daten im Container-Dateisystem gehen dabei verloren!

**Lösung: Persistent Volumes (PV) und Persistent Volume Claims (PVC)**

### Storage-Konzepte

```
┌─────────────────────────────────────────────────────┐
│            Storage-Hierarchie                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. StorageClass                                   │
│     - Definiert Storage-Typ (z.B. SSD, HDD)       │
│     - Automatische PV-Provisionierung             │
│                                                     │
│  2. PersistentVolume (PV)                         │
│     - Tatsächlicher Storage (Admin erstellt)      │
│     - Oder: Automatisch von StorageClass erstellt│
│                                                     │
│  3. PersistentVolumeClaim (PVC)                   │
│     - Anfrage für Storage (User erstellt)         │
│     - "Ich brauche 5GB Storage"                   │
│                                                     │
│  4. Pod                                           │
│     - Verwendet PVC als Volume                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Access Modes

```
┌────────────────────────────────────────────────┐
│  Access Modes (Zugriffsmodi)                  │
├────────────────────────────────────────────────┤
│                                                │
│  RWO (ReadWriteOnce)                          │
│  - Nur von EINEM Node les- und schreibbar     │
│  - Ideal für Datenbanken                      │
│                                                │
│  RWM (ReadWriteMany)                          │
│  - Von MEHREREN Nodes les- und schreibbar     │
│  - Ideal für geteilte Dateien                 │
│                                                │
│  ROX (ReadOnlyMany)                           │
│  - Von mehreren Nodes nur lesbar              │
│  - Ideal für statische Inhalte                │
│                                                │
└────────────────────────────────────────────────┘
```

### StorageClass prüfen

```bash
# Verfügbare StorageClasses anzeigen
oc get sc
# oder
kubectl get storageclasses

# OUTPUT (Beispiel):
# NAME                     PROVISIONER          RECLAIMPOLICY
# local-path (default)     rancher.io/local-path   Delete
```

### PVC erstellen und mounten

**Mit oc Tool (einfachste Methode):**

```bash
# Namespace wechseln
kubectl config set-context docker-desktop --namespace rma-myfirst

# PVC erstellen und direkt in Deployment mounten
oc set volumes deployment myhttpd \
  --add \
  --name myhttpd-data \
  -t pvc \
  --claim-size 5G \
  --claim-name myhttpd \
  --claim-mode rwm \
  --mount-path /var/www/html

# PVC und Pods prüfen
kubectl get pvc
# OUTPUT:
# NAME      STATUS   VOLUME             CAPACITY   ACCESS MODES
# myhttpd   Bound    pvc-abc123-def456  5Gi        RWX

kubectl get pods
```

**Was passiert hier?**
1. PVC wird automatisch erstellt (5GB, ReadWriteMany)
2. StorageClass erstellt automatisch PV
3. Deployment wird aktualisiert (neue Pods mit Volume)
4. Volume wird unter `/var/www/html` gemountet

### Persistenz testen

```bash
# Datei in PVC schreiben
kubectl exec -it myhttpd-846bd886d4-89wz2 -- bash
echo "test persistent volume" > /var/www/html/test.txt
exit

# Alle Pods löschen (simuliert Absturz)
kubectl scale deployment myhttpd --replicas 0
kubectl get pods  # Keine Pods mehr

# Pods wieder starten
kubectl scale deployment myhttpd --replicas 3

# Datei ist noch da!
curl www.myfirst.local/test.txt
# OUTPUT: test persistent volume
```

### PersistentVolume Reclaim Policy

```bash
# PV anzeigen
kubectl get pv

# OUTPUT:
# NAME              CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS
# pvc-abc123-def456 5Gi        RWX            Delete           Bound
```

**Reclaim Policies:**
- **Delete** (Standard): PV wird gelöscht, wenn PVC gelöscht wird → **Datenverlust!**
- **Retain**: PV bleibt erhalten → Daten bleiben erhalten

**Wichtig für Produktion:** Reclaim Policy auf `Retain` setzen!

```bash
# PV editieren
kubectl edit pv pvc-abc123-def456

# Ändern:
persistentVolumeReclaimPolicy: Retain
```

---

## 9. StatefulSets

### Wann StatefulSets statt Deployments?

**Deployments** sind ideal für:
- Stateless Anwendungen (Webserver, APIs)
- Pods sind austauschbar
- Keine feste Identität notwendig

**StatefulSets** sind notwendig für:
- ✅ **Datenbanken** (MySQL, PostgreSQL, MongoDB)
- ✅ Anwendungen mit fester Identität (z.B. Kafka, ZooKeeper)
- ✅ Jeder Pod braucht eigenen persistenten Storage
- ✅ Feste Netzwerk-Identität (Pod-Namen ändern sich nicht)

### Unterschiede: Deployment vs. StatefulSet

```
┌─────────────────────────────────────────────────────────┐
│            Deployment                                    │
├─────────────────────────────────────────────────────────┤
│  Pod-Namen: myapp-6d7f8c9b-abc12 (zufällig)            │
│  Reihenfolge: Parallel gestartet                        │
│  Storage: Ein PVC für alle Pods                         │
│  Identität: Keine                                       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│            StatefulSet                                   │
├─────────────────────────────────────────────────────────┤
│  Pod-Namen: mydb-0, mydb-1, mydb-2 (vorhersagbar)      │
│  Reihenfolge: Sequentiell gestartet (0→1→2)           │
│  Storage: Jeder Pod hat eigenen PVC                     │
│  Identität: Fest (mydb-0 bleibt immer mydb-0)         │
└─────────────────────────────────────────────────────────┘
```

### StatefulSet erstellen

**Beispiel: MariaDB mit StatefulSet**

```bash
# Namespace vorbereiten
kubectl config set-context docker-desktop --namespace rma-mariadb

# Bestehendes Deployment als Basis exportieren
kubectl get deployment mymariadb -o yaml > mydb-deploy.yaml

# Kopie für StatefulSet erstellen
cp mydb-deploy.yaml mydb-statefulset.yaml

# Editieren
code mydb-statefulset.yaml
```

**mydb-statefulset.yaml:**

```yaml
apiVersion: apps/v1
kind: StatefulSet  # ← Geändert von Deployment!
metadata:
  labels:
    app: mymariadb
  name: mymariadb
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mymariadb
  template:
    metadata:
      labels:
        app: mymariadb
    spec:
      containers:
      - env:
        - name: MARIADB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              key: MARIADB_ROOT_PASSWORD
              name: mymaria
        image: docker.io/library/mariadb
        name: mariadb
        volumeMounts:
        - mountPath: /var/lib/mysql
          name: rma-mariadb-data
  # ↓ NEU: volumeClaimTemplates (jeder Pod bekommt eigenen PVC!)
  volumeClaimTemplates:
  - metadata:
      name: rma-mariadb-data
    spec:
      accessModes: [ "ReadWriteOnce" ]  # RWO für Datenbanken!
      resources:
        requests:
          storage: 5Gi
```

**Deployen:**

```bash
# Altes Deployment löschen
kubectl delete deployment mymariadb

# StatefulSet erstellen
kubectl create -f mydb-statefulset.yaml

# Prüfen
kubectl get pods,pvc
# OUTPUT:
# NAME           READY   STATUS    RESTARTS   AGE
# pod/mymariadb-0   1/1     Running   0          30s
# pod/mymariadb-1   1/1     Running   0          25s
#
# NAME                                       STATUS   VOLUME
# persistentvolumeclaim/rma-mariadb-data-mymariadb-0   Bound    pvc-abc...
# persistentvolumeclaim/rma-mariadb-data-mymariadb-1   Bound    pvc-def...
```

**Wichtige Beobachtungen:**
- Pod-Namen sind vorhersagbar: `mymariadb-0`, `mymariadb-1`
- Jeder Pod hat eigenen PVC: `rma-mariadb-data-mymariadb-0`
- Pods starten sequentiell (0 zuerst, dann 1)

### StatefulSet Verhalten

**Pod löschen:**

```bash
# Pod 0 löschen
kubectl delete pod mymariadb-0

# Neuer Pod wird mit GLEICHEM Namen erstellt
kubectl get pods
# OUTPUT:
# NAME           READY   STATUS    RESTARTS   AGE
# mymariadb-0    1/1     Running   0          5s   ← Gleicher Name!
# mymariadb-1    1/1     Running   0          2m
```

**Daten bleiben erhalten:**
- Der neue `mymariadb-0` verwendet denselben PVC wie vorher
- Alle Datenbank-Daten sind noch da!

---

## 10. Resource Management & Monitoring

### Warum Resource Management?

Ohne Limits:
- Ein Pod kann alle Ressourcen eines Nodes verbrauchen
- Andere Pods verhungern (CPU) oder werden beendet (Memory)
- Cluster wird instabil

Mit Limits:
- ✅ Faire Ressourcen-Verteilung
- ✅ Vorhersagbares Verhalten
- ✅ Schutz vor "Noisy Neighbors"

### Metrics Server installieren

Der **Metrics Server** sammelt CPU- und Memory-Daten von allen Nodes und Pods.

```bash
# Metrics Server Manifest installieren
mkdir -p setup/metrics
cd setup/metrics/
cp /pfad/zu/components-insecure-tls.yaml .

kubectl create -f components-insecure-tls.yaml

# Warten bis Pod läuft (dauert ~30 Sekunden)
kubectl get pods -n kube-system | grep metrics-server
```

**Ressourcen-Verbrauch anzeigen:**

```bash
# Node-Ressourcen
kubectl top node
# OUTPUT:
# NAME             CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# docker-desktop   500m         12%    2048Mi          25%

# Pod-Ressourcen
kubectl top pods
# OUTPUT:
# NAME                       CPU(cores)   MEMORY(bytes)
# myhttpd-86658f4b46-abc12   10m          50Mi
# myhttpd-86658f4b46-def34   8m           48Mi

# Alle Pods mit Summe
kubectl top pods --sum
```

### Resource Requests und Limits

```
┌─────────────────────────────────────────────────┐
│  Requests vs. Limits                            │
├─────────────────────────────────────────────────┤
│                                                 │
│  Requests (Garantie):                          │
│  - Mindestmenge, die Pod GARANTIERT bekommt   │
│  - Scheduler platziert Pod nur auf Node mit    │
│    genügend freien Ressourcen                  │
│                                                 │
│  Limits (Maximum):                             │
│  - Maximale Menge, die Pod nutzen darf        │
│  - CPU: Pod wird gedrosselt (throttled)       │
│  - Memory: Pod wird beendet (OOMKilled)       │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Mit oc Tool setzen:**

```bash
# Requests und Limits für Deployment setzen
oc set resources deployment/myhttpd \
  --limits cpu=500m,memory=200Mi \
  --requests cpu=100m,memory=50Mi

# Prüfen
kubectl describe pod myhttpd-xxx | grep -A5 -i limits
# OUTPUT:
#     Limits:
#       cpu:     500m
#       memory:  200Mi
#     Requests:
#       cpu:        100m
#       memory:     50Mi
```

**CPU-Einheiten:**
- `1` = 1 CPU-Core
- `500m` = 0.5 CPU-Core (m = Milli)
- `100m` = 0.1 CPU-Core

**Memory-Einheiten:**
- `100Mi` = 100 Mebibyte
- `1Gi` = 1 Gibibyte

### Resource Quotas (Namespace-Level)

Quotas begrenzen die **gesamten** Ressourcen in einem Namespace.

```bash
# Quota erstellen
kubectl create quota myhttpd \
  --hard limits.cpu=5,requests.cpu=3,limits.memory=5Gi,requests.memory=1Gi,pods=10

# Quota anzeigen
kubectl describe resourcequotas myhttpd
# OUTPUT:
# Name:            myhttpd
# Namespace:       rma-myfirst
# Resource         Used   Hard
# --------         ----   ----
# limits.cpu       1500m  5
# limits.memory    600Mi  5Gi
# pods             3      10
# requests.cpu     300m   3
# requests.memory  150Mi  1Gi
```

**Was bedeutet das?**
- Maximal 10 Pods in diesem Namespace
- Insgesamt maximal 5 CPU-Cores (Limits) und 3 CPU-Cores (Requests)
- Insgesamt maximal 5Gi Memory (Limits) und 1Gi Memory (Requests)

**Wichtig:** Wenn Quota aktiv ist, **MÜSSEN** alle Pods Requests/Limits definieren!

### OOMScore und Linux Out-of-Memory Killer

```bash
# Node-Details anzeigen (zeigt Ressourcen-Druck)
kubectl describe node docker-desktop

# In Linux: OOM Score eines Prozesses prüfen
# (Niedrigerer Score = wichtiger, wird zuletzt gekilled)
cat /proc/<PID>/oom_score
```

---

## 11. Health Checks & Probes

### Warum Health Checks?

**Ohne Probes:**
- Kubernetes weiß nur: Container läuft (Prozess existiert)
- Container kann "tot" sein (Deadlock, keine Antwort), aber Prozess läuft
- Traffic wird weiterhin an kaputten Container geschickt

**Mit Probes:**
- ✅ Kubernetes erkennt kaputte Container und startet sie neu
- ✅ Traffic wird nur an gesunde Container geschickt
- ✅ Rolling Updates warten, bis neue Container bereit sind

### Probe-Typen

```
┌─────────────────────────────────────────────────────┐
│            Health Probe Typen                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. Liveness Probe                                 │
│     - Frage: "Ist der Container noch am Leben?"   │
│     - Aktion: Container neu starten bei Fehler    │
│     - Beispiel: HTTP GET /healthz → 200 OK        │
│                                                     │
│  2. Readiness Probe                                │
│     - Frage: "Ist der Container bereit für Traffic?"│
│     - Aktion: Aus Service-Endpoints entfernen     │
│     - Beispiel: HTTP GET / → 200 OK               │
│                                                     │
│  3. Startup Probe (optional)                       │
│     - Für langsam startende Container             │
│     - Andere Probes warten auf Startup Probe      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Probe-Mechanismen

```yaml
# HTTP GET (am häufigsten)
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10  # Warte 10s nach Start
  periodSeconds: 5         # Prüfe alle 5 Sekunden

# TCP Socket
livenessProbe:
  tcpSocket:
    port: 3306
  initialDelaySeconds: 15

# Command (Exit Code 0 = gesund)
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
  initialDelaySeconds: 5
```

### Readiness Probe setzen

```bash
# Readiness Probe für HTTP-Server
oc set probe deployment/myhttpd \
  --readiness \
  --get-url=http://:8080/index.html \
  --initial-delay-seconds 5

# Prüfen
kubectl describe deployment myhttpd
# Zeigt: Readiness: http-get http://:8080/index.html

# Pods beobachten
kubectl get pods -w
```

**Was passiert?**
- Neue Pods werden erstellt
- Pod-Status: `Running` aber `READY 0/1` (noch nicht bereit)
- Nach 5 Sekunden: HTTP GET auf `/index.html`
- Wenn 200 OK: Pod wird `READY 1/1` und bekommt Traffic

### Liveness Probe setzen

```bash
# Liveness Probe hinzufügen
oc set probe deployment/myhttpd \
  --liveness \
  --get-url=http://:8080/index.html

# Pods beobachten
kubectl get pods -w
```

**Liveness Probe testen:**

```bash
# In Container einloggen
kubectl exec -it myhttpd-d85f48795-2l2sb -- bash

# index.html löschen (simuliert Fehler)
rm /var/www/html/index.html

# Nach draußen wechseln und Pods beobachten
kubectl get pods -w
# OUTPUT:
# NAME                       READY   STATUS    RESTARTS   AGE
# myhttpd-d85f48795-2l2sb    1/1     Running   0          2m
# myhttpd-d85f48795-2l2sb    0/1     Running   1          2m   ← Container neu gestartet!
```

**Was ist passiert?**
1. Liveness Probe prüft `/index.html`
2. HTTP GET gibt 404 zurück (Datei fehlt)
3. Kubernetes startet Container neu (RESTARTS-Zähler erhöht sich)
4. Container-Entrypoint erstellt `index.html` neu
5. Probe wird wieder grün

### Probes optimal konfigurieren

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5    # Warte 5s nach Container-Start
  periodSeconds: 10         # Prüfe alle 10 Sekunden
  timeoutSeconds: 2         # Timeout nach 2 Sekunden
  successThreshold: 1       # 1x Erfolg = bereit
  failureThreshold: 3       # 3x Fehler = nicht bereit

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30   # Mehr Zeit für Startup!
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3       # 3x Fehler = Container neu starten
```

**Best Practices:**
- Liveness `initialDelaySeconds` höher als Readiness (Container muss erst starten)
- `failureThreshold` ≥ 3 (nicht sofort neu starten bei kurzem Problem)
- Unterschiedliche Endpoints für Liveness und Readiness

---

## 12. Horizontal Pod Autoscaling (HPA)

### Was ist Autoscaling?

**Horizontal Pod Autoscaler (HPA)** passt automatisch die Anzahl der Pod-Replicas basierend auf CPU-Auslastung (oder anderen Metriken) an.

```
        Niedrige Last              Hohe Last
┌──────────────────────┐   ┌──────────────────────┐
│   Deployment         │   │   Deployment         │
│   ┌────┐  ┌────┐    │   │   ┌────┐  ┌────┐    │
│   │Pod │  │Pod │    │   │   │Pod │  │Pod │    │
│   └────┘  └────┘    │   │   └────┘  └────┘    │
│   2 Replicas        │   │   ┌────┐  ┌────┐    │
│                      │   │   │Pod │  │Pod │    │
│   CPU: 20%          │   │   └────┘  └────┘    │
│                      │   │   ┌────┐  ┌────┐    │
└──────────────────────┘   │   │Pod │  │Pod │    │
                           │   └────┘  └────┘    │
                           │   6 Replicas        │
                           │   CPU: 85%          │
                           └──────────────────────┘
```

### HPA erstellen

**Voraussetzungen:**
- Metrics Server muss laufen
- Pods müssen CPU **Requests** definiert haben (HPA berechnet % basierend auf Request!)

```bash
# HPA erstellen
kubectl autoscale deployment myhttpd \
  --cpu-percent 80 \
  --min 2 \
  --max 10

# HPA anzeigen
kubectl get hpa
# OUTPUT:
# NAME      REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
# myhttpd   Deployment/myhttpd   15%/80%   2         10        2          1m
#                                ↑
#                         Aktuelle/Ziel CPU-Auslastung
```

**Was bedeutet das?**
- Minimum: 2 Pods (auch bei niedriger Last)
- Maximum: 10 Pods (auch bei sehr hoher Last)
- Ziel: CPU-Auslastung bei 80% halten
- Wenn aktuelle Auslastung > 80%: Mehr Pods erstellen
- Wenn aktuelle Auslastung < 80%: Pods abbauen

### HPA-Formel

```
Gewünschte Replicas = ceil(Aktuelle Replicas × (Aktuelle Metrik / Ziel Metrik))

Beispiel:
- Aktuelle Replicas: 2
- CPU Request pro Pod: 100m
- Aktuelle CPU-Nutzung pro Pod: 120m (= 120% von Request)
- Ziel: 80%

Gewünschte Replicas = ceil(2 × (120% / 80%)) = ceil(2 × 1.5) = 3

→ HPA erstellt 1 zusätzlichen Pod
```

### Autoscaling testen

**Last erzeugen:**

```bash
# In Pod einloggen
kubectl exec -it myhttpd-d85f48795-4rzrs -- bash

# CPU-Last erzeugen (md5sum berechnet endlos Hashes)
md5sum /dev/zero &
md5sum /dev/zero &
md5sum /dev/zero &

# Im Hintergrund laufen lassen und raus
exit
```

**Autoscaling beobachten:**

```bash
# CPU-Auslastung beobachten
kubectl top pods
# OUTPUT:
# NAME                       CPU(cores)   MEMORY(bytes)
# myhttpd-d85f48795-4rzrs    450m         55Mi   ← CPU hoch!

# HPA Status
kubectl get hpa
# OUTPUT:
# NAME      REFERENCE            TARGETS    MINPODS   MAXPODS   REPLICAS
# myhttpd   Deployment/myhttpd   450%/80%   2         10        2
#                                ↑ CPU stark über Ziel!

# Nach ~1 Minute: Neue Pods werden erstellt
kubectl get pods -w
# OUTPUT:
# myhttpd-d85f48795-4rzrs    1/1     Running   0          5m
# myhttpd-d85f48795-new1     0/1     Pending   0          1s   ← Neue Pods!
# myhttpd-d85f48795-new2     0/1     Pending   0          1s
```

**Last beenden:**

```bash
# Überlasteten Pod löschen (Last verschwindet)
kubectl delete pod myhttpd-d85f48795-4rzrs

# HPA skaliert nach ~5 Minuten wieder runter
kubectl get hpa -w
```

**Wichtig:** HPA reagiert nicht sofort!
- Scale-Up: Nach ~1 Minute bei hoher Last
- Scale-Down: Nach ~5 Minuten bei niedriger Last (konservativ, um "Flapping" zu vermeiden)

---

## 13. Jobs & CronJobs

### Jobs - Einmalige Tasks

**Job** vs. **Deployment:**
- Deployment: Läuft dauerhaft (Webserver)
- Job: Läuft einmal bis Completion (Batch-Job, Datenbank-Migration)

```
Deployment:                 Job:
┌──────────┐               ┌──────────┐
│  Start   │               │  Start   │
│    ↓     │               │    ↓     │
│  Running │ ← dauerhaft   │  Running │
│    ↓     │               │    ↓     │
│  (Crash) │               │ Complete │ ← endet!
│    ↓     │               └──────────┘
│ Restart  │
└──────────┘
```

### Job erstellen

```bash
# FALSCH: Pod ohne Restart-Policy
kubectl run mydate --image quay.io/jfreygner/mydate:0.2
# → Pod läuft, beendet sich, startet neu, beendet sich, ... (CrashLoopBackOff)

# RICHTIG: Job
kubectl create job mydate --image quay.io/jfreygner/mydate:0.2

# Prüfen
kubectl get pods,jobs
# OUTPUT:
# NAME              READY   STATUS      RESTARTS   AGE
# pod/mydate-abc12  0/1     Completed   0          30s
#
# NAME              COMPLETIONS   DURATION   AGE
# job.batch/mydate  1/1           5s         30s
```

**Job-Verhalten:**
- Pod startet
- Container führt Befehl aus
- Container beendet sich (Exit Code 0)
- Pod-Status wird `Completed`
- Pod wird NICHT neu gestartet
- Job zeigt: `COMPLETIONS 1/1` (1 von 1 erfolgreich)

### CronJobs - Geplante Aufgaben

**CronJob** = Job, der nach einem Zeitplan wiederholt ausgeführt wird (wie Linux Cron).

```bash
# CronJob erstellen (läuft jede 2. Minute, Mo-Fr, 8-16 Uhr)
kubectl create cronjob mydate \
  --image quay.io/jfreygner/mydate:0.2 \
  --schedule '*/2 8-16 * * 1-5'

# Prüfen
kubectl get cronjobs.batch
# OUTPUT:
# NAME     SCHEDULE              SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# mydate   */2 8-16 * * 1-5      False     0        <none>          10s

# Nach 2 Minuten: Job und Pod werden erstellt
kubectl get cronjobs.batch,jobs.batch,pods
# OUTPUT:
# NAME                     SCHEDULE              SUSPEND   ACTIVE
# cronjob.batch/mydate     */2 8-16 * * 1-5      False     1
#
# NAME                        COMPLETIONS   DURATION
# job.batch/mydate-28392840   1/1           3s
#
# NAME                          READY   STATUS      RESTARTS
# pod/mydate-28392840-abc12     0/1     Completed   0
```

### Cron-Syntax verstehen

```
*/2 8-16 * * 1-5
│   │    │ │ │
│   │    │ │ └─ Wochentag (1-5 = Mo-Fr)
│   │    │ └─── Monat (1-12)
│   │    └───── Tag des Monats (1-31)
│   └────────── Stunde (8-16 = 8:00-16:59 Uhr)
└────────────── Minute (*/2 = alle 2 Minuten)
```

**Beispiele:**
- `0 0 * * *` - Täglich um Mitternacht
- `*/15 * * * *` - Alle 15 Minuten
- `0 9 * * 1` - Jeden Montag um 9:00 Uhr
- `0 0 1 * *` - Am 1. Tag jedes Monats um Mitternacht

**CronJob-Optionen:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mydate
spec:
  schedule: "*/2 8-16 * * 1-5"
  successfulJobsHistoryLimit: 3  # Behalte 3 erfolgreiche Jobs
  failedJobsHistoryLimit: 1      # Behalte 1 fehlgeschlagenen Job
  concurrencyPolicy: Forbid      # Erlaube keine parallelen Runs
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mydate
            image: quay.io/jfreygner/mydate:0.2
          restartPolicy: OnFailure
```

---

## 14. Praxisbeispiel: Nextcloud mit MariaDB

Dieses Beispiel zeigt eine **vollständige Multi-Container-Anwendung** mit allen gelernten Konzepten.

### Architektur

```
                      Internet
                         │
                         ↓
        ┌────────────────────────────────┐
        │   Ingress (nginx)              │
        │   nextcloud.myfirst.local      │
        └────────────┬───────────────────┘
                     │
                     ↓
        ┌────────────────────────────────┐
        │   Service: nextcloud           │
        │   Port: 80                     │
        └────────────┬───────────────────┘
                     │
                     ↓
        ┌────────────────────────────────┐
        │   Deployment: nextcloud        │
        │   Image: nextcloud:32.0.2      │
        │   ┌──────────────────────────┐ │
        │   │ PVC: nextcloud (5Gi)     │ │
        │   │ Mount: /var/www/html     │ │
        │   └──────────────────────────┘ │
        └────────────┬───────────────────┘
                     │
                     │ Datenbankverbindung
                     ↓
        ┌────────────────────────────────┐
        │   Service: mariadb             │
        │   Port: 3306                   │
        └────────────┬───────────────────┘
                     │
                     ↓
        ┌────────────────────────────────┐
        │   Deployment: mariadb          │
        │   Image: mariadb:10.6          │
        │   ┌──────────────────────────┐ │
        │   │ PVC: mariadb (5Gi)       │ │
        │   │ Mount: /var/lib/mysql    │ │
        │   └──────────────────────────┘ │
        │   ┌──────────────────────────┐ │
        │   │ Secret: DB-Credentials   │ │
        │   └──────────────────────────┘ │
        └────────────────────────────────┘
```

### Schritt-für-Schritt Deployment

#### 1. Namespace und Secret

```bash
# Namespace erstellen
kubectl create namespace rma-nextcloud
kubectl config set-context docker-desktop --namespace rma-nextcloud

# Passwort sicher eingeben
read -s -p 'Passwort: '

# Secret mit allen benötigten Variablen
kubectl create secret generic nextcloud \
  --from-literal MYSQL_ROOT_PASSWORD=$REPLY \
  --from-literal MYSQL_PASSWORD=$REPLY \
  --from-literal MYSQL_DATABASE=nextcloud \
  --from-literal MYSQL_USER=nextcloud \
  --from-literal MYSQL_HOST=mariadb
```

#### 2. MariaDB deployen

```bash
# Deployment erstellen
kubectl create deployment mariadb --image docker.io/library/mariadb:10.6

# Environment-Variablen aus Secret
kubectl set env deployment mariadb --from secret/nextcloud

# Persistent Volume hinzufügen
oc set volumes deployment mariadb \
  --add \
  --name mariadb-data \
  -t pvc \
  --claim-name mariadb \
  --claim-size 5Gi \
  --claim-mode rwo \
  --mount-path /var/lib/mysql

# Warten bis Pod läuft
kubectl get pods -w

# Service erstellen (intern, nur von Nextcloud erreichbar)
kubectl expose deployment mariadb --port 3306
```

#### 3. Nextcloud deployen

```bash
# Deployment erstellen
kubectl create deployment nextcloud \
  --image docker.io/library/nextcloud:32.0.2-apache

# Environment-Variablen (Verbindung zu MariaDB)
kubectl set env deployment nextcloud --from secret/nextcloud

# Persistent Volume für Nextcloud-Daten
oc set volumes deployment nextcloud \
  --add \
  --name nextcloud-data \
  -t pvc \
  --claim-name nextcloud \
  --claim-size 5Gi \
  --claim-mode rwm \
  --mount-path /var/www/html

# Service erstellen (für Ingress)
kubectl expose deployment nextcloud --port 80
```

#### 4. Ingress konfigurieren

```bash
# Ingress erstellen
kubectl create ingress nextcloud \
  --class nginx \
  --rule "nextcloud.myfirst.local/*=nextcloud:80"

# Alles prüfen
kubectl get pods,pvc,svc,ingress
```

#### 5. DNS und Zugriff

```bash
# Cluster-IP herausfinden
ip a s

# /etc/hosts editieren
echo "172.22.84.207 nextcloud.myfirst.local" | sudo tee -a /etc/hosts

# Zugriff testen
curl nextcloud.myfirst.local
# oder im Browser: http://nextcloud.myfirst.local
```

### Was passiert bei der Installation?

1. **Nextcloud-Pod startet:**
   - Nextcloud-Container lädt Daten auf `/var/www/html` (PVC)
   - Verbindung zu MariaDB über Service `mariadb:3306`
   - Verwendet Environment-Variablen aus Secret

2. **MariaDB-Pod startet:**
   - MariaDB initialisiert Datenbank auf `/var/lib/mysql` (PVC)
   - Erstellt Datenbank `nextcloud`
   - Erstellt User `nextcloud` mit Passwort aus Secret

3. **Ingress routet Traffic:**
   - Browser → `nextcloud.myfirst.local`
   - Ingress Controller → Service `nextcloud:80`
   - Service → Nextcloud-Pods

### Vollständige Ressourcen-Übersicht

```bash
kubectl get all,pvc,secrets,ingress
```

**OUTPUT:**
```
# Pods
pod/mariadb-xxx     1/1  Running
pod/nextcloud-xxx   1/1  Running

# Services
service/mariadb     ClusterIP  10.96.x.x    <none>  3306/TCP
service/nextcloud   ClusterIP  10.96.x.x    <none>  80/TCP

# Deployments
deployment.apps/mariadb     1/1  1  1
deployment.apps/nextcloud   1/1  1  1

# PVCs
persistentvolumeclaim/mariadb    Bound  pvc-xxx  5Gi  RWO
persistentvolumeclaim/nextcloud  Bound  pvc-xxx  5Gi  RWX

# Secrets
secret/nextcloud  Opaque  5

# Ingress
ingress.networking.k8s.io/nextcloud  nginx  nextcloud.myfirst.local
```

### Optionale Komponenten (Production-Ready Setup)

**1. ResourceQuota hinzufügen**

Begrenzt Ressourcen im Namespace:

```bash
# ResourceQuota erstellen
kubectl create quota nextcloud-quota \
  --hard=limits.cpu=4,limits.memory=8Gi,requests.cpu=2,requests.memory=4Gi,pods=10,persistentvolumeclaims=5

# Prüfen
kubectl describe resourcequota nextcloud-quota
```

**2. LimitRange hinzufügen**

Setzt Standard-Werte für Container:

```yaml
# limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: nextcloud-limits
spec:
  limits:
  - max:
      cpu: "2"
      memory: "2Gi"
    min:
      cpu: "100m"
      memory: "128Mi"
    default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "200m"
      memory: "256Mi"
    type: Container
```

```bash
kubectl create -f limitrange.yaml
```

**3. Horizontal Pod Autoscaler (HPA) für Nextcloud**

Automatisches Scaling basierend auf Last:

```bash
# Erst: CPU Requests für Nextcloud setzen (wichtig für HPA!)
oc set resources deployment/nextcloud \
  --limits=cpu=1,memory=1Gi \
  --requests=cpu=200m,memory=512Mi

# HPA erstellen
kubectl autoscale deployment nextcloud \
  --cpu-percent=70 \
  --min=2 \
  --max=5

# Prüfen
kubectl get hpa
```

**4. NetworkPolicy für Sicherheit**

Erlaubt nur notwendigen Traffic:

```yaml
# networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mariadb-netpol
spec:
  podSelector:
    matchLabels:
      app: mariadb
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: nextcloud
    ports:
    - protocol: TCP
      port: 3306

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: nextcloud-netpol
spec:
  podSelector:
    matchLabels:
      app: nextcloud
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 80
```

```bash
kubectl create -f networkpolicy.yaml
```

**5. Probes für Nextcloud und MariaDB**

```bash
# Readiness Probe für Nextcloud
oc set probe deployment/nextcloud \
  --readiness \
  --get-url=http://:80/status.php \
  --initial-delay-seconds=30 \
  --period-seconds=10

# Liveness Probe für Nextcloud
oc set probe deployment/nextcloud \
  --liveness \
  --get-url=http://:80/status.php \
  --initial-delay-seconds=60 \
  --period-seconds=30

# TCP Probe für MariaDB
oc set probe deployment/mariadb \
  --readiness \
  --open-tcp=3306 \
  --initial-delay-seconds=10

oc set probe deployment/mariadb \
  --liveness \
  --open-tcp=3306 \
  --initial-delay-seconds=30
```

### Vollständige Deployment-Checkliste

```
┌──────────────────────────────────────────────────────────┐
│    Nextcloud Production Deployment - Checkliste          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ✅ 1x Namespace (rma-nextcloud)                         │
│  ✅ 1x Secret (DB-Credentials)                           │
│  ✅ 1x Deployment (MariaDB mit StatefulSet-Option)       │
│  ✅ 1x Deployment (Nextcloud)                            │
│  ✅ 2x PVC (mariadb, nextcloud)                          │
│  ✅ 2x Service (mariadb: ClusterIP, nextcloud: ClusterIP)│
│  ✅ 1x Ingress (nextcloud)                               │
│                                                          │
│  Optional (Production):                                  │
│  ⬜ ResourceQuota (Namespace-Limits)                     │
│  ⬜ LimitRange (Default-Werte)                           │
│  ⬜ HPA (Auto-Scaling für Nextcloud)                     │
│  ⬜ NetworkPolicy (Firewall-Regeln)                      │
│  ⬜ Health Probes (Liveness/Readiness)                   │
│  ⬜ Backup-CronJob (regelmäßige Backups)                 │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 15. Backup & Restore

### Warum Backups?

- Disaster Recovery (Cluster-Ausfall)
- Migrationen (anderer Cluster, andere Umgebung)
- Versionierung (Änderungen nachvollziehen)
- GitOps (Deklarative Konfiguration in Git)

### Ressourcen exportieren

**Einzelne Ressource:**

```bash
# Service als YAML exportieren
kubectl get service mymariadb -o yaml > mymariadb.yaml
```

**Mehrere Ressourcen zusammen:**

```bash
# Alle Ressourcen einer Anwendung
kubectl get deployment,service,configmap,pvc myhttpd -o yaml > myhttpd-backup.yaml

# Mit Ingress, HPA, etc.
kubectl get cm,deploy,service,ingress,pvc,hpa myhttpd -o yaml > myhttpd-complete.yaml
```

### YAML-Dateien bereinigen

Exportierte YAMLs enthalten viele automatisch generierte Felder, die für Restore nicht benötigt werden (und Probleme verursachen können).

**Zu entfernen/bereinigen:**

```yaml
metadata:
  name: myhttpd          # ✅ Behalten
  namespace: rma-myfirst # ✅ Behalten
  labels:                # ✅ Behalten
    app: myhttpd
  # ❌ LÖSCHEN:
  creationTimestamp: "2025-01-15T10:30:00Z"
  uid: abc-def-ghi
  resourceVersion: "123456"
  generation: 2
  managedFields: [...]
  selfLink: /api/v1/...

spec:
  clusterIP: 10.96.50.100  # ❌ LÖSCHEN (wird automatisch vergeben)
  clusterIPs:              # ❌ LÖSCHEN
  - 10.96.50.100

status:                    # ❌ GANZEN BLOCK LÖSCHEN
  conditions: [...]
  loadBalancer: {}
```

**Ingress: Hostname entfernen**

```yaml
# Vor Bereinigung:
status:
  loadBalancer:
    ingress:
    - hostname: xxx.example.com  # ❌ LÖSCHEN

# Nach Bereinigung:
# status-Block komplett entfernt
```

**PVC: volumeName entfernen**

```yaml
# Vor Bereinigung:
spec:
  volumeName: pvc-abc-123-def  # ❌ LÖSCHEN

# Nach Bereinigung:
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  # volumeName entfernt!
```

### Restore durchführen

**Aus Backup wiederherstellen:**

```bash
# Alte Ressourcen löschen (optional)
kubectl delete -f myhttpd-backup.yaml

# Aus Backup wiederherstellen
kubectl create -f myhttpd-backup.yaml

# Prüfen
kubectl get all
```

**Mehrere Dateien gleichzeitig:**

```bash
# Alle YAML-Dateien in einem Verzeichnis
kubectl create -f ./backup-directory/

# Rekursiv (inkl. Unterordner)
kubectl create -f ./backup-directory/ -R
```

### Deklarativ vs. Imperativ

```
┌─────────────────────────────────────────────────────┐
│  Imperativ vs. Deklarativ                           │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Imperativ (Ad-hoc):                               │
│  - Befehle wie: kubectl create, scale, set        │
│  - Schnell für Entwicklung/Testing                │
│  - Schwer nachvollziehbar (keine Historie)        │
│  - Nicht reproduzierbar                           │
│                                                     │
│  Deklarativ (GitOps):                             │
│  - Alles in YAML-Dateien                          │
│  - kubectl apply -f file.yaml                     │
│  - Versioniert in Git                             │
│  - Reproduzierbar und auditierbar                 │
│  - ✅ Best Practice für Produktion!              │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Best Practice Workflow:**

```bash
# 1. Ressourcen deklarativ erstellen
kubectl apply -f deployment.yaml

# 2. Bei Änderungen: YAML editieren (nicht kubectl edit!)
vim deployment.yaml

# 3. Änderungen anwenden
kubectl apply -f deployment.yaml

# 4. In Git committen
git add deployment.yaml
git commit -m "Update deployment: increase replicas to 5"
git push
```

---

## 16. kubectl Befehle - Cheat Sheet

### Cluster & Kontext

```bash
# Cluster-Informationen
kubectl cluster-info
kubectl version

# Contexts verwalten
kubectl config get-contexts           # Alle Contexts
kubectl config current-context        # Aktueller Context
kubectl config use-context <context>  # Context wechseln
kubectl config set-context <context> --namespace <ns>  # Namespace setzen

# API-Ressourcen
kubectl api-resources                      # Alle Ressourcen-Typen
kubectl api-resources --namespaced=true    # Nur Namespace-spezifisch
kubectl explain <resource>                 # Ressource erklären (z.B. pod)
```

### Namespace

```bash
kubectl get namespaces                # Alle Namespaces
kubectl create namespace <name>       # Namespace erstellen
kubectl delete namespace <name>       # Namespace löschen
kubectl config set-context --current --namespace <name>  # Standard-Namespace setzen
```

### Pods

```bash
# Erstellen
kubectl run <name> --image <image>           # Pod erstellen (nicht empfohlen)

# Anzeigen
kubectl get pods                              # Pods im aktuellen Namespace
kubectl get pods -A                           # Alle Namespaces
kubectl get pods -o wide                      # Mit zusätzlichen Infos (IP, Node)
kubectl get pods --show-labels                # Mit Labels
kubectl get pods -w                           # Watch (Echtzeit-Updates)

# Details
kubectl describe pod <pod-name>               # Detaillierte Infos
kubectl logs <pod-name>                       # Logs anzeigen
kubectl logs <pod-name> -f                    # Logs folgen (Echtzeit)
kubectl logs <pod-name> --previous            # Logs des vorherigen Containers

# Interaktion
kubectl exec <pod-name> -- <command>          # Befehl ausführen
kubectl exec -it <pod-name> -- bash           # Interaktive Shell
kubectl port-forward <pod-name> 8080:80       # Port-Forwarding

# Löschen
kubectl delete pod <pod-name>                 # Pod löschen
kubectl delete pod --all                      # Alle Pods löschen
```

### Deployments

```bash
# Erstellen
kubectl create deployment <name> --image <image>  # Deployment erstellen

# Anzeigen
kubectl get deployments                       # Deployments anzeigen
kubectl describe deployment <name>            # Details

# Skalieren
kubectl scale deployment <name> --replicas 3  # Auf 3 Replicas skalieren

# Image aktualisieren
kubectl set image deployment/<name> <container>=<image>

# Editieren
kubectl edit deployment <name>                # Im Editor öffnen

# Rollout
kubectl rollout status deployment <name>      # Rollout-Status
kubectl rollout history deployment <name>     # Historie anzeigen
kubectl rollout undo deployment <name>        # Rollback
kubectl rollout restart deployment <name>     # Pods neu starten

# Löschen
kubectl delete deployment <name>
```

### Services

```bash
# Erstellen
kubectl expose deployment <name> --port 8080  # Service erstellen
kubectl expose deployment <name> --port 80 --type NodePort

# Anzeigen
kubectl get services                          # Services anzeigen
kubectl get svc                               # Kurzform
kubectl describe service <name>               # Details
kubectl get endpoints <name>                  # Endpoints (Pod-IPs)

# Editieren
kubectl edit service <name>

# Löschen
kubectl delete service <name>
```

### Ingress

```bash
# Erstellen
kubectl create ingress <name> --class nginx --rule "host.com/*=service:80"

# Anzeigen
kubectl get ingress                           # Alle Ingress
kubectl get ingressclasses.networking.k8s.io  # Ingress Classes
kubectl describe ingress <name>               # Details

# Löschen
kubectl delete ingress <name>
```

### ConfigMaps & Secrets

```bash
# ConfigMap
kubectl create configmap <name> --from-file <file>
kubectl create configmap <name> --from-literal KEY=value
kubectl get configmaps
kubectl describe configmap <name>
kubectl get configmap <name> -o yaml

# Secret
kubectl create secret generic <name> --from-literal KEY=value
kubectl create secret docker-registry <name> \
  --docker-server <server> \
  --docker-username <user> \
  --docker-password <pass>
kubectl get secrets
kubectl describe secret <name>
kubectl get secret <name> -o yaml

# Löschen
kubectl delete configmap <name>
kubectl delete secret <name>
```

### Persistent Storage

```bash
# PVC
kubectl get pvc                               # PersistentVolumeClaims
kubectl describe pvc <name>
kubectl delete pvc <name>

# PV
kubectl get pv                                # PersistentVolumes
kubectl describe pv <name>

# StorageClasses
kubectl get storageclasses
kubectl get sc                                # Kurzform
```

### Resource Management

```bash
# Monitoring
kubectl top nodes                             # Node-Ressourcen
kubectl top pods                              # Pod-Ressourcen
kubectl top pods --sum                        # Mit Summe

# Limits & Requests setzen (mit oc)
oc set resources deployment/<name> \
  --limits cpu=500m,memory=200Mi \
  --requests cpu=100m,memory=50Mi

# Quotas
kubectl create quota <name> --hard limits.cpu=5,pods=10
kubectl get resourcequotas
kubectl describe resourcequota <name>
```

### Autoscaling

```bash
# HPA erstellen
kubectl autoscale deployment <name> --cpu-percent 80 --min 2 --max 10

# Anzeigen
kubectl get hpa
kubectl describe hpa <name>

# Löschen
kubectl delete hpa <name>
```

### Jobs & CronJobs

```bash
# Job
kubectl create job <name> --image <image>
kubectl get jobs
kubectl describe job <name>
kubectl delete job <name>

# CronJob
kubectl create cronjob <name> --image <image> --schedule "*/5 * * * *"
kubectl get cronjobs
kubectl describe cronjob <name>
kubectl delete cronjob <name>
```

### Probes (mit oc)

```bash
# Readiness Probe
oc set probe deployment/<name> --readiness --get-url=http://:8080/

# Liveness Probe
oc set probe deployment/<name> --liveness --get-url=http://:8080/healthz

# Probe entfernen
oc set probe deployment/<name> --remove --readiness
```

### Volumes (mit oc)

```bash
# Volume hinzufügen (ConfigMap)
oc set volumes deployment/<name> \
  --add --name <vol-name> -t configmap \
  --configmap-name <cm-name> \
  --mount-path /path

# Volume hinzufügen (PVC)
oc set volumes deployment/<name> \
  --add --name <vol-name> -t pvc \
  --claim-name <pvc-name> \
  --claim-size 5Gi \
  --mount-path /path

# Volumes anzeigen
oc set volumes deployment/<name>
```

### Environment-Variablen

```bash
# Env-Var setzen
kubectl set env deployment/<name> KEY=value

# Aus Secret/ConfigMap
kubectl set env deployment/<name> --from secret/<name>
kubectl set env deployment/<name> --from configmap/<name>

# Env-Vars anzeigen
kubectl set env deployment/<name> --list
```

### Debugging & Troubleshooting

```bash
# Events anzeigen
kubectl get events                            # Alle Events
kubectl get events --sort-by=.lastTimestamp   # Sortiert
kubectl get events -w                         # Watch

# Logs
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>   # Spezifischer Container
kubectl logs -l app=myapp --all-containers    # Alle Pods mit Label

# Node-Details
kubectl describe node <node-name>
kubectl get nodes -o wide

# Ressourcen-Details
kubectl describe <resource> <name>
kubectl get <resource> <name> -o yaml         # Als YAML
kubectl get <resource> <name> -o json         # Als JSON

# Verbosity erhöhen (Debugging)
kubectl -v=8 get pods                         # Verbose-Level 0-10
```

### Backup & Restore

```bash
# Exportieren
kubectl get <resource> <name> -o yaml > backup.yaml
kubectl get all -o yaml > all-resources.yaml

# Importieren (Imperativ - nur für neue Ressourcen)
kubectl create -f backup.yaml

# Apply (Deklarativ - erstellt ODER aktualisiert)
kubectl apply -f backup.yaml

# Mehrere Dateien
kubectl create -f ./directory/                # Alle YAML-Dateien
kubectl apply -f ./directory/ -R              # Rekursiv

# Unterschied zwischen create und apply anzeigen
kubectl diff -f deployment.yaml               # Zeigt Änderungen vor Apply
```

### Deklaratives Management (apply, replace, diff)

```bash
# Apply: Empfohlene Methode (erstellt oder aktualisiert)
kubectl apply -f deployment.yaml
kubectl apply -f ./manifests/ -R

# Unterschiede vor Apply anzeigen
kubectl diff -f deployment.yaml

# Replace: Ersetzt komplette Ressource (gefährlich!)
kubectl replace -f deployment.yaml
kubectl replace -f deployment.yaml --force   # Löscht und erstellt neu

# Kustomize (Built-in ab kubectl 1.14)
kubectl apply -k ./kustomization/
```

**Unterschied create vs. apply:**
```
┌─────────────────────────────────────────────────────────┐
│  create                    apply                        │
├─────────────────────────────────────────────────────────┤
│  • Imperativ               • Deklarativ                 │
│  • Nur neue Ressourcen     • Erstellt ODER aktualisiert │
│  • Fehler bei Existenz     • Idempotent                 │
│  • Keine Historie          • 3-Wege-Merge               │
│  • Schnell für Testing     • Best Practice für Prod     │
└─────────────────────────────────────────────────────────┘
```

### Hilfe & Dokumentation

```bash
kubectl --help                                # Allgemeine Hilfe
kubectl <command> --help                      # Hilfe zu Befehl
kubectl explain <resource>                    # Ressource dokumentieren
kubectl explain pod.spec.containers           # Feld-Dokumentation
```

---

## 17. Kubernetes Ressourcen - Vollständige Übersicht

### Ressourcen-Kategorien

Kubernetes-Ressourcen lassen sich in zwei Hauptkategorien einteilen:

```
┌──────────────────────────────────────────────────────────────┐
│           Cluster-Wide vs. Namespaced Resources              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  🔴 Cluster-Wide Resources (rot)                             │
│  • Verfügbar im gesamten Cluster                            │
│  • Keine Namespace-Zuordnung                                │
│  • Beispiele: Node, Namespace, ClusterRole, StorageClass    │
│                                                              │
│  🔵 Namespaced Resources (blau)                              │
│  • Gebunden an einen Namespace                              │
│  • Isolation zwischen Namespaces                            │
│  • Beispiele: Pod, Service, Deployment, ConfigMap           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Ressourcen-Übersicht mit Beziehungen

```
┌────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Resources Map                            │
└────────────────────────────────────────────────────────────────────────┘

                         🔴 ingressclass
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
    🔵 pod (a) ←→ 🔵 endpoint (a) → 🔵 service → 🔵 ingress
        ↑                   ↑ (if ready)
        │                   │
    🔵 replicaset (a) ←┬─ 🔵 job ←─ 🔵 cronjob
        ↑              │
        │              │
    🔵 deployment      🔵 statefulset  🔵 daemonset
        ↑              ↑                   ↑
        │              │                   │
    ┌───┴───┬──────────┴──────┬────────────┴──────────┐
    │       │                 │                       │
🔵 configmap  🔵 secrets → 🔵 serviceaccount → 🔵 rolebinding ──┐
    │          │                   ↓                           │
    │          │           🔵 horizontalpodautoscaler          │
    │          │                   ↓                           │
    │          └──────→ 🔵 persistentvolumeclaim               │
    │                          ↓                               │
    │                   🔴 persistentvolume                    │
    │                          ↑                               │
    │                   🔴 storageclass                        │
    │                                                          │
    └──────────────────────────────────────────────────────────┤
                                                               │
        🔵 resourcequotas    🔵 limitrange                     │
                                                               │
                                                         🔵 role
                                                               ↑
                    ┌──────────────────────────────────────────┘
                    │
            🔴 clusterrole ←─ 🔴 clusterrolebinding
                    ↑
                🔴 user
```

### Workload-Ressourcen

**Pod (Namespace)**
- Kleinste deploybare Einheit
- Ein oder mehrere Container
- Ephemeral (nicht dauerhaft)

**ReplicaSet (Namespace)**
- Stellt sicher, dass X Replicas eines Pods laufen
- Wird normalerweise von Deployment verwaltet
- Selten direkt verwendet

**Deployment (Namespace)**
- Verwaltet ReplicaSets
- Deklaratives Update-Management
- Rolling Updates und Rollbacks
- **Best Practice:** Standard für stateless Apps

**StatefulSet (Namespace)**
- Wie Deployment, aber für stateful Apps
- Feste Pod-Namen (pod-0, pod-1, ...)
- Eigener PersistentVolume pro Pod
- Geordnetes Starten/Stoppen
- **Best Practice:** Für Datenbanken, Message Queues

**DaemonSet (Namespace)**
- Läuft auf JEDEM Node (oder Subset)
- Automatisch auf neuen Nodes deployed
- **Beispiele:** Logging-Agents, Monitoring, CNI-Plugins

**Job (Namespace)**
- Führt eine Aufgabe einmalig aus
- Pod läuft bis Completion
- Kein automatischer Neustart nach Erfolg

**CronJob (Namespace)**
- Zeitgesteuertes Job-Scheduling
- Wie Linux Cron
- **Beispiele:** Backups, Reports, Cleanup-Tasks

### Networking-Ressourcen

**Service (Namespace)**
- Stabile IP und DNS für Pod-Gruppe
- Load Balancing über Endpoints
- Typen: ClusterIP, NodePort, LoadBalancer

**Endpoints (Namespace)**
- Liste der Pod-IPs hinter einem Service
- Automatisch von Kubernetes verwaltet

**Ingress (Namespace)**
- HTTP/HTTPS Routing zu Services
- Hostname- und pfad-basiertes Routing
- SSL/TLS-Terminierung

**IngressClass (Cluster-Wide)**
- Definiert Ingress-Controller-Typ
- Beispiele: nginx, traefik, haproxy

**NetworkPolicy (Namespace)**
- Firewall-Regeln für Pods
- Ingress/Egress Traffic-Kontrolle
- Erfordert CNI-Plugin mit NetworkPolicy-Support

### Configuration-Ressourcen

**ConfigMap (Namespace)**
- Nicht-sensible Konfigurationsdaten
- Als Umgebungsvariablen oder Volumes

**Secret (Namespace)**
- Sensible Daten (Passwörter, Keys, Zertifikate)
- Base64-kodiert (NICHT verschlüsselt!)
- Typen: generic, docker-registry, tls

**ServiceAccount (Namespace)**
- Identität für Pods
- Für API-Server-Zugriff
- Automatisches Mounting von Secrets

### Storage-Ressourcen

**PersistentVolume (PV) (Cluster-Wide)**
- Tatsächlicher Storage
- Wird von Admin provisioniert
- Oder: automatisch von StorageClass

**PersistentVolumeClaim (PVC) (Namespace)**
- Anforderung für Storage
- "Ich brauche 10GB"
- Wird an PV gebunden

**StorageClass (Cluster-Wide)**
- Storage-Typ-Definition
- Automatische PV-Provisionierung
- Beispiele: fast-ssd, slow-hdd, cloud-storage

### Resource Management

**ResourceQuota (Namespace)**
- Limits für gesamten Namespace
- CPU, Memory, Anzahl Pods, PVCs, etc.
- **Wichtig:** Wenn Quota aktiv → Requests/Limits Pflicht!

**LimitRange (Namespace)**
- Standard- und Max/Min-Werte für Pods
- Automatische Defaults wenn nicht angegeben
- **Best Practice:** In jedem Namespace!

**HorizontalPodAutoscaler (HPA) (Namespace)**
- Automatisches Scaling basierend auf Metriken
- CPU, Memory, Custom Metrics
- Verändert Replicas von Deployment/StatefulSet

### Security & Access Control (RBAC)

**Role (Namespace)**
- Permissions innerhalb eines Namespace
- Was darf gemacht werden (Verben: get, list, create, delete, ...)
- Auf welchen Ressourcen (Pods, Services, ...)

**RoleBinding (Namespace)**
- Verknüpft Role mit User/ServiceAccount
- "User X hat Role Y im Namespace Z"

**ClusterRole (Cluster-Wide)**
- Wie Role, aber cluster-weit
- Oder: für cluster-wide Ressourcen (Nodes, PVs)

**ClusterRoleBinding (Cluster-Wide)**
- Verknüpft ClusterRole mit User/ServiceAccount
- Gilt für ganzen Cluster

**Beispiel RBAC-Setup:**
```yaml
# Role: Darf Pods lesen
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]

---
# RoleBinding: User "alice" bekommt Role "pod-reader"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: dev
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Weitere wichtige Ressourcen

**Node (Cluster-Wide)**
- Physischer oder virtueller Server
- Worker oder Control Plane
- Kann gedraint/cordoned werden

**Namespace (Cluster-Wide)**
- Virtuelle Cluster-Trennung
- Für Isolation und Organisation

**PriorityClass (Cluster-Wide)**
- Pod-Prioritäten definieren
- Wichtige Pods werden zuerst gescheduled
- Bei Ressourcenmangel: Low-Priority Pods werden evicted

### Ressourcen prüfen

```bash
# Alle Ressourcen-Typen
kubectl api-resources

# Nur namespaced
kubectl api-resources --namespaced=true

# Nur cluster-wide
kubectl api-resources --namespaced=false

# Ressource erklären
kubectl explain deployment
kubectl explain deployment.spec.template.spec.containers
```

---

## 18. Hands-On Workshop - Kompletter Praxis-Durchlauf

Dieser Abschnitt dokumentiert einen **vollständigen praktischen Kubernetes-Workshop** mit realen Befehlen aus einem Training. Die Befehle sind chronologisch geordnet und zeigen den kompletten Workflow von Setup bis Production-Deployment.

### Workshop-Übersicht (957 Befehle)

Der Workshop deckt folgende Themen ab:
1. ✅ Initial Setup (kubectl, Tab-Completion, Cluster-Verbindung)
2. ✅ Namespaces und Kontexte
3. ✅ Pods und Deployments
4. ✅ Services und Networking
5. ✅ Ingress Controller Setup
6. ✅ ConfigMaps und Secrets
7. ✅ Persistent Storage (PVC/PV)
8. ✅ StatefulSets für Datenbanken
9. ✅ Resource Management (Metrics, Limits, Quotas)
10. ✅ RBAC und Security
11. ✅ Health Probes
12. ✅ Horizontal Pod Autoscaling
13. ✅ Jobs und CronJobs
14. ✅ Nextcloud Production Deployment
15. ✅ Kubernetes Dashboard
16. ✅ Backup/Restore und Kustomize
17. ✅ Helm Package Manager

### Phase 1: Initial Setup (Befehle 1-25)

**kubectl Installation und Tab-Completion:**
```bash
# 6: Tab-Completion installieren (massiv produktivitätssteigernd!)
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl

# 7: Aktivieren
source /etc/bash_completion.d/kubectl

# 9: Nodes prüfen (Cluster-Verbindung)
kubectl get nodes

# 11: Cluster-Konfiguration anzeigen
cat .kube/config

# 12: Contexts anzeigen
kubectl config get-contexts

# 16: Alle verfügbaren API-Ressourcen
kubectl api-resources

# 18: Nur Namespace-spezifische Ressourcen
kubectl api-resources --namespaced=true

# 19: Anzahl der Ressourcen-Typen
kubectl api-resources | wc -l
# OUTPUT: ~60+ Ressourcen-Typen

# 20: Ressource erklären
kubectl explain pod
```

**Namespace erstellen und Context setzen:**
```bash
# 22: Namespace erstellen
kubectl create namespace fre-myfirst

# 23: Alle Namespaces anzeigen
kubectl get namespaces

# 24: Context auf neuen Namespace setzen (wichtig!)
kubectl config set-context docker-desktop --namespace fre-myfirst

# 25: Prüfen
kubectl config get-contexts
```

### Phase 2: Pods und Deployments (Befehle 26-93)

**Pod erstellen (nicht empfohlen für Produktion):**
```bash
# 26: Einfacher Pod
kubectl run myhttpd --image quay.io/jfreygner/myhttpd:0.20

# 27-28: Status prüfen
kubectl get pods
kubectl get all

# 33-34: In Pod einloggen
kubectl exec -it myhttpd -- bash

# 38: Pod löschen (ist danach komplett weg!)
kubectl delete pod myhttpd
```

**Deployment erstellen (Best Practice):**
```bash
# 40: Deployment erstellen (mit Self-Healing)
kubectl create deployment myhttpd --image quay.io/jfreygner/myhttpd:0.20

# 41: Alles anzeigen (Deployment + ReplicaSet + Pod)
kubectl get all

# 42: Auf 3 Replicas skalieren
kubectl scale deployment myhttpd --replicas 3

# 44: Pods mit IPs anzeigen
kubectl get pods -o wide

# 45: Einen Pod löschen
kubectl delete pod myhttpd-746766bc85-lq8h7

# 46: Pod wird automatisch neu erstellt!
kubectl get pods -o wide
```

**Environment-Variablen und Rollouts:**
```bash
# 69: Env-Var setzen (triggert Rollout)
kubectl set env deployment myhttpd HTTPD_PORT=4711

# 73: Rollout-Historie anzeigen
kubectl rollout history deployment myhttpd

# 74-76: Einzelne Revision anzeigen
kubectl rollout history deployment myhttpd --revision 1
kubectl rollout history deployment myhttpd --revision 2

# 77: Rollback zur vorherigen Version
kubectl rollout undo deployment myhttpd

# 84: Zu spezifischer Revision zurück
kubectl rollout undo deployment myhttpd --to-revision 2
```

### Phase 3: Services und Networking (Befehle 94-149)

**Service erstellen:**
```bash
# 95: Service für Deployment erstellen
kubectl expose deployment myhttpd --port 8080

# 96: Service anzeigen
kubectl get service
# OUTPUT: ClusterIP wird vergeben (z.B. 10.110.219.138)

# 97: Service testen (intern im Cluster)
curl 10.110.219.138:8080

# 99: Service-Details anzeigen
kubectl describe service myhttpd

# 109: Endpoints anzeigen (Pod-IPs)
kubectl describe endpoints myhttpd
```

**Service-Typ ändern auf NodePort:**
```bash
# 111: Service editieren
kubectl edit deployments.apps myhttpd
# Ändern: type: NodePort

# 120: Service und Endpoints prüfen
kubectl describe service myhttpd
kubectl describe endpoints myhttpd
```

### Phase 4: Ingress Controller (Befehle 127-149)

**Ingress Controller installieren:**
```bash
# 127-129: Verzeichnis vorbereiten
mkdir -p setup/ingress
cd setup/ingress/
cp /mnt/c/Users/Administrator/Downloads/deploy.yaml .

# 130: Ingress Controller deployen
kubectl create -f deploy.yaml

# 131: Ingress Classes prüfen
kubectl get ingressclasses.networking.k8s.io
# OUTPUT: nginx verfügbar

# 133: Alle Komponenten im Namespace
kubectl get all -n ingress-nginx
```

**Ingress Regel erstellen:**
```bash
# 137: Ingress für myhttpd
kubectl create ingress myhttpd --class nginx --rule "www.myfirst.local/*=myhttpd:8080"

# 139-140: Status prüfen
kubectl get ingress
kubectl get all

# 142: IP-Adresse herausfinden
ip a s

# 143: Lokalen DNS-Eintrag hinzufügen
echo "172.22.84.207 www.myfirst.local" | sudo tee -a /etc/hosts

# 144: Testen
curl www.myfirst.local
# OUTPUT: Webseite wird angezeigt!
```

### Phase 5: ConfigMaps (Befehle 238-283)

**Config-Datei aus Pod extrahieren und als ConfigMap speichern:**
```bash
# 247: Config-Datei extrahieren
kubectl exec myhttpd-5cc4859bb9-8zrsd -- cat /etc/httpd/conf/httpd.conf > httpd.conf

# 251: In Editor öffnen und anpassen
code httpd.conf

# 253: ConfigMap erstellen
kubectl create configmap myhttpd --from-file httpd.conf
```

**oc Tool installieren (für erweiterte Funktionen):**
```bash
# 256-260: OpenShift Client (oc) herunterladen
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.19.19/openshift-client-linux-4.19.19.tar.gz
sudo tar xf ~/openshift-client-linux-4.19.19.tar.gz -C /usr/local/bin oc

# 261: Version prüfen
oc version

# 262-263: Tab-Completion
oc completion bash | sudo tee /etc/bash_completion.d/oc &> /dev/null
source /etc/bash_completion.d/oc
```

**ConfigMap in Deployment einbinden:**
```bash
# 271: ConfigMap als Volume mounten
oc set volumes deployment myhttpd \
  --add \
  --name myhttpd-conf \
  -t configmap \
  --configmap-name myhttpd \
  --mount-path /etc/httpd/conf/httpd.conf \
  --sub-path httpd.conf

# 277: ConfigMap aktualisieren
oc set data configmap myhttpd --from-file httpd.conf

# 280: Pods neu starten für neue Config
kubectl delete pod myhttpd-6fd746d769-rspnz
```

### Phase 6: Persistent Storage (Befehle 284-332)

**PVC erstellen und mounten:**
```bash
# 284: StorageClasses anzeigen
oc get sc

# 289: PVC erstellen und in Deployment mounten
oc set volumes deployment myhttpd \
  --add \
  --name myhttpd-data \
  -t pvc \
  --claim-size 5G \
  --claim-name myhttpd \
  --claim-mode rwm \
  --mount-path /var/www/html

# 290-291: Status prüfen
kubectl get pods
oc get deployments.apps

# 293: In Pod einloggen und Datei erstellen
kubectl exec -it myhttpd-d5478dd48-g4llt -- bash
# echo "Persistent Data" > /var/www/html/index.html

# 301-303: Persistenz testen (alle Pods löschen)
kubectl scale deployment myhttpd --replicas 0
kubectl scale deployment myhttpd --replicas 3

# 304: Daten sind noch da!
curl www.myfirst.local
```

**PersistentVolume Reclaim Policy ändern:**
```bash
# 309: PersistentVolumes anzeigen
kubectl get pv

# 314: PV editieren (Reclaim Policy auf Retain)
kubectl edit pv pvc-6395405a-e0e8-4dc4-aea6-5bcc4dcde0a8
```

### Phase 7: StatefulSet für MariaDB (Befehle 333-367)

**MariaDB mit StatefulSet deployen:**
```bash
# 333: Namespace wechseln
kubectl config set-context docker-desktop --namespace fre-mydb

# 335: PVC für MariaDB hinzufügen
oc set volumes deployment mydb \
  --add \
  --name mydb-data \
  -t pvc \
  --claim-size 5G \
  --claim-name mydb \
  --claim-mode rwo \
  --mount-path /var/lib/mysql

# 359-361: Deployment als Basis für StatefulSet exportieren
kubectl get -o yaml deployment mydb > mydb-deploy.yaml
cp mydb-deploy.yaml mydb-statefulset.yaml
code mydb-statefulset.yaml

# 365-367: StatefulSet deployen
kubectl delete deployments.apps mydb
kubectl create -f mydb-statefulset.yaml
kubectl get pods,pvc
# OUTPUT: mydb-0, mydb-1 mit jeweils eigenem PVC
```

### Phase 8: Resource Management (Befehle 369-472)

**Metrics Server installieren:**
```bash
# 369-375: Metrics Server deployen
mkdir setup/metrics
cd setup/metrics/
cp /mnt/c/Users/Administrator/Downloads/components-insecure-tls.yaml .
kubectl create -f components-insecure-tls.yaml

# 376-377: Ressourcen-Verbrauch anzeigen
kubectl top pods
kubectl top node
```

**Resource Limits setzen:**
```bash
# 426-427: Requests und Limits setzen
oc set resources deployment myhttpd \
  --limits cpu=2,memory=6Gi \
  --requests cpu=1,memory=5Gi

# 429: Limits prüfen
oc describe pod myhttpd-54db85758d-dksgn | grep -i -A6 limits
```

**ResourceQuota erstellen:**
```bash
# 441: Quota für Namespace
kubectl create quota myhttpd \
  --hard limits.cpu=5,requests.cpu=3,limits.memory=5Gi,requests.memory=1Gi,pods=10

# 442: Quota-Status anzeigen
kubectl describe resourcequotas myhttpd
```

**LimitRange für Default-Werte:**
```bash
# 462-464: LimitRange aus YAML erstellen
vi myhttpd-limitrange.yaml
oc create -f myhttpd-limitrange.yaml
kubectl describe limitranges myhttpd
```

### Phase 9: RBAC (Befehle 476-502)

**Roles und RoleBindings erkunden:**
```bash
# 482-485: RBAC-Komponenten im ingress-nginx Namespace
kubectl config set-context docker-desktop --namespace ingress-nginx
kubectl get roles
kubectl get rolebindings.rbac.authorization.k8s.io
kubectl describe role ingress-nginx

# 492-496: ClusterRoles und ClusterRoleBindings
kubectl get clusterrole
kubectl describe clusterrole cluster-admin
kubectl describe clusterrole view
kubectl get clusterrolebindings.rbac.authorization.k8s.io
```

### Phase 10: Health Probes (Befehle 536-556)

**Readiness und Liveness Probes setzen:**
```bash
# 537: Readiness Probe
oc set probe deployment/myhttpd \
  --readiness \
  --get-url=http://:8080/index.html \
  --initial-delay-seconds 10

# 538: Pods beobachten
oc get pods -w
# Pods zeigen READY 0/1 → 1/1 wenn Probe erfolgreich

# 549: Liveness Probe
oc set probe deployment/myhttpd \
  --liveness \
  --get-url=http://:8080/index.html

# 550: In Pod einloggen und index.html löschen (Test)
kubectl exec -it myhttpd-759f988486-m7ztn -- bash
# rm /var/www/html/index.html

# 551: Pods beobachten
kubectl get pods -w
# Pod wird automatisch neu gestartet (RESTARTS erhöht sich)
```

### Phase 11: Horizontal Pod Autoscaler (Befehle 559-588)

**HPA erstellen und testen:**
```bash
# 559: HPA erstellen
kubectl autoscale deployment myhttpd --cpu-percent 80 --min 2 --max 10

# 561-562: Status prüfen
kubectl get hpa
kubectl get pods

# 564: Ressourcen-Verbrauch
kubectl top pods --sum

# 574: In Pod einloggen und CPU-Last erzeugen
kubectl exec -it myhttpd-759f988486-m7ztn -- bash
# md5sum /dev/zero &  # CPU-Last erzeugen

# 577-578: HPA beobachten
kubectl top pods --sum
kubectl get hpa
# OUTPUT: CPU steigt, HPA erstellt neue Pods

# 586-587: Last stoppen
kubectl delete pod myhttpd-759f988486-m7ztn
# HPA skaliert nach ~5 Minuten wieder runter
```

### Phase 12: Jobs und CronJobs (Befehle 590-613)

**Jobs:**
```bash
# 598: Job erstellen
kubectl create job mydate --image quay.io/jfreygner/mydate:0.2

# 599-600: Status prüfen
kubectl get pods,job
kubectl logs job/mydate
# OUTPUT: Datum, Pod Status: Completed
```

**CronJobs:**
```bash
# 602: CronJob erstellen (alle 2 Minuten, Mo-Fr, 8-16 Uhr)
kubectl create cronjob mydate \
  --image quay.io/jfreygner/mydate:0.2 \
  --schedule '*/2 8-16 * * 1-5'

# 604-611: Status beobachten
kubectl get cronjob,job,pod
date
# Nach 2 Minuten: Neuer Job wird erstellt

# 612-613: Logs anzeigen
kubectl logs job/mydate-29395344
kubectl logs job/mydate-29395346
```

### Phase 13: Nextcloud Production Deployment (Befehle 614-688)

**Komplettes Nextcloud-Projekt mit MariaDB:**
```bash
# 614-615: Namespace vorbereiten
kubectl create namespace fre-nextcloud
kubectl config set-context docker-desktop --namespace fre-nextcloud

# 616-617: Secret erstellen
read -s -p 'passwort: '
kubectl create secret generic nextcloud \
  --from-literal MYSQL_ROOT_PASSWORD=$REPLY \
  --from-literal MYSQL_PASSWORD=$REPLY \
  --from-literal MYSQL_DATABASE=nextcloud \
  --from-literal MYSQL_USER=nextcloud \
  --from-literal MYSQL_HOST=mariadb

# 618-625: MariaDB deployen
kubectl create deployment mariadb --image docker.io/library/mariadb:10.6
kubectl set env deployment mariadb --from secret/nextcloud
oc set volumes deployment mariadb \
  --add \
  --name mariadb-data \
  -t pvc \
  --claim-name mariadb \
  --claim-size 5Gi \
  --claim-mode rwo \
  --mount-path /var/lib/mysql
kubectl expose deployment mariadb --port 3306

# 627-632: Nextcloud deployen
kubectl create deployment nextcloud --image docker.io/library/nextcloud:32.0.2-apache
kubectl set env deployment nextcloud --from secret/nextcloud
oc set volumes deployment nextcloud \
  --add \
  --name nextcloud-data \
  -t pvc \
  --claim-name nextcloud \
  --claim-size 5Gi \
  --claim-mode rwm \
  --mount-path /var/www/html
kubectl expose deployment nextcloud --port 80
kubectl create ingress nextcloud --class nginx --rule "nextcloud.myfirst.local/*=nextcloud:80"

# 634: Alle Ressourcen anzeigen
kubectl get all,pvc,secrets

# 638-643: MariaDB als StatefulSet deployen (Production)
kubectl get deployments.apps mariadb -o yaml > mariadb-deploy.yaml
cp mariadb-deploy.yaml mariadb-statefulset.yaml
vi mariadb-statefulset.yaml
kubectl delete deployments.apps mariadb
kubectl create -f mariadb-statefulset.yaml
```

**Nextcloud Backup erstellen:**
```bash
# 656-663: Backup-Pod mit PVC-Mount
kubectl create deployment testpod --image quay.io/jfreygner/testpod:0.5
oc set volumes deployment testpod --add --name wurscht --mount-path /data -t pvc --claim-name mariadb-data-mariadb-0
kubectl exec -it testpod-7bfc6b9649-wf995 -- bash
# tar czf /tmp/mariadb.tgz /data
kubectl cp testpod-7bfc6b9649-wf995:/tmp/mariadb.tgz mariadb.tgz
```

**Nextcloud Restore:**
```bash
# 681-684: Restore aus Backup
kubectl cp mariadb.tgz testpod-c7559bcf8-qqdkr:/tmp/mariadb.tgz
kubectl exec -it testpod-c7559bcf8-qqdkr -- bash
# cd /data && tar xzf /tmp/mariadb.tgz
kubectl delete deployments.apps testpod
kubectl scale statefulset mariadb --replicas 1
```

### Phase 14: Kubernetes Dashboard (Befehle 689-707)

**Dashboard mit Helm installieren:**
```bash
# 693-695: Helm installieren
wget https://get.helm.sh/helm-v4.0.0-linux-amd64.tar.gz
tar xvf helm-v4.0.0-linux-amd64.tar.gz
sudo cp linux-amd64/helm /usr/local/bin

# 696-697: Tab-Completion
helm completion bash | sudo tee /etc/bash_completion.d/helm &> /dev/null
source /etc/bash_completion.d/helm

# 699-700: Dashboard deployen
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace --namespace kubernetes-dashboard

# 702: Port-Forwarding starten
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 &

# 705-706: ServiceAccount Berechtigungen und Token
oc adm policy add-cluster-role-to-user cluster-admin -z kubernetes-dashboard-kong
kubectl create token kubernetes-dashboard-kong
# Token im Browser eingeben: https://localhost:8443
```

### Phase 15: Backup/Restore mit YAML (Befehle 709-748)

**Alle Ressourcen exportieren:**
```bash
# 709-711: Alle Ressourcen einer Anwendung exportieren
kubectl config set-context docker-desktop --namespace fre-myfirst
kubectl get all,pvc,configmap,ingress
kubectl get -o yaml cm,deploy,service,ingress,pvc,hpa myhttpd > myhttpd-all.yaml

# 712-715: Namespace löschen und neu erstellen
kubectl delete namespaces fre-myfirst
kubectl create namespace fre-myfirst
kubectl create -f myhttpd-all.yaml

# 717: YAML bereinigen (Status, UIDs, etc. entfernen)
vi myhttpd-all.yaml

# 720-723: Erneut testen
kubectl delete namespaces fre-myfirst
kubectl create namespace fre-myfirst
kubectl create -f myhttpd-all.yaml
kubectl get all,pvc
```

**Templates erstellen (für Wiederverwendung):**
```bash
# 749-765: Einzelne Ressourcen in separate Dateien
mkdir templates
cd templates/
kubectl get -o yaml cm myhttpd > myhttpd-cm.yaml
kubectl get -o yaml pvc myhttpd > myhttpd-pvc.yaml
# ... weitere Ressourcen

# 761-764: Alle Templates gleichzeitig deployen
kubectl create namespace fre-mydemo3
kubectl config set-context docker-desktop --namespace fre-mydemo3
kubectl create -f .
```

### Phase 16: Kustomize (Befehle 783-862)

**Kustomize-Struktur erstellen:**
```bash
# 783-787: Verzeichnisstruktur
mkdir -p kustomize/{base,overlays/{test,devel,prod}}
tree kustomize/
cp templates/* kustomize/base

# 794-797: Base kustomization.yaml erstellen
cd kustomize/base/
ls > kustomization.yaml
vi kustomization.yaml
kubectl create -k .  # Erstellt aus allen Dateien in base/
```

**Overlay für Devel-Umgebung:**
```bash
# 799-817: Devel Overlay konfigurieren
cd ../overlays/devel/
vi kustomization.yaml
# resources:
#   - ../../base
# namespace: fre-myhttpd-devel
# patchesStrategicMerge:
#   - deploy-patch.yaml

# 808-811: Deployment-Patch erstellen
cp ../../base/myhttpd-deploy.yaml deploy-patch.yaml
vi deploy-patch.yaml  # Replicas auf 2 ändern

# 820-822: Deployen
kubectl create namespace fre-myhttpd-devel
kubectl create -k .
kubectl get all -n fre-myhttpd-devel
```

**Overlay für Prod-Umgebung:**
```bash
# 827-838: Prod Overlay
cp devel/* prod/
cd prod/
vi deploy-patch.yaml  # Replicas auf 5, Limits erhöhen
vi kustomization.yaml  # namespace: fre-myhttpd-prod
kubectl create namespace fre-myhttpd-prod
kubectl create -k .
kubectl get all,pvc -n fre-myhttpd-prod
```

**Kustomize diff und apply:**
```bash
# 845-851: Änderungen testen mit diff
kubectl diff -k .
vi deploy-patch.yaml  # Änderungen machen
kubectl diff -k .     # Zeigt Unterschiede
kubectl apply -k .    # Anwenden
```

### Phase 17: Helm Package Manager (Befehle 863-943)

**Helm Repository verwenden:**
```bash
# 863-873: Bitnami Repo hinzufügen
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo list
helm search repo mysql
helm pull bitnami/mysql  # Chart herunterladen
tar xvf mysql-14.0.3.tgz

# 877-884: Chart installieren
kubectl create namespace fre-mysql
kubectl config set-context docker-desktop --namespace fre-mysql
helm install mydb bitnami/mysql
kubectl get all

# 884-886: Helm-Historie
helm list
helm history mydb
```

**Eigenen Helm Chart erstellen:**
```bash
# 891-903: Chart-Struktur generieren
helm create myhttpd
cd myhttpd/templates/

# Eigene YAML-Dateien hinzufügen
kubectl config set-context docker-desktop --namespace fre-myfirst
kubectl get deployments.apps myhttpd -o yaml > deployment.yaml
kubectl get pvc myhttpd -o yaml > pvc.yaml
kubectl get svc myhttpd -o yaml > service.yaml
kubectl get ingress myhttpd -o yaml > ingress.yaml
kubectl get cm myhttpd -o yaml > cm.yaml

# 905-911: YAML-Dateien mit Helm-Templates anpassen
rm hpa.yaml httproute.yaml serviceaccount.yaml
code cm.yaml  # {{ .Values.xyz }} verwenden
# ... weitere Dateien anpassen
```

**Helm Chart deployen mit values.yaml:**
```bash
# 914-926: Chart installieren
kubectl create namespace fre-myhttpd-helm
kubectl config set-context docker-desktop --namespace fre-myhttpd-helm
vi myhttpd/values.yaml  # Werte anpassen
helm install mysepperl myhttpd/
helm list

# 920-932: Upgrade mit custom values
vi values-prod.yaml  # Production-Werte
helm upgrade -f values-prod.yaml mysepperl myhttpd/
kubectl get ingress
```

### Wichtige Erkenntnisse aus dem Workshop

**Best Practices (aus der Praxis):**
1. ✅ **Tab-Completion** sofort einrichten (Befehl 6-7) → massiv produktiver!
2. ✅ **Context + Namespace** immer setzen (Befehl 24) → verhindert Fehler
3. ✅ **Deployments statt Pods** (Befehl 40) → Self-Healing
4. ✅ **oc Tool** verwenden (Befehl 256-260) → erweiterte Funktionen
5. ✅ **Metrics Server** früh installieren (Befehl 375) → für HPA notwendig
6. ✅ **Resource Limits** setzen (Befehl 426) → Cluster-Stabilität
7. ✅ **Health Probes** konfigurieren (Befehl 537, 549) → Zuverlässigkeit
8. ✅ **StatefulSets für Datenbanken** (Befehl 366) → Datensicherheit
9. ✅ **Backup-Strategie** etablieren (Befehl 656-663) → Disaster Recovery
10. ✅ **Kustomize/Helm** für Wiederverwendung (Befehl 783+, 891+)

**Häufige Fehler (und wie man sie vermeidet):**
```bash
# ❌ FALSCH: Pod ohne Restart-Policy
kubectl run myapp --image nginx
# → CrashLoopBackOff bei Beendigung

# ✅ RICHTIG: Deployment oder Job verwenden
kubectl create deployment myapp --image nginx
kubectl create job myapp --image nginx

# ❌ FALSCH: ConfigMap mounten überschreibt ganzes Verzeichnis
oc set volumes ... --mount-path /etc/httpd/conf
# → Alle anderen Dateien in /etc/httpd/conf verschwinden!

# ✅ RICHTIG: sub-path verwenden
oc set volumes ... --mount-path /etc/httpd/conf/httpd.conf --sub-path httpd.conf

# ❌ FALSCH: PVC löschen mit Reclaim Policy "Delete"
kubectl delete pvc mydata
# → Alle Daten verloren!

# ✅ RICHTIG: Erst Reclaim Policy auf "Retain" ändern
kubectl edit pv pvc-xxx  # persistentVolumeReclaimPolicy: Retain
```

**Nützliche Alias (aus der History):**
```bash
# Häufig verwendete Befehle verkürzen
alias k='kubectl'
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias kccc='kubectl config current-context'
alias kcgc='kubectl config get-contexts'
```

---

## 19. Best Practices

### 1. Namespaces für Organisation

✅ **Empfohlen:**
- Verschiedene Teams: `team-frontend`, `team-backend`
- Verschiedene Umgebungen: `dev`, `test`, `prod`
- Verschiedene Anwendungen: `app1`, `app2`

❌ **Nicht empfohlen:**
- Alles im `default` Namespace
- Zu viele Namespaces (Overhead)

```bash
# Namespace-Struktur (Beispiel)
kubectl get namespaces
# dev-team-a
# dev-team-b
# staging
# production
# monitoring
# logging
```

### 2. Labels und Selectors konsistent verwenden

Labels sind der Schlüssel für Services, Deployments, und andere Kubernetes-Ressourcen.

✅ **Best Practice:**
```yaml
metadata:
  labels:
    app: myapp               # Anwendungsname
    version: v1.2.3          # Version
    environment: production  # Umgebung
    tier: frontend           # Schicht (frontend/backend/database)
```

**Services nutzen Labels:**
```yaml
spec:
  selector:
    app: myapp    # Service routet zu allen Pods mit diesem Label
```

### 3. Ressourcen-Limits IMMER setzen

❌ **Ohne Limits:**
- Ein Pod kann alle Node-Ressourcen verbrauchen
- Andere Pods verhungern oder werden beendet
- Cluster wird instabil

✅ **Mit Limits:**
```yaml
resources:
  requests:      # Garantierte Ressourcen
    cpu: 100m
    memory: 128Mi
  limits:        # Maximum
    cpu: 500m
    memory: 512Mi
```

**Faustregel:**
- `requests` = Normal-Betrieb
- `limits` = Spitzenlast (2-5x requests)
- Memory-Limit niemals fehlen lassen (Pod wird bei Überschreitung beendet!)

### 4. Secrets niemals in Git speichern

❌ **FALSCH:**
```yaml
# deployment.yaml in Git
env:
- name: DB_PASSWORD
  value: "MySecretPassword123"  # ← NIEMALS SO!
```

✅ **RICHTIG:**
```yaml
# deployment.yaml in Git
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: myapp-secret
      key: DB_PASSWORD

# Secret wird separat erstellt (nicht in Git!)
```

**Alternativen für Produktion:**
- HashiCorp Vault
- Sealed Secrets (verschlüsselte Secrets in Git)
- External Secrets Operator (AWS Secrets Manager, Azure Key Vault)

### 5. Health Checks immer konfigurieren

❌ **Ohne Probes:**
- Kaputte Container bekommen Traffic
- Langsam startende Container bekommen zu früh Traffic
- Deadlocks werden nicht erkannt

✅ **Mit Probes:**
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30    # Genug Zeit für Startup!
  periodSeconds: 10
  failureThreshold: 3        # Nicht zu aggressiv

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 2
```

### 6. Deklarativ arbeiten (GitOps)

✅ **Best Practice:**
1. Alle Manifeste in Git speichern
2. Änderungen via Pull Requests
3. Automatisches Deployment (Flux CD, ArgoCD)
4. Rollback = Git Revert

❌ **Nicht empfohlen:**
- Manuelle `kubectl edit` Befehle
- Konfiguration nicht versioniert
- Keine Nachvollziehbarkeit

### 7. Separate Deployments für Stateful Services

✅ **Empfohlen:**
- **Datenbanken** → StatefulSet (feste Identität, eigene PVCs)
- **Stateless Apps** → Deployment (austauschbare Pods)

❌ **Nicht empfohlen:**
- Datenbank in Deployment (Daten können verloren gehen)

### 8. Multi-Stage Deployments

```
┌────────────┐    ┌────────────┐    ┌────────────┐
│    Dev     │ →  │   Staging  │ →  │    Prod    │
│ (Namespace)│    │ (Namespace)│    │ (Namespace)│
└────────────┘    └────────────┘    └────────────┘
```

**Vorteile:**
- Testen in produktionsnaher Umgebung
- Rollback-Möglichkeit
- Schrittweise Freigabe

### 9. Monitoring und Logging von Anfang an

✅ **Implementieren:**
- Prometheus + Grafana für Metriken
- Loki/ELK für Logs
- Alerts bei kritischen Zuständen

**Wichtige Metriken:**
- CPU/Memory-Auslastung
- Pod-Restarts (häufige Restarts = Problem!)
- Request-Latenz
- Error-Rate

### 10. Regelmäßige Updates

✅ **Best Practice:**
- Kubernetes-Version aktuell halten (max. 2 Minor-Versionen hinter aktuellster)
- Container-Images regelmäßig aktualisieren
- Security-Patches zeitnah einspielen

**Update-Strategie:**
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1           # Max. 1 zusätzlicher Pod während Update
      maxUnavailable: 0     # Keine Downtime!
```

### 11. Network Policies für Segmentierung

Standardmäßig kann jeder Pod mit jedem Pod kommunizieren.

✅ **Produktions-Setup:**
```yaml
# Deny-All Policy (Basis)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-by-default
spec:
  podSelector: {}  # Alle Pods
  policyTypes:
  - Ingress
  - Egress

# Allow-Specific Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### 12. Immutable Infrastructure

✅ **Best Practice:**
- Nie in laufende Container einloggen und Änderungen machen
- Änderungen immer via neues Image/ConfigMap
- Container als "Cattle, not Pets" behandeln

❌ **Anti-Pattern:**
```bash
# NIEMALS SO:
kubectl exec -it pod -- bash
# Im Container: apt-get install ...
# Änderungen gehen bei Neustart verloren!
```

### 13. Documentation as Code

```bash
# In jedem Projekt: README.md mit:
# - Architektur-Übersicht
# - Deployment-Anleitung
# - Troubleshooting-Guide
# - Kontakt-Informationen
```

---

## Zusammenfassung

Dieser Kurs hat folgende Kubernetes-Konzepte abgedeckt:

### Grundlagen
- ✅ Kubernetes-Architektur (Control Plane, Worker Nodes)
- ✅ kubectl Setup und Verwendung
- ✅ Namespaces für Organisation

### Workloads
- ✅ Pods (kleinste Einheit)
- ✅ Deployments (Self-Healing, Skalierung)
- ✅ ReplicaSets (automatisch von Deployments verwaltet)
- ✅ StatefulSets (für Datenbanken)
- ✅ Jobs und CronJobs (Batch-Workloads)

### Netzwerk
- ✅ Services (ClusterIP, NodePort, LoadBalancer)
- ✅ Ingress (HTTP-Routing)
- ✅ DNS-basierte Service-Discovery

### Konfiguration
- ✅ ConfigMaps (Konfigurationsdateien)
- ✅ Secrets (sensible Daten)
- ✅ Environment-Variablen

### Storage
- ✅ PersistentVolumes und PersistentVolumeClaims
- ✅ StorageClasses
- ✅ Access Modes (RWO, RWM, ROX)

### Betrieb
- ✅ Resource Requests und Limits
- ✅ ResourceQuotas
- ✅ Health Checks (Liveness, Readiness Probes)
- ✅ Horizontal Pod Autoscaling
- ✅ Monitoring mit Metrics Server

### Best Practices
- ✅ Deklaratives Management (GitOps)
- ✅ Labels und Selectors
- ✅ Security (Secrets, RBAC)
- ✅ High Availability (Multi-Replica)

---

**Nächste Schritte:**

1. **Vertiefen:**
   - RBAC (Role-Based Access Control)
   - Helm (Package Manager für Kubernetes)
   - Operators (komplexe Anwendungen automatisieren)
   - Service Mesh (Istio, Linkerd)

2. **Zertifizierungen:**
   - CKAD (Certified Kubernetes Application Developer)
   - CKA (Certified Kubernetes Administrator)

3. **Praxis:**
   - Eigene Anwendungen deployen
   - CI/CD-Pipelines mit Kubernetes
   - Multi-Cluster Management

---

**Viel Erfolg mit Kubernetes!** 🚀
