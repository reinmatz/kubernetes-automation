# Nextcloud Production Installation auf Kubernetes - Kompletter Leitfaden

## Inhaltsverzeichnis

1. [Einführung](#1-einführung)
2. [Voraussetzungen](#2-voraussetzungen)
3. [Architektur-Übersicht](#3-architektur-übersicht)
4. [Stufe 1: Basis-Installation](#4-stufe-1-basis-installation)
5. [Stufe 2: Production-Ready Features](#5-stufe-2-production-ready-features)
6. [Stufe 3: Monitoring & HA-Integration](#6-stufe-3-monitoring--ha-integration)
7. [Backup & Restore](#7-backup--restore)
8. [Troubleshooting](#8-troubleshooting)
9. [Wartung & Updates](#9-wartung--updates)
10. [Best Practices](#10-best-practices)

---

## 1. Einführung

### Was ist dieses Projekt?

Dieses Dokument führt Sie Schritt für Schritt durch die Installation einer **produktionsreifen Nextcloud-Instanz** auf Kubernetes. Nextcloud ist eine Open-Source-Plattform für Cloud-Speicher, Dateifreigabe und Kollaboration - ähnlich wie Dropbox oder Google Drive, aber selbst gehostet.

### Warum Kubernetes für Nextcloud?

- ✅ **Hochverfügbarkeit**: Keine Downtime bei Server-Ausfällen
- ✅ **Skalierbarkeit**: Automatische Anpassung an Last
- ✅ **Automatisierung**: Self-Healing, automatische Backups
- ✅ **Isolation**: Saubere Trennung von anderen Anwendungen

### Progressive Lern-Struktur

Dieses Dokument ist in **3 Stufen** aufgebaut:

1. **Stufe 1 - Basis**: Funktionierende Nextcloud + MariaDB (Lernfokus)
2. **Stufe 2 - Production**: Hochverfügbarkeit, Security, Resource Management
3. **Stufe 3 - Enterprise**: Monitoring, Backup, Integration mit HA-Cluster

Jede Stufe baut auf der vorherigen auf. Sie können bei Stufe 1 stoppen (für Testsysteme) oder alle Stufen durchlaufen (für Produktionssysteme).

---

## 2. Voraussetzungen

### Was Sie brauchen

#### Kubernetes-Cluster
- Funktionierende Kubernetes-Installation (v1.24+)
- Zugriff via `kubectl` konfiguriert
- StorageClass für persistente Volumes verfügbar

```bash
# Cluster-Status prüfen
kubectl cluster-info
kubectl get nodes

# StorageClass prüfen (mindestens eine sollte verfügbar sein)
kubectl get storageclasses
```

**Erwartetes Ergebnis:**
```
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
local-path (default) rancher.io/local-path   Delete          WaitForFirstConsumer
```

#### Software-Voraussetzungen
- `kubectl` (v1.24+) installiert
- `openssl` für Passwort-Generierung
- Optional: `oc` (OpenShift CLI) für erweiterte Funktionen
- Optional: `helm` (v3) für Helm-Charts

```bash
# Versionen prüfen
kubectl version --client
openssl version
```

#### Netzwerk-Anforderungen (je nach Stufe)

**Stufe 1 (Basis):**
- Port-Forwarding für lokalen Zugriff ausreichend

**Stufe 2 (Production):**
- Ingress Controller installiert (z.B. Nginx Ingress)
- DNS-Eintrag oder `/etc/hosts` Eintrag

**Stufe 3 (Enterprise):**
- MetalLB oder externer Load Balancer
- Cert-Manager für TLS-Zertifikate
- Prometheus Operator für Monitoring

### Ressourcen-Planung

#### Minimum-Anforderungen (Stufe 1 - Test/Dev)
```
MariaDB:
  CPU: 500m
  Memory: 512Mi
  Storage: 5Gi

Nextcloud:
  CPU: 500m
  Memory: 512Mi
  Storage: 5Gi
```

#### Empfohlene Anforderungen (Stufe 2+3 - Production)
```
MariaDB (StatefulSet):
  CPU: 1000m
  Memory: 2Gi
  Storage: 20Gi

Nextcloud (3 Replicas):
  CPU: 1000m (pro Pod)
  Memory: 1Gi (pro Pod)
  Storage: 50Gi (shared)
```

---

## 3. Architektur-Übersicht

### Gesamtarchitektur (alle Stufen)

```
                    Internet / Lokales Netzwerk
                               ↓
    ┌──────────────────────────────────────────────────┐
    │              Stufe 3: Ingress (TLS)              │
    │         nextcloud.yourdomain.com (HTTPS)         │
    │                  Cert-Manager                     │
    └────────────────────┬─────────────────────────────┘
                         │
    ┌────────────────────┴─────────────────────────────┐
    │         Stufe 2: Load Balancer Service           │
    │              (MetalLB: externe IP)               │
    └────────────────────┬─────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
    ┌────▼─────────┐            ┌───────▼──────┐
    │  Nextcloud   │            │  Nextcloud   │
    │   Pod 1      │◄──────────►│   Pod 2      │
    │              │  Session   │              │
    │ Replica 1/3  │  Sharing   │ Replica 2/3  │
    └────┬─────────┘            └───────┬──────┘
         │                              │
         │      ┌──────────────┐       │
         └─────►│ Nextcloud    │◄──────┘
                │   Pod 3      │
                │ Replica 3/3  │
                └──────┬───────┘
                       │
                       ↓
         ┌─────────────────────────────┐
         │   Service: nextcloud-svc    │
         │      (ClusterIP/LB)         │
         └─────────────┬───────────────┘
                       │
         ┌─────────────▼───────────────┐
         │  PVC: nextcloud-data (RWX)  │
         │      50Gi - Shared Storage  │
         └─────────────────────────────┘

                       │
                       │ Database Connection
                       │ (mysql://mariadb:3306)
                       ↓
         ┌─────────────────────────────┐
         │   Service: mariadb          │
         │      ClusterIP: 3306        │
         └─────────────┬───────────────┘
                       │
                       ↓
         ┌──────────────────────────────┐
         │   StatefulSet: mariadb       │
         │   ┌────────────────────┐     │
         │   │  mariadb-0         │     │
         │   │  (Primary)         │     │
         │   └────────┬───────────┘     │
         │            │                 │
         │   ┌────────▼───────────┐     │
         │   │ PVC: mariadb-data  │     │
         │   │   (RWO - 20Gi)     │     │
         │   └────────────────────┘     │
         └──────────────────────────────┘
                       │
                       ↓
         ┌─────────────────────────────┐
         │    Secret: nextcloud-db     │
         │  - DB_PASSWORD              │
         │  - DB_USER                  │
         │  - DB_NAME                  │
         └─────────────────────────────┘

         ┌─────────────────────────────┐
         │ Stufe 3: Monitoring Stack   │
         │ ┌─────────────────────────┐ │
         │ │ Prometheus              │ │
         │ │  - ServiceMonitor       │ │
         │ │  - Metrics Scraping     │ │
         │ └─────────────────────────┘ │
         │ ┌─────────────────────────┐ │
         │ │ Grafana                 │ │
         │ │  - Nextcloud Dashboard  │ │
         │ │  - MariaDB Metrics      │ │
         │ └─────────────────────────┘ │
         └─────────────────────────────┘

         ┌─────────────────────────────┐
         │ Stufe 3: Backup Strategy    │
         │ ┌─────────────────────────┐ │
         │ │ CronJob: db-backup      │ │
         │ │  Schedule: Daily 2 AM   │ │
         │ │  Retention: 7 days      │ │
         │ └─────────────────────────┘ │
         │ ┌─────────────────────────┐ │
         │ │ PVC Snapshots           │ │
         │ │  (VolumeSnapshot)       │ │
         │ └─────────────────────────┘ │
         └─────────────────────────────┘
```

### Komponenten-Übersicht

| Komponente | Typ | Zweck | Stufe |
|------------|-----|-------|-------|
| **nextcloud** | Deployment (später: 3 Replicas) | Nextcloud-Anwendung | 1, 2 |
| **mariadb** | StatefulSet | Datenbank (persistent identity) | 1, 2 |
| **nextcloud-svc** | Service (ClusterIP → LoadBalancer) | Interner/Externer Zugriff | 1, 2, 3 |
| **mariadb-svc** | Service (ClusterIP) | DB-Zugriff für Nextcloud | 1 |
| **nextcloud-data** | PVC (ReadWriteMany) | Nextcloud-Dateien (geteilt) | 1, 2 |
| **mariadb-data** | PVC (ReadWriteOnce) | Datenbank-Daten | 1, 2 |
| **nextcloud-db** | Secret | Datenbank-Credentials | 1 |
| **nextcloud-ingress** | Ingress | HTTPS-Zugriff mit Domain | 3 |
| **certificate** | Certificate (Cert-Manager) | TLS-Zertifikat | 3 |
| **nextcloud-monitor** | ServiceMonitor | Prometheus-Integration | 3 |
| **db-backup** | CronJob | Automatische Backups | 3 |
| **network-policies** | NetworkPolicy | Pod-zu-Pod-Isolation | 2 |

---

## 4. Stufe 1: Basis-Installation

### Übersicht Stufe 1

In dieser Stufe erstellen wir eine **funktionierende Nextcloud-Installation** mit:
- ✅ Nextcloud-Pod (1 Replica)
- ✅ MariaDB-Pod (Single Instance)
- ✅ Persistenter Storage für beide
- ✅ Grundlegende Konfiguration
- ✅ Zugriff via Port-Forwarding

**Zeitaufwand:** ~15-20 Minuten
**Ziel:** Verstehen der Kubernetes-Grundlagen und funktionierende Nextcloud

---

### 4.1 Namespace erstellen

#### Was ist ein Namespace?

Ein Namespace ist wie ein **virtueller Cluster** innerhalb Ihres Kubernetes-Clusters. Er isoliert Ressourcen voneinander und ermöglicht:
- Logische Trennung (z.B. dev/test/prod)
- Resource Quotas pro Namespace
- Bessere Übersichtlichkeit

#### Schritt-für-Schritt

```bash
# 1. Namespace erstellen
kubectl create namespace nextcloud-prod

# 2. Namespace verifizieren
kubectl get namespaces

# 3. Namespace als Standard setzen (optional, aber empfohlen)
kubectl config set-context --current --namespace=nextcloud-prod

# 4. Aktuellen Context prüfen
kubectl config get-contexts
```

**Erwartetes Ergebnis:**
```
NAME                READY   STATUS    AGE
nextcloud-prod      Active            5s
```

**Was passiert hier?**
- Kubernetes erstellt einen neuen Namespace
- Alle folgenden Ressourcen werden in diesem Namespace erstellt
- Isolation von anderen Projekten/Anwendungen

---

### 4.2 Secrets für Datenbank-Credentials erstellen

#### Was sind Secrets?

Secrets speichern **sensible Daten** (Passwörter, API-Keys, Zertifikate) sicher in Kubernetes. Sie sind:
- Base64-kodiert (nicht verschlüsselt!)
- Separat von Anwendungs-Code gespeichert
- Können als Environment-Variablen oder Dateien eingebunden werden

#### Warum Secrets statt Klartext?

❌ **FALSCH** (Passwort im Deployment):
```yaml
env:
- name: MYSQL_ROOT_PASSWORD
  value: "MyPassword123"  # ← Nie so machen!
```

✅ **RICHTIG** (Passwort in Secret):
```yaml
env:
- name: MYSQL_ROOT_PASSWORD
  valueFrom:
    secretKeyRef:
      name: nextcloud-db
      key: MYSQL_ROOT_PASSWORD
```

#### Schritt-für-Schritt: Passwörter generieren und Secret erstellen

```bash
# 1. Starkes Passwort generieren (Linux/macOS)
# Option A: Über Terminal-Eingabe (sicherer, kein History-Eintrag)
read -s -p 'Datenbankpasswort: ' DB_PASSWORD
echo

# Option B: Automatisch generieren
DB_PASSWORD=$(openssl rand -base64 32)
echo "Generiertes Passwort: $DB_PASSWORD"
# ⚠️ WICHTIG: Passwort sicher speichern (z.B. in Password Manager)!

# 2. Secret mit allen benötigten Variablen erstellen
kubectl create secret generic nextcloud-db \
  --from-literal=MYSQL_ROOT_PASSWORD=$DB_PASSWORD \
  --from-literal=MYSQL_PASSWORD=$DB_PASSWORD \
  --from-literal=MYSQL_DATABASE=nextcloud \
  --from-literal=MYSQL_USER=nextcloud \
  --from-literal=MYSQL_HOST=mariadb

# 3. Secret verifizieren
kubectl get secrets

# 4. Secret-Details anzeigen (Werte sind Base64-kodiert)
kubectl describe secret nextcloud-db

# 5. Einen Wert dekodieren (zum Testen)
kubectl get secret nextcloud-db -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d
echo
```

**Erwartetes Ergebnis:**
```
NAME            TYPE     DATA   AGE
nextcloud-db    Opaque   5      10s
```

**Was passiert hier?**
1. `openssl rand -base64 32` generiert ein 32-Zeichen Base64-Passwort
2. `kubectl create secret generic` erstellt ein Secret mit 5 Key-Value-Paaren:
   - `MYSQL_ROOT_PASSWORD`: Root-Passwort für MariaDB
   - `MYSQL_PASSWORD`: Passwort für Nextcloud-User
   - `MYSQL_DATABASE`: Name der Datenbank
   - `MYSQL_USER`: Datenbank-User für Nextcloud
   - `MYSQL_HOST`: Hostname des MariaDB-Service

**Sicherheitshinweis:**
- Secret ist **nicht verschlüsselt** in etcd gespeichert!
- Für Produktion: Encryption at rest aktivieren oder externe Lösung (Vault, Sealed Secrets)
- Niemals Secrets in Git committen!

---

### 4.3 MariaDB Deployment erstellen

#### Was ist ein Deployment?

Ein **Deployment** ist eine Kubernetes-Ressource, die:
- Pods erstellt und verwaltet
- Self-Healing bietet (Pod stirbt → neuer Pod wird erstellt)
- Updates ermöglicht (Rolling Updates)

**Wichtig:** In **Stufe 2** werden wir MariaDB von Deployment auf **StatefulSet** umstellen (bessere Konsistenz für Datenbanken).

#### MariaDB-Deployment YAML

Erstellen Sie eine Datei `mariadb-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: nextcloud-prod
  labels:
    app: mariadb
    tier: database
spec:
  replicas: 1  # Nur 1 Replica (Stufe 1)
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
        tier: database
    spec:
      containers:
      - name: mariadb
        image: docker.io/library/mariadb:10.11
        ports:
        - containerPort: 3306
          name: mysql
        env:
        # Alle Environment-Variablen kommen aus dem Secret
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_DATABASE
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_PASSWORD
        volumeMounts:
        - name: mariadb-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-data
        persistentVolumeClaim:
          claimName: mariadb-data
```

#### Persistent Volume Claim (PVC) für MariaDB

Erstellen Sie eine Datei `mariadb-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-data
  namespace: nextcloud-prod
spec:
  accessModes:
  - ReadWriteOnce  # RWO: Nur von einem Node nutzbar
  resources:
    requests:
      storage: 5Gi
  # StorageClass wird automatisch gewählt (default)
```

**Was ist ein PVC?**
- **PersistentVolumeClaim** = Anfrage für Speicher
- Kubernetes erstellt automatisch ein **PersistentVolume** (PV)
- Daten bleiben erhalten, auch wenn Pod neu erstellt wird

**Access Modes erklärt:**
- **ReadWriteOnce (RWO)**: Nur 1 Node kann lesen/schreiben (ideal für Datenbanken)
- **ReadWriteMany (RWX)**: Mehrere Nodes können lesen/schreiben (ideal für gemeinsame Dateien)
- **ReadOnlyMany (ROX)**: Mehrere Nodes nur lesen

#### Deployment durchführen

```bash
# 1. PVC erstellen
kubectl apply -f mariadb-pvc.yaml

# 2. PVC-Status prüfen (sollte 'Pending' sein)
kubectl get pvc

# 3. Deployment erstellen
kubectl apply -f mariadb-deployment.yaml

# 4. PVC-Status erneut prüfen (jetzt 'Bound')
kubectl get pvc
# OUTPUT:
# NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES
# mariadb-data   Bound    pvc-abc123-def456-ghi789-jkl012-mno345    5Gi        RWO

# 5. Pod-Status prüfen
kubectl get pods
# OUTPUT:
# NAME                       READY   STATUS    RESTARTS   AGE
# mariadb-5d8f9c6b7d-abc12   1/1     Running   0          30s

# 6. Logs prüfen (MariaDB-Initialisierung)
kubectl logs -f deployment/mariadb
# Warten bis: "mysqld: ready for connections"
```

**Was passiert hier?**

1. **PVC wird erstellt:**
   - Kubernetes reserviert 5Gi Speicher
   - Status: `Pending` (noch nicht an Pod gebunden)

2. **Deployment erstellt Pod:**
   - Pod wird auf einem Node geplant
   - Container-Image `mariadb:10.11` wird heruntergeladen
   - Environment-Variablen werden aus Secret gelesen

3. **Volume wird gemountet:**
   - PVC wird an Pod gebunden → Status: `Bound`
   - Volume wird unter `/var/lib/mysql` im Container gemountet

4. **MariaDB initialisiert:**
   - Datenbank `nextcloud` wird erstellt
   - User `nextcloud` mit Passwort wird angelegt
   - MariaDB ist bereit für Connections

**Troubleshooting:**

```bash
# Pod startet nicht?
kubectl describe pod -l app=mariadb

# Pod crasht?
kubectl logs -l app=mariadb --previous

# PVC bleibt 'Pending'?
kubectl describe pvc mariadb-data
# → Prüfen ob StorageClass verfügbar ist
```

---

### 4.4 MariaDB Service erstellen

#### Was ist ein Service?

Ein **Service** ist ein stabiler Netzwerk-Endpoint für Pods:
- Pods haben dynamische IPs (ändern sich bei Neustart)
- Service hat stabile IP (ClusterIP)
- DNS-Name: `<service-name>.<namespace>.svc.cluster.local`

#### Service YAML

Erstellen Sie `mariadb-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mariadb
  namespace: nextcloud-prod
  labels:
    app: mariadb
spec:
  type: ClusterIP  # Nur innerhalb des Clusters erreichbar
  ports:
  - port: 3306
    targetPort: 3306
    protocol: TCP
    name: mysql
  selector:
    app: mariadb  # Alle Pods mit diesem Label werden angesprochen
```

#### Service deployen

```bash
# 1. Service erstellen
kubectl apply -f mariadb-service.yaml

# 2. Service prüfen
kubectl get service mariadb
# OUTPUT:
# NAME      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# mariadb   ClusterIP   10.96.100.50    <none>        3306/TCP   10s

# 3. Endpoints prüfen (zeigt Pod-IPs)
kubectl get endpoints mariadb
# OUTPUT:
# NAME      ENDPOINTS           AGE
# mariadb   10.244.1.5:3306     10s

# 4. DNS-Auflösung testen
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup mariadb
# OUTPUT:
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
#
# Name:      mariadb
# Address 1: 10.96.100.50 mariadb.nextcloud-prod.svc.cluster.local
```

**Was passiert hier?**

1. **Service erstellt ClusterIP:**
   - Kubernetes weist eine stabile IP zu (z.B. `10.96.100.50`)
   - Diese IP ändert sich nie (solange Service existiert)

2. **Selector findet Pods:**
   - Service sucht alle Pods mit Label `app: mariadb`
   - Fügt deren IPs zu Endpoints hinzu

3. **DNS-Eintrag wird erstellt:**
   - `mariadb` → `10.96.100.50` (innerhalb Namespace)
   - `mariadb.nextcloud-prod.svc.cluster.local` → `10.96.100.50` (vollständiger Name)

4. **Load Balancing:**
   - Wenn mehrere Pods existieren (später in Stufe 2), verteilt Service Traffic automatisch

**Nextcloud kann jetzt mit MariaDB verbinden über:**
- Hostname: `mariadb`
- Port: `3306`

---

### 4.5 Nextcloud Deployment erstellen

#### Nextcloud PVC (ReadWriteMany!)

**Wichtig:** Nextcloud benötigt **ReadWriteMany** (RWX), weil später mehrere Pods auf dieselben Dateien zugreifen.

Erstellen Sie `nextcloud-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data
  namespace: nextcloud-prod
spec:
  accessModes:
  - ReadWriteMany  # RWX: Mehrere Pods können gleichzeitig zugreifen
  resources:
    requests:
      storage: 5Gi
```

**Achtung:** Nicht alle StorageClasses unterstützen RWX!

```bash
# StorageClass-Fähigkeiten prüfen
kubectl get storageclasses -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.allowVolumeExpansion}{"\n"}{end}'

# Wenn Ihre StorageClass kein RWX unterstützt:
# Option 1: NFS-StorageClass installieren
# Option 2: Für Stufe 1: RWO verwenden (dann nur 1 Nextcloud-Replica möglich)
```

#### Nextcloud Deployment YAML

Erstellen Sie `nextcloud-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  labels:
    app: nextcloud
    tier: frontend
spec:
  replicas: 1  # Stufe 1: Nur 1 Replica
  selector:
    matchLabels:
      app: nextcloud
  template:
    metadata:
      labels:
        app: nextcloud
        tier: frontend
    spec:
      containers:
      - name: nextcloud
        image: docker.io/library/nextcloud:28-apache
        ports:
        - containerPort: 80
          name: http
        env:
        # Datenbank-Verbindung
        - name: MYSQL_HOST
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_HOST
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_DATABASE
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_PASSWORD
        # Nextcloud-spezifische Einstellungen
        - name: NEXTCLOUD_TRUSTED_DOMAINS
          value: "localhost nextcloud.local"
        - name: APACHE_DISABLE_REWRITE_IP
          value: "1"
        volumeMounts:
        - name: nextcloud-data
          mountPath: /var/www/html
      volumes:
      - name: nextcloud-data
        persistentVolumeClaim:
          claimName: nextcloud-data
```

**Environment-Variablen erklärt:**

| Variable | Zweck |
|----------|-------|
| `MYSQL_HOST` | Hostname des MariaDB-Service (`mariadb`) |
| `MYSQL_DATABASE` | Datenbank-Name (`nextcloud`) |
| `MYSQL_USER` | Datenbank-User (`nextcloud`) |
| `MYSQL_PASSWORD` | Datenbank-Passwort (aus Secret) |
| `NEXTCLOUD_TRUSTED_DOMAINS` | Erlaubte Domains (wichtig für Security!) |
| `APACHE_DISABLE_REWRITE_IP` | Deaktiviert IP-Rewrite (für Ingress) |

#### Deployment durchführen

```bash
# 1. PVC erstellen
kubectl apply -f nextcloud-pvc.yaml

# 2. Deployment erstellen
kubectl apply -f nextcloud-deployment.yaml

# 3. Pod-Status beobachten (Initialisierung dauert 2-3 Minuten!)
kubectl get pods -w
# Drücken Sie Ctrl+C wenn Pod 'Running' ist

# 4. Logs verfolgen (Nextcloud-Setup)
kubectl logs -f deployment/nextcloud

# Warten bis Sie sehen:
# "AH00163: Apache/2.4.XX (Debian) PHP/8.X.X configured"
# "Nextcloud was successfully installed"
```

**Was passiert während der Initialisierung?**

1. **Nextcloud-Container startet:**
   - Apache-Webserver startet
   - PHP-Module werden geladen

2. **Verbindung zu MariaDB:**
   - Nextcloud verbindet zu `mariadb:3306`
   - Prüft ob Datenbank `nextcloud` existiert

3. **Erstmalige Installation:**
   - Nextcloud-Datenbank-Schema wird erstellt
   - Admin-User wird vorbereitet
   - Konfiguration in `/var/www/html/config/config.php`

4. **Bereit für Zugriff:**
   - Nextcloud-Webinterface ist verfügbar

**Troubleshooting:**

```bash
# Pod startet nicht?
kubectl describe pod -l app=nextcloud

# Verbindung zu MariaDB schlägt fehl?
kubectl logs -l app=nextcloud | grep -i mysql
kubectl exec -it deployment/nextcloud -- ping mariadb

# Initialisierung hängt?
kubectl exec -it deployment/nextcloud -- cat /var/www/html/config/config.php
```

---

### 4.6 Nextcloud Service erstellen

Erstellen Sie `nextcloud-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  labels:
    app: nextcloud
spec:
  type: ClusterIP  # Stufe 1: Interner Zugriff
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: nextcloud
```

```bash
# Service erstellen
kubectl apply -f nextcloud-service.yaml

# Service prüfen
kubectl get service nextcloud
```

---

### 4.7 Zugriff auf Nextcloud (Port-Forwarding)

Da wir in Stufe 1 noch keinen Ingress haben, nutzen wir **Port-Forwarding** für lokalen Zugriff:

```bash
# Port-Forwarding starten (Terminal bleibt offen!)
kubectl port-forward service/nextcloud 8080:80

# In neuem Terminal oder Browser:
# http://localhost:8080
```

**Nextcloud Setup-Assistent:**

1. Browser öffnen: `http://localhost:8080`
2. Admin-Account erstellen:
   - Username: `admin`
   - Passwort: (starkes Passwort wählen!)
3. "Empfohlene Apps installieren" (optional)
4. Klick auf "Installation abschließen"

**Glückwunsch!** 🎉 Nextcloud läuft jetzt auf Kubernetes!

---

### 4.8 Stufe 1 - Abschluss & Verifikation

#### Vollständiger Status-Check

```bash
# Alle Ressourcen anzeigen
kubectl get all -n nextcloud-prod

# Erwartetes Ergebnis:
# NAME                             READY   STATUS    RESTARTS   AGE
# pod/mariadb-xxx                  1/1     Running   0          10m
# pod/nextcloud-xxx                1/1     Running   0          8m
#
# NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# service/mariadb     ClusterIP   10.96.100.50    <none>        3306/TCP   10m
# service/nextcloud   ClusterIP   10.96.200.100   <none>        80/TCP     8m
#
# NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/mariadb     1/1     1            1           10m
# deployment.apps/nextcloud   1/1     1            1           8m

# PVCs prüfen
kubectl get pvc

# Erwartetes Ergebnis:
# NAME             STATUS   VOLUME        CAPACITY   ACCESS MODES
# mariadb-data     Bound    pvc-xxx       5Gi        RWO
# nextcloud-data   Bound    pvc-yyy       5Gi        RWX

# Secrets prüfen
kubectl get secrets

# Events prüfen (letzte Probleme?)
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

#### Funktionstest

1. **Datei hochladen:**
   - Klick auf "+" → "Datei hochladen"
   - Kleine Testdatei hochladen
   - Prüfen ob Datei erscheint

2. **Persistenz testen:**
   ```bash
   # Nextcloud-Pod löschen
   kubectl delete pod -l app=nextcloud

   # Neuer Pod wird automatisch erstellt
   kubectl get pods -w

   # Port-Forwarding neu starten
   kubectl port-forward service/nextcloud 8080:80

   # Browser: http://localhost:8080
   # → Datei sollte noch da sein!
   ```

3. **Datenbank-Persistenz testen:**
   ```bash
   # MariaDB-Pod löschen
   kubectl delete pod -l app=mariadb

   # Warten bis neuer Pod 'Running'
   kubectl get pods -w

   # Nextcloud neu laden → sollte funktionieren
   ```

#### Was Sie erreicht haben (Stufe 1)

✅ Funktionierendes Nextcloud + MariaDB auf Kubernetes
✅ Persistenter Storage (Daten bleiben erhalten)
✅ Self-Healing (Pods werden automatisch neu erstellt)
✅ Grundlegendes Verständnis von:
- Namespaces
- Secrets
- Deployments
- Services
- PersistentVolumeClaims

#### Limitierungen von Stufe 1

❌ Keine Hochverfügbarkeit (nur 1 Replica)
❌ Kein externer Zugriff (nur Port-Forwarding)
❌ Keine Resource Limits (kann alle Node-Ressourcen verbrauchen)
❌ Keine Health Checks (Kubernetes weiß nicht ob Nextcloud "gesund" ist)
❌ Keine Security-Features (Netzwerk-Isolation, TLS)
❌ Kein Monitoring/Logging

**→ Stufe 2 behebt diese Limitierungen!**

---

## 5. Stufe 2: Production-Ready Features

### Übersicht Stufe 2

In dieser Stufe machen wir Nextcloud **produktionsreif**:
- ✅ **Hochverfügbarkeit**: Mehrere Nextcloud-Replicas
- ✅ **StatefulSet für MariaDB**: Stabile Pod-Identität
- ✅ **Resource Management**: CPU/Memory Limits
- ✅ **Health Checks**: Liveness & Readiness Probes
- ✅ **Security**: Network Policies, Pod Security
- ✅ **Externer Zugriff**: LoadBalancer Service

**Zeitaufwand:** ~30-40 Minuten
**Voraussetzung:** Abgeschlossene Stufe 1

---

### 5.1 MariaDB: Von Deployment zu StatefulSet

#### Warum StatefulSet für Datenbanken?

**Problem mit Deployments für Datenbanken:**
- Pod-Namen sind zufällig (`mariadb-abc123`)
- Bei Neustart: Neuer Name, neue IP
- Schwierig für Master-Slave-Replikation
- Kein garantiertes Startup-/Shutdown-Verhalten

**Vorteile von StatefulSets:**
- ✅ Feste Pod-Namen (`mariadb-0`, `mariadb-1`)
- ✅ Stabile Netzwerk-Identität
- ✅ Sequentielles Startup (0 → 1 → 2)
- ✅ Jeder Pod bekommt eigenen PVC
- ✅ Ideal für Datenbanken, Kafka, ZooKeeper

```
Deployment:                  StatefulSet:
mariadb-abc123 (zufällig)   mariadb-0 (fix)
mariadb-def456              mariadb-1
mariadb-ghi789              mariadb-2
```

#### MariaDB StatefulSet YAML

**Wichtig:** Wir löschen erst das alte Deployment und erstellen dann das StatefulSet.

Erstellen Sie `mariadb-statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
  namespace: nextcloud-prod
  labels:
    app: mariadb
    tier: database
spec:
  serviceName: mariadb  # Headless Service (wird erstellt)
  replicas: 1  # Stufe 2: Erstmal 1 Replica (später skalierbar)
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
        tier: database
    spec:
      containers:
      - name: mariadb
        image: docker.io/library/mariadb:10.11
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_DATABASE
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_PASSWORD
        # NEU: Resource Limits
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 2Gi
        # NEU: Liveness Probe (ist DB am Leben?)
        livenessProbe:
          exec:
            command:
            - bash
            - -c
            - "mysqladmin ping -u root -p$MYSQL_ROOT_PASSWORD"
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        # NEU: Readiness Probe (ist DB bereit?)
        readinessProbe:
          exec:
            command:
            - bash
            - -c
            - "mysql -u root -p$MYSQL_ROOT_PASSWORD -e 'SELECT 1'"
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        volumeMounts:
        - name: mariadb-data
          mountPath: /var/lib/mysql
  # NEU: volumeClaimTemplates (automatische PVC-Erstellung pro Pod)
  volumeClaimTemplates:
  - metadata:
      name: mariadb-data
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 20Gi  # Mehr Storage für Production
```

**Neue Konzepte erklärt:**

1. **serviceName: mariadb**
   - StatefulSet benötigt einen Headless Service
   - Ermöglicht stabile DNS-Namen: `mariadb-0.mariadb.nextcloud-prod.svc.cluster.local`

2. **resources (Requests & Limits)**
   ```yaml
   requests:  # Garantierte Ressourcen
     cpu: 500m      # 0.5 CPU-Cores
     memory: 512Mi  # 512 Megabyte
   limits:    # Maximum
     cpu: 1000m     # 1 CPU-Core
     memory: 2Gi    # 2 Gigabyte
   ```
   - **Requests**: Kubernetes plant Pod nur auf Node mit freien Ressourcen
   - **Limits**: Pod wird gedrosselt (CPU) oder beendet (Memory) bei Überschreitung

3. **Liveness Probe**
   - Prüft: Ist Container "am Leben"?
   - Befehl: `mysqladmin ping` → Exit Code 0 = gesund
   - Bei Fehler: Container wird neu gestartet
   - `initialDelaySeconds: 30` → Warte 30s nach Container-Start
   - `periodSeconds: 10` → Prüfe alle 10 Sekunden
   - `failureThreshold: 3` → Nach 3 Fehlern neu starten

4. **Readiness Probe**
   - Prüft: Ist Container "bereit" für Traffic?
   - Befehl: `mysql -e 'SELECT 1'` → Kann DB Queries verarbeiten?
   - Bei Fehler: Pod wird aus Service-Endpoints entfernt (bekommt keinen Traffic)

5. **volumeClaimTemplates**
   - Erstellt automatisch PVC für jeden Pod
   - Pod `mariadb-0` → PVC `mariadb-data-mariadb-0`
   - Pod `mariadb-1` → PVC `mariadb-data-mariadb-1`

#### Migration: Deployment → StatefulSet

**Achtung:** Dieser Prozess löscht den Pod kurz (wenige Sekunden Downtime)!

```bash
# 1. Backup der aktuellen Konfiguration
kubectl get deployment mariadb -o yaml > mariadb-deployment-backup.yaml

# 2. Altes Deployment löschen
kubectl delete deployment mariadb

# 3. Alten PVC löschen (wird neu erstellt mit anderem Namen)
kubectl delete pvc mariadb-data

# 4. StatefulSet erstellen
kubectl apply -f mariadb-statefulset.yaml

# 5. Pod-Status beobachten
kubectl get pods -w
# Warten bis: mariadb-0   1/1   Running

# 6. PVC prüfen (neuer Name!)
kubectl get pvc
# OUTPUT:
# NAME                      STATUS   VOLUME   CAPACITY   ACCESS MODES
# mariadb-data-mariadb-0    Bound    pvc-xxx  20Gi       RWO

# 7. Logs prüfen
kubectl logs mariadb-0 -f
# Warten bis: "mysqld: ready for connections"
```

**Was ist passiert?**
1. Deployment gelöscht → Pod `mariadb-abc123` beendet
2. StatefulSet erstellt → Pod `mariadb-0` startet
3. PVC `mariadb-data-mariadb-0` automatisch erstellt
4. MariaDB initialisiert neu (⚠️ Datenbank-Daten sind weg!)

**⚠️ Datenverlust vermeiden:**

Wenn Sie Daten behalten wollen:
```bash
# Option A: Datenbank-Dump vor Migration
kubectl exec -it deployment/mariadb -- mysqldump -u root -p$DB_PASSWORD --all-databases > backup.sql

# Nach StatefulSet-Erstellung:
kubectl exec -it mariadb-0 -- mysql -u root -p$DB_PASSWORD < backup.sql

# Option B: PVC umbenennen (fortgeschritten)
kubectl get pvc mariadb-data -o yaml > old-pvc.yaml
# Editieren: name → mariadb-data-mariadb-0
kubectl apply -f old-pvc.yaml
```

#### StatefulSet-Verhalten testen

```bash
# 1. Pod löschen
kubectl delete pod mariadb-0

# 2. Neuer Pod wird erstellt (gleicher Name!)
kubectl get pods -w
# OUTPUT:
# NAME        READY   STATUS    RESTARTS   AGE
# mariadb-0   0/1     Pending   0          2s
# mariadb-0   1/1     Running   0          10s

# 3. Derselbe PVC wird wieder verwendet
kubectl describe pod mariadb-0 | grep ClaimName
# OUTPUT:
# ClaimName:  mariadb-data-mariadb-0
```

**Wichtig:** Der neue Pod `mariadb-0` verwendet **denselben PVC** → Daten bleiben erhalten!

---

### 5.2 Nextcloud: Hochverfügbarkeit mit mehreren Replicas

#### Warum mehrere Replicas?

**Single Replica (Stufe 1):**
- ❌ Bei Pod-Ausfall: Downtime bis Neustart
- ❌ Keine Load-Verteilung
- ❌ Kein Rolling Update ohne Downtime

**Multi-Replica (Stufe 2):**
- ✅ Bei Pod-Ausfall: Andere Pods übernehmen
- ✅ Load Balancing über mehrere Pods
- ✅ Rolling Updates ohne Downtime
- ✅ Horizontal skalierbar

#### Nextcloud Deployment (Production-Ready)

Erstellen Sie `nextcloud-deployment-ha.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  labels:
    app: nextcloud
    tier: frontend
spec:
  replicas: 3  # NEU: 3 Replicas für HA
  selector:
    matchLabels:
      app: nextcloud
  # NEU: Update-Strategie
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Max. 1 zusätzlicher Pod während Update
      maxUnavailable: 0  # Kein Pod darf unavailable sein (keine Downtime!)
  template:
    metadata:
      labels:
        app: nextcloud
        tier: frontend
    spec:
      # NEU: Anti-Affinity (Pods auf verschiedene Nodes verteilen)
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: nextcloud
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nextcloud
        image: docker.io/library/nextcloud:28-apache
        ports:
        - containerPort: 80
          name: http
        env:
        - name: MYSQL_HOST
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_HOST
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_DATABASE
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nextcloud-db
              key: MYSQL_PASSWORD
        - name: NEXTCLOUD_TRUSTED_DOMAINS
          value: "localhost nextcloud.local nextcloud.yourdomain.com"
        - name: APACHE_DISABLE_REWRITE_IP
          value: "1"
        # NEU: Redis für Session-Sharing (später erweitern)
        - name: REDIS_HOST
          value: "redis"  # Optional: Redis für Session-Storage
        # NEU: Resource Limits
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2000m
            memory: 2Gi
        # NEU: Liveness Probe (HTTP-Check)
        livenessProbe:
          httpGet:
            path: /status.php
            port: 80
            httpHeaders:
            - name: Host
              value: "localhost"
          initialDelaySeconds: 60  # Nextcloud braucht Zeit zum Starten
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        # NEU: Readiness Probe
        readinessProbe:
          httpGet:
            path: /status.php
            port: 80
            httpHeaders:
            - name: Host
              value: "localhost"
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        volumeMounts:
        - name: nextcloud-data
          mountPath: /var/www/html
      volumes:
      - name: nextcloud-data
        persistentVolumeClaim:
          claimName: nextcloud-data
```

**Neue Konzepte erklärt:**

1. **replicas: 3**
   - 3 unabhängige Nextcloud-Pods
   - Service verteilt Traffic über alle 3 (Load Balancing)

2. **Rolling Update Strategy**
   ```yaml
   maxSurge: 1        # Während Update: Max. 4 Pods (3+1)
   maxUnavailable: 0  # Mindestens 3 Pods bleiben running
   ```
   **Ablauf bei Update:**
   - Start: 3 Pods (v1)
   - Update startet: 1 neuer Pod (v2) wird erstellt → 4 Pods total
   - Warte bis neuer Pod 'Ready'
   - Lösche 1 alten Pod (v1) → 3 Pods (2×v1, 1×v2)
   - Wiederhole bis alle Pods v2

3. **Pod Anti-Affinity**
   ```yaml
   podAntiAffinity:
     preferredDuringSchedulingIgnoredDuringExecution:
     - weight: 100
       podAffinityTerm:
         labelSelector:
           matchLabels:
             app: nextcloud
         topologyKey: kubernetes.io/hostname
   ```
   **Was macht das?**
   - "Versuche, Nextcloud-Pods auf **verschiedene Nodes** zu verteilen"
   - `preferred` = Soft Constraint (kein Zwang, aber bevorzugt)
   - `topologyKey: hostname` = Verteile basierend auf Node-Namen
   - **Vorteil:** Bei Node-Ausfall läuft Nextcloud auf anderen Nodes weiter

4. **Liveness/Readiness Probes (HTTP)**
   ```yaml
   httpGet:
     path: /status.php  # Nextcloud-Status-Endpoint
     port: 80
     httpHeaders:
     - name: Host
       value: "localhost"
   ```
   - `/status.php` gibt JSON zurück: `{"installed":true,"maintenance":false}`
   - HTTP 200 = gesund
   - HTTP 5xx oder Timeout = ungesund

#### Deployment durchführen

```bash
# 1. Altes Deployment löschen (falls vorhanden)
kubectl delete deployment nextcloud

# 2. Neues HA-Deployment erstellen
kubectl apply -f nextcloud-deployment-ha.yaml

# 3. Rollout-Status beobachten
kubectl rollout status deployment/nextcloud
# OUTPUT:
# Waiting for deployment "nextcloud" rollout to finish: 0 of 3 updated replicas are available...
# Waiting for deployment "nextcloud" rollout to finish: 1 of 3 updated replicas are available...
# Waiting for deployment "nextcloud" rollout to finish: 2 of 3 updated replicas are available...
# deployment "nextcloud" successfully rolled out

# 4. Pods prüfen
kubectl get pods -o wide
# OUTPUT:
# NAME                         READY   STATUS    RESTARTS   AGE   IP            NODE
# nextcloud-abc123             1/1     Running   0          2m    10.244.1.5    node1
# nextcloud-def456             1/1     Running   0          2m    10.244.2.8    node2
# nextcloud-ghi789             1/1     Running   0          2m    10.244.3.12   node3

# 5. Readiness-Status prüfen
kubectl get pods -l app=nextcloud -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
# Alle sollten "True" zeigen
```

**Was passiert?**
1. Kubernetes erstellt 3 Pods gleichzeitig
2. Jeder Pod:
   - Startet Nextcloud-Container
   - Mountet `/var/www/html` vom PVC (shared!)
   - Verbindet zu MariaDB
3. Readiness Probe prüft `/status.php`
4. Nach 30s: Pods werden `Ready` → bekommen Traffic vom Service

#### Hochverfügbarkeit testen

```bash
# 1. Baseline: Alle Pods laufen
kubectl get pods

# 2. Einen Pod löschen (simuliert Crash)
kubectl delete pod nextcloud-abc123

# 3. Sofort wieder prüfen
kubectl get pods
# OUTPUT:
# nextcloud-abc123             0/1     Terminating   0          5m
# nextcloud-def456             1/1     Running       0          5m
# nextcloud-ghi789             1/1     Running       0          5m
# nextcloud-xyz999             0/1     ContainerCreating   0   2s  ← Neuer Pod!

# 4. Service-Endpoints (laufende Pods)
kubectl get endpoints nextcloud
# OUTPUT:
# NAME        ENDPOINTS                           AGE
# nextcloud   10.244.2.8:80,10.244.3.12:80        5m
# ↑ Nur 2 IPs (gelöschter Pod wurde automatisch entfernt)

# 5. Nach ~30 Sekunden: Neuer Pod ist Ready
kubectl get pods
# nextcloud-def456             1/1     Running   0          6m
# nextcloud-ghi789             1/1     Running   0          6m
# nextcloud-xyz999             1/1     Running   0          30s

# 6. Service-Endpoints wieder vollständig
kubectl get endpoints nextcloud
# Jetzt 3 IPs wieder
```

**Was ist passiert?**
1. Pod `abc123` stirbt → Service entfernt ihn aus Endpoints
2. **Kein Traffic-Verlust:** Andere 2 Pods übernehmen
3. ReplicaSet erstellt automatisch neuen Pod `xyz999`
4. Neuer Pod wird `Ready` → Service fügt ihn zu Endpoints hinzu
5. **Self-Healing komplett automatisch!**

---

### 5.3 Network Policies - Netzwerk-Isolation

#### Was sind Network Policies?

**Standardverhalten in Kubernetes:**
- ❌ Jeder Pod kann mit jedem Pod kommunizieren
- ❌ Keine Isolation zwischen Namespaces
- ❌ Sicherheitsrisiko!

**Mit Network Policies:**
- ✅ Whitelist-basierte Firewall-Regeln
- ✅ "Deny by default, allow specific"
- ✅ Pod-zu-Pod-Isolation
- ✅ Namespace-Isolation

#### Nextcloud Network Policies

Erstellen Sie `network-policies.yaml`:

```yaml
---
# 1. Deny-All Policy (Baseline)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nextcloud-prod
spec:
  podSelector: {}  # Alle Pods im Namespace
  policyTypes:
  - Ingress
  - Egress

---
# 2. MariaDB Policy (nur Nextcloud darf verbinden)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mariadb-allow-nextcloud
  namespace: nextcloud-prod
spec:
  podSelector:
    matchLabels:
      app: mariadb
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Erlaube Ingress nur von Nextcloud-Pods
  - from:
    - podSelector:
        matchLabels:
          app: nextcloud
    ports:
    - protocol: TCP
      port: 3306
  egress:
  # Erlaube DNS-Auflösung
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53

---
# 3. Nextcloud Policy (Ingress von außen, Egress zu MariaDB)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: nextcloud-allow-web
  namespace: nextcloud-prod
spec:
  podSelector:
    matchLabels:
      app: nextcloud
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Erlaube HTTP/HTTPS von überall
  - from: []  # Leere Liste = von überall
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  egress:
  # Erlaube Verbindung zu MariaDB
  - to:
    - podSelector:
        matchLabels:
          app: mariadb
    ports:
    - protocol: TCP
      port: 3306
  # Erlaube DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Erlaube Internet (für App-Updates, etc.)
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
```

**Policies erklärt:**

1. **default-deny-all**
   ```yaml
   podSelector: {}  # Alle Pods
   policyTypes:
   - Ingress  # Kein eingehender Traffic
   - Egress   # Kein ausgehender Traffic
   ```
   - Baseline: Alles verboten
   - Andere Policies erlauben spezifische Verbindungen

2. **mariadb-allow-nextcloud**
   ```yaml
   ingress:
   - from:
     - podSelector:
         matchLabels:
           app: nextcloud  # Nur von Nextcloud-Pods
     ports:
     - port: 3306
   ```
   - MariaDB akzeptiert nur Verbindungen von Nextcloud
   - Port 3306 (MySQL)
   - **Sicherheit:** Andere Pods im Cluster können NICHT auf DB zugreifen

3. **nextcloud-allow-web**
   ```yaml
   ingress:
   - from: []  # Von überall
     ports:
     - port: 80
   ```
   - Nextcloud akzeptiert HTTP/HTTPS von überall
   - Kann zu MariaDB verbinden (Egress)
   - Kann Internet erreichen (für Updates)

#### Network Policies deployen

```bash
# 1. Policies erstellen
kubectl apply -f network-policies.yaml

# 2. Policies prüfen
kubectl get networkpolicies

# OUTPUT:
# NAME                       POD-SELECTOR   AGE
# default-deny-all           <none>         10s
# mariadb-allow-nextcloud    app=mariadb    10s
# nextcloud-allow-web        app=nextcloud  10s

# 3. Policy-Details
kubectl describe networkpolicy mariadb-allow-nextcloud
```

#### Network Policies testen

```bash
# 1. Baseline-Test: Nextcloud → MariaDB (sollte funktionieren)
kubectl exec -it deployment/nextcloud -- nc -zv mariadb 3306
# OUTPUT:
# Connection to mariadb 3306 port [tcp/mysql] succeeded!

# 2. Negative Test: Debug-Pod → MariaDB (sollte NICHT funktionieren)
kubectl run debug --image=busybox --rm -it --restart=Never -- sh
# Im Debug-Pod:
nc -zv mariadb.nextcloud-prod.svc.cluster.local 3306
# OUTPUT (nach Timeout):
# nc: mariadb.nextcloud-prod.svc.cluster.local (10.96.100.50:3306): Connection timed out

# 3. Positive Test: Internet-Zugriff von Nextcloud
kubectl exec -it deployment/nextcloud -- curl -I https://google.com
# OUTPUT:
# HTTP/2 200
```

**Was ist passiert?**
1. ✅ Nextcloud → MariaDB: Erlaubt (durch `mariadb-allow-nextcloud`)
2. ❌ Debug-Pod → MariaDB: Blockiert (durch `default-deny-all`)
3. ✅ Nextcloud → Internet: Erlaubt (durch `nextcloud-allow-web` Egress)

**Sicherheits-Gewinn:**
- Selbst wenn Angreifer in Debug-Pod eindringt: **Kein Zugriff auf Datenbank**
- Lateral Movement im Cluster verhindert

---

### 5.4 LoadBalancer Service - Externer Zugriff

#### ClusterIP vs. LoadBalancer

**ClusterIP (Stufe 1):**
- Nur innerhalb des Clusters erreichbar
- Kein externer Zugriff
- Port-Forwarding notwendig

**LoadBalancer (Stufe 2):**
- Externe IP-Adresse (via MetalLB oder Cloud-Provider)
- Direkt von außen erreichbar
- Kein Port-Forwarding notwendig

#### Voraussetzung: MetalLB

Falls MetalLB nicht installiert ist (prüfen mit `kubectl get pods -n metallb-system`):

```bash
# MetalLB installieren (nur wenn nicht vorhanden)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# IP-Pool konfigurieren
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: nextcloud-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.100.200-192.168.100.210  # Passen Sie IP-Range an!
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: nextcloud-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - nextcloud-pool
EOF
```

#### Nextcloud Service (LoadBalancer)

Erstellen Sie `nextcloud-service-lb.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nextcloud-lb
  namespace: nextcloud-prod
  labels:
    app: nextcloud
spec:
  type: LoadBalancer  # NEU: Externe IP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: nextcloud
  # Optional: Spezifische IP anfordern
  # loadBalancerIP: 192.168.100.200
```

```bash
# 1. Service erstellen
kubectl apply -f nextcloud-service-lb.yaml

# 2. Service prüfen (warten bis EXTERNAL-IP erscheint)
kubectl get service nextcloud-lb -w
# OUTPUT:
# NAME           TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)        AGE
# nextcloud-lb   LoadBalancer   10.96.200.100   <pending>         80:31234/TCP   5s
# nextcloud-lb   LoadBalancer   10.96.200.100   192.168.100.200   80:31234/TCP   30s

# 3. Von anderem Rechner im Netzwerk zugreifen
curl http://192.168.100.200
# Oder Browser: http://192.168.100.200
```

**Was ist passiert?**
1. Service Typ `LoadBalancer` erstellt
2. MetalLB weist externe IP zu (aus Pool `192.168.100.200-210`)
3. MetalLB konfiguriert ARP-Responses (Layer 2)
4. Externe Clients können jetzt direkt auf `192.168.100.200` zugreifen
5. Traffic wird auf alle 3 Nextcloud-Pods verteilt

#### DNS konfigurieren (optional)

Für schönere URLs:

```bash
# /etc/hosts editieren (Linux/macOS)
echo "192.168.100.200 nextcloud.local" | sudo tee -a /etc/hosts

# Oder: DNS-Eintrag im Router/DNS-Server erstellen
# nextcloud.local → 192.168.100.200

# Testen
curl http://nextcloud.local
```

---

### 5.5 Stufe 2 - Abschluss & Verifikation

#### Vollständiger Status-Check

```bash
# Alle Ressourcen
kubectl get all,pvc,secrets,networkpolicies,services

# StatefulSet prüfen
kubectl get statefulsets
# OUTPUT:
# NAME      READY   AGE
# mariadb   1/1     30m

# Deployment Replicas prüfen
kubectl get deployment nextcloud
# OUTPUT:
# NAME        READY   UP-TO-DATE   AVAILABLE   AGE
# nextcloud   3/3     3            3           20m

# Service mit externer IP
kubectl get service nextcloud-lb
# OUTPUT:
# NAME           TYPE           EXTERNAL-IP       PORT(S)
# nextcloud-lb   LoadBalancer   192.168.100.200   80:31234/TCP

# Resource-Verbrauch
kubectl top pods
# OUTPUT:
# NAME                       CPU(cores)   MEMORY(bytes)
# mariadb-0                  150m         450Mi
# nextcloud-abc123           200m         600Mi
# nextcloud-def456           180m         580Mi
# nextcloud-ghi789           190m         590Mi
```

#### Production-Readiness-Checkliste

✅ **Hochverfügbarkeit:**
- [x] 3 Nextcloud-Replicas
- [x] StatefulSet für MariaDB
- [x] Anti-Affinity (Pods auf verschiedenen Nodes)
- [x] Rolling Updates ohne Downtime

✅ **Resource Management:**
- [x] CPU/Memory Requests definiert
- [x] CPU/Memory Limits gesetzt
- [x] Pods können nicht alle Node-Ressourcen verbrauchen

✅ **Health Checks:**
- [x] Liveness Probes (Auto-Restart bei Problemen)
- [x] Readiness Probes (Traffic nur an gesunde Pods)

✅ **Security:**
- [x] Secrets für Credentials
- [x] Network Policies (Isolation)
- [x] Nicht-Root-User (Nextcloud-Image default)

✅ **Netzwerk:**
- [x] LoadBalancer Service (externe IP)
- [x] Service Load-Balancing über 3 Pods
- [x] Stabile DNS-Namen

#### Load-Test

```bash
# Apache Bench (100 Requests, 10 concurrent)
ab -n 100 -c 10 http://192.168.100.200/status.php

# Während des Tests: Resource-Verbrauch beobachten
kubectl top pods -l app=nextcloud

# Erwartetes Ergebnis:
# - Alle 3 Pods verarbeiten Requests (Last-Verteilung)
# - CPU/Memory bleibt unter Limits
```

#### Failover-Test

```bash
# 1. Terminal 1: Continuous Requests
while true; do curl -s http://192.168.100.200/status.php; sleep 1; done

# 2. Terminal 2: Pod löschen
kubectl delete pod -l app=nextcloud --force --grace-period=0 | head -1

# 3. Terminal 1: Beobachten
# → Maximal 1-2 Failed Requests
# → Dann wieder erfolgreich (andere Pods übernehmen)
```

**Erwartetes Ergebnis:**
- ✅ Minimale Downtime (1-2 Sekunden)
- ✅ Automatisches Self-Healing
- ✅ Neue Pods werden erstellt

---

## 6. Stufe 3: Monitoring & HA-Integration

### Übersicht Stufe 3

In dieser Stufe integrieren wir Nextcloud mit dem **Enterprise-Cluster**:
- ✅ **TLS/HTTPS**: Cert-Manager für automatische Zertifikate
- ✅ **Ingress**: Nginx Ingress mit Domain
- ✅ **Monitoring**: Prometheus ServiceMonitor
- ✅ **Logging**: Loki-Integration
- ✅ **Backup**: Automatische Datenbank-Backups
- ✅ **Dashboards**: Grafana-Monitoring

**Zeitaufwand:** ~40-50 Minuten
**Voraussetzung:** Abgeschlossene Stufe 2 + HA-Cluster mit Monitoring-Stack

---

### 6.1 TLS mit Cert-Manager

#### Cert-Manager Voraussetzung prüfen

```bash
# Cert-Manager installiert?
kubectl get pods -n cert-manager

# ClusterIssuer vorhanden?
kubectl get clusterissuers
```

Falls nicht installiert, siehe HA-Cluster-Dokumentation oder:

```bash
# Cert-Manager installieren
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Self-Signed ClusterIssuer (für Test)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

#### Certificate Resource erstellen

Erstellen Sie `nextcloud-certificate.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nextcloud-tls
  namespace: nextcloud-prod
spec:
  secretName: nextcloud-tls-secret
  duration: 2160h  # 90 Tage
  renewBefore: 360h  # Erneuern 15 Tage vorher
  subject:
    organizations:
    - Nextcloud Production
  commonName: nextcloud.yourdomain.com
  dnsNames:
  - nextcloud.yourdomain.com
  - nextcloud.local
  issuerRef:
    name: selfsigned-issuer  # Oder: letsencrypt-prod
    kind: ClusterIssuer
```

**Für Let's Encrypt (Production):**

```yaml
---
# Let's Encrypt ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # ← Ändern!
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
---
# Certificate mit Let's Encrypt
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nextcloud-tls
  namespace: nextcloud-prod
spec:
  secretName: nextcloud-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - nextcloud.yourdomain.com  # ← Ändern zu Ihrer Domain!
```

```bash
# Certificate erstellen
kubectl apply -f nextcloud-certificate.yaml

# Status prüfen
kubectl get certificate -n nextcloud-prod
# OUTPUT:
# NAME            READY   SECRET                  AGE
# nextcloud-tls   True    nextcloud-tls-secret    30s

# Secret prüfen (enthält TLS-Zertifikat)
kubectl get secret nextcloud-tls-secret -o yaml
```

**Was ist passiert?**
1. Cert-Manager erstellt Private Key
2. Certificate Signing Request (CSR) wird erstellt
3. Let's Encrypt validiert Domain (HTTP-01 Challenge via Ingress)
4. Zertifikat wird ausgestellt
5. Secret `nextcloud-tls-secret` enthält:
   - `tls.crt`: Zertifikat
   - `tls.key`: Private Key

---

### 6.2 Ingress mit TLS

#### Nginx Ingress Controller prüfen

```bash
# Ingress Controller installiert?
kubectl get pods -n ingress-nginx

# IngressClass verfügbar?
kubectl get ingressclasses
```

#### Ingress Resource erstellen

Erstellen Sie `nextcloud-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud
  namespace: nextcloud-prod
  annotations:
    # Nginx-spezifische Einstellungen
    nginx.ingress.kubernetes.io/proxy-body-size: "10g"  # Max. Upload-Größe
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/server-snippet: |
      location = /.well-known/carddav {
        return 301 $scheme://$host/remote.php/dav;
      }
      location = /.well-known/caldav {
        return 301 $scheme://$host/remote.php/dav;
      }
    # Cert-Manager Annotation
    cert-manager.io/cluster-issuer: "selfsigned-issuer"  # Oder: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - nextcloud.yourdomain.com  # ← Ändern!
    secretName: nextcloud-tls-secret
  rules:
  - host: nextcloud.yourdomain.com  # ← Ändern!
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nextcloud-lb  # Oder: nextcloud (ClusterIP Service)
            port:
              number: 80
```

**Annotations erklärt:**

| Annotation | Zweck |
|------------|-------|
| `proxy-body-size: "10g"` | Max. 10GB Datei-Uploads |
| `proxy-buffering: "off"` | Streaming für große Dateien |
| `server-snippet` | CalDAV/CardDAV Redirects für Nextcloud |
| `cert-manager.io/cluster-issuer` | Automatische TLS-Zertifikat-Erstellung |

```bash
# Ingress erstellen
kubectl apply -f nextcloud-ingress.yaml

# Ingress prüfen
kubectl get ingress nextcloud
# OUTPUT:
# NAME        CLASS   HOSTS                      ADDRESS           PORTS     AGE
# nextcloud   nginx   nextcloud.yourdomain.com   192.168.100.100   80, 443   30s

# Ingress-Details
kubectl describe ingress nextcloud
```

#### HTTPS testen

```bash
# DNS/hosts konfigurieren (falls nötig)
echo "192.168.100.100 nextcloud.yourdomain.com" | sudo tee -a /etc/hosts

# HTTP → HTTPS Redirect testen
curl -I http://nextcloud.yourdomain.com
# OUTPUT:
# HTTP/1.1 308 Permanent Redirect
# Location: https://nextcloud.yourdomain.com/

# HTTPS testen
curl -k https://nextcloud.yourdomain.com/status.php
# OUTPUT:
# {"installed":true,"maintenance":false,...}

# Browser: https://nextcloud.yourdomain.com
```

#### Nextcloud Trusted Domains aktualisieren

Nextcloud muss die neue Domain kennen:

```bash
# Option 1: Environment-Variable (Deployment aktualisieren)
kubectl set env deployment/nextcloud NEXTCLOUD_TRUSTED_DOMAINS="nextcloud.yourdomain.com"

# Option 2: Direkt in config.php (temporär)
kubectl exec -it deployment/nextcloud -- bash
# Im Container:
vi /var/www/html/config/config.php
# Hinzufügen:
# 'trusted_domains' =>
# array (
#   0 => 'localhost',
#   1 => 'nextcloud.yourdomain.com',
# ),
```

---

### 6.3 Prometheus Monitoring

#### ServiceMonitor erstellen

Erstellen Sie `nextcloud-servicemonitor.yaml`:

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
    interval: 30s
    path: /ocs/v2.php/apps/serverinfo/api/v1/info?format=json
    scheme: http
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mariadb
  namespace: nextcloud-prod
  labels:
    app: mariadb
spec:
  selector:
    matchLabels:
      app: mariadb
  endpoints:
  - port: mysql
    interval: 30s
```

**Wichtig:** Nextcloud benötigt das **ServerInfo**-Plugin für Metriken:

```bash
# ServerInfo-App aktivieren (in Nextcloud-Pod)
kubectl exec -it deployment/nextcloud -- su -s /bin/bash www-data -c "php occ app:install serverinfo"
kubectl exec -it deployment/nextcloud -- su -s /bin/bash www-data -c "php occ app:enable serverinfo"

# ServiceMonitor erstellen
kubectl apply -f nextcloud-servicemonitor.yaml

# ServiceMonitor prüfen
kubectl get servicemonitors -n nextcloud-prod
```

#### Prometheus prüfen

```bash
# Prometheus UI öffnen (Port-Forward)
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Browser: http://localhost:9090
# Targets prüfen: Status → Targets
# Suche nach "nextcloud-prod/nextcloud" und "nextcloud-prod/mariadb"
```

**Metriken testen:**

In Prometheus UI → Graph:
```promql
# Nextcloud-Uptime
up{job="nextcloud"}

# Anzahl Nextcloud-Users
nextcloud_users_total

# MariaDB-Verbindungen
mysql_global_status_threads_connected
```

---

### 6.4 Grafana Dashboard

#### Dashboard importieren

Erstellen Sie `nextcloud-dashboard.json` (vereinfachte Version):

```json
{
  "dashboard": {
    "title": "Nextcloud Production",
    "panels": [
      {
        "title": "Nextcloud Pods",
        "targets": [
          {
            "expr": "up{job=\"nextcloud\"}",
            "legendFormat": "{{pod}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "CPU Usage",
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"nextcloud-prod\"}[5m])) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Memory Usage",
        "targets": [
          {
            "expr": "sum(container_memory_working_set_bytes{namespace=\"nextcloud-prod\"}) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Active Users",
        "targets": [
          {
            "expr": "nextcloud_users_total",
            "legendFormat": "Total Users"
          }
        ],
        "type": "stat"
      }
    ]
  }
}
```

#### Dashboard in Grafana laden

```bash
# Grafana UI öffnen
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Browser: http://localhost:3000
# Login: admin / (Passwort aus Secret)
kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d

# Dashboard importieren:
# 1. "+" → "Import"
# 2. "Upload JSON file" → nextcloud-dashboard.json
# 3. "Import"
```

**Alternative: ConfigMap für automatisches Laden**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nextcloud-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  nextcloud.json: |
    {... Dashboard JSON ...}
```

---

### 6.5 Backup-Strategie

#### Datenbank-Backup CronJob

Erstellen Sie `db-backup-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mariadb-backup
  namespace: nextcloud-prod
spec:
  schedule: "0 2 * * *"  # Täglich um 2 Uhr nachts
  successfulJobsHistoryLimit: 7  # Behalte 7 erfolgreiche Backups
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: docker.io/library/mariadb:10.11
            env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nextcloud-db
                  key: MYSQL_ROOT_PASSWORD
            command:
            - /bin/bash
            - -c
            - |
              set -e
              BACKUP_FILE="/backup/nextcloud-$(date +%Y%m%d-%H%M%S).sql.gz"
              echo "Starting backup to $BACKUP_FILE"

              mysqldump -h mariadb -u root -p$MYSQL_ROOT_PASSWORD \
                --single-transaction \
                --routines \
                --triggers \
                --all-databases \
                | gzip > $BACKUP_FILE

              echo "Backup completed: $BACKUP_FILE"

              # Cleanup: Lösche Backups älter als 7 Tage
              find /backup -name "nextcloud-*.sql.gz" -mtime +7 -delete

              echo "Old backups cleaned up"
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-storage
---
# PVC für Backups
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-storage
  namespace: nextcloud-prod
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

**CronJob-Optionen erklärt:**

| Option | Wert | Bedeutung |
|--------|------|-----------|
| `schedule` | `0 2 * * *` | Täglich um 2:00 Uhr |
| `successfulJobsHistoryLimit` | `7` | Behalte letzte 7 erfolgreiche Jobs |
| `--single-transaction` | | Konsistentes Backup ohne DB-Lock |
| `--all-databases` | | Alle Datenbanken sichern |
| `gzip` | | Kompression (spart Speicher) |

#### Backup deployen und testen

```bash
# CronJob erstellen
kubectl apply -f db-backup-cronjob.yaml

# CronJob prüfen
kubectl get cronjobs

# Manuell triggern (zum Testen)
kubectl create job --from=cronjob/mariadb-backup manual-backup-1

# Job-Status
kubectl get jobs
kubectl logs job/manual-backup-1

# Backup-Dateien prüfen
kubectl exec -it deployment/nextcloud -- ls -lh /backup/
# Oder: Mount backup-storage PVC in Debug-Pod
```

#### Backup wiederherstellen

```bash
# 1. Backup-Liste anzeigen
kubectl exec -it deployment/nextcloud -- ls -lh /backup/

# 2. Backup wiederherstellen
BACKUP_FILE="nextcloud-20250115-020000.sql.gz"

kubectl exec -it mariadb-0 -- bash -c "
  zcat /backup/$BACKUP_FILE | mysql -u root -p\$MYSQL_ROOT_PASSWORD
"

# 3. Nextcloud-Pods neu starten
kubectl rollout restart deployment/nextcloud
```

---

### 6.6 Stufe 3 - Abschluss

#### Enterprise-Readiness-Checkliste

✅ **TLS/Security:**
- [x] HTTPS mit Cert-Manager
- [x] Automatische Zertifikat-Erneuerung
- [x] Network Policies aktiv

✅ **Monitoring:**
- [x] Prometheus ServiceMonitor
- [x] Grafana Dashboard
- [x] Metriken von Nextcloud + MariaDB

✅ **Backup:**
- [x] Automatische tägliche Backups
- [x] 7-Tage-Retention
- [x] Restore-Prozedur dokumentiert

✅ **Hochverfügbarkeit:**
- [x] 3 Nextcloud-Replicas
- [x] Ingress mit Load Balancing
- [x] StatefulSet für MariaDB

✅ **Zugriff:**
- [x] HTTPS-Domain (nextcloud.yourdomain.com)
- [x] Externe IP (MetalLB)
- [x] CalDAV/CardDAV Redirects

---

## 7. Backup & Restore

### 7.1 Vollständiges Backup

#### Was muss gesichert werden?

1. **Datenbank** (MariaDB)
   - Alle Nextcloud-Metadaten
   - User-Informationen
   - Shares, Permissions, etc.

2. **Nextcloud-Dateien** (PVC: nextcloud-data)
   - User-Uploads
   - Nextcloud-Apps
   - Konfiguration (`config/config.php`)

3. **Kubernetes-Manifeste**
   - Deployments, Services, Ingress
   - Secrets, ConfigMaps
   - Network Policies

#### Backup-Skript (vollständig)

Erstellen Sie `backup-nextcloud-full.sh`:

```bash
#!/bin/bash
set -e

NAMESPACE="nextcloud-prod"
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "=== Nextcloud Full Backup ==="
echo "Backup Directory: $BACKUP_DIR"

# 1. Kubernetes-Manifeste exportieren
echo "1. Exporting Kubernetes manifests..."
kubectl get all,pvc,secrets,ingress,networkpolicies,servicemonitors -n $NAMESPACE -o yaml > "$BACKUP_DIR/k8s-resources.yaml"

# 2. Datenbank-Backup
echo "2. Backing up MariaDB..."
DB_PASSWORD=$(kubectl get secret nextcloud-db -n $NAMESPACE -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d)

kubectl exec -n $NAMESPACE mariadb-0 -- bash -c "
  mysqldump -u root -p$DB_PASSWORD \
    --single-transaction \
    --routines \
    --triggers \
    --all-databases \
    | gzip
" > "$BACKUP_DIR/database.sql.gz"

# 3. Nextcloud-Dateien (PVC Snapshot oder Kopie)
echo "3. Creating PVC snapshot..."
# Option A: VolumeSnapshot (wenn unterstützt)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: nextcloud-data
EOF

# Option B: Datei-Kopie (langsamer, aber universell)
# kubectl cp $NAMESPACE/nextcloud-pod:/var/www/html "$BACKUP_DIR/nextcloud-files"

echo "Backup completed: $BACKUP_DIR"
echo "Files:"
ls -lh "$BACKUP_DIR"
```

**Backup ausführen:**

```bash
chmod +x backup-nextcloud-full.sh
./backup-nextcloud-full.sh
```

---

### 7.2 Disaster Recovery

#### Kompletter Cluster-Restore

**Szenario:** Cluster ist komplett ausgefallen, Neuaufbau von Grund auf.

```bash
# 1. Namespace erstellen
kubectl create namespace nextcloud-prod

# 2. Secrets wiederherstellen (aus Backup)
kubectl apply -f backups/20250115-020000/k8s-resources.yaml

# 3. PVCs manuell erstellen (falls VolumeSnapshot nicht unterstützt)
kubectl apply -f mariadb-pvc.yaml
kubectl apply -f nextcloud-pvc.yaml

# 4. Datenbank-Daten wiederherstellen
# Temporärer MariaDB-Pod für Restore
kubectl run mariadb-restore --image=mariadb:10.11 -n nextcloud-prod \
  --env MYSQL_ROOT_PASSWORD=temp123 \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "mariadb",
      "image": "mariadb:10.11",
      "volumeMounts": [{
        "name": "data",
        "mountPath": "/var/lib/mysql"
      }]
    }],
    "volumes": [{
      "name": "data",
      "persistentVolumeClaim": {
        "claimName": "mariadb-data-mariadb-0"
      }
    }]
  }
}'

# Warten bis Pod läuft
kubectl wait --for=condition=ready pod/mariadb-restore -n nextcloud-prod --timeout=300s

# Backup in Pod kopieren
kubectl cp backups/20250115-020000/database.sql.gz nextcloud-prod/mariadb-restore:/tmp/

# Restore durchführen
kubectl exec -it mariadb-restore -n nextcloud-prod -- bash -c "
  zcat /tmp/database.sql.gz | mysql -u root -ptemp123
"

# Restore-Pod löschen
kubectl delete pod mariadb-restore -n nextcloud-prod

# 5. StatefulSet + Deployment wiederherstellen
kubectl apply -f mariadb-statefulset.yaml
kubectl apply -f nextcloud-deployment-ha.yaml
kubectl apply -f nextcloud-service-lb.yaml
kubectl apply -f nextcloud-ingress.yaml

# 6. Verifizieren
kubectl get pods -n nextcloud-prod
```

---

## 8. Troubleshooting

### 8.1 Häufige Probleme

#### Problem: Nextcloud-Pod startet nicht

**Symptome:**
```bash
kubectl get pods
# nextcloud-abc123   0/1   CrashLoopBackOff   5   10m
```

**Diagnose:**
```bash
# Logs prüfen
kubectl logs nextcloud-abc123

# Events prüfen
kubectl describe pod nextcloud-abc123

# Häufige Ursachen:
# 1. Datenbank nicht erreichbar
kubectl exec -it nextcloud-abc123 -- ping mariadb

# 2. PVC nicht gemountet
kubectl describe pvc nextcloud-data

# 3. Resource Limits zu niedrig
kubectl top pod nextcloud-abc123
```

**Lösung:**
```bash
# Datenbank-Verbindung testen
kubectl run -it --rm debug --image=mysql:8 --restart=Never -- \
  mysql -h mariadb -u nextcloud -p

# PVC-Problem: StorageClass prüfen
kubectl get sc

# Resource-Limits erhöhen
kubectl set resources deployment/nextcloud \
  --limits=cpu=2,memory=2Gi \
  --requests=cpu=500m,memory=512Mi
```

---

#### Problem: "Trusted Domain" Fehler

**Symptome:**
Browser zeigt: "Access through untrusted domain"

**Lösung:**
```bash
# Option 1: Environment-Variable
kubectl set env deployment/nextcloud \
  NEXTCLOUD_TRUSTED_DOMAINS="localhost nextcloud.local nextcloud.yourdomain.com"

# Option 2: Manuell in config.php
kubectl exec -it deployment/nextcloud -- bash
vi /var/www/html/config/config.php
# Hinzufügen:
# 'trusted_domains' =>
# array (
#   0 => 'localhost',
#   1 => 'nextcloud.yourdomain.com',
# ),

# Pods neu starten
kubectl rollout restart deployment/nextcloud
```

---

#### Problem: Datei-Uploads schlagen fehl

**Symptome:**
"Error while uploading file" im Browser

**Diagnose:**
```bash
# Ingress Body-Size prüfen
kubectl describe ingress nextcloud | grep body-size

# PHP Memory Limit prüfen
kubectl exec -it deployment/nextcloud -- php -i | grep memory_limit
```

**Lösung:**
```bash
# Ingress Annotation erhöhen
kubectl annotate ingress nextcloud \
  nginx.ingress.kubernetes.io/proxy-body-size=10g --overwrite

# PHP Memory Limit erhöhen (Environment-Variable)
kubectl set env deployment/nextcloud PHP_MEMORY_LIMIT=512M
```

---

#### Problem: Langsame Performance

**Diagnose:**
```bash
# Resource-Verbrauch
kubectl top pods -n nextcloud-prod

# Anzahl Pods
kubectl get pods -l app=nextcloud

# PVC Performance (IOPS)
kubectl exec -it deployment/nextcloud -- bash
dd if=/dev/zero of=/var/www/html/testfile bs=1M count=100
# Sollte > 50 MB/s sein
```

**Lösung:**
```bash
# Mehr Replicas
kubectl scale deployment/nextcloud --replicas=5

# Resource-Limits erhöhen
kubectl set resources deployment/nextcloud \
  --limits=cpu=4,memory=4Gi \
  --requests=cpu=1,memory=1Gi

# Redis für Session-Caching hinzufügen (fortgeschritten)
```

---

### 8.2 Debugging-Commands

```bash
# Alle Events im Namespace
kubectl get events -n nextcloud-prod --sort-by='.lastTimestamp'

# Pod-Logs (alle Container)
kubectl logs -l app=nextcloud --all-containers=true

# Interaktive Shell in Pod
kubectl exec -it deployment/nextcloud -- bash

# Datenbank-Verbindung testen
kubectl run -it --rm mysql-client --image=mysql:8 --restart=Never -- \
  mysql -h mariadb.nextcloud-prod.svc.cluster.local -u nextcloud -p

# DNS-Auflösung testen
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup mariadb.nextcloud-prod.svc.cluster.local

# Network Policy testen
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
# Im Pod: nc -zv mariadb 3306
```

---

## 9. Wartung & Updates

### 9.1 Nextcloud-Update

#### Update-Prozess (Rolling Update)

```bash
# 1. Aktuelles Image-Version prüfen
kubectl get deployment nextcloud -o jsonpath='{.spec.template.spec.containers[0].image}'

# 2. Neue Version setzen
kubectl set image deployment/nextcloud nextcloud=docker.io/library/nextcloud:29-apache

# 3. Rollout beobachten
kubectl rollout status deployment/nextcloud

# 4. Rollout-Historie
kubectl rollout history deployment/nextcloud
```

**Was passiert?**
1. Kubernetes erstellt neuen Pod mit Version 29
2. Warte bis neuer Pod `Ready`
3. Lösche alten Pod mit Version 28
4. Wiederhole für alle Pods
5. **Keine Downtime** (maxUnavailable: 0)

#### Rollback bei Problemen

```bash
# Sofortiger Rollback zur vorherigen Version
kubectl rollout undo deployment/nextcloud

# Rollback zu spezifischer Revision
kubectl rollout history deployment/nextcloud
kubectl rollout undo deployment/nextcloud --to-revision=2
```

---

### 9.2 MariaDB-Update

**Achtung:** MariaDB-Updates sind komplexer (Datenbank-Schema-Migrationen)!

```bash
# 1. BACKUP ERSTELLEN!
./backup-nextcloud-full.sh

# 2. Maintenance Mode aktivieren
kubectl exec -it deployment/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --on"

# 3. MariaDB-Image aktualisieren
kubectl set image statefulset/mariadb mariadb=docker.io/library/mariadb:10.12

# 4. Rollout beobachten (StatefulSet: Sequentiell!)
kubectl rollout status statefulset/mariadb

# 5. Datenbank-Upgrade (falls nötig)
kubectl exec -it mariadb-0 -- mysql_upgrade -u root -p

# 6. Maintenance Mode deaktivieren
kubectl exec -it deployment/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

---

### 9.3 Kubernetes-Manifeste pflegen

**GitOps-Workflow (empfohlen):**

```bash
# 1. Alle Manifeste exportieren
kubectl get deployment,statefulset,service,ingress,pvc,networkpolicy \
  -n nextcloud-prod -o yaml > nextcloud-prod-manifests.yaml

# 2. Bereinigen (automatisch generierte Felder entfernen)
# Zu löschen:
# - metadata.resourceVersion
# - metadata.uid
# - metadata.creationTimestamp
# - status (ganzer Block)
# - spec.clusterIP (Services)

# 3. In Git committen
git add nextcloud-prod-manifests.yaml
git commit -m "Update Nextcloud production manifests"
git push

# 4. Flux CD automatisch synchronisiert (wenn konfiguriert)
```

---

## 10. Best Practices

### 10.1 Security Best Practices

✅ **Secrets Management:**
- Niemals Secrets in Git committen
- Rotation von Passwörtern alle 90 Tage
- Externe Secret-Stores (Vault, Sealed Secrets)

✅ **Network Policies:**
- "Deny by default, allow specific"
- Regelmäßig auditieren (`kubectl get networkpolicies`)

✅ **RBAC:**
- Separate ServiceAccounts für Nextcloud/MariaDB
- Minimale Berechtigungen (Least Privilege)

✅ **Pod Security:**
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 33  # www-data
    fsGroup: 33
```

✅ **Image Security:**
- Nur offizielle Images von Docker Hub
- Image-Tags mit Versionen (nicht `latest`)
- Vulnerability Scanning (Trivy, Clair)

---

### 10.2 Performance Best Practices

✅ **Resource Tuning:**
```yaml
resources:
  requests:
    cpu: 1000m       # Basis-Last
    memory: 1Gi
  limits:
    cpu: 4000m       # 4x für Spitzen
    memory: 4Gi
```

✅ **Horizontal Pod Autoscaling:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nextcloud
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nextcloud
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

✅ **Redis für Caching:**
```yaml
# Redis Deployment für Session-Storage
- name: REDIS_HOST
  value: redis
- name: REDIS_HOST_PORT
  value: "6379"
```

✅ **PVC Performance:**
- SSD-basierte StorageClass
- ReadWriteMany (NFS) für Nextcloud-Dateien
- ReadWriteOnce (iSCSI/SAN) für MariaDB

---

### 10.3 Availability Best Practices

✅ **Pod Disruption Budget:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nextcloud-pdb
spec:
  minAvailable: 2  # Mindestens 2 Pods während Wartung
  selector:
    matchLabels:
      app: nextcloud
```

✅ **Liveness/Readiness Probes:**
```yaml
livenessProbe:
  httpGet:
    path: /status.php
    port: 80
  initialDelaySeconds: 60   # Genug Zeit für Startup
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3       # Nach 30s (3×10s) neu starten

readinessProbe:
  httpGet:
    path: /status.php
    port: 80
  initialDelaySeconds: 10   # Schneller bereit als liveness
  periodSeconds: 5
  failureThreshold: 2       # Nach 10s (2×5s) aus Endpoints
```

✅ **Multi-AZ Deployment:**
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:  # HARD constraint
    - labelSelector:
        matchLabels:
          app: nextcloud
      topologyKey: topology.kubernetes.io/zone  # Verschiedene Availability Zones
```

---

### 10.4 Backup Best Practices

✅ **3-2-1 Rule:**
- **3** Kopien der Daten
- **2** verschiedene Speichermedien
- **1** Kopie off-site

✅ **Automatisierung:**
- Tägliche automatische Backups (CronJob)
- Wöchentliche vollständige Backups
- Monatliche Archivierung

✅ **Testing:**
```bash
# Monatlicher Restore-Test
# 1. Test-Namespace erstellen
kubectl create namespace nextcloud-restore-test

# 2. Backup wiederherstellen
./restore-backup.sh backups/20250115-020000 nextcloud-restore-test

# 3. Funktionalität prüfen
kubectl port-forward -n nextcloud-restore-test svc/nextcloud 8081:80
curl http://localhost:8081/status.php

# 4. Test-Namespace löschen
kubectl delete namespace nextcloud-restore-test
```

---

## Zusammenfassung

### Was Sie erreicht haben

Nach Abschluss aller 3 Stufen haben Sie:

✅ **Stufe 1 - Basis:**
- Funktionierende Nextcloud mit MariaDB
- Grundlegendes Kubernetes-Verständnis
- Persistente Datenbank und Dateien

✅ **Stufe 2 - Production-Ready:**
- Hochverfügbarkeit (3 Nextcloud-Replicas)
- StatefulSet für Datenbank
- Resource Management (Requests/Limits)
- Health Checks (Liveness/Readiness)
- Network Policies (Security)
- LoadBalancer Service (externer Zugriff)

✅ **Stufe 3 - Enterprise:**
- HTTPS mit automatischen Zertifikaten
- Ingress mit Domain
- Prometheus Monitoring
- Grafana Dashboards
- Automatische Backups
- Integration mit HA-Cluster

### Produktionsreife Features

| Feature | Stufe 1 | Stufe 2 | Stufe 3 |
|---------|---------|---------|---------|
| Funktionalität | ✅ | ✅ | ✅ |
| Hochverfügbarkeit | ❌ | ✅ | ✅ |
| Resource Limits | ❌ | ✅ | ✅ |
| Health Checks | ❌ | ✅ | ✅ |
| Network Security | ❌ | ✅ | ✅ |
| Externer Zugriff | Port-Forward | LoadBalancer | Ingress + TLS |
| Monitoring | ❌ | ❌ | ✅ |
| Backups | ❌ | ❌ | ✅ |
| **Production-Ready** | ❌ | ⚠️ | ✅ |

### Nächste Schritte

1. **Performance-Tuning:**
   - Redis für Caching
   - MariaDB Query-Optimierung
   - CDN für statische Assets

2. **Erweiterte Security:**
   - RBAC für Nextcloud ServiceAccount
   - Pod Security Policies
   - OPA/Gatekeeper für Policy Enforcement

3. **Skalierung:**
   - Horizontal Pod Autoscaler (HPA)
   - Vertical Pod Autoscaler (VPA)
   - Cluster Autoscaler

4. **Multi-Tenant:**
   - Mehrere Nextcloud-Instanzen pro Namespace
   - Shared MariaDB mit separaten Datenbanken

5. **Disaster Recovery:**
   - Velero für Cluster-weite Backups
   - Cross-Region Replikation
   - Chaos Engineering (Failure-Tests)

---

## Anhänge

### A.1 Vollständige YAML-Manifeste

Alle Manifeste sind verfügbar in:
- `Kubernetes HA/manifests/nextcloud/`

### A.2 Skript-Sammlung

- `deploy-nextcloud-basic.sh`: Stufe 1 automatisch deployen
- `deploy-nextcloud-production.sh`: Stufe 2+3 deployen
- `backup-nextcloud-full.sh`: Vollständiges Backup
- `restore-nextcloud.sh`: Disaster Recovery

### A.3 Troubleshooting-Matrix

| Problem | Symptom | Diagnose-Command | Lösung |
|---------|---------|------------------|--------|
| Pod startet nicht | CrashLoopBackOff | `kubectl logs` | Logs prüfen, Events checken |
| DB nicht erreichbar | Connection refused | `kubectl exec -- ping mariadb` | Service/NetworkPolicy prüfen |
| Datei-Upload fehl | 413 Payload Too Large | `kubectl describe ingress` | proxy-body-size erhöhen |
| Langsame Performance | Hohe Latenz | `kubectl top pods` | Mehr Replicas, Resources erhöhen |
| Zertifikat ungültig | HTTPS-Warnung | `kubectl describe certificate` | Cert-Manager Logs prüfen |

---

**Viel Erfolg mit Ihrer produktionsreifen Nextcloud-Installation auf Kubernetes!** 🚀

