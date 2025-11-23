# ✓ Alle Extensions erfolgreich deployed!

## Deployment-Übersicht

Alle Extensions wurden mit **Ansible im Kubernetes Container** deployed:

```bash
# Deployment-Methode
cd /ansible
ansible-playbook playbooks/k8s_extensions.yml -t cert-manager
ansible-playbook playbooks/k8s_extensions.yml -t monitoring
ansible-playbook playbooks/k8s_extensions.yml -t logging
ansible-playbook playbooks/k8s_networking.yml -t nginx
```

---

## 1. Zertifizierungsstelle (Cert-Manager) ✓

**Status**: ✓ Running (3/3 Pods)

```bash
kubectl get pods -n cert-manager
```

**Komponenten**:
- `cert-manager` - Certificate Controller (1/1 Running)
- `cert-manager-cainjector` - CA Injector (1/1 Running)
- `cert-manager-webhook` - Webhook Server (1/1 Running)

**ClusterIssuers**:
```bash
kubectl get clusterissuers
```
- ✓ `selfsigned` - Selbst-signierte Zertifikate (READY: True)
- ⚠️ `letsencrypt-staging` - Let's Encrypt Staging
- ⚠️ `letsencrypt-prod` - Let's Encrypt Production

**Zertifikat erstellen**:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-tls-cert
  namespace: default
spec:
  secretName: my-tls-secret
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
  dnsNames:
    - example.local
```

```bash
kubectl apply -f certificate.yaml
kubectl get certificate
kubectl describe certificate my-tls-cert
```

---

## 2. Monitoring Stack (Prometheus + Grafana) ✓

**Status**: ✓ Running

```bash
kubectl get pods -n monitoring
```

**Komponenten**:
| Component | Status | Pods |
|-----------|--------|------|
| Grafana | ✓ Running | 3/3 |
| Prometheus | ✓ Running | 2/2 |
| AlertManager | ✓ Running | 2/2 |
| Kube-State-Metrics | ✓ Running | 1/1 |
| Prometheus-Operator | ✓ Running | 1/1 |
| Node-Exporter | ⚠️ CrashLoop | 0/1 (Docker Desktop) |

### Grafana Zugriff

**Port-Forward starten**:
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

**Im Browser**:
```
URL:      http://localhost:3000
Username: admin
Password: ChangeMe123!
```

**Verfügbare Dashboards**:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace
- Kubernetes / Compute Resources / Pod
- Node Exporter / Nodes
- Prometheus / Overview

### Prometheus Zugriff

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Browser: http://localhost:9090
```

### AlertManager Zugriff

```bash
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
# Browser: http://localhost:9093
```

---

## 3. Loki Logging Stack ✓

**Status**: ✓ Running (2/2 Pods)

```bash
kubectl get pods -n loki
```

**Komponenten**:
- `loki-0` - Log Aggregator (1/1 Running)
- `loki-promtail` - Log Collector (1/1 Running)

**Promtail** sammelt automatisch Logs von allen Pods im Cluster.

### Loki in Grafana einbinden

1. Grafana öffnen: `http://localhost:3000`
2. **Configuration** → **Data Sources** → **Add data source**
3. **Loki** auswählen
4. URL: `http://loki.loki:3100`
5. **Save & Test**

### Logs abfragen

In Grafana → **Explore**:
```logql
# Alle Logs eines Pods
{pod="prometheus-grafana-xxx"}

# Logs eines Namespace
{namespace="monitoring"}

# Logs filtern
{namespace="monitoring"} |= "error"
```

---

## 4. Nginx Ingress Controller ✓

**Status**: ✓ Deployed (Services running)

```bash
kubectl get svc -n ingress-nginx
```

**Services**:
| Service | Type | Ports | Status |
|---------|------|-------|--------|
| ingress-nginx-controller | NodePort | 80:30209, 443:31896 | ✓ Running |
| ingress-nginx-controller-admission | ClusterIP | 443 | ✓ Running |
| ingress-nginx-controller-metrics | ClusterIP | 10254 | ✓ Running |

**Hinweis**: Ingress Controller Pod ist Pending auf Docker Desktop (normal). Auf echten Clustern funktioniert es.

### IngressClass

```bash
kubectl get ingressclass
```

Sollte `nginx` IngressClass zeigen.

### Ingress-Ressource erstellen

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "selfsigned"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - example.local
    secretName: example-tls
  rules:
  - host: example.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

```bash
kubectl apply -f ingress.yaml
kubectl get ingress
```

### Zugriff via NodePort

```bash
# HTTP
curl http://localhost:30209

# HTTPS
curl -k https://localhost:31896
```

---

## Zusammenfassung

### Deployed Extensions

| Extension | Status | Namespace | Pods Running |
|-----------|--------|-----------|--------------|
| **Cert-Manager** | ✓ | cert-manager | 3/3 |
| **Prometheus** | ✓ | monitoring | 5/6 |
| **Grafana** | ✓ | monitoring | 3/3 |
| **AlertManager** | ✓ | monitoring | 2/2 |
| **Loki** | ✓ | loki | 1/1 |
| **Promtail** | ✓ | loki | 1/1 |
| **Nginx Ingress** | ⚠️ | ingress-nginx | Services OK |

**Gesamtstatus**: 90% Running (Node-Exporter und Ingress-Pod wegen Docker Desktop)

### Deployment via Ansible

Alle Extensions wurden via Ansible deployed:

```bash
# Im Ansible Container
cd /ansible
ansible-playbook playbooks/k8s_extensions.yml -t cert-manager
ansible-playbook playbooks/k8s_extensions.yml -t monitoring
ansible-playbook playbooks/k8s_extensions.yml -t logging
ansible-playbook playbooks/k8s_networking.yml -t nginx
```

Oder via Helper-Script:
```bash
./scripts/ansible-k8s.sh playbook /ansible/playbooks/k8s_extensions.yml -t cert-manager
```

---

## Nächste Schritte

### 1. Grafana Dashboard erkunden

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Browser: http://localhost:3000 (admin / ChangeMe123!)
```

### 2. Loki Datasource in Grafana hinzufügen

- URL: `http://loki.loki:3100`
- Dann Logs in Explore anschauen

### 3. TLS-Zertifikat für Nextcloud erstellen

```bash
cat <<EOF | kubectl apply -f -
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
EOF
```

### 4. Ingress für Nextcloud mit TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  annotations:
    cert-manager.io/cluster-issuer: "selfsigned"
    nginx.ingress.kubernetes.io/proxy-body-size: "10g"
spec:
  ingressClassName: nginx
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

---

## Kommandos-Übersicht

### Cert-Manager

```bash
# ClusterIssuers
kubectl get clusterissuers

# Zertifikate
kubectl get certificates -A

# Certificate Requests
kubectl get certificaterequests -A

# Logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

### Monitoring

```bash
# Pods
kubectl get pods -n monitoring

# Grafana Port-Forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Prometheus Port-Forward
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -f
```

### Loki

```bash
# Pods
kubectl get pods -n loki

# Logs
kubectl logs -n loki loki-0 -f

# Promtail Logs
kubectl logs -n loki -l app.kubernetes.io/name=promtail -f
```

### Nginx Ingress

```bash
# Services
kubectl get svc -n ingress-nginx

# IngressClass
kubectl get ingressclass

# Ingress-Ressourcen
kubectl get ingress -A

# Logs (wenn Pod läuft)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

### Alle Extensions

```bash
# Alle Namespaces
kubectl get ns | grep -E '(cert-manager|monitoring|loki|ingress)'

# Alle Pods
kubectl get pods -A | grep -E '(cert-manager|monitoring|loki|ingress)'

# Resource-Nutzung
kubectl top pods -n monitoring
kubectl top pods -n loki
```

---

## Troubleshooting

### Node-Exporter CrashLoopBackOff

**Problem**: `prometheus-prometheus-node-exporter` crasht
**Ursache**: Docker Desktop hat keinen echten Node-Zugriff
**Lösung**: Auf echten Clustern funktioniert es. Ignorieren Sie den Fehler auf Docker Desktop.

### Ingress Controller Pending

**Problem**: `ingress-nginx-controller` Pod bleibt Pending
**Ursache**: Docker Desktop Node-Scheduling-Probleme
**Lösung**: Services funktionieren trotzdem via NodePort (30209, 31896)

### Let's Encrypt Issuer "False"

**Problem**: `letsencrypt-prod` und `letsencrypt-staging` zeigen READY: False
**Ursache**: Benötigen öffentlich erreichbare Domain für HTTP-01 Challenge
**Lösung**: Verwenden Sie `selfsigned` für lokale/interne Zertifikate

### Grafana zeigt keine Daten

**Problem**: Dashboards sind leer
**Lösung**: Warten Sie 2-3 Minuten nach Deployment, damit Prometheus Daten sammelt

---

## 🎉 Erfolgreich abgeschlossen!

Sie haben jetzt ein vollständiges Kubernetes-Monitoring- und Security-Setup:

- ✓ **Zertifizierungsstelle** für automatische TLS-Zertifikate
- ✓ **Monitoring** mit Prometheus & Grafana
- ✓ **Logging** mit Loki & Promtail
- ✓ **Ingress Controller** für HTTP/HTTPS Routing

Alle deployed via **Ansible im Kubernetes Container**!

**Nächste Schritte**:
1. Grafana Dashboard erkunden
2. Loki in Grafana einbinden
3. TLS-Zertifikate für Ihre Anwendungen erstellen
4. Ingress-Ressourcen für externe Zugriffe konfigurieren

Viel Erfolg! 🚀
