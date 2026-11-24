#!/bin/bash
# rancher-install.sh — orion'dan çalıştır (controller üzerinden)
set -uo pipefail
CP=root@192.168.10.73
K() { ssh -o BatchMode=yes "$CP" "kubectl $*"; }

K get ns cattle-system >/dev/null 2>&1 || K create ns cattle-system
K -n cattle-system get deploy rancher >/dev/null 2>&1 && { echo "Rancher zaten kurulu"; exit 0; }

K apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: rancher
  namespace: cattle-system
  labels:
    app: rancher
spec:
  type: LoadBalancer
  selector:
    app: rancher
  ports:
    - port: 80
      targetPort: 80
    - port: 443
      targetPort: 443
EOF

K create secret generic ingress-internal-tls --namespace cattle-system \
  --from-file=tls.crt=/dev/null 2>/dev/null || true

ssh -o BatchMode=yes "$CP" "helm repo add rancher-stable https://releases.rancher.com/chart || true; helm repo update"
ssh -o BatchMode=yes "$CP" "helm upgrade --install rancher rancher-stable/rancher -n cattle-system --set replicas=1 --timeout 20m"
K -n cattle-system rollout status deploy/ranchar 2>/dev/null || K -n cattle-system rollout status deploy/rancher
LB=$(K -n cattle-system get svc rancher -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
PW=$(K -n cattle-system get secret bootstrap-password -o jsonpath='{.data.password}' | base64 -d)
echo "RANCHER_URL=http://$LB/"
echo "BOOTSTRAP_PASSWORD=$PW"
echo RANCHER_DONE
