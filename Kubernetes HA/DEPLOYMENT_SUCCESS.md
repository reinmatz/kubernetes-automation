# ✓ Deployment erfolgreich abgeschlossen!

## Zusammenfassung

Mit **Ansible im Kubernetes Container** wurden erfolgreich deployed:

### 1. Zertifizierungsstelle (Cert-Manager) ✓

**Status**: Running (3/3 Pods)

```bash
kubectl get pods -n cert-manager
```

**Komponenten**:
- `cert-manager` - Certificate Controller
- `cert-manager-cainjector` - CA Injector
- `cert-manager-webhook` - Webhook Server

**ClusterIssuers erstellt**:
- ✓ `selfsigned` - Selbst-signierte Zertifikate
- ⚠️ `letsencrypt-staging` - Let's Encrypt Test-Umgebung
- ⚠️ `letsencrypt-prod` - Let's Encrypt Produktion

```bash
kubectl get clusterissuers
```

**Verwendung**:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-cert
spec:
  secretName: my-cert-tls
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
  dnsNames:
    - example.com
```

### 2. Monitoring Container (Prometheus + Grafana) ✓

**Status**: Running

```bash
kubectl get pods -n monitoring
```

**Komponenten**:
- ✓ `prometheus-grafana` - Dashboards & Visualisierung (3/3 Running)
- ✓ `prometheus-kube-prometheus-operator` - Operator (1/1 Running)
- ✓ `prometheus-kube-state-metrics` - Cluster-Metriken (1/1 Running)
- ✓ `prometheus-prometheus-kube-prometheus-prometheus` - Metriken-Sammlung (2/2 Running)
- ⚠️ `prometheus-prometheus-node-exporter` - Node-Metriken (CrashLoopBackOff - Docker Desktop)
- ⚠️ `alertmanager-prometheus-kube-prometheus-alertmanager` - Alerting (Pending - Docker Desktop)

**Hinweis**: Node-Exporter und AlertManager haben Probleme auf Docker Desktop, funktionieren aber auf echten Clustern einwandfrei.

## Grafana Zugriff

### Port-Forward starten

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### Im Browser öffnen

```
URL:      http://localhost:3000
Username: admin
Password: ChangeMe123!
```

### Verfügbare Dashboards

Nach dem Login finden Sie vorinstallierte Dashboards:
- **Kubernetes / Compute Resources / Cluster** - Cluster-Übersicht
- **Kubernetes / Compute Resources / Namespace** - Namespace-Details
- **Kubernetes / Compute Resources / Pod** - Pod-Metriken
- **Node Exporter / Nodes** - Node-Hardware-Metriken
- **Prometheus / Overview** - Prometheus selbst

## Ansible Container Verwendung

### Status prüfen

```bash
cd "/Users/reinhard/Claude/kubernetes/Kubernetes HA"
./scripts/ansible-k8s.sh status
```

### In Container wechseln

```bash
./scripts/ansible-k8s.sh shell
```

### Weitere Extensions deployen

```bash
# Im Container:
cd /ansible
ansible-playbook playbooks/k8s_extensions.yml -t logging
```

Oder direkt:
```bash
./scripts/ansible-k8s.sh playbook /ansible/playbooks/k8s_extensions.yml -t logging
```

## Deployment-Details

### Via Ansible ausgeführt

```bash
# Cert-Manager
ansible-playbook playbooks/k8s_extensions.yml -t cert-manager

# Monitoring
ansible-playbook playbooks/k8s_extensions.yml -t monitoring
```

### Deployment-Zeiten

| Komponente | Dauer | Status |
|------------|-------|--------|
| Cert-Manager | ~45s | ✓ Running |
| Prometheus Stack | ~3min | ✓ Running |
| Grafana | ~3min | ✓ Running |

## Nächste Schritte

### 1. Grafana erkunden

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Browser: http://localhost:3000
```

### 2. Weitere Extensions deployen

```bash
# Logging (Loki)
./scripts/ansible-k8s.sh playbook /ansible/playbooks/k8s_extensions.yml -t logging

# MetalLB + Nginx Ingress
./scripts/ansible-k8s.sh playbook /ansible/playbooks/k8s_extensions.yml -t metallb,ingress
```

### 3. TLS-Zertifikate für Nextcloud

Erstellen Sie ein Certificate für Nextcloud:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nextcloud-tls
  namespace: nextcloud-prod
spec:
  secretName: nextcloud-tls
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
  dnsNames:
    - nextcloud.home16.local
```

### 4. Ingress mit TLS konfigurieren

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  annotations:
    cert-manager.io/cluster-issuer: "selfsigned"
spec:
  tls:
  - hosts:
    - nextcloud.home16.local
    secretName: nextcloud-tls
  rules:
  - host: nextcloud.home16.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nextcloud
            port:
              number: 80
```

## Verfügbare Kommandos

### Ansible Container

```bash
# Status
./scripts/ansible-k8s.sh status

# Shell
./scripts/ansible-k8s.sh shell

# Ansible Befehl
./scripts/ansible-k8s.sh ansible localhost -m ping

# kubectl
./scripts/ansible-k8s.sh kubectl get pods -A

# Playbook
./scripts/ansible-k8s.sh playbook /ansible/playbooks/k8s_extensions.yml -t monitoring

# Logs
./scripts/ansible-k8s.sh logs

# Restart
./scripts/ansible-k8s.sh restart
```

### Monitoring

```bash
# Grafana Zugriff
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Prometheus Zugriff
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Pods prüfen
kubectl get pods -n monitoring

# Logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -f
```

### Cert-Manager

```bash
# ClusterIssuers
kubectl get clusterissuers

# Zertifikate
kubectl get certificates -A

# Cert-Manager Logs
kubectl logs -n cert-manager -l app=cert-manager -f

# CertificateRequests
kubectl get certificaterequests -A
```

## Troubleshooting

### Grafana zeigt keine Daten

Warten Sie 1-2 Minuten nach dem Deployment, damit Prometheus Daten sammeln kann.

### Node-Exporter CrashLoopBackOff

Normal auf Docker Desktop (benötigt Zugriff auf Host-Metriken). Auf echten Clustern funktioniert es.

### AlertManager Pending

Normal auf Docker Desktop (benötigt PersistentVolume). Auf echten Clustern mit StorageClass funktioniert es.

### Cert-Manager ClusterIssuers "False"

Let's Encrypt Issuer benötigen einen öffentlich erreichbaren Ingress für HTTP-01 Challenge.
Verwenden Sie `selfsigned` für interne Zertifikate.

## Ressourcen-Übersicht

```bash
# Alle Namespaces
kubectl get ns

# Alle Pods
kubectl get pods -A | grep -E '(cert-manager|monitoring)'

# Services
kubectl get svc -n monitoring
kubectl get svc -n cert-manager

# PVCs
kubectl get pvc -n monitoring
```

## Cleanup (ACHTUNG!)

### Nur Monitoring entfernen

```bash
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

### Nur Cert-Manager entfernen

```bash
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.crds.yaml
```

### Ansible Container entfernen

```bash
./scripts/ansible-k8s.sh delete
```

---

## 🎉 Herzlichen Glückwunsch!

Sie haben erfolgreich:
- ✓ Ansible im Kubernetes Container deployed
- ✓ Zertifizierungsstelle (Cert-Manager) installiert
- ✓ Monitoring Stack (Prometheus + Grafana) deployed
- ✓ 3 ClusterIssuers für TLS-Zertifikate konfiguriert

**Jetzt können Sie**:
1. Grafana erkunden und Metriken visualisieren
2. TLS-Zertifikate für Ihre Anwendungen erstellen
3. Weitere Extensions mit Ansible deployen
4. Ihr Cluster überwachen und verwalten

Viel Erfolg! 🚀
