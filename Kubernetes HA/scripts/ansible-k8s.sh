#!/bin/bash
# Ansible in Kubernetes - Helper Script
# Verwendung: ./ansible-k8s.sh [command] [args...]

set -e

NAMESPACE="ansible"
DEPLOYMENT="ansible-k8s"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funktionen
print_usage() {
    cat <<EOF
${BLUE}Ansible in Kubernetes - Helper Script${NC}

${GREEN}Verwendung:${NC}
  $0 [command] [args...]

${GREEN}Verfügbare Befehle:${NC}

  ${YELLOW}shell${NC}
      Interaktive Shell im Ansible-Container öffnen
      Beispiel: $0 shell

  ${YELLOW}ansible [args...]${NC}
      Ansible-Befehl im Container ausführen
      Beispiel: $0 ansible localhost -m ping

  ${YELLOW}playbook <file> [args...]${NC}
      Ansible-Playbook ausführen
      Beispiel: $0 playbook /ansible/playbooks/site.yml -v

  ${YELLOW}kubectl [args...]${NC}
      kubectl im Ansible-Container ausführen
      Beispiel: $0 kubectl get nodes

  ${YELLOW}copy <source> <dest>${NC}
      Datei/Verzeichnis in Container kopieren
      Beispiel: $0 copy playbooks/ /ansible/playbooks/

  ${YELLOW}logs${NC}
      Container-Logs anzeigen
      Beispiel: $0 logs

  ${YELLOW}status${NC}
      Status des Ansible-Deployments anzeigen
      Beispiel: $0 status

  ${YELLOW}restart${NC}
      Ansible-Pod neu starten
      Beispiel: $0 restart

  ${YELLOW}deploy${NC}
      Ansible-Manifeste deployen/aktualisieren
      Beispiel: $0 deploy

  ${YELLOW}delete${NC}
      Ansible-Deployment entfernen
      Beispiel: $0 delete

${GREEN}Beispiele:${NC}

  # Shell öffnen
  $0 shell

  # Ansible ping test
  $0 ansible localhost -m ping

  # Playbook ausführen
  $0 playbook /ansible/playbooks/extensions.yml -t monitoring

  # Kubernetes Nodes anzeigen
  $0 kubectl get nodes

  # Playbooks kopieren
  $0 copy ../extensions_playbook.yml /ansible/playbooks/extensions.yml

EOF
}

get_pod() {
    kubectl get pod -n "$NAMESPACE" -l "app=$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Hauptlogik
case "${1:-help}" in
    shell)
        echo -e "${GREEN}Öffne Shell im Ansible-Container...${NC}"
        kubectl exec -it -n "$NAMESPACE" deployment/"$DEPLOYMENT" -- /bin/bash
        ;;

    ansible)
        shift
        echo -e "${GREEN}Führe Ansible-Befehl aus...${NC}"
        kubectl exec -n "$NAMESPACE" deployment/"$DEPLOYMENT" -- ansible "$@"
        ;;

    playbook)
        shift
        echo -e "${GREEN}Führe Ansible-Playbook aus...${NC}"
        kubectl exec -n "$NAMESPACE" deployment/"$DEPLOYMENT" -- ansible-playbook "$@"
        ;;

    kubectl)
        shift
        echo -e "${GREEN}Führe kubectl im Container aus...${NC}"
        kubectl exec -n "$NAMESPACE" deployment/"$DEPLOYMENT" -- sh -c "unset KUBECONFIG && kubectl $*"
        ;;

    copy)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Source und Destination erforderlich${NC}"
            echo "Verwendung: $0 copy <source> <dest>"
            exit 1
        fi
        POD=$(get_pod)
        if [ -z "$POD" ]; then
            echo -e "${RED}Error: Ansible-Pod nicht gefunden${NC}"
            exit 1
        fi
        echo -e "${GREEN}Kopiere $2 nach $POD:$3${NC}"
        kubectl cp "$2" "$NAMESPACE/$POD:$3"
        echo -e "${GREEN}✓ Erfolgreich kopiert${NC}"
        ;;

    logs)
        echo -e "${GREEN}Zeige Ansible-Container Logs...${NC}"
        kubectl logs -n "$NAMESPACE" deployment/"$DEPLOYMENT" --tail=100 -f
        ;;

    status)
        echo -e "${BLUE}=== Ansible Deployment Status ===${NC}\n"
        kubectl get all -n "$NAMESPACE"
        echo -e "\n${BLUE}=== PVCs ===${NC}"
        kubectl get pvc -n "$NAMESPACE"
        echo -e "\n${BLUE}=== ConfigMaps ===${NC}"
        kubectl get configmap -n "$NAMESPACE"
        echo -e "\n${BLUE}=== ServiceAccounts ===${NC}"
        kubectl get serviceaccount -n "$NAMESPACE"
        ;;

    restart)
        echo -e "${YELLOW}Starte Ansible-Pod neu...${NC}"
        kubectl delete pod -n "$NAMESPACE" -l "app=$DEPLOYMENT"
        echo -e "${GREEN}Warte auf Pod...${NC}"
        kubectl wait --for=condition=Ready pod -l "app=$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
        echo -e "${GREEN}✓ Pod neu gestartet${NC}"
        ;;

    deploy)
        MANIFEST_DIR="$(dirname "$0")/../manifests/ansible"
        if [ ! -d "$MANIFEST_DIR" ]; then
            echo -e "${RED}Error: Manifest-Verzeichnis nicht gefunden: $MANIFEST_DIR${NC}"
            exit 1
        fi
        echo -e "${GREEN}Deploye Ansible-Manifeste...${NC}"
        kubectl apply -f "$MANIFEST_DIR/"
        echo -e "${GREEN}Warte auf Pod...${NC}"
        kubectl wait --for=condition=Ready pod -l "app=$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
        echo -e "${GREEN}✓ Deployment erfolgreich${NC}"
        ;;

    delete)
        echo -e "${YELLOW}Lösche Ansible-Deployment...${NC}"
        MANIFEST_DIR="$(dirname "$0")/../manifests/ansible"
        if [ -d "$MANIFEST_DIR" ]; then
            kubectl delete -f "$MANIFEST_DIR/" || true
        else
            kubectl delete namespace "$NAMESPACE" || true
        fi
        echo -e "${GREEN}✓ Ansible-Deployment entfernt${NC}"
        ;;

    help|--help|-h)
        print_usage
        ;;

    *)
        echo -e "${RED}Unbekannter Befehl: $1${NC}\n"
        print_usage
        exit 1
        ;;
esac
