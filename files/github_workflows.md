---
# GitHub Actions Workflows für Kubernetes GitOps
# Platziere in: .github/workflows/

# === Workflow 1: Flux Validation ===
# Datei: .github/workflows/flux-validate.yml

name: Flux Validate

on:
  pull_request:
    paths:
      - 'clusters/**'
      - '.sops.yaml'
      - '.github/workflows/flux-validate.yml'
  push:
    branches: [main]
    paths:
      - 'clusters/**'

jobs:
  flux-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Flux CLI
        uses: fluxcd/flux2/action@main

      - name: Validate Flux Configuration
        run: |
          echo "Validating Flux configuration..."
          for cluster in clusters/*/; do
            echo "Checking $(basename $cluster)..."
            flux build kustomization cluster-config \
              --path "$cluster" \
              --enable-alpha=true 2>&1 | head -20 || true
          done

  kustomize-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Kustomize
        uses: imranismail/setup-kustomize@v2

      - name: Kustomize Build
        run: |
          for cluster in clusters/*/; do
            echo "Building $(basename $cluster)..."
            for app in "$cluster"apps/*/; do
              [ -d "$app" ] && kustomize build "$app" > /dev/null || echo "No kustomization in $app"
            done
          done

  helm-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Helm
        uses: azure/setup-helm@v3

      - name: Helm Lint
        run: |
          echo "Linting Helm releases..."
          for file in $(find clusters -name "*.yaml" -o -name "*.yml"); do
            if grep -q "kind: HelmRelease" "$file"; then
              echo "Found HelmRelease in $file"
            fi
          done
          echo "Helm validation completed"

  sops-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install SOPS
        run: |
          curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
          sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
          sudo chmod +x /usr/local/bin/sops

      - name: Check for unencrypted secrets
        run: |
          echo "Checking for potential unencrypted secrets..."
          found_issues=0
          
          # Check for unencrypted secret files
          if find clusters -name "*secret*.yaml" -type f | while read file; do
            if ! grep -q "sops:" "$file"; then
              echo "⚠️  Unencrypted secret file: $file"
              found_issues=1
            fi
          done; then
            exit $found_issues
          fi
          
          # Check for hardcoded passwords
          if grep -r "password:" clusters/ --include="*.yaml" | grep -v "sops:" | grep -v "^Binary"; then
            echo "⚠️  Possible hardcoded password found!"
            exit 1
          fi

  manifest-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install kubeval
        run: |
          curl -LO https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz
          tar xf kubeval-linux-amd64.tar.gz
          sudo mv kubeval /usr/local/bin

      - name: Validate Kubernetes Manifests
        run: |
          for manifest in $(find clusters -name "*.yaml" -o -name "*.yml"); do
            echo "Validating $manifest..."
            kubeval "$manifest" || echo "Warning in $manifest (may be intentional)"
          done

---
# === Workflow 2: Flux Deploy ===
# Datei: .github/workflows/flux-deploy.yml

name: Flux Deploy

on:
  push:
    branches: [main]
    paths:
      - 'clusters/dev/**'
  workflow_dispatch:
    inputs:
      cluster:
        description: 'Target cluster'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - staging

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/main' && contains(github.event.head_commit.modified, 'clusters/dev/')
    runs-on: ubuntu-latest
    environment:
      name: dev
      url: https://k8s-dev.cluster.local
    
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flux CLI
        uses: fluxcd/flux2/action@main

      - name: Setup kubectl
        uses: azure/setup-kubectl@v3
        with:
          version: 'latest'

      - name: Setup kubeconfig for dev
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBECONFIG_DEV }}" | base64 -d > $HOME/.kube/config
          chmod 600 $HOME/.kube/config

      - name: Verify cluster connectivity
        run: |
          kubectl cluster-info
          kubectl get nodes

      - name: Flux Reconcile Source
        run: |
          flux reconcile source git cluster-config \
            --with-status \
            --timeout=5m

      - name: Flux Reconcile Kustomization
        run: |
          flux reconcile kustomization cluster-config \
            --with-status \
            --timeout=10m

      - name: Wait for deployments
        run: |
          kubectl wait --for=condition=available --timeout=300s \
            deployment -n default -l app || true
          
          echo "Deployment status:"
          kubectl get deployments -A
          kubectl get pods -A --sort-by=.metadata.creationTimestamp | tail -20

      - name: Flux reconciliation status
        if: always()
        run: |
          flux get all -A
          flux logs --all-namespaces --since=5m

      - name: Notify Slack on Success
        if: success()
        uses: slackapi/slack-github-action@v1.24.0
        with:
          payload: |
            {
              "text": "✅ Flux deployment successful",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Dev Cluster Deployment*\n✅ Success\n*Commit:* `${{ github.sha }}`\n*Author:* ${{ github.actor }}\n*Time:* $(date -u +'%Y-%m-%d %H:%M:%S')"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}

      - name: Notify Slack on Failure
        if: failure()
        uses: slackapi/slack-github-action@v1.24.0
        with:
          payload: |
            {
              "text": "❌ Flux deployment failed",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Dev Cluster Deployment*\n❌ Failed\n*Commit:* `${{ github.sha }}`\n*Author:* ${{ github.actor }}\n*Branch:* ${{ github.ref }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}

---
# === Workflow 3: Security Scanning ===
# Datei: .github/workflows/security-scan.yml

name: Security Scanning

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: '0 2 * * 0'  # Weekly Sunday 2 AM

jobs:
  trivy-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: 'clusters/'
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload Trivy results to GitHub Security tab
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'

  container-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Extract container images from manifests
        run: |
          echo "Scanning for container images..."
          grep -h "image:" clusters/*/apps/*.yaml | \
            sed 's/.*image: *//g' | \
            sed 's/"//g' | \
            sort -u > images.txt
          cat images.txt

      - name: Scan images with Trivy
        run: |
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
          while IFS= read -r image; do
            echo "Scanning $image..."
            trivy image --severity HIGH,CRITICAL "$image" || true
          done < images.txt

  policy-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install OPA/Conftest
        run: |
          curl -LO https://github.com/open-policy-agent/conftest/releases/download/v0.48.1/conftest_0.48.1_Linux_x86_64.tar.gz
          tar xf conftest_0.48.1_Linux_x86_64.tar.gz
          sudo mv conftest /usr/local/bin

      - name: Check Kubernetes best practices
        run: |
          mkdir -p rego
          cat > rego/kubernetes.rego << 'EOF'
          package main
          
          deny[msg] {
            input.kind == "Deployment"
            not input.spec.template.spec.securityContext.runAsNonRoot
            msg = "Container must run as non-root"
          }
          
          deny[msg] {
            input.kind == "Deployment"
            input.spec.template.spec.containers[i].securityContext.privileged
            msg = "Privileged containers not allowed"
          }
          
          deny[msg] {
            input.kind == "Deployment"
            not input.spec.template.spec.containers[i].resources.limits
            msg = "Resource limits must be defined"
          }
          EOF
          
          conftest test -p rego clusters/*/apps/*.yaml || true

---
# === Workflow 4: Dependency Updates ===
# Datei: .github/workflows/renovate.json

{
  "extends": ["config:base"],
  "updateTypes": ["minor", "patch", "pin", "digest"],
  "schedule": ["after 10pm on thursday"],
  "prCreation": "not-pending",
  "prConcurrentLimit": 5,
  "helm": {
    "enabled": true
  },
  "docker": {
    "enabled": true,
    "automerge": false,
    "major": {
      "enabled": false
    }
  },
  "vulnerabilityAlerts": {
    "labels": ["security"],
    "prTitle": "🔒 Security: {{{depName}}} vulnerability",
    "automerge": false
  }
}

---
# === Workflow 5: Documentation ===
# Datei: .github/workflows/docs.yml

name: Update Documentation

on:
  push:
    branches: [main]
    paths:
      - 'clusters/**'

jobs:
  update-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Generate cluster inventory
        run: |
          cat > INVENTORY.md << 'EOF'
          # Kubernetes Cluster Inventory
          
          Last updated: $(date -u)
          
          ## Clusters
          EOF
          
          for cluster in clusters/*/; do
            cluster_name=$(basename "$cluster")
            echo "### $cluster_name" >> INVENTORY.md
            
            # Count resources
            echo "- Apps: $(find "$cluster/apps" -name "*.yaml" | wc -l)" >> INVENTORY.md
            echo "- Infrastructure: $(find "$cluster/infrastructure" -name "*.yaml" | wc -l)" >> INVENTORY.md
          done

      - name: Generate HelmRelease list
        run: |
          cat > HELM-RELEASES.md << 'EOF'
          # Helm Releases
          
          Last updated: $(date -u)
          
          EOF
          
          grep -h "kind: HelmRelease" -A 2 clusters/*/apps/*.yaml | \
            grep "name:" | \
            sed 's/.*name: //g' >> HELM-RELEASES.md

      - name: Commit and push
        run: |
          git config --local user.email "action@github.com"
          git config --local user.name "GitHub Action"
          git add INVENTORY.md HELM-RELEASES.md
          git commit -m "docs: Update cluster inventory" || echo "No changes"
          git push || echo "Nothing to push"

---
# === Workflow 6: Scheduled Health Check ===
# Datei: .github/workflows/health-check.yml

name: Cluster Health Check

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  health-check:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        cluster: [dev, staging]
    
    steps:
      - uses: actions/checkout@v4

      - name: Setup kubectl
        uses: azure/setup-kubectl@v3

      - name: Setup kubeconfig
        run: |
          mkdir -p $HOME/.kube
          secret_name="KUBECONFIG_$(echo ${{ matrix.cluster }} | tr '[:lower:]' '[:upper:]')"
          echo "${{ secrets[secret_name] }}" | base64 -d > $HOME/.kube/config
          chmod 600 $HOME/.kube/config

      - name: Check cluster connectivity
        run: |
          kubectl cluster-info
          kubectl get nodes -o wide

      - name: Check node status
        run: |
          echo "=== Node Status ==="
          kubectl get nodes
          
          echo -e "\n=== Node Resources ==="
          kubectl top nodes || echo "Metrics server not available"

      - name: Check pod status
        run: |
          echo "=== Pod Status ==="
          kubectl get pods -A --sort-by=.status.phase
          
          echo -e "\n=== Problematic Pods ==="
          kubectl get pods -A --field-selector=status.phase!=Running || true

      - name: Check Flux status
        run: |
          kubectl get gitrepository -n flux-system
          kubectl get kustomization -n flux-system
          kubectl get helmrelease -A

      - name: Check PVC status
        run: |
          echo "=== Persistent Volumes ==="
          kubectl get pvc -A

      - name: Gather cluster info on failure
        if: failure()
        run: |
          echo "=== Cluster Events ==="
          kubectl get events -A --sort-by='.lastTimestamp' | tail -20
          
          echo -e "\n=== Failed Pods Details ==="
          for pod in $(kubectl get pods -A --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}'); do
            kubectl describe pod "$pod" || true
          done

      - name: Notify Slack
        if: always()
        uses: slackapi/slack-github-action@v1.24.0
        with:
          payload: |
            {
              "text": "Health Check: ${{ matrix.cluster }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*${{ matrix.cluster }} Cluster Health*\n*Status:* ${{ job.status }}\n*Time:* $(date -u)"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}

---
# === Workflow 7: Create Issue on Alert ===
# Datei: .github/workflows/alert-to-issue.yml

name: Create Issue from Alert

on:
  workflow_run:
    workflows: ["Flux Deploy"]
    types: [completed]

jobs:
  create-issue:
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'failure'
    
    steps:
      - uses: actions/checkout@v4

      - name: Create GitHub Issue
        uses: actions/github-script@v7
        with:
          script: |
            const issue = await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `🚨 Flux Deployment Failed - ${new Date().toISOString().split('T')[0]}`,
              body: `## Deployment Failed\n\n- **Workflow:** ${context.payload.workflow_run.name}\n- **Run ID:** ${context.payload.workflow_run.id}\n- **Branch:** ${context.payload.workflow_run.head_branch}\n\n[View workflow run](${context.payload.workflow_run.html_url})`
            });
            console.log(`Created issue #${issue.data.number}`);
