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
    -subj "/CN=192.168.10.77" -addext "subjectAltName=IP:192.168.10.77,DNS:192.168.10.77"
fi
kubectl -n cattle-system create secret tls rancher-tls --cert=tls.crt --key=tls.key \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | head -1
# helm install
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest 2>&1 | tail -1 || helm repo update
helm repo update >/dev/null 2>&1
PW=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
echo "BOOTSTRAP_PW=$PW" > /root/rancher-pw.txt; chmod 600 /root/rancher-pw.txt
CRTB=$(base64 -w0 tls.crt); KEYB=$(base64 -w0 tls.key)
helm install rancher rancher-latest/rancher -n cattle-system \
  --set hostname=192.168.10.77 \
  --set ingress.tls.source=secret \
  --set privateCA=true \
  --set "ingress.tls.certificate=$CRTB" \
  --set "ingress.tls.certificateKey=$KEYB" \
  --set bootstrapPassword=$PW \
  --wait --timeout 9m 2>&1 | tail -4
kubectl -n cattle-system get pods 2>/dev/null | head -6
curl -sk -o /dev/null -w "UI_HTTPS=%{http_code}\n" https://192.168.10.77/
echo RANCHER_DONE
