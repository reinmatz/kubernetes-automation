# GitOps Quick Reference - Flux CD Cheat Sheet

---

## 🚀 Quick Start Commands

```bash
# 1. Flux CLI installieren
curl -s https://fluxcd.io/install.sh | bash

# 2. GitHub Token erstellen
# GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
# Scopes: repo, read:org
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx

# 3. Repository clonen & Setup
git clone https://github.com/YOUR_USER/k8s-cluster-config.git
cd k8s-cluster-config
mkdir -p clusters/dev/{apps,infrastructure}

# 4. Flux Bootstrap
flux bootstrap github \
  --owner=YOUR_USER \
  --repo=k8s-cluster-config \
  --branch=main \
  --path=clusters/dev \
  --personal

# 5. Verify
flux check
kubectl get pods -n flux-system
```

---

## 🔍 Status & Debugging

### Flux Status überprüfen

```bash
# Quick status
flux check

# Detaillierte Status
flux get all -A

# Nur fehlgeschlagene Ressourcen
flux get all -A --status=failed

# Watcher aktivieren
flux get all -A --watch
```

### Logs anschauen

```bash
# Alle Flux Logs
flux logs --all-namespaces --follow

# Logs seit letzter Stunde
flux logs --all-namespaces --since=1h

# Nur Source Controller Logs
flux logs -n flux-system -l app=source-controller --follow

# Nur Kustomize Controller
flux logs -n flux-system -l app=kustomize-controller --follow

# Spezifische Kustomization debuggen
flux logs -n flux-system -l kustomize.toolkit.fluxcd.io/name=cluster-config
```

### Detaillierte Beschreibung

```bash
# GitRepository Status
kubectl describe gitrepository cluster-config -n flux-system

# Kustomization Status
kubectl describe kustomization cluster-config -n flux-system

# HelmRelease Status
kubectl describe helmrelease prometheus -n monitoring

# Events ansehen
kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -20
```

### Manuelles Reconcile

```bash
# Sofort syncen (statt auf Interval warten)
flux reconcile source git cluster-config --with-status

# Kustomization neu deployen
flux reconcile kustomization cluster-config --with-status

# Helm Release neu deployen
flux reconcile helmrelease prometheus -n monitoring --with-status

# Verbose output
flux reconcile kustomization cluster-config --with-status -v
```

---

## 📝 Häufige Tasks

### Neue App deployen

```bash
# 1. App Verzeichnis erstellen
mkdir -p clusters/dev/apps/my-app
cd clusters/dev/apps/my-app

# 2. Kustomization erstellen
cat > kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
EOF

# 3. Manifests erstellen (deployment.yaml, service.yaml)

# 4. Committen & pushen
git add .
git commit -m "Add my-app to dev"
git push origin main

# 5. Flux synchronisiert automatisch (nach ~30 Sekunden)
```

### Helm Chart updaten

```bash
# Chart im Repo aktualisieren
cat > clusters/dev/apps/prometheus.yaml << 'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  chart:
    spec:
      chart: kube-prometheus-stack
      version: "55.1.0"  # Neue Version
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
EOF

git add .
git commit -m "Upgrade Prometheus to 55.1.0"
git push

# Verify
flux reconcile helmrelease prometheus -n monitoring --with-status
```

### Secret verschlüsseln

```bash
# 1. SOPS installieren
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops

# 2. AGE installieren
curl -LO https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xf age-v1.1.1-linux-amd64.tar.gz && sudo mv age/age /usr/local/bin/

# 3. AGE Key generieren
age-keygen -o $HOME/.config/sops/age/keys.txt

# 4. .sops.yaml in Repo Root
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: clusters/.*/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

# 5. Secret erstellen & verschlüsseln
cat > clusters/dev/apps/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
data:
  password: cGFzc3dvcmQxMjM=
EOF

sops -e -i clusters/dev/apps/secret.yaml

# 6. Checken dass es verschlüsselt ist
grep "sops:" clusters/dev/apps/secret.yaml

# 7. Committen
git add .
git commit -m "Add encrypted secret"
git push
```

### Image Tag aktualisieren

```bash
# 1. Kustomization mit Image Updates
cat > clusters/dev/apps/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

images:
  - name: nginx
    newTag: "1.26"
EOF

# 2. Oder manuell in Deployment updaten
# clusters/dev/apps/deployment.yaml
# spec.template.spec.containers[0].image: nginx:1.26

git add .
git commit -m "Update nginx to 1.26"
git push
```

### Rollback zu vorherigem State

```bash
# 1. Git history anschauen
git log --oneline clusters/dev/ | head -10

# 2. Zu vorherigem Commit zurück
git revert <commit-hash>

# 3. Push
git push origin main

# 4. Flux synchronisiert automatisch zurück
flux reconcile kustomization cluster-config --with-status
```

---

## ⚠️ Troubleshooting

### Pod zeigt ImagePullBackOff

```bash
# 1. Problem anschauen
kubectl describe pod my-pod -n my-namespace

# 2. Image vorhanden? Falsche Registry?
kubectl get pods -n my-namespace -o jsonpath='{.items[0].spec.containers[0].image}'

# 3. Image Policy in Kustomization prüfen
cat clusters/dev/apps/kustomization.yaml | grep -A 5 "images:"

# 4. Pull Secret vorhanden?
kubectl get secrets -n my-namespace

# 5. Registry erreichbar?
kubectl run -it debug --image=busybox -- sh
# In Container: wget https://registry-url/v2/
```

### Flux synct nicht

```bash
# 1. Flux Status
flux check

# 2. GitRepository Status
kubectl describe gitrepository cluster-config -n flux-system

# 3. GitHub Connectivity
curl -I https://github.com/YOUR_USER/k8s-cluster-config

# 4. SSH Key oder Token Problem?
# GitHub → Settings → Developer settings → Check Token Scopes
# Sollte: repo, read:org

# 5. Repo im Cluster erreichbar?
kubectl exec -it -n flux-system <source-controller-pod> -- sh
# curl https://github.com/YOUR_USER/k8s-cluster-config

# 6. Neuen Token setzen
kubectl create secret generic flux-system \
  --from-literal=username=git \
  --from-literal=password=$NEW_GITHUB_TOKEN \
  -n flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

# 7. Reconcile forcen
flux reconcile source git cluster-config --with-status --force
```

### Fehler: "failed to download chart"

```bash
# 1. Helm Repo erreichbar?
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community

# 2. Chart Version vorhanden?
helm search repo prometheus-community/kube-prometheus-stack --versions

# 3. Flux Logs prüfen
flux logs -n flux-system -l app=helm-controller --follow

# 4. HelmRepository Status
kubectl describe helmrepository prometheus-community -n flux-system

# 5. Chart aktualisieren in manifest
# Version ändern in clusters/dev/apps/prometheus.yaml
```

### Secret nicht dekryptiert

```bash
# 1. SOPS Status
kubectl get secrets -n flux-system sops-age

# 2. .sops.yaml korrekt?
cat .sops.yaml

# 3. Manuelle Test
export SOPS_AGE_RECIPIENTS=$(cat $HOME/.config/sops/age/keys.txt | grep "public key:" | sed 's/public key: //')
sops -d clusters/dev/apps/secret.yaml

# 4. Flux mit SOPS starten?
kubectl logs -n flux-system -l app=kustomize-controller | grep -i sops

# 5. AGE Key nur base64 encoden!
kubectl get secrets -n flux-system sops-age -o jsonpath='{.data.age\.agekey}' | base64 -d | head -1

# 6. Secret policy korrekt im manifest?
head -20 clusters/dev/apps/secret.yaml  # Sollte "sops:" Section haben
```

### Too many requests zu GitHub

```bash
# Problem: Rate Limit überschritten
# Lösung: Interval erhöhen

kubectl edit gitrepository cluster-config -n flux-system
# spec.interval: ändern von 30s zu 5m

# Oder als Datei:
cat > clusters/dev/infrastructure/sources.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 5m  # Nicht zu oft pollen
  url: https://github.com/YOUR_USER/k8s-cluster-config
EOF

git add . && git commit -m "Increase polling interval" && git push
```

---

## 🔒 Security Best Practices

### Never do:

```bash
# ❌ FALSCH: Password im Git
echo "password: mysecretpassword" >> secret.yaml
git add secret.yaml
git push

# ❌ FALSCH: Unencrypted secret commiten
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
data:
  password: cGFzc3dvcmQxMjM=  # base64, NICHT encrypted!

# ❌ FALSCH: Token in Repository
GITHUB_TOKEN=ghp_xxxxxxxxxxxx  # Niemals ins Repo!
```

### Richtig machen:

```bash
# ✅ RICHTIG: Secret mit SOPS verschlüsseln
sops -e -i secret.yaml

# ✅ RICHTIG: Token als GitHub Secret
# GitHub → Settings → Secrets and variables → Actions

# ✅ RICHTIG: Environment variables nutzen
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 📊 Monitoring Flux

### Health Check

```bash
# Status aller Flux Resources
flux get all -A

# Output sollte sein:
# NAME                  REVISION  SUSPENDED  READY  MESSAGE
# gitrepository/...     main      False      True   fetched revision main/xxxxx
# kustomization/...     main      False      True   Applied revision main/xxxxx
```

### Prometheus Metrics

```bash
# Flux exposes Prometheus metrics
kubectl port-forward -n flux-system svc/source-controller 8080:8080 &
curl http://localhost:8080/metrics | grep gotk

# Wichtige Metriken:
# gotk_reconcile_condition{type="Ready",status="True"} = Erfolgreich
# gotk_reconcile_duration_seconds = Wie lange dauerte es
# gotk_source_update_total{status="error"} = Fehler beim Update
```

### Grafana Dashboard

```bash
# Flux Dashboard importieren
# Grafana → + → Import → ID: 12833
# (Flux CD Community Dashboard)
```

---

## 🔄 Produktive Workflows

### Git Workflow für Team

```bash
# Feature entwickeln
git checkout -b feature/add-monitoring
# ... edits ...
git add . && git commit -m "Add monitoring"

# Pull Request erstellen
gh pr create \
  --title "Add monitoring" \
  --body "Adds Prometheus and Grafana" \
  --base main

# PR Review & Tests (GitHub Actions)
# Approve & Merge

# Flux synchronisiert automatisch
flux reconcile kustomization cluster-config --with-status
```

### Release Management

```bash
# Tag für Release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Production deployen (separater Branch oder Tag)
flux bootstrap github \
  --owner=YOUR_USER \
  --repo=k8s-cluster-config \
  --branch=main \
  --path=clusters/prod \
  --personal
```

---

## 📚 Useful Commands Zusammengefasst

```bash
# Status & Debug
flux check
flux get all -A
flux logs --all-namespaces --follow
kubectl describe gitrepository cluster-config -n flux-system

# Manuell syncen
flux reconcile source git cluster-config --with-status
flux reconcile kustomization cluster-config --with-status

# Suspend (zum Debuggen)
flux suspend kustomization cluster-config
flux resume kustomization cluster-config

# Löschen
flux delete kustomization cluster-config
flux delete source git cluster-config

# Erstellen
flux create source git cluster-config --url=https://...
flux create kustomization cluster-config --source=cluster-config --path=./clusters/dev

# Export/Import
flux export source git cluster-config > source.yaml
flux export kustomization cluster-config > kustomization.yaml

# Exportiere ganze Cluster Config
flux export all > full-backup.yaml
```

---

## 🎯 Checkliste für Production GitOps

- [ ] GitHub Repository erstellt und konfiguriert
- [ ] Flux in allen Clustern bootstrapped
- [ ] SOPS/AGE Keys konfiguriert
- [ ] Branch Protection Rules aktiv
- [ ] GitHub Actions Workflows getestet
- [ ] Secrets erfolgreich encrypted
- [ ] Monitoring & Alerts konfiguriert
- [ ] Backup-Strategie implementiert
- [ ] Disaster Recovery getestet
- [ ] Team trainiert auf GitOps Workflow
- [ ] Runbooks dokumentiert
- [ ] Incident Response Plan vorhanden

---

**GitOps = Git ist deine Single Source of Truth! 🎯**
