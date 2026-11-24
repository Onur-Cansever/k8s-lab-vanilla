#!/bin/bash
# rancher-install.sh — Rancher meta-cluster kurulumu
# MIMARI: Rancher, yonetecegi cluster'in DISINDA calismalidir.
# Laboratuvarda: k8sdig VM (192.168.10.77, tek-node k8s) = meta-cluster.
# Kullanim: ssh root@192.168.10.77 'bash /root/rancher-install.sh'
set -euo pipefail
kubectl get nodes 2>/dev/null | grep -q Ready || { echo "K8S_NOT_READY"; exit 1; }
# helm
if ! command -v helm >/dev/null; then
  curl -fsSL -o /tmp/helm.tgz https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz
  tar -xzf /tmp/helm.tgz -C /tmp && install -m755 /tmp/linux-amd64/helm /usr/local/bin/helm
fi
# bootstrap RBAC (agent import icin; helm install once gereksiz)
kubectl create namespace cattle-system 2>/dev/null || true
# not: rbac.rancher.io domain'i mevcut degil; bootstrap RBAC import adiminda
#     https://www.rancher.io/docs/... icindeki manifest ile kurulur
# self-signed TLS (lab: IP ile)
cd /tmp
if [ ! -s tls.crt ]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout tls.key -out tls.crt \
    -subj "/CN=k8sdig.lab" -addext "subjectAltName=DNS:k8sdig.lab,IP:192.168.10.77"
fi
# secret'ler (chart beklentisi — dogrulanmis):
#   tls-ca: cacerts.pem anahtari (rancher server CA mount, subPath)
#   tls-rancher-ingress: chart, inline certificate ile otomatik olusturur
kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem=/tmp/tls.crt \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | head -1
# helm install (wait SIZ: webhook yarisi icin hemen pause yapacagiz)
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest 2>&1 | tail -1 || helm repo update
helm repo update >/dev/null 2>&1
RAW=$(openssl rand -base64 48)
PW=$(printf '%s' "$RAW" | tr -dc 'A-Za-z0-9')
PW=${PW:0:24}
echo "BOOTSTRAP_PW=$PW" > /root/rancher-pw.txt; chmod 600 /root/rancher-pw.txt
CRTB=$(base64 -w0 tls.crt); KEYB=$(base64 -w0 tls.key)
helm install rancher rancher-latest/rancher -n cattle-system \
  --set hostname=k8sdig.lab \
  --set ingress.tls.source=secret \
  --set privateCA=true \
  --set "ingress.tls.certificate=$CRTB" \
  --set "ingress.tls.certificateKey=$KEYB" \
  --set bootstrapPassword=$PW \
  --set replicas=1 \
  --timeout 9m 2>&1 | tail -4
# WEBHOOK YARISI ONLEMI: rancher pod, ilk provisioning'inden ONCE duraklat;
# webhook ready olunca serbest birak (bosuna 401 döngusunu engeller)
kubectl -n cattle-system scale deploy rancher --replicas=0 2>/dev/null || true
kubectl -n cattle-system rollout status deploy/rancher-webhook --timeout=6m 2>/dev/null || sleep 120
kubectl -n cattle-system scale deploy rancher --replicas=1 2>/dev/null || true
kubectl -n cattle-system rollout status deploy/rancher --timeout=9m 2>&1 | tail -2
kubectl -n cattle-system get pods 2>/dev/null | grep -v helm-operation | head -5
curl -sk -o /dev/null -w "UI_HTTPS=%{http_code}\n" https://k8sdig.lab/
echo RANCHER_DONE
