# Ansible in Kubernetes - Deployment Guide

## Übersicht

Dieses Setup deployed einen vollständig funktionsfähigen Ansible-Container in Ihrem Kubernetes Cluster mit:

- **Ansible 2.12+** mit allen notwendigen Modulen
- **kubectl** für Kubernetes-Management
- **Python Kubernetes-Module** (kubernetes, openshift, PyYAML)
- **ServiceAccount mit ClusterAdmin-Rechten** für volle Cluster-Verwaltung
- **Persistent Storage** für Playbooks und Daten

## Deployment

### Alle Ressourcen deployen

```bash
kubectl apply -f manifests/ansible/
```

### Einzelne Komponenten

```bash
# Namespace und RBAC
kubectl apply -f manifests/ansible/01-namespace.yaml
kubectl apply -f manifests/ansible/02-serviceaccount-rbac.yaml

# Configuration
kubectl apply -f manifests/ansible/03-configmap.yaml

# Deployments
kubectl apply -f manifests/ansible/04-deployment.yaml
kubectl apply -f manifests/ansible/06-ansible-runner-custom.yaml
```

## Verwendung

### In den Ansible-Container wechseln

```bash
kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash
```

### Ansible-Befehle ausführen

```bash
# Ansible ping test
kubectl exec -n ansible deployment/ansible-k8s -- ansible localhost -m ping

# Ansible ad-hoc Befehl
kubectl exec -n ansible deployment/ansible-k8s -- ansible all -m shell -a "date"

# Playbook ausführen (nachdem Playbook kopiert wurde)
kubectl exec -n ansible deployment/ansible-k8s -- ansible-playbook /ansible/playbooks/site.yml
```

### kubectl im Ansible-Container

```bash
# Cluster-Info
kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl get nodes"

# Pods auflisten
kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl get pods -A"

# Kubernetes-Ressourcen verwalten
kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl apply -f /ansible/manifests/"
```

## Playbooks in den Container kopieren

### Von lokalem System

```bash
# Einzelne Datei
kubectl cp site_playbook.yml ansible/ansible-k8s-xxxxx:/ansible/playbooks/site.yml

# Ganzes Verzeichnis
kubectl cp playbooks/ ansible/ansible-k8s-xxxxx:/ansible/playbooks/

# Pod-Name automatisch ermitteln
POD=$(kubectl get pod -n ansible -l app=ansible-k8s -o jsonpath='{.items[0].metadata.name}')
kubectl cp playbooks/ ansible/$POD:/ansible/playbooks/
```

### Via ConfigMap/Secret

Für häufig verwendete Playbooks können Sie ConfigMaps erstellen:

```bash
kubectl create configmap my-playbook \
  --from-file=playbook.yml \
  -n ansible

# Dann in Deployment mounten (siehe 06-ansible-runner-custom.yaml)
```

## Inventory Management

### Inventory im Container erstellen

```bash
kubectl exec -n ansible deployment/ansible-k8s -- sh -c 'cat > /ansible/inventory/hosts <<EOF
[all:vars]
ansible_connection=local

[kubernetes]
localhost ansible_connection=local
EOF'
```

### Inventory von außen bereitstellen

```bash
kubectl create configmap ansible-inventory \
  --from-file=inventory_hosts.yml \
  -n ansible

# Mount in Pod (Volume in Deployment hinzufügen)
```

## Beispiele

### 1. Kubernetes-Ressourcen mit Ansible verwalten

```bash
# In den Container wechseln
kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash

# Im Container:
cat > /ansible/playbooks/k8s-test.yml <<'EOF'
---
- name: Manage Kubernetes Resources
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Create namespace
      kubernetes.core.k8s:
        name: test-namespace
        kind: Namespace
        state: present

    - name: Get all pods
      kubernetes.core.k8s_info:
        kind: Pod
        namespace: default
      register: pods

    - name: Display pods
      debug:
        msg: "{{ pods.resources | map(attribute='metadata.name') | list }}"
EOF

# Playbook ausführen
ansible-playbook /ansible/playbooks/k8s-test.yml
```

### 2. Extensions deployen (Monitoring + Cert-Manager)

```bash
# Playbooks in Container kopieren
POD=$(kubectl get pod -n ansible -l app=ansible-k8s -o jsonpath='{.items[0].metadata.name}')
kubectl cp "../extensions_playbook.yml" "ansible/$POD:/ansible/playbooks/extensions.yml"
kubectl cp "../inventory_hosts.yml" "ansible/$POD:/ansible/inventory/hosts.yml"

# Im Container ausführen
kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash
cd /ansible
ansible-playbook -i inventory/hosts.yml playbooks/extensions.yml -t "monitoring,cert-manager" -v
```

## Monitoring & Logging

### Status prüfen

```bash
# Pod-Status
kubectl get pods -n ansible

# Logs anzeigen
kubectl logs -n ansible deployment/ansible-k8s -f

# Events
kubectl get events -n ansible --sort-by='.lastTimestamp'
```

### Resource-Nutzung

```bash
# CPU/Memory
kubectl top pod -n ansible

# Storage
kubectl get pvc -n ansible
```

## Troubleshooting

### Problem: kubectl funktioniert nicht

**Lösung**: KUBECONFIG muss unset sein

```bash
kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl get nodes"
```

### Problem: Ansible Collections fehlen

**Lösung**: Collections manuell installieren

```bash
kubectl exec -n ansible deployment/ansible-k8s -- \
  ansible-galaxy collection install kubernetes.core community.general -p /home/runner/.ansible/collections
```

### Problem: Python Module fehlen

**Lösung**: Via pip installieren

```bash
kubectl exec -n ansible deployment/ansible-k8s -- \
  pip3 install kubernetes openshift PyYAML jsonpatch
```

### Pod neu starten

```bash
kubectl delete pod -n ansible -l app=ansible-k8s
kubectl wait --for=condition=Ready pod -l app=ansible-k8s -n ansible --timeout=180s
```

## Shell-Alias (Optional)

Fügen Sie zu Ihrer `~/.bashrc` oder `~/.zshrc` hinzu:

```bash
# Ansible in Kubernetes
alias ansible-k8s='kubectl exec -n ansible deployment/ansible-k8s -- ansible'
alias ansible-playbook-k8s='kubectl exec -n ansible deployment/ansible-k8s -- ansible-playbook'
alias ansible-shell='kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash'

# Mit kubectl im Ansible Container
alias ansible-kubectl='kubectl exec -n ansible deployment/ansible-k8s -- sh -c "unset KUBECONFIG && kubectl"'
```

Dann können Sie einfach verwenden:

```bash
ansible-k8s localhost -m ping
ansible-playbook-k8s /ansible/playbooks/site.yml
ansible-shell
ansible-kubectl get nodes
```

## Cleanup

### Ansible-Deployment entfernen

```bash
kubectl delete -f manifests/ansible/
```

### Nur Pods neu starten

```bash
kubectl rollout restart deployment/ansible-k8s -n ansible
```

## Nächste Schritte

1. **Monitoring & Cert-Manager deployen**:
   ```bash
   # Kopiere Playbooks in Container und führe aus
   kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash
   # Im Container: ansible-playbook ...
   ```

2. **GitOps einrichten**: Verwenden Sie Flux CD um Playbooks automatisch zu deployen

3. **Scheduled Jobs**: Erstellen Sie CronJobs für regelmäßige Ansible-Runs

## Support

- Logs: `kubectl logs -n ansible deployment/ansible-k8s -f`
- Shell: `kubectl exec -it -n ansible deployment/ansible-k8s -- /bin/bash`
- Status: `kubectl get all -n ansible`
