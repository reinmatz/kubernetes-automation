# Ansible in Kubernetes - Quick Start Guide

## ✓ Installation abgeschlossen!

Ansible wurde erfolgreich als Container in Ihrem Kubernetes Cluster deployed.

## Schnellzugriff

### Helper Script verwenden (empfohlen)

```bash
cd "/Users/reinhard/Claude/kubernetes/Kubernetes HA"

# Status prüfen
./scripts/ansible-k8s.sh status

# Shell öffnen
./scripts/ansible-k8s.sh shell

# Ansible-Befehl
./scripts/ansible-k8s.sh ansible localhost -m ping

# kubectl im Container
./scripts/ansible-k8s.sh kubectl get nodes

# Hilfe anzeigen
./scripts/ansible-k8s.sh help
```

### Direkte kubectl-Befehle

```bash
# Shell im Container
kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash

# Ansible-Befehl
kubectl exec -n ansible deployment/ansible-k8s -- ansible localhost -m ping

# kubectl (WICHTIG: unset KUBECONFIG!)
kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl get nodes"
```

## Nächste Schritte: Monitoring & Cert-Manager deployen

### 1. Playbooks in Container kopieren

```bash
cd "/Users/reinhard/Claude/kubernetes/Kubernetes HA"

# Pod-Name ermitteln
POD=$(kubectl get pod -n ansible -l app=ansible-k8s -o jsonpath='{.items[0].metadata.name}')

# Extensions Playbook kopieren
kubectl cp extensions_playbook.yml ansible/$POD:/ansible/playbooks/extensions.yml

# Inventory kopieren
kubectl cp inventory_hosts.yml ansible/$POD:/ansible/inventory/hosts.yml
```

**ODER mit Helper Script:**

```bash
./scripts/ansible-k8s.sh copy extensions_playbook.yml /ansible/playbooks/extensions.yml
./scripts/ansible-k8s.sh copy inventory_hosts.yml /ansible/inventory/hosts.yml
```

### 2. Playbook ausführen

```bash
# Shell im Container öffnen
./scripts/ansible-k8s.sh shell

# Im Container:
cd /ansible

# Nur Monitoring + Cert-Manager deployen
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t "monitoring,cert-manager" -v

# ODER alle Extensions deployen
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -v
```

**ODER direkt ausführen:**

```bash
./scripts/ansible-k8s.sh playbook /ansible/playbooks/extensions.yml -i /ansible/inventory/hosts.yml -t "monitoring,cert-manager" -v
```

### 3. Deployment überwachen

```bash
# In separatem Terminal
watch kubectl get pods -A

# Oder Logs verfolgen
./scripts/ansible-k8s.sh logs
```

## Deployment-Details

### Was wurde installiert?

| Komponente | Beschreibung | Status |
|------------|--------------|--------|
| **Namespace** | `ansible` | ✓ Erstellt |
| **ServiceAccount** | `ansible-operator` mit ClusterAdmin | ✓ Erstellt |
| **Deployment** | `ansible-k8s` mit Ansible 2.12+ | ✓ Running |
| **Tools** | kubectl, Python kubernetes modules | ✓ Installiert |
| **Storage** | 5GB PVC für persistente Daten | ⚠️ Pending (local-path) |

### Verfügbare Extensions

Nach dem Kopieren der Playbooks können Sie deployen:

1. **MetalLB** - LoadBalancer für externe IPs
2. **Nginx Ingress** - HTTP/HTTPS Routing
3. **Prometheus + Grafana** - Monitoring & Dashboards
4. **Loki + Promtail** - Log-Aggregation
5. **Cert-Manager** - Automatische TLS-Zertifikate

## Grafana Zugriff (nach Monitoring-Deployment)

```bash
# Port-Forward zu Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Browser öffnen: http://localhost:3000
# Login: admin / ChangeMe123!
```

## Troubleshooting

### Problem: Pod startet nicht

```bash
# Logs prüfen
kubectl logs -n ansible deployment/ansible-k8s -c ansible

# Events prüfen
kubectl get events -n ansible --sort-by='.lastTimestamp'

# Pod neu starten
./scripts/ansible-k8s.sh restart
```

### Problem: kubectl funktioniert nicht im Container

**Ursache**: KUBECONFIG ist falsch gesetzt

**Lösung**: Immer mit `unset KUBECONFIG` aufrufen:

```bash
kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl get nodes"
```

Oder Helper Script verwenden:
```bash
./scripts/ansible-k8s.sh kubectl get nodes
```

### Problem: Ansible Collections fehlen

```bash
kubectl exec -n ansible deployment/ansible-k8s -- \
  ansible-galaxy collection install kubernetes.core community.general -p /home/runner/.ansible/collections
```

## Konfiguration anpassen

### Inventory bearbeiten

Vor dem Deployment sollten Sie `inventory_hosts.yml` anpassen:

```yaml
# Wichtige Variablen:
grafana_admin_password: "ChangeMe123!"  # ÄNDERN!
cert_manager_email: "admin@cluster.local"  # ÄNDERN!
metallb_ip_range: "192.168.100.200-192.168.100.210"  # An Ihr Netzwerk anpassen
```

### Extensions aktivieren/deaktivieren

Im Inventory:

```yaml
prometheus_enabled: true      # Monitoring
loki_enabled: true           # Logging
cert_manager_enabled: true   # TLS-Zertifikate
metallb_enabled: true        # LoadBalancer
nginx_ingress_enabled: true  # Ingress Controller
flux_enabled: false          # GitOps (später)
```

## Ressourcen

- **Manifests**: `manifests/ansible/`
- **Helper Script**: `scripts/ansible-k8s.sh`
- **Playbooks**: `extensions_playbook.yml`, `site_playbook.yml`
- **Dokumentation**: `manifests/ansible/README.md`

## Cleanup

### Ansible entfernen (ACHTUNG!)

```bash
./scripts/ansible-k8s.sh delete
```

### Nur Pod neu starten

```bash
./scripts/ansible-k8s.sh restart
```

---

## Los geht's! 🚀

```bash
# 1. Status prüfen
./scripts/ansible-k8s.sh status

# 2. Shell öffnen
./scripts/ansible-k8s.sh shell

# 3. Monitoring deployen (im Container)
cd /ansible
# ... erst Playbooks kopieren, dann ausführen
```

Viel Erfolg! Bei Problemen siehe `manifests/ansible/README.md`
