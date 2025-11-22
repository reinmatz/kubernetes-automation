# Nextcloud Production Manifests

Kubernetes YAML-Manifeste für eine produktionsreife Nextcloud-Installation mit MariaDB.

## Übersicht

Diese Manifeste implementieren eine vollständige Nextcloud-Umgebung mit:

- ✅ **Hochverfügbarkeit** (3 Nextcloud-Replicas)
- ✅ **Persistenter Storage** (MariaDB + Nextcloud-Dateien)
- ✅ **Security** (Network Policies, Secrets)
- ✅ **TLS/HTTPS** (Cert-Manager, Let's Encrypt)
- ✅ **Monitoring** (Prometheus, ServiceMonitor, Alerts)
- ✅ **Backups** (CronJob, tägliche Datenbank-Backups)
- ✅ **Autoscaling** (HPA, PDB)

## Dateien-Übersicht

| Datei | Beschreibung | Stufe |
|-------|--------------|-------|
| `00-namespace.yaml` | Namespace für Nextcloud-Ressourcen | 1 |
| `01-secrets.yaml` | Secrets-Template (⚠️ nicht für Prod!) | 1 |
| `02-storage.yaml` | PVCs für Nextcloud-Daten + Backups | 1 |
| `03-mariadb-statefulset.yaml` | MariaDB StatefulSet mit Probes | 2 |
| `04-mariadb-service.yaml` | MariaDB Service (Headless) | 1 |
| `05-nextcloud-deployment.yaml` | Nextcloud HA-Deployment (3 Replicas) | 2 |
| `06-nextcloud-service.yaml` | Nextcloud LoadBalancer Service | 2 |
| `07-ingress.yaml` | Ingress mit TLS (Nginx) | 3 |
| `08-certificate.yaml` | Cert-Manager Certificate (Let's Encrypt) | 3 |
| `09-network-policies.yaml` | Network Policies (Pod-Isolation) | 2 |
| `10-monitoring.yaml` | ServiceMonitor, PrometheusRule, Alerts | 3 |
| `11-backup-cronjob.yaml` | Automatische Datenbank-Backups | 3 |
| `12-hpa.yaml` | Horizontal Pod Autoscaler + PDB | 3 |

**Stufen:**
- **Stufe 1**: Basis-Funktionalität
- **Stufe 2**: Production-Ready
- **Stufe 3**: Enterprise (Monitoring, TLS, Backups)

## Voraussetzungen

### Erforderlich (alle Stufen)

- Kubernetes-Cluster (v1.24+)
- kubectl konfiguriert
- StorageClass verfügbar (mit RWX-Support für Nextcloud-Daten!)

```bash
# Cluster-Status prüfen
kubectl cluster-info
kubectl get storageclasses
```

### Zusätzlich für Stufe 2

- Nginx Ingress Controller (für LoadBalancer Service)
- MetalLB oder Cloud-Provider LoadBalancer

```bash
kubectl get pods -n ingress-nginx
kubectl get ingressclasses
```

### Zusätzlich für Stufe 3

- Cert-Manager (für TLS-Zertifikate)
- Prometheus Operator (für Monitoring)

```bash
kubectl get pods -n cert-manager
kubectl get pods -n monitoring
kubectl get clusterissuers
```

## Schnellstart

### 1. Secrets erstellen (WICHTIG!)

**⚠️ NIEMALS `01-secrets.yaml` direkt deployen!**

Stattdessen:

```bash
# Sicheres Passwort generieren
read -s -p 'Datenbankpasswort: ' DB_PASSWORD
echo

# Secret erstellen
kubectl create namespace nextcloud-prod

kubectl create secret generic nextcloud-db \
  --namespace nextcloud-prod \
  --from-literal=MYSQL_ROOT_PASSWORD=$DB_PASSWORD \
  --from-literal=MYSQL_PASSWORD=$DB_PASSWORD \
  --from-literal=MYSQL_DATABASE=nextcloud \
  --from-literal=MYSQL_USER=nextcloud \
  --from-literal=MYSQL_HOST=mariadb
```

### 2. Manifeste anpassen

**Wichtige Anpassungen:**

```bash
# Domain in folgenden Dateien ändern:
# - 05-nextcloud-deployment.yaml (NEXTCLOUD_TRUSTED_DOMAINS)
# - 07-ingress.yaml (host)
# - 08-certificate.yaml (dnsNames, email)

# IP-Adressen anpassen (falls MetalLB verwendet):
# - 06-nextcloud-service.yaml (loadBalancerIP)

# Storage-Größen anpassen:
# - 02-storage.yaml (storage requests)
```

### 3. Deployment durchführen

#### Option A: Stufe für Stufe (empfohlen für Lernen)

```bash
# Stufe 1: Basis
kubectl apply -f 00-namespace.yaml
# Secret erstellen (siehe oben)
kubectl apply -f 02-storage.yaml
kubectl apply -f 03-mariadb-statefulset.yaml
kubectl apply -f 04-mariadb-service.yaml
kubectl apply -f 05-nextcloud-deployment.yaml
kubectl apply -f 06-nextcloud-service.yaml

# Warten bis Pods laufen
kubectl get pods -n nextcloud-prod -w

# Stufe 2: Production-Ready
kubectl apply -f 09-network-policies.yaml
kubectl apply -f 12-hpa.yaml

# Stufe 3: Enterprise
kubectl apply -f 08-certificate.yaml
kubectl apply -f 07-ingress.yaml
kubectl apply -f 10-monitoring.yaml
kubectl apply -f 11-backup-cronjob.yaml
```

#### Option B: Alles auf einmal (für Produktion)

```bash
# Secrets erstellen (siehe oben)

# Alle Manifeste deployen
kubectl apply -f .

# Status prüfen
kubectl get all,pvc,secrets,ingress,networkpolicies -n nextcloud-prod
```

### 4. Zugriff testen

#### LoadBalancer (Stufe 2)

```bash
# Externe IP prüfen
kubectl get service nextcloud -n nextcloud-prod

# Zugriff testen
curl http://<EXTERNAL-IP>
```

#### Ingress mit TLS (Stufe 3)

```bash
# Certificate-Status prüfen
kubectl get certificate -n nextcloud-prod

# DNS konfigurieren (oder /etc/hosts)
echo "<INGRESS-IP> nextcloud.yourdomain.com" | sudo tee -a /etc/hosts

# Zugriff testen
curl https://nextcloud.yourdomain.com
```

### 5. Nextcloud konfigurieren

```bash
# Port-Forwarding (falls kein Ingress)
kubectl port-forward -n nextcloud-prod service/nextcloud 8080:80

# Browser öffnen
# http://localhost:8080 (oder https://nextcloud.yourdomain.com)

# Nextcloud Setup-Assistent:
# - Admin-User erstellen
# - Apps installieren
```

## Wartung

### Backups prüfen

```bash
# CronJob-Status
kubectl get cronjobs -n nextcloud-prod

# Letzte Backup-Jobs
kubectl get jobs -n nextcloud-prod

# Backup-Dateien anzeigen
kubectl exec -n nextcloud-prod deployment/nextcloud -- ls -lh /backup/

# Manuelles Backup triggern
kubectl create job --from=cronjob/mariadb-backup manual-backup-$(date +%Y%m%d) -n nextcloud-prod
```

### Updates durchführen

```bash
# Nextcloud-Image aktualisieren
kubectl set image deployment/nextcloud nextcloud=docker.io/library/nextcloud:29-apache -n nextcloud-prod

# Rollout beobachten
kubectl rollout status deployment/nextcloud -n nextcloud-prod

# Bei Problemen: Rollback
kubectl rollout undo deployment/nextcloud -n nextcloud-prod
```

### Monitoring

```bash
# Prometheus-Targets prüfen
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Grafana-Dashboard öffnen
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Alerts prüfen
kubectl get prometheusrules -n nextcloud-prod
```

## Troubleshooting

### Pods starten nicht

```bash
# Logs prüfen
kubectl logs -n nextcloud-prod -l app=nextcloud --tail=100
kubectl logs -n nextcloud-prod -l app=mariadb --tail=100

# Events prüfen
kubectl get events -n nextcloud-prod --sort-by='.lastTimestamp'

# Pod-Details
kubectl describe pod -n nextcloud-prod -l app=nextcloud
```

### Datenbank-Verbindung schlägt fehl

```bash
# DNS-Auflösung testen
kubectl exec -n nextcloud-prod deployment/nextcloud -- nslookup mariadb

# Netzwerk-Verbindung testen
kubectl exec -n nextcloud-prod deployment/nextcloud -- nc -zv mariadb 3306

# Network Policies prüfen
kubectl get networkpolicies -n nextcloud-prod
kubectl describe networkpolicy nextcloud-allow-web -n nextcloud-prod
```

### TLS-Zertifikat wird nicht ausgestellt

```bash
# Certificate-Status
kubectl get certificate -n nextcloud-prod
kubectl describe certificate nextcloud-tls -n nextcloud-prod

# Cert-Manager Logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Challenge prüfen
kubectl get challenges -n nextcloud-prod
kubectl describe challenges -n nextcloud-prod
```

### Backup schlägt fehl

```bash
# CronJob-Logs
kubectl logs -n nextcloud-prod job/mariadb-backup-<timestamp>

# PVC-Status prüfen
kubectl get pvc backup-storage -n nextcloud-prod
kubectl describe pvc backup-storage -n nextcloud-prod

# Manuell testen
kubectl exec -n nextcloud-prod mariadb-0 -- mysqldump -u root -p<PASSWORD> --all-databases
```

## Sicherheitshinweise

### Secrets

⚠️ **NIEMALS Secrets in Git committen!**

- Verwenden Sie `kubectl create secret` (siehe oben)
- Oder: Sealed Secrets / External Secrets Operator
- Oder: HashiCorp Vault

### Network Policies

Die Manifeste implementieren "Deny by Default":
- MariaDB akzeptiert nur Verbindungen von Nextcloud
- Nextcloud kann nur zu MariaDB + Internet
- Alle anderen Verbindungen blockiert

### Updates

- Regelmäßig Updates einspielen (Nextcloud + MariaDB)
- Security-Patches zeitnah deployen
- Vor Updates: Backup erstellen!

## Weiterführende Dokumentation

Siehe: `../../Nextcloud_Production_Installation_Guide.md`

Enthält:
- Detaillierte Schritt-für-Schritt-Anleitungen
- Erklärungen zu allen Konzepten
- Troubleshooting-Guide
- Best Practices
- Performance-Tuning

## Lizenz

MIT License

## Support

Bei Fragen oder Problemen:
1. Dokumentation lesen (`Nextcloud_Production_Installation_Guide.md`)
2. Logs prüfen (`kubectl logs`)
3. Events prüfen (`kubectl get events`)
4. Issues erstellen im Projekt-Repository
