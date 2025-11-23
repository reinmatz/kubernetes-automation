# Grafana Setup Guide - Zertifikats-Monitoring

## ✓ Browser geöffnet!

### Zugriff auf die Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Nextcloud** | https://localhost:31896 | (Admin erstellen beim ersten Zugriff) |
| **Grafana** | http://localhost:3000 | admin / ChangeMe123! |

---

## Nextcloud - Erster Zugriff

### 1. Browser-Zertifikats-Warnung akzeptieren

Da wir ein selbst-signiertes Zertifikat verwenden, zeigt der Browser eine Warnung:

**Chrome/Edge**:
1. Klicken Sie auf "Erweitert"
2. Klicken Sie auf "Weiter zu localhost (unsicher)"

**Firefox**:
1. Klicken Sie auf "Erweitert"
2. Klicken Sie auf "Risiko akzeptieren und fortfahren"

**Safari**:
1. Klicken Sie auf "Details anzeigen"
2. Klicken Sie auf "Diese Website besuchen"

### 2. Admin-Benutzer erstellen

Beim ersten Zugriff sehen Sie das Setup:

1. **Admin-Benutzername** eingeben (z.B. `admin`)
2. **Passwort** eingeben (sicheres Passwort!)
3. **Datenbank** ist bereits konfiguriert (MariaDB)
4. Klicken Sie auf "Installation abschließen"

**Hinweis**: Die Datenbank-Verbindung ist bereits über Secrets konfiguriert!

### 3. Trusted Domain konfigurieren

Falls Sie eine Fehlermeldung sehen:

```bash
kubectl exec -n nextcloud-prod deployment/nextcloud -- \
  su -s /bin/bash www-data -c \
  "php occ config:system:set trusted_domains 1 --value=localhost"
```

---

## Grafana - Dashboard Setup

### 1. Login

1. Browser öffnet automatisch: **http://localhost:3000**
2. Login:
   - **Username**: `admin`
   - **Password**: `ChangeMe123!`

### 2. Passwort ändern (empfohlen)

1. Klicken Sie auf "Skip" oder ändern Sie das Passwort
2. Klicken Sie links auf das Grafana-Logo

### 3. Certificate Manager Dashboard importieren

#### Option A: Manueller Import (empfohlen)

1. **Dashboards** → **Import** (links im Menü)
2. **Upload JSON file** klicken
3. Datei auswählen: `grafana-certificate-dashboard.json`
4. **Import** klicken

#### Option B: Dashboard-ID verwenden

Alternativ können Sie ein vorgefertigtes Dashboard verwenden:

1. **Dashboards** → **Import**
2. Dashboard-ID eingeben: **11001**
3. **Load** klicken
4. **Prometheus** als Data Source auswählen
5. **Import** klicken

### 4. Dashboard anpassen

Nach dem Import sehen Sie:

- **Certificate Expiry Time** - Ablaufzeit aller Zertifikate
- **Certificate Ready Status** - Status (Ready/Not Ready)
- **Certificates Expiring Soon** - Zertifikate die in <30 Tagen ablaufen
- **Certificate Renewal Time** - Geplante Erneuerungszeiten
- **All Certificates Overview** - Übersicht aller Zertifikate

---

## Monitoring-Übersicht in Grafana

### Vorinstallierte Dashboards

Grafana enthält bereits viele Kubernetes-Dashboards:

1. **Dashboards** → **Browse**
2. Verfügbare Dashboards:
   - **Kubernetes / Compute Resources / Cluster**
   - **Kubernetes / Compute Resources / Namespace**
   - **Kubernetes / Compute Resources / Pod**
   - **Node Exporter / Nodes**
   - **Prometheus / Overview**

### Nextcloud-Monitoring hinzufügen

#### ServiceMonitor erstellen

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  labels:
    app: nextcloud
spec:
  selector:
    matchLabels:
      app: nextcloud
  endpoints:
  - port: http
    path: /ocs/v2.php/apps/serverinfo/api/v1/info
    params:
      format: ["json"]
    interval: 30s
```

```bash
kubectl apply -f nextcloud-servicemonitor.yaml
```

---

## Alerts konfigurieren

### 1. Zertifikats-Alert erstellen

1. **Alerting** → **Alert rules** → **New alert rule**

2. **Query**:
   ```promql
   (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 7
   ```

3. **Conditions**:
   - Alert condition: `WHEN last() OF query(A) IS BELOW 7`

4. **Details**:
   - **Alert name**: Certificate expiring soon
   - **Folder**: General
   - **Evaluation group**: certificate-alerts
   - **Evaluation interval**: 5m

5. **Annotations**:
   - **Summary**: Certificate {{$labels.name}} expires in {{ $value }} days
   - **Description**: The certificate {{$labels.name}} in namespace {{$labels.namespace}} will expire soon

6. **Save and exit**

### 2. Alert-Benachrichtigung einrichten

1. **Alerting** → **Contact points** → **New contact point**

2. Wählen Sie:
   - **Email** (SMTP konfigurieren)
   - **Slack** (Webhook URL)
   - **Discord** (Webhook URL)
   - Oder andere...

3. **Save contact point**

---

## Prometheus Metriken erkunden

### 1. Explore öffnen

1. Klicken Sie auf **Explore** (Kompass-Symbol links)
2. Wählen Sie **Prometheus** als Data Source

### 2. Wichtige Cert-Manager Metriken

```promql
# Zertifikats-Ablaufzeit in Tagen
(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400

# Zertifikats-Status (1 = Ready, 0 = Not Ready)
certmanager_certificate_ready_status

# Erneuerungs-Zeitstempel
certmanager_certificate_renewal_timestamp_seconds

# Alle Nextcloud-Zertifikate
certmanager_certificate_expiration_timestamp_seconds{namespace="nextcloud-prod"}
```

### 3. Kubernetes Cluster Metriken

```promql
# CPU-Auslastung pro Namespace
sum(rate(container_cpu_usage_seconds_total{namespace="nextcloud-prod"}[5m])) by (pod)

# Memory-Nutzung pro Pod
container_memory_usage_bytes{namespace="nextcloud-prod"}

# Pod-Status
kube_pod_status_phase{namespace="nextcloud-prod"}
```

---

## Loki - Logs in Grafana

### 1. Loki Data Source hinzufügen

1. **Configuration** (Zahnrad-Symbol) → **Data Sources**
2. **Add data source**
3. **Loki** auswählen
4. **URL** eingeben: `http://loki.loki:3100`
5. **Save & Test**

### 2. Logs anzeigen

1. **Explore** → **Loki** wählen
2. Log-Queries:

```logql
# Alle Nextcloud Logs
{namespace="nextcloud-prod"}

# Fehler in Nextcloud
{namespace="nextcloud-prod"} |= "error"

# Bestimmter Pod
{pod="nextcloud-xxx"}

# Letzte 5 Minuten
{namespace="nextcloud-prod"} [5m]
```

### 3. Log-Dashboard erstellen

1. **Dashboards** → **New Dashboard** → **Add visualization**
2. Data Source: **Loki**
3. Query: `{namespace="nextcloud-prod"}`
4. Visualization: **Logs**
5. **Save dashboard**

---

## Nützliche Grafana-Tipps

### Zeitbereich ändern

Oben rechts: Klicken Sie auf die Zeit (z.B. "Last 6 hours")
- Last 15 minutes
- Last 1 hour
- Last 6 hours
- Last 24 hours
- Last 7 days
- Custom range

### Auto-Refresh aktivieren

Oben rechts: Klicken Sie auf das Refresh-Symbol
- 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h

### Dashboard favorisieren

Klicken Sie auf den Stern ⭐ oben im Dashboard

### Variablen verwenden

Für dynamische Dashboards:
1. **Dashboard settings** (Zahnrad) → **Variables**
2. **Add variable**
3. Type: **Query**
4. Query: `label_values(certmanager_certificate_expiration_timestamp_seconds, namespace)`

---

## Troubleshooting

### Grafana zeigt keine Daten

**Problem**: Dashboards sind leer

**Lösung**:
1. Warten Sie 2-3 Minuten nach Deployment
2. Prüfen Sie Prometheus:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```
   Browser: http://localhost:9090
3. Prüfen Sie Targets: **Status** → **Targets**
4. Suchen Sie nach `cert-manager`

### Cert-Manager Metriken fehlen

**Problem**: Keine `certmanager_*` Metriken

**Lösung**:
```bash
# ServiceMonitor prüfen
kubectl get servicemonitor -n cert-manager

# Cert-Manager Logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Metrics Endpoint prüfen
kubectl port-forward -n cert-manager svc/cert-manager 9402:9402
curl http://localhost:9402/metrics | grep certmanager
```

### Loki Data Source Fehler

**Problem**: "Error calling resource" beim Testen

**Lösung**:
```bash
# Loki Status prüfen
kubectl get pods -n loki

# Port-Forward testen
kubectl port-forward -n loki svc/loki 3100:3100
curl http://localhost:3100/ready
```

---

## Port-Forward Kommandos

Falls die Browser-Fenster geschlossen wurden:

```bash
# Nextcloud HTTPS (via Ingress NodePort)
# Browser: https://localhost:31896

# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Browser: http://localhost:3000

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Browser: http://localhost:9090

# Loki
kubectl port-forward -n loki svc/loki 3100:3100
# Browser: http://localhost:3100
```

---

## Screenshot-Tipps

### Dashboard exportieren

1. **Share dashboard** (oben rechts)
2. **Export** → **Save to file**
3. JSON wird heruntergeladen

### Dashboard als PNG

1. **Share dashboard** → **Snapshot**
2. **Publish to snapshot.raintank.io**
3. Oder: Screenshot mit Browser-Tools (Cmd+Shift+4 auf Mac)

---

## 🎯 Quick Start Checklist

- [ ] Nextcloud geöffnet (https://localhost:31896)
- [ ] Browser-Warnung akzeptiert
- [ ] Admin-Benutzer erstellt
- [ ] Grafana geöffnet (http://localhost:3000)
- [ ] Mit admin/ChangeMe123! angemeldet
- [ ] Certificate Dashboard importiert
- [ ] Loki Data Source hinzugefügt
- [ ] Zertifikats-Alert konfiguriert

---

## Nächste Schritte

1. **Nextcloud verwenden**: Dateien hochladen, Benutzer erstellen
2. **Dashboards erkunden**: Alle vorinstallierten Kubernetes-Dashboards ansehen
3. **Alerts testen**: Zertifikats-Ablauf-Alert simulieren
4. **Logs analysieren**: Nextcloud-Logs in Loki durchsuchen
5. **Monitoring erweitern**: Weitere ServiceMonitors erstellen

Viel Spaß mit Ihrem überwachten Kubernetes-Cluster! 📊🚀
