# Nextcloud Deployment Scripts

Automatisierte Skripte für die Nextcloud-Installation auf Kubernetes.

## Verfügbare Skripte

| Skript | Beschreibung | Stufe |
|--------|--------------|-------|
| `deploy-nextcloud-basic.sh` | Basis-Installation (schnell, einfach) | 1 |
| `deploy-nextcloud-production.sh` | Vollständige Production-Installation | 1+2+3 |
| `backup-nextcloud.sh` | Vollständiges Backup (DB + Files + Manifests) | - |

## Verwendung

### 1. Basis-Installation (Stufe 1)

Schnelle Installation für Test/Dev-Umgebungen:

```bash
cd scripts/
./deploy-nextcloud-basic.sh
```

**Features:**
- Nextcloud + MariaDB
- Persistenter Storage
- LoadBalancer Service
- ~5 Minuten Deployment-Zeit

**Zugriff:**
```bash
# Via LoadBalancer IP
kubectl get service nextcloud -n nextcloud-prod

# Oder via Port-Forwarding
kubectl port-forward -n nextcloud-prod service/nextcloud 8080:80
# Browser: http://localhost:8080
```

---

### 2. Production-Installation (Alle Stufen)

Vollständige Installation mit allen Production-Features:

```bash
cd scripts/

# Domain und E-Mail konfigurieren
export NEXTCLOUD_DOMAIN=nextcloud.example.com
export LETSENCRYPT_EMAIL=admin@example.com

# Deployment starten
./deploy-nextcloud-production.sh
```

**Features:**
- Alle Features von Stufe 1
- 3 Nextcloud-Replicas (HA)
- StatefulSet für MariaDB
- Resource Limits & Probes
- Network Policies (Security)
- TLS/HTTPS mit Let's Encrypt
- Ingress (Nginx)
- Prometheus Monitoring
- Automatische Backups
- Horizontal Pod Autoscaler
- ~10-15 Minuten Deployment-Zeit

**Environment-Variablen:**

| Variable | Beschreibung | Standard |
|----------|--------------|----------|
| `NEXTCLOUD_DOMAIN` | Domain für Nextcloud | `nextcloud.yourdomain.com` |
| `LETSENCRYPT_EMAIL` | E-Mail für Let's Encrypt | `admin@example.com` |

**Beispiel:**
```bash
export NEXTCLOUD_DOMAIN=cloud.mycompany.com
export LETSENCRYPT_EMAIL=it@mycompany.com
./deploy-nextcloud-production.sh
```

**Zugriff:**
```bash
# Via HTTPS (nach DNS-Konfiguration)
https://nextcloud.example.com

# DNS konfigurieren:
# 1. Ingress-IP herausfinden:
kubectl get ingress nextcloud -n nextcloud-prod

# 2. DNS-Eintrag erstellen:
# nextcloud.example.com → <INGRESS-IP>

# Oder /etc/hosts für Testing:
echo "<INGRESS-IP> nextcloud.example.com" | sudo tee -a /etc/hosts
```

---

### 3. Backup erstellen

Vollständiges Backup von Datenbank, Dateien und Manifesten:

```bash
cd scripts/
./backup-nextcloud.sh [backup-directory]
```

**Standard-Verzeichnis:** `./backups/nextcloud-YYYYMMDD-HHMMSS/`

**Backup beinhaltet:**
- Kubernetes-Manifeste (alle Ressourcen)
- Secrets (⚠️ sicher aufbewahren!)
- MariaDB-Dump (komprimiert)
- VolumeSnapshot (wenn unterstützt)
- Backup-Manifest (Info-Datei)

**Beispiel:**
```bash
# Standard-Backup
./backup-nextcloud.sh

# Custom Backup-Verzeichnis
./backup-nextcloud.sh /mnt/backups/kubernetes

# Backup-Größe prüfen
du -sh backups/nextcloud-*
```

**Während Backup:**
- Nextcloud wird in Maintenance Mode versetzt
- Datenbank-Konsistenz wird sichergestellt
- Maintenance Mode wird automatisch deaktiviert

**⚠️ Sicherheitshinweis:**
Backups enthalten sensible Daten!
- `secrets.yaml`: Datenbank-Passwörter
- `database.sql.gz`: Alle User-Daten
- Verschlüsselt speichern
- Off-site Backup (3-2-1 Regel)

---

## Voraussetzungen

### Für alle Skripte

- kubectl (v1.24+) installiert
- Zugriff auf Kubernetes-Cluster
- StorageClass verfügbar (mit RWX-Support!)

```bash
kubectl cluster-info
kubectl get storageclasses
```

### Zusätzlich für Production-Skript

**Erforderlich:**
- Nginx Ingress Controller
- Cert-Manager
- MetalLB oder Cloud-Provider LoadBalancer

**Optional (aber empfohlen):**
- Prometheus Operator (für Monitoring)
- Metrics Server (für HPA)

**Prüfen:**
```bash
# Nginx Ingress
kubectl get ingressclass nginx

# Cert-Manager
kubectl get namespace cert-manager

# Prometheus Operator
kubectl get crd servicemonitors.monitoring.coreos.com

# Metrics Server
kubectl get apiservice v1beta1.metrics.k8s.io
```

---

## Troubleshooting

### Script-Fehler

```bash
# Debug-Modus aktivieren
bash -x ./deploy-nextcloud-production.sh

# Logs prüfen
kubectl logs -n nextcloud-prod -l app=nextcloud --tail=100
kubectl get events -n nextcloud-prod --sort-by='.lastTimestamp'
```

### Deployment hängt

```bash
# Pods-Status prüfen
kubectl get pods -n nextcloud-prod -w

# Pod-Details
kubectl describe pod -n nextcloud-prod -l app=nextcloud

# Logs
kubectl logs -n nextcloud-prod deployment/nextcloud -f
```

### Secrets-Fehler

```bash
# Secrets neu erstellen
kubectl delete secret nextcloud-db -n nextcloud-prod

# Deployment neu starten
./deploy-nextcloud-basic.sh
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
```

### Backup schlägt fehl

```bash
# Maintenance Mode manuell deaktivieren
NEXTCLOUD_POD=$(kubectl get pods -n nextcloud-prod -l app=nextcloud -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n nextcloud-prod $NEXTCLOUD_POD -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"

# Backup mit Debug
bash -x ./backup-nextcloud.sh
```

---

## Restore (Disaster Recovery)

Siehe: `../Nextcloud_Production_Installation_Guide.md` - Kapitel 7.2

**Kurzanleitung:**

```bash
# 1. Namespace erstellen
kubectl create namespace nextcloud-prod

# 2. Secrets wiederherstellen
kubectl apply -f backups/nextcloud-YYYYMMDD-HHMMSS/secrets.yaml

# 3. PVCs erstellen
kubectl apply -f ../manifests/nextcloud/02-storage.yaml

# 4. Datenbank wiederherstellen
# (siehe detaillierte Anleitung im Guide)

# 5. Manifeste deployen
kubectl apply -f backups/nextcloud-YYYYMMDD-HHMMSS/kubernetes-manifests.yaml
```

---

## Wartung

### Updates

```bash
# Nextcloud-Version aktualisieren
kubectl set image deployment/nextcloud nextcloud=docker.io/library/nextcloud:29-apache -n nextcloud-prod

# Rollout beobachten
kubectl rollout status deployment/nextcloud -n nextcloud-prod

# Bei Problemen: Rollback
kubectl rollout undo deployment/nextcloud -n nextcloud-prod
```

### Skalierung

```bash
# Mehr Replicas (manuell)
kubectl scale deployment/nextcloud --replicas=5 -n nextcloud-prod

# HPA-Status (automatische Skalierung)
kubectl get hpa nextcloud -n nextcloud-prod
```

### Monitoring

```bash
# Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

---

## Best Practices

### Vor Production-Deployment

1. ✅ **Backup-Strategie testen**
   ```bash
   ./backup-nextcloud.sh
   # Restore in Test-Namespace testen
   ```

2. ✅ **DNS vorbereiten**
   - Domain registrieren
   - DNS-Eintrag vorbereiten
   - Let's Encrypt Rate Limits beachten

3. ✅ **Storage konfigurieren**
   - RWX-fähige StorageClass (NFS, CephFS)
   - Ausreichend Speicher (>100GB empfohlen)

4. ✅ **Secrets extern verwalten**
   - Sealed Secrets
   - External Secrets Operator
   - HashiCorp Vault

### Nach Deployment

1. ✅ **Trusted Domains konfigurieren**
   ```bash
   kubectl exec -n nextcloud-prod deployment/nextcloud -- \
     su -s /bin/bash www-data -c "php occ config:system:set trusted_domains 1 --value=nextcloud.example.com"
   ```

2. ✅ **Monitoring einrichten**
   - Grafana-Dashboard importieren
   - Alerts konfigurieren
   - Uptime-Monitoring (externes Tool)

3. ✅ **Backups testen**
   - Automatische Backups prüfen (CronJob)
   - Restore testen
   - Off-site Backups konfigurieren

4. ✅ **Performance-Tuning**
   - Redis für Caching installieren
   - APCu aktivieren
   - PHP Memory Limit erhöhen

---

## Support

Bei Problemen:

1. **Dokumentation lesen:** `../Nextcloud_Production_Installation_Guide.md`
2. **Logs prüfen:** `kubectl logs -n nextcloud-prod`
3. **Events prüfen:** `kubectl get events -n nextcloud-prod`
4. **Issues erstellen:** GitHub Repository

---

## Lizenz

MIT License
