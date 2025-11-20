# Kubernetes Kurs - Zusammenfassung

## Fehlerhafte Eingaben (gelöscht)

| Fehler | Befehl | Problem |
|--------|--------|---------|
| Zeile 19 (history) | `kubectl api-resources --namespacend=true` | Tippfehler: "namespacend" statt "namespaced" |
| Zeile 41 (history) | `kubectl create deployment myhttpd --image quay-io/...` | Image-URL: "quay-io" statt "quay.io" |
| Zeile 64 (history) | `kubectl d` | Unvollständiger Befehl |
| Zeile 70 (history) | `kubectl exec -it myhttpd-746766bc85-2b2k9 --` | Unvollständig |
| Zeile 131 (WSL) | `mkir -p setup/ingress` | Tippfehler: "mkir" statt "mkdir" |
| Zeile 189 (WSL) | `curl ww.myfirst.local` | Tippfehler: "ww" statt "www" |
| Zeile 217 (WSL) | `mdir myhttpd` | Tippfehler: "mdir" statt "mkdir" |

---

## Kurs-Inhalte

### 1. Grundlagen & Cluster-Konfiguration

#### Tab-Completion aktivieren
```bash
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl
source /etc/bash_completion.d/kubectl
```

#### Cluster-Informationen anzeigen
```bash
kubectl config get-contexts           # Alle Kontexte auflisten
kubectl config get-clusters           # Verfügbare Cluster
kubectl config get-users              # Benutzer anzeigen
kubectl config set-context docker-desktop --namespace <namespace>
```

#### API-Ressourcen
```bash
kubectl api-resources                       # Alle verfügbaren Ressourcen
kubectl api-resources --namespaced=true     # Nur namespacierte Ressourcen
kubectl explain pod                         # Dokumentation zu einer Ressource
```

---

### 2. Pod-Management

#### Pod erstellen und verwalten
```bash
kubectl run myhttpd --image quay.io/jfreygner/myhttpd:0.20
kubectl get pods
kubectl get pods -o wide                    # Detaillierte Informationen
kubectl delete pod <pod-name>
```

#### In Pods "hineinarbeiten"
```bash
kubectl exec -it <pod-name> -- bash        # Interaktive Shell
kubectl exec -it <pod-name> -- <command>   # Einzelnen Befehl ausführen
kubectl logs <pod-name>                    # Logs anzeigen
kubectl describe pod <pod-name>             # Metadaten anzeigen
```

---

### 3. Deployment-Verwaltung

#### Deployments erstellen
```bash
kubectl create deployment myhttpd --image quay.io/jfreygner/myhttpd:0.20
kubectl get deployments
kubectl get all                             # Alle Ressourcen anzeigen
```

#### Deployments skalieren
```bash
kubectl scale deployment myhttpd --replicas 3
```

#### Konfiguration bearbeiten
```bash
kubectl edit deployments.apps myhttpd      # Vi-Editor öffnet
kubectl set env deployment myhttpd KEY=VALUE
```

#### Rollout-History
```bash
kubectl rollout history deployment myhttpd
kubectl rollout history deployment myhttpd --revision 1
kubectl rollout undo deployment myhttpd --to-revision 1
```

---

### 4. Namespace-Management

```bash
kubectl create namespace rma-myfirst
kubectl get namespaces
kubectl config set-context docker-desktop --namespace rma-myfirst
```

---

### 5. Netzwerk & Service

#### Services exponieren
```bash
kubectl expose deployment myhttpd --port 8080
kubectl get services
kubectl describe service myhttpd
kubectl describe endpoints myhttpd
```

#### Port Forwarding
```bash
kubectl port-forward <pod-name> 3306:3306 &
```

#### Ingress-Konfiguration
```bash
kubectl get ingressclasses.networking.k8s.io
kubectl create ingress myhttpd --class nginx --rule "www.myfirst.local/*=myhttpd:8080"
echo "172.22.84.207 www.myfirst.local" | sudo tee -a /etc/hosts
curl www.myfirst.local
```

---

### 6. Konfigurationsmanagement

#### ConfigMaps
```bash
kubectl create configmap <name> --from-file=<file>
kubectl get configmaps
kubectl set data configmap <name> --from-file=<file>
oc set volumes deployment myhttpd --add --name <name> -t configmap \
  --configmap-name <name> --mount-path <path> --sub-path <subpath>
```

#### Secrets
```bash
read -s -p 'Passwort: '
kubectl create secret generic mymaria --from-literal MARIADB_ROOT_PASSWORD=$REPLY
kubectl get secrets
kubectl get -o yaml secrets <secret-name>
```

#### Service Accounts & Registry
```bash
kubectl create secret docker-registry redhat-registry \
  --docker-server registry.redhat.io \
  --docker-username <user> \
  --docker-password $REPLY
kubectl get serviceaccounts
oc secrets link default redhat-registry --for pull
```

---

### 7. Storage & Persistent Volumes

#### Grundkonzepte
- **NAS** (Filesystem)
- **SAN** (Block Device)
- **Object Store**

#### PV & PVC Verwaltung
```bash
kubectl get pvc                     # Persistent Volume Claims
kubectl get pv                      # Persistent Volumes
oc get sc                           # Storage Classes
```

#### Access Modes
- `rwo` - ReadWriteOnce
- `rwm` - ReadWriteMany
- `r` - ReadOnly

#### Volumes zu Deployment hinzufügen
```bash
oc set volumes deployment myhttpd --add --name myhttpd-data \
  -t pvc --claim-size 5G --claim-name myhttpd \
  --claim-mode rwm --mount-path /var/www/html
```

#### Reclaim Policy
- **Delete**: Löscht Daten (Standard, Vorsicht!)
- **Retain**: Behält Daten nach Löschung

---

### 8. StatefulSets

#### Unterschied zu Deployments
StatefulSets sind für zustandsbehaftete Anwendungen (z.B. Datenbanken):
- Stabile Netzwerk-Identität
- Persistente Speicher
- Geordnete Rollouts

#### Beispiel: MariaDB StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  labels:
    app: mymariadb
  name: mymariadb
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mymariadb
  template:
    metadata:
      labels:
        app: mymariadb
    spec:
      containers:
      - env:
        - name: MARIADB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              key: MARIADB_ROOT_PASSWORD
              name: mymaria
        image: docker.io/library/mariadb
        name: mariadb
        volumeMounts:
        - mountPath: /var/lib/mysql
          name: rma-mariadb-data
  volumeClaimTemplates:
  - metadata:
      name: rma-mariadb-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
```

#### StatefulSet verwalten
```bash
kubectl create -f mydb-statefulset.yaml
kubectl get pods,pvc
kubectl delete -f mydb-statefulset.yaml
```

---

### 9. OpenShift OC CLI

#### Installation
```bash
# Version prüfen
kubectl version

# OC Client herunterladen
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.19.19/openshift-client-linux-4.19.19.tar.gz
cd /usr/local/bin/
sudo tar xf ~/openshift-client-linux-4.19.19.tar.gz oc

# Tab-Completion
oc completion bash | sudo tee /etc/bash_completion.d/oc
source /etc/bash_completion.d/oc
```

#### OC Befehle
```bash
oc version
oc set volumes deployment <name> --add ...
oc set data configmap <name> --from-file=<file>
oc set data secret <name> --from-literal KEY=$VALUE
oc get pods
oc secrets link default <registry> --for pull
```

---

### 10. Häufige kubectl Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `kubectl get <resource>` | Ressourcen auflisten |
| `kubectl get <resource> <name> -o yaml` | YAML-Format |
| `kubectl get <resource> <name> -o json` | JSON-Format |
| `kubectl get <resource> <name> -o wide` | Erweiterte Informationen |
| `kubectl describe <resource> <name>` | Detaillierte Metadaten |
| `kubectl create <resource> ...` | Imperativ: Ressource erstellen |
| `kubectl create -f <file>` | Deklarativ: Aus Datei/Verzeichnis |
| `kubectl delete <resource> <name>` | Ressource löschen |
| `kubectl delete -f <file>` | Aus Datei löschen |
| `kubectl set <parameter> <resource> <name>` | Parameter setzen |
| `kubectl edit <resource> <name>` | Mit Editor bearbeiten |
| `kubectl logs <pod>` | Logs anzeigen |
| `kubectl exec <pod> -- <cmd>` | Befehl im Pod ausführen |
| `kubectl expose <deployment> ...` | Service erstellen |
| `kubectl explain <resource>` | Dokumentation |
| `kubectl run <name> ...` | Pod direkt erstellen |
| `kubectl rollout <deployment>` | Rollout-Management |
| `kubectl scale <deployment> --replicas N` | Replicas skalieren |
| `kubectl api-resources` | Alle API-Ressourcen anzeigen |
| `kubectl get events --sort-by lastTimestamp` | Fehlersuche |

---

### 11. Backup & Restore

#### Backup erstellen
```bash
kubectl get svc mymariadb -o yaml > mymariadb.yaml
kubectl get deploy,svc mymariadb -o yaml > mymariadb-all.yaml
```

#### Restore
```bash
# Optional: Alte Ressource löschen
# kubectl delete svc mymariadb
# kubectl delete all --all

kubectl create -f mymariadb.yaml
```

---

### 12. Datenverwaltung

#### Daten aus Container kopieren
```bash
kubectl cp <pod>:<path> <local-path>
kubectl cp <pod>:<path> . 
```

#### Daten in Container schreiben
```bash
kubectl exec -it <pod> -- bash
echo "test persistent volume" > /var/www/html/test.txt
```

#### Rsync mit OpenShift
```bash
oc rsync <pod>:/path /local/path
```

---

## Lernpfad-Übersicht

1. **Cluster & Konfiguration** → Grundlagen, Kontexte, Namespaces
2. **Pods & Deployments** → Ressourcen-Verwaltung, Skalierung
3. **Netzwerk** → Services, Ingress, DNS
4. **Konfiguration** → ConfigMaps, Secrets, Service Accounts
5. **Storage** → PV/PVC, StatefulSets
6. **Erweiterte Tools** → OC CLI, Rollouts, Backup/Restore

---

## Wichtige Links

- Kubernetes Dokumentation: https://kubernetes.io/docs
- RedHat Developer: https://developers.redhat.com
- RedHat Console: https://console.redhat.com
- OpenShift Clients: https://mirror.openshift.com

---

**Kurs-Status**: Grundlagen bis StatefulSets und OpenShift abgedeckt
**Letzte Aktualisierung**: Basierend auf Kurs-History und WSL-Notizen

