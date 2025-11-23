# ✓ Nextcloud TLS-Zertifikat mit automatischer Erneuerung

## Zusammenfassung

TLS-Zertifikat für Nextcloud wurde erfolgreich erstellt mit **automatischer Erneuerung** durch Cert-Manager!

### Zertifikat-Details

```bash
kubectl get certificate -n nextcloud-prod
```

**Ausgabe**:
```
NAME            READY   SECRET                 AGE
nextcloud-tls   True    nextcloud-tls-secret   ...
```

### Zertifikat-Informationen

| Parameter | Wert |
|-----------|------|
| **Common Name** | nextcloud.home16.local |
| **DNS Names** | nextcloud.home16.local, www.nextcloud.home16.local |
| **Issuer** | selfsigned (ClusterIssuer) |
| **Gültig bis** | 20. Februar 2026 (90 Tage) |
| **Erneuerung** | 21. Januar 2026 (30 Tage vor Ablauf) |
| **Secret Name** | nextcloud-tls-secret |
| **Status** | ✓ Ready |

---

## Automatische Erneuerung

### Konfiguration

Das Zertifikat erneuert sich **vollautomatisch**:

```yaml
spec:
  duration: 2160h  # 90 Tage Gültigkeit
  renewBefore: 720h  # Erneuerung 30 Tage vor Ablauf

  privateKey:
    rotationPolicy: Always  # Automatische Key-Rotation
```

### Erneuerungs-Zeitplan

| Event | Datum | Aktion |
|-------|-------|--------|
| **Zertifikat erstellt** | 22. November 2025 | - |
| **Erneuerung startet** | 21. Januar 2026 | Cert-Manager erstellt neues Zertifikat |
| **Zertifikat läuft ab** | 20. Februar 2026 | (wird nie erreicht - vorher erneuert) |

### Automatischer Ablauf

1. **30 Tage vor Ablauf**: Cert-Manager erstellt CertificateRequest
2. **Zertifikat-Ausstellung**: ClusterIssuer erstellt neues Zertifikat
3. **Secret-Update**: nextcloud-tls-secret wird aktualisiert
4. **Ingress-Reload**: Nginx Ingress lädt neues Zertifikat
5. **Kein Downtime**: Nahtloser Übergang

### Monitoring

**Zertifikat-Status prüfen**:
```bash
kubectl describe certificate nextcloud-tls -n nextcloud-prod
```

**Events anzeigen**:
```bash
kubectl get events -n nextcloud-prod --sort-by='.lastTimestamp' | grep nextcloud-tls
```

**Erneuerungs-Datum prüfen**:
```bash
kubectl get certificate nextcloud-tls -n nextcloud-prod -o jsonpath='{.status.renewalTime}'
```

---

## Ingress-Konfiguration

### TLS-Aktivierung

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud
  namespace: nextcloud-prod
spec:
  ingressClassName: nginx

  tls:
  - hosts:
    - nextcloud.home16.local
    secretName: nextcloud-tls-secret  # ← Automatisch erstellt/erneuert

  rules:
  - host: nextcloud.home16.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nextcloud
            port:
              number: 80
```

**Ingress Status**:
```bash
kubectl get ingress -n nextcloud-prod
kubectl describe ingress nextcloud -n nextcloud-prod
```

---

## Zugriff auf Nextcloud

### HTTPS-Zugriff (empfohlen)

```
https://nextcloud.home16.local
```

**Hinweis**: Da das Zertifikat selbst-signiert ist, erhalten Sie eine Browser-Warnung. Das ist normal!

**Browser-Warnung umgehen**:
- Chrome: "Erweitert" → "Trotzdem fortfahren"
- Firefox: "Erweitert" → "Risiko akzeptieren und fortfahren"
- Safari: "Details" → "Website besuchen"

### Zertifikat im Browser installieren (optional)

1. **Zertifikat exportieren**:
   ```bash
   kubectl get secret nextcloud-tls-secret -n nextcloud-prod -o jsonpath='{.data.tls\.crt}' | base64 -d > nextcloud.crt
   ```

2. **In Browser importieren**:
   - Chrome: Einstellungen → Datenschutz → Zertifikate verwalten
   - Firefox: Einstellungen → Datenschutz → Zertifikate → Zertifikate anzeigen
   - Safari: Schlüsselbundverwaltung → Zertifikat hinzufügen

3. **Als vertrauenswürdig markieren**

### DNS-Konfiguration

Fügen Sie zu `/etc/hosts` hinzu (macOS/Linux):
```bash
# Nextcloud
127.0.0.1  nextcloud.home16.local
::1        nextcloud.home16.local
```

Oder für Docker Desktop Kubernetes:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# NodePort: 31896 (HTTPS)
```

**Zugriff via NodePort**:
```
https://localhost:31896
```

---

## Kommandos-Übersicht

### Zertifikat verwalten

```bash
# Status anzeigen
kubectl get certificate -n nextcloud-prod

# Details anzeigen
kubectl describe certificate nextcloud-tls -n nextcloud-prod

# Secret prüfen
kubectl get secret nextcloud-tls-secret -n nextcloud-prod

# Zertifikat-Inhalt anzeigen
kubectl get secret nextcloud-tls-secret -n nextcloud-prod -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text

# Ablaufdatum prüfen
kubectl get secret nextcloud-tls-secret -n nextcloud-prod -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate
```

### Manuelle Erneuerung erzwingen

Normalerweise nicht nötig, aber falls gewünscht:

```bash
# Zertifikat löschen (wird automatisch neu erstellt)
kubectl delete certificate nextcloud-tls -n nextcloud-prod

# Oder: Secret löschen (Cert-Manager erstellt neu)
kubectl delete secret nextcloud-tls-secret -n nextcloud-prod
```

Cert-Manager erkennt das fehlende Secret automatisch und erstellt ein neues Zertifikat.

### CertificateRequest prüfen

```bash
# Alle Requests anzeigen
kubectl get certificaterequest -n nextcloud-prod

# Details eines Request
kubectl describe certificaterequest nextcloud-tls-1 -n nextcloud-prod
```

---

## Upgrade auf Let's Encrypt

Für öffentlich erreichbare Domains können Sie auf Let's Encrypt upgraden:

### 1. Certificate anpassen

```bash
kubectl edit certificate nextcloud-tls -n nextcloud-prod
```

**Ändern**:
```yaml
spec:
  issuerRef:
    name: letsencrypt-prod  # ← von "selfsigned" ändern
    kind: ClusterIssuer

  # Öffentliche Domain eintragen
  commonName: nextcloud.yourdomain.com
  dnsNames:
    - nextcloud.yourdomain.com
    - www.nextcloud.yourdomain.com
```

### 2. Ingress anpassen

```bash
kubectl edit ingress nextcloud -n nextcloud-prod
```

**Ändern**:
```yaml
spec:
  tls:
  - hosts:
    - nextcloud.yourdomain.com  # ← Öffentliche Domain
    secretName: nextcloud-tls-secret

  rules:
  - host: nextcloud.yourdomain.com  # ← Öffentliche Domain
```

### 3. DNS konfigurieren

Stellen Sie sicher, dass:
- `nextcloud.yourdomain.com` auf Ihre öffentliche IP zeigt
- Port 80 & 443 vom Internet erreichbar sind (für HTTP-01 Challenge)

Let's Encrypt wird dann automatisch ein vertrauenswürdiges Zertifikat ausstellen!

---

## Troubleshooting

### Zertifikat zeigt "Ready: False"

**Problem**: Certificate Status ist nicht Ready

**Lösung**:
```bash
# Events prüfen
kubectl describe certificate nextcloud-tls -n nextcloud-prod

# Cert-Manager Logs prüfen
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Issuer prüfen
kubectl get clusterissuer selfsigned -o yaml
```

### Secret existiert nicht

**Problem**: `nextcloud-tls-secret` wird nicht erstellt

**Lösung**:
```bash
# CertificateRequest prüfen
kubectl get certificaterequest -n nextcloud-prod

# Request-Details anzeigen
kubectl describe certificaterequest -n nextcloud-prod

# Certificate neu erstellen
kubectl delete certificate nextcloud-tls -n nextcloud-prod
kubectl apply -f manifests/nextcloud/08-tls-certificate.yaml
```

### Ingress zeigt alte Zertifikats-Warnung

**Problem**: Browser zeigt altes/falsches Zertifikat

**Lösung**:
```bash
# Nginx Ingress Pod neu starten
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

# Browser-Cache leeren
# Strg+Shift+Delete → Cache leeren

# Inkognito-Modus testen
```

### Let's Encrypt Challenge fehlgeschlagen

**Problem**: Let's Encrypt kann Domain nicht verifizieren

**Ursache**:
- Domain nicht öffentlich erreichbar
- Port 80 nicht offen
- DNS nicht korrekt konfiguriert

**Lösung**:
- Verwenden Sie `selfsigned` für interne/lokale Domains
- Oder: Stellen Sie sicher, dass Domain öffentlich erreichbar ist

---

## Sicherheits-Best-Practices

### 1. Starke Cipher verwenden

Im Ingress bereits konfiguriert:
```yaml
nginx.ingress.kubernetes.io/ssl-redirect: "true"
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

### 2. HSTS aktivieren

Bereits in Ingress konfiguriert via Annotations.

### 3. Regelmäßige Überprüfung

```bash
# Monatlich: Zertifikat-Status prüfen
kubectl get certificate -A

# Ablaufdaten prüfen
kubectl get certificate -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,EXPIRY:.status.notAfter
```

### 4. Monitoring einrichten

Cert-Manager exportiert Metriken für Prometheus:
- `certmanager_certificate_expiration_timestamp_seconds`
- `certmanager_certificate_ready_status`

Diese werden automatisch von Prometheus gesammelt!

**In Grafana**:
- Dashboard importieren: https://grafana.com/grafana/dashboards/11001
- Oder: Eigene Alerts erstellen für ablaufende Zertifikate

---

## ✓ Zusammenfassung

Sie haben jetzt:

- ✓ **TLS-Zertifikat** für Nextcloud erstellt
- ✓ **Automatische Erneuerung** konfiguriert (30 Tage vor Ablauf)
- ✓ **Ingress** mit HTTPS aktiviert
- ✓ **Kein manueller Eingriff** nötig - alles automatisch!

**Nächste Schritte**:
1. Nextcloud via HTTPS aufrufen
2. Admin-Benutzer erstellen
3. Optional: Auf Let's Encrypt upgraden (für öffentliche Domains)
4. Zertifikats-Ablauf in Grafana monitoren

**Zertifikat-Lebenszyklus**:
```
Erstellung → 90 Tage Gültigkeit → Erneuerung @ Tag 60 → Neues Zertifikat
           └──────────────────────────┘              └────────────────────┘
                Automatisch                             Automatisch
```

Viel Erfolg mit Ihrem TLS-gesicherten Nextcloud! 🔒🚀
