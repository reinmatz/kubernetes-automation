# Kubernetes HA - GitOps mit Flux CD & GitHub (Teil 3)

**Complete GitOps Workflow - Infrastructure as Code meets Application Deployment**

---

## 📋 Inhaltsverzeichnis

1. [GitOps Konzepte](#1-gitops-konzepte)
2. [Flux CD Installation](#2-flux-cd-installation)
3. [GitHub Repository Setup](#3-github-repository-setup)
4. [Flux Konfiguration](#4-flux-konfiguration)
5. [Multi-Environment Setup](#5-multi-environment-setup)
6. [Secrets Management](#6-secrets-management)
7. [Pull-Request Workflows](#7-pull-request-workflows)
8. [CI/CD Integration](#8-cicd-integration)
9. [Monitoring & Alerts](#9-monitoring--alerts)
10. [Disaster Recovery](#10-disaster-recovery)
11. [Best Practices](#11-best-practices)

---

## 1. GitOps Konzepte

### Was ist GitOps?

GitOps ist ein Operational Framework, das Git als Single Source of Truth (SSoT) für:
- **Infrastructure** (Kubernetes Manifests)
- **Applications** (Deployments, Services, Ingress)
- **Configuration** (ConfigMaps, Secrets)
- **Policy** (NetworkPolicies, RBAC)

nutzt.

### Vorteile

✅ **Auditable** - Alle Änderungen in Git History  
✅ **Versioned** - Rollback zu beliebigen Commits  
✅ **Declarative** - Gewünschter Zustand definieren  
✅ **Automatic** - Cluster konvergiert zu Git State  
✅ **Collaborative** - Pull-Request basierte Deployments  

### Flux vs Argo CD

| Feature | Flux | Argo CD |
|---------|------|---------|
| **Komplexität** | Einfacher | Umfangreicher |
| **Native K8s** | ✅ Ja (Helm/Kustomize) | ✅ Ja |
| **Web UI** | Optional (weave-gitops) | ✅ Integriert |
| **Learning Curve** | Flach | Steiler |
| **Best for** | Small-Medium | Large-Scale |
| **Use Case** | Diese Anleitung | Multi-Tenant |

**Wir nutzen Flux** - einfach, native, mächtig! 🎯

---

## 2. Flux CD Installation

### 2.1 Prerequisites

```bash
# Git installiert?
git --version

# kubectl konfiguriert?
kubectl get nodes

# GitHub CLI (optional, aber hilfreich)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh
```

### 2.2 Flux CLI Installation

```bash
# Flux CLI installieren
curl -s https://fluxcd.io/install.sh | bash

# Verify
flux --version
flux check --pre
```

Output sollte ähnlich sein:
```
flux: v2.0.1
...
✓ cluster-info: {version v1.28.0}
✓ flux: ready to install
```

### 2.3 Flux Installation im Cluster

```bash
# Namespace erstellen
kubectl create namespace flux-system

# Flux komponenten installieren
flux install \
  --namespace=flux-system \
  --watch-all-namespaces

# Verify
flux check
kubectl get pods -n flux-system

# Output:
# NAME                              READY   STATUS    RESTARTS   AGE
# flux-helm-controller-xxx          1/1     Running   0          2m
# flux-kustomize-controller-xxx     1/1     Running   0          2m
# flux-notification-controller-xxx  1/1     Running   0          2m
# flux-source-controller-xxx        1/1     Running   0          2m
```

---

## 3. GitHub Repository Setup

### 3.1 Repository erstellen

**GitHub WebUI:**

1. Login zu github.com
2. `+` → New Repository
3. Repository Name: `k8s-cluster-config`
4. Description: "Kubernetes Cluster GitOps Configuration"
5. **Public** (optional) oder Private
6. Initialize with README: ✅ Yes
7. Create Repository

**Oder via GitHub CLI:**

```bash
gh auth login

gh repo create k8s-cluster-config \
  --public \
  --description "Kubernetes Cluster GitOps Configuration" \
  --source=. \
  --remote=origin
```

### 3.2 Repository lokal klonen

```bash
# Clone
git clone https://github.com/YOUR_USER/k8s-cluster-config.git
cd k8s-cluster-config

# Verify
git remote -v
# origin  https://github.com/YOUR_USER/k8s-cluster-config.git (fetch)
# origin  https://github.com/YOUR_USER/k8s-cluster-config.git (push)
```

### 3.3 Repository Struktur

```bash
# Erstelle Struktur
mkdir -p clusters/{dev,staging,prod}
mkdir -p clusters/{dev,staging,prod}/{apps,infrastructure}
mkdir -p apps/{core,workloads}

# Basis-Struktur
cat > README.md << 'EOF'
# Kubernetes Cluster Configuration

GitOps repository für Kubernetes HA Cluster.

## Structure

```
clusters/
  dev/
    apps/              # Application deployments
    infrastructure/    # Infrastructure components
  staging/
    apps/
    infrastructure/
  prod/
    apps/
    infrastructure/

apps/
  core/               # Core applications
  workloads/          # User workloads
```

## Deployment

```bash
# Deploy cluster
flux bootstrap github \
  --owner=YOUR_USER \
  --repo=k8s-cluster-config \
  --branch=main \
  --path=clusters/dev
```

## Documentation

- [Flux Docs](https://fluxcd.io/docs/)
- [Kustomize](https://kustomize.io/)
- [Helm Charts](https://helm.sh/)

EOF

git add .
git commit -m "Initial repository structure"
git push origin main
```

---

## 4. Flux Konfiguration

### 4.1 Flux Bootstrap

```bash
# Persönliches GitHub Token erstellen:
# GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
# Scopes: repo, read:org

export GITHUB_USER=YOUR_USER
export GITHUB_REPO=k8s-cluster-config
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx

# Flux Bootstrap
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=clusters/dev \
  --personal \
  --token-auth

# Output:
# ✓ Manifests pushed to repository
# ✓ Flux installed in cluster
# ✓ Ready to synchronize

# Verify
flux check
kubectl get gitrepository -n flux-system
```

### 4.2 Was Flux Bootstrap macht

1. **Erstellt Namespace:** `flux-system`
2. **Generiert Secrets:** Für GitHub authentification
3. **Pushed Manifests:** `flux-system/` Ordner ins Repo
4. **Installiert CRDs:** Flux Custom Resources
5. **Deployed Controller:** Source, Kustomize, Helm

### 4.3 Flux Struktur nach Bootstrap

```
clusters/dev/
├── flux-system/
│   ├── gotk-components.yaml       # Generated
│   ├── gotk-sync.yaml             # Generated
│   └── kustomization.yaml         # Generated
└── (deine apps und infrastructure)
```

**WICHTIG:** `flux-system/` wird automatisch generiert!

---

## 5. Multi-Environment Setup

### 5.1 Environment Struktur

```bash
# Erstelle 3 Umgebungen (dev, staging, prod)

# Dev Environment
mkdir -p clusters/dev/{apps,infrastructure,fluxconfig}
cat > clusters/dev/fluxconfig/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: flux-config
  namespace: flux-system

resources:
  - ../apps
  - ../infrastructure
EOF

# Staging Environment
mkdir -p clusters/staging/{apps,infrastructure,fluxconfig}
cat > clusters/staging/fluxconfig/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: flux-config
  namespace: flux-system

resources:
  - ../apps
  - ../infrastructure
EOF

# Production Environment
mkdir -p clusters/prod/{apps,infrastructure,fluxconfig}
cat > clusters/prod/fluxconfig/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: flux-config
  namespace: flux-system

resources:
  - ../apps
  - ../infrastructure
EOF

git add .
git commit -m "Add multi-environment setup"
git push
```

### 5.2 Flux Sources für jede Umgebung

**Dev Environment (`clusters/dev/infrastructure/sources.yaml`):**

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 30s
  url: https://github.com/YOUR_USER/k8s-cluster-config
  ref:
    branch: main
  secretRef:
    name: flux-system  # Created by flux bootstrap

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/dev
  prune: true
  wait: true
  sourceRef:
    kind: GitRepository
    name: cluster-config
  decryption:
    provider: sops
    secretRef:
      name: sops-gpg  # Für Secrets (siehe Punkt 6)
```

**Staging Environment (`clusters/staging/infrastructure/sources.yaml`):**

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 1m  # Länger als dev
  url: https://github.com/YOUR_USER/k8s-cluster-config
  ref:
    branch: main
  secretRef:
    name: flux-system

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/staging
  prune: true
  wait: true
  sourceRef:
    kind: GitRepository
    name: cluster-config
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: "*"
      namespace: "default"
```

**Production Environment (`clusters/prod/infrastructure/sources.yaml`):**

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 5m  # Längste Interval
  url: https://github.com/YOUR_USER/k8s-cluster-config
  ref:
    branch: main  # Oder separate 'prod' branch
  secretRef:
    name: flux-system

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-config
  namespace: flux-system
spec:
  interval: 30m  # Längeres Interval in Production
  path: ./clusters/prod
  prune: false   # Vorsicht: nicht automatisch löschen
  wait: true
  timeout: 15m
  sourceRef:
    kind: GitRepository
    name: cluster-config
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: "*"
      namespace: "default"
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-config
```

### 5.3 Deploy mit Environment-Spezifischen Sources

```bash
# Dev
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=clusters/dev \
  --personal

# Staging (auf anderem Cluster)
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=clusters/staging \
  --personal

# Production (auf drittem Cluster)
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=clusters/prod \
  --personal
```

---

## 6. Secrets Management

### 6.1 Problem: Secrets in Git

❌ **NIEMALS** Passwörter ins Git committen!

Lösungen:
1. **SOPS** - Symmetric encryption (einfach)
2. **Sealed Secrets** - Cluster-specific encryption
3. **External Secrets** - HashiCorp Vault, AWS Secrets Manager
4. **Bitnami Sealed Secrets** - Cluster-gebunden

Wir nutzen **SOPS mit AGE Encryption** (einfach + sicher):

### 6.2 SOPS Installation & Setup

```bash
# SOPS installieren
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# AGE Key Generation Tool
curl -LO https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/
sudo chmod +x /usr/local/bin/age

# Verify
sops --version
age --version
```

### 6.3 AGE Key erstellen

```bash
# AGE Public/Private Key Pair generieren
age-keygen -o $HOME/.config/sops/age/keys.txt

# Output:
# Public key: age1xxx...
# (speichere die public key!)

# Permissions sichern
chmod 600 $HOME/.config/sops/age/keys.txt
```

### 6.4 SOPS Configuration

**`.sops.yaml` in Repository Root:**

```yaml
---
creation_rules:
  - path_regex: clusters/.*/.*secret.*\.yaml$
    key_groups:
      - age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  - path_regex: clusters/dev/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  - path_regex: clusters/staging/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  - path_regex: clusters/prod/.*secret.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  # Default for alles andere
  - encrypted_regex: ^(data|stringData)$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 6.5 Secret Encryption im Cluster

```bash
# Install Flux native SOPS support
flux install \
  --namespace=flux-system \
  --watch-all-namespaces \
  --with-kustomize

# AGE Secret im Cluster erstellen
kubectl create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt \
  -n flux-system

# Verify
kubectl get secrets -n flux-system sops-age
```

### 6.6 Secret Erstellen & Verschlüsseln

```bash
# Unverschlüsseltes Secret
cat > clusters/dev/apps/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
data:
  username: dXNlcm5hbWU=  # base64: username
  password: cGFzc3dvcmQxMjM=  # base64: password123
EOF

# Mit SOPS verschlüsseln
sops -e -i clusters/dev/apps/secret.yaml

# Verify (Content sollte verschlüsselt sein)
cat clusters/dev/apps/secret.yaml
# Sollte "sops:" Section haben

# Commit encrypted secret
git add clusters/dev/apps/secret.yaml
git commit -m "Add encrypted secret"
git push
```

### 6.7 Secret Decryption via Flux Kustomization

**`clusters/dev/apps/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system

resources:
  - secret.yaml
  - deployment.yaml

patchesJson6902:
  - target:
      kind: Secret
      name: my-secret
    patch: |-
      - op: replace
        path: /data/password
        value: "{{ .Values.password }}"
```

Flux wird automatisch mit SOPS decryption arbeiten!

---

## 7. Pull-Request Workflows

### 7.1 Feature Branch Workflow

```bash
# 1. Feature Branch erstellen
git checkout -b feature/add-monitoring

# 2. Änderungen machen
mkdir -p clusters/dev/apps/monitoring
cat > clusters/dev/apps/monitoring/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - prometheus.yaml
  - grafana.yaml
EOF

# 3. Commit & Push
git add .
git commit -m "Add monitoring stack to dev"
git push origin feature/add-monitoring

# 4. Pull Request erstellen
gh pr create \
  --title "Add monitoring to dev cluster" \
  --body "Adds Prometheus and Grafana to dev environment" \
  --base main

# 5. PR Review & Testing (siehe unten)

# 6. Merge
gh pr merge --auto --squash
```

### 7.2 Helm Chart Deployments via Git

**`clusters/dev/apps/prometheus.yaml` (Helm Release):**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: kube-prometheus-stack
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
      version: "55.0.0"  # Pin version für reproducibility
  
  values:
    prometheus:
      prometheusSpec:
        retention: 30d
        scrapeInterval: 30s
    
    grafana:
      adminPassword: "${GRAFANA_PASSWORD}"  # From ConfigMap
      adminUser: admin
      persistence:
        enabled: true
        size: 5Gi
  
  install:
    crds: Create
  update:
    crds: CreateReplace
  
  postRenderers:
    - kustomize:
        patchesJson6902:
          - target:
              kind: Service
              name: prometheus-kube-prometheus-prometheus
            patch:
              - op: replace
                path: /spec/type
                value: LoadBalancer
```

**Helm Repository Source (`clusters/dev/infrastructure/helm-repos.yaml`):**

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts

---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: grafana
  namespace: flux-system
spec:
  interval: 1h
  url: https://grafana.github.io/helm-charts

---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

### 7.3 Kustomize-basierte Deployments

**`clusters/dev/apps/nginx/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ingress-nginx

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml

commonLabels:
  app: nginx-ingress
  env: dev

replicas:
  - name: nginx-ingress
    count: 2

patchesStrategicMerge:
  - |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-ingress
    spec:
      template:
        spec:
          containers:
            - name: nginx
              resources:
                limits:
                  memory: 512Mi
                requests:
                  memory: 256Mi

patchesJson6902:
  - target:
      kind: Service
      name: nginx-ingress
    patch: |-
      - op: replace
        path: /spec/type
        value: LoadBalancer
      - op: add
        path: /spec/loadBalancerIP
        value: "192.168.100.200"

configMapGenerator:
  - name: nginx-config
    files:
      - nginx.conf

images:
  - name: nginx
    newTag: "1.25"

secretGenerator:
  - name: nginx-tls
    files:
      - tls.crt
      - tls.key
```

---

## 8. CI/CD Integration

### 8.1 GitHub Actions für Flux

**`.github/workflows/flux-validate.yml`:**

```yaml
name: Flux Validation

on:
  pull_request:
    paths:
      - 'clusters/**'
      - '.github/workflows/flux-validate.yml'

jobs:
  flux-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Setup Flux CLI
        uses: fluxcd/flux2/action@main

      - name: Validate Flux
        run: |
          for dir in clusters/*; do
            echo "Validating $dir..."
            flux build kustomization cluster-config \
              --kustomization-file $dir/fluxconfig/kustomization.yaml
          done

  kustomize-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Kustomize
        uses: imranismail/setup-kustomize@v2

      - name: Kustomize Build
        run: |
          for dir in clusters/*/; do
            echo "Building $dir..."
            kustomize build "$dir"
          done

  helm-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Helm
        uses: azure/setup-helm@v3

      - name: Helm Lint
        run: |
          helm lint clusters/*/apps/*.yaml || true
          helm template -f clusters/*/apps/*.yaml . || true

  policy-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Conftest
        run: |
          curl -LO https://github.com/open-policy-agent/conftest/releases/download/v0.48.1/conftest_0.48.1_Linux_x86_64.tar.gz
          tar xf conftest_0.48.1_Linux_x86_64.tar.gz
          sudo mv conftest /usr/local/bin

      - name: Check Policies
        run: |
          conftest test -p clusters/policies clusters/*/apps/*.yaml || true
```

### 8.2 Automated Deployment on Merge

**`.github/workflows/flux-deploy.yml`:**

```yaml
name: Flux Deploy

on:
  push:
    branches: [main]
    paths:
      - 'clusters/dev/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3

      - name: Setup Flux CLI
        uses: fluxcd/flux2/action@main

      - name: Configure kubectl
        uses: azure/setup-kubectl@v3
        with:
          version: 'latest'

      - name: Configure kubeconfig
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > $HOME/.kube/config
          chmod 600 $HOME/.kube/config

      - name: Flux Reconcile
        run: |
          flux reconcile source git cluster-config --with-status
          flux reconcile kustomization cluster-config --with-status

      - name: Wait for deployments
        run: |
          kubectl rollout status deployment -n default --timeout=5m || true
          kubectl get pods -A
```

---

## 9. Monitoring & Alerts

### 9.1 Flux Metrics in Prometheus

**`clusters/dev/infrastructure/flux-monitoring.yaml`:**

```yaml
---
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: flux
  namespace: flux-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: flux
  endpoints:
    - port: metrics

---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: flux-alerts
  namespace: flux-system
spec:
  groups:
    - name: flux
      rules:
        - alert: FluxReconciliationFailure
          expr: increase(gotk_reconcile_condition{type="Ready",status="False"}[5m]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Flux reconciliation failed for {{ $labels.name }}"
            description: "{{ $labels.kind }}/{{ $labels.name }} failed to reconcile"

        - alert: FluxSuspended
          expr: gotk_suspend_status > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Flux resource suspended: {{ $labels.name }}"

        - alert: FluxSourceUpdateFailure
          expr: increase(gotk_source_update_total{status="error"}[5m]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Flux source update failed: {{ $labels.name }}"
```

### 9.2 Grafana Dashboard für Flux

**`clusters/dev/infrastructure/flux-dashboard.yaml`:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flux-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  flux-dashboard.json: |
    {
      "dashboard": {
        "title": "Flux CD",
        "panels": [
          {
            "title": "Reconciliation Status",
            "targets": [
              {
                "expr": "gotk_reconcile_condition{status=\"True\",type=\"Ready\"}"
              }
            ]
          },
          {
            "title": "Reconciliation Failures",
            "targets": [
              {
                "expr": "increase(gotk_reconcile_condition{type=\"Ready\",status=\"False\"}[5m])"
              }
            ]
          },
          {
            "title": "Source Update Errors",
            "targets": [
              {
                "expr": "gotk_source_update_total{status=\"error\"}"
              }
            ]
          }
        ]
      }
    }
```

### 9.3 Slack Notifications

**`.github/workflows/flux-notifications.yml`:**

```yaml
name: Flux Notifications

on:
  push:
    branches: [main]

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Send Slack Notification
        uses: slackapi/slack-github-action@v1.24.0
        with:
          payload: |
            {
              "text": "🚀 Deployment started",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Flux Deployment*\n*Repo:* ${{ github.repository }}\n*Commit:* `${{ github.sha }}`\n*Author:* ${{ github.actor }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

---

## 10. Disaster Recovery

### 10.1 etcd Backup mit Velero

```bash
# Velero Helm Repository
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Velero installieren
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values - << 'EOF'
configuration:
  backupStorageLocation:
    bucket: my-backup-bucket
    provider: aws
  schedules:
    etcd-backup:
      schedule: "0 2 * * *"  # 2 AM daily
      template:
        includedNamespaces:
          - "*"
        storageLocation: default
        ttl: 720h  # 30 days
EOF
```

### 10.2 Git Repository Backup

```bash
# GitHub CLI mit backup
gh repo clone YOUR_USER/k8s-cluster-config backup/

# Automated daily backup
0 3 * * * cd /backups && git clone --mirror https://github.com/YOUR_USER/k8s-cluster-config.git k8s-cluster-config.git
```

### 10.3 Cluster Restoration

**Falls Cluster down:**

1. **Neuen Cluster deployen** (mit Ansible Part 2)
2. **Flux bootstrap mit ursprünglichem Repo:**

```bash
export GITHUB_TOKEN=...
flux bootstrap github \
  --owner=YOUR_USER \
  --repo=k8s-cluster-config \
  --branch=main \
  --path=clusters/prod
```

3. **Git bringt automatisch alles wieder:**
   - Applications
   - Secrets (encrypted)
   - Configurations
   - Helm releases

### 10.4 Rollback via Git

```bash
# Letzten stabilen Commit finden
git log --oneline clusters/

# Zu Version vor Problem zurück
git revert <commit-hash>
git push origin main

# Flux synchronisiert automatisch
flux reconcile kustomization cluster-config --with-status
```

---

## 11. Best Practices

### 11.1 Branch Strategy

```
main (stable)
  ├── feature/add-monitoring (PR)
  ├── feature/upgrade-k8s (PR)
  └── hotfix/fix-secret (PR)

staging (Pre-production)
  └── (mirror of main, tested)

prod (Production)
  └── (only after staging success)
```

### 11.2 Commit Hygiene

```bash
# Good: Atomic, descriptive commits
git commit -m "Add Prometheus monitoring stack to dev cluster

- Adds prometheus helm chart
- Configures 30d retention
- Enables persistent storage
- Related to #42"

# Bad: Too many changes
git commit -m "Updated stuff"
```

### 11.3 Access Control

**GitHub Branch Protection Rules:**

1. Settings → Branches → Add rule
2. Branch name: `main`
3. Require pull request reviews: ✅ 2 approvals
4. Require status checks to pass: ✅ flux-validate
5. Require branches to be up to date: ✅
6. Restrict who can push: ✅ (nur maintainers)

### 11.4 Code Review Template

**`.github/pull_request_template.md`:**

```markdown
## Description
Brief explanation of changes

## Type
- [ ] Feature
- [ ] Bugfix
- [ ] Security
- [ ] Documentation
- [ ] Infrastructure

## Checklist
- [ ] Manifest validates with `flux build`
- [ ] SOPS encrypted secrets if needed
- [ ] No hardcoded passwords/tokens
- [ ] Images pinned to specific versions
- [ ] Resource limits defined
- [ ] Labels and annotations correct
- [ ] Documentation updated
- [ ] Tested in dev cluster
- [ ] No breaking changes

## Testing
Describe how this was tested:

## Related Issues
Fixes #123
```

### 11.5 Notification Strategy

```bash
# Slack notifications für:
# ✓ PR opened/merged
# ✓ Flux reconciliation failures
# ✓ Security updates
# ✓ Deployment completed

# Email notifications für:
# ✓ Critical alerts
# ✓ Production changes
# ✓ Security issues
```

---

## 🔍 Troubleshooting GitOps

### Flux Reconciliation fehlgeschlagen

```bash
# 1. Check status
flux get all -A

# 2. Detailed error
flux describe kustomization cluster-config

# 3. Logs
flux logs --all-namespaces --follow

# 4. Git sync status
kubectl get gitrepository -n flux-system -o wide

# 5. Suspend und debug
flux suspend kustomization cluster-config
# Fix issue
flux resume kustomization cluster-config
```

### Secret nicht dekryptiert

```bash
# 1. AGE key im Cluster?
kubectl get secrets -n flux-system sops-age

# 2. SOPS policy korrekt?
cat .sops.yaml

# 3. Manual test
sops -d clusters/dev/apps/secret.yaml

# 4. Flux mit SOPS starten?
kubectl logs -n flux-system -l app=kustomize-controller | grep -i sops
```

### Performance Issues

```bash
# 1. Reconciliation Interval erhöhen
kubectl edit kustomization cluster-config -n flux-system
# spec.interval: 30m  # instead of 10m

# 2. Webhook statt polling
flux create source git cluster-config \
  --url=https://github.com/... \
  --push-branch=main

# 3. Parallel deployments
flux create kustomization apps \
  --source=cluster-config \
  --path=./clusters/dev/apps \
  --interval=5m \
  --wait=true

flux create kustomization infra \
  --source=cluster-config \
  --path=./clusters/dev/infrastructure \
  --interval=5m \
  --depends-on=apps
```

---

## 📊 Execution Checklist

- [ ] GitHub Repository erstellt
- [ ] Repository geklont
- [ ] Flux CLI installiert
- [ ] Flux im Cluster installiert
- [ ] GitHub Token generiert
- [ ] Flux Bootstrap durchgeführt
- [ ] Multi-Environment Struktur erstellt
- [ ] SOPS eingerichtet
- [ ] AGE Keys generiert
- [ ] Secrets encrypted
- [ ] GitHub Actions workflows erstellt
- [ ] Branch Protection Rules konfiguriert
- [ ] Test-Deployment durchgeführt (Monitoring)
- [ ] Monitoring alerts konfiguriert
- [ ] Backup strategy definiert
- [ ] Team trainiert auf GitOps Workflow

---

## 🎯 Next Steps nach Setup

1. **Applications migrieren:**
   - Deploy Apps via Helm Releases in Git
   - Kustomize for custom configurations
   - HelmChart Resources für komplexe Anwendungen

2. **Policies definieren:**
   - OPA/Rego Policies mit Conftest
   - Pod Security Standards
   - Network Policies

3. **Automation erweitern:**
   - ArgoCD für UI (optional)
   - Dependabot für dependency updates
   - Renovate for automated version bumps

4. **Security hardening:**
   - RBAC für Team zugriff
   - Audit logging aktivieren
   - Supply chain security (SBOM, image scanning)

5. **Production readiness:**
   - HA etcd backups
   - Disaster recovery drills
   - Change management process
   - On-call rotations

---

## 📚 Referenzen

- [Flux CD Documentation](https://fluxcd.io/docs/)
- [SOPS Guide](https://fluxcd.io/docs/guides/mozilla-sops/)
- [Kustomize](https://kustomize.io/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [GitHub Actions](https://docs.github.com/en/actions)

---

**Git ist deine neue "Single Source of Truth"!** 🚀

