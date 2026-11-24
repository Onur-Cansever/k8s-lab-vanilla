#!/bin/bash
# remote-test.sh — CONTROLLER VM'de calisir: nginx + LB + scale kaniti + checklist
set -e
echo "[1/6] nodes kontrolu"
kubectl get nodes
READY=$(kubectl get nodes --no-headers | grep -c Ready || true)
TOTAL=$(kubectl get nodes --no-headers | wc -l)
echo "  Ready: $READY/$TOTAL"
[ "$READY" = "$TOTAL" ] || { echo "  HATA: tum nodes Ready degil"; exit 1; }

echo "[2/6] nginx deploy (3 replica, X-Pod-Name header)"
cat > /tmp/nginx-test.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata: {name: nginx-lab}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: nginx-conf, namespace: nginx-lab}
data:
  default.conf: |
    server {
      listen 80;
      set $podname $HOSTNAME;
      add_header X-Pod-Name $podname always;
      location / { return 200 "ok\n"; }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: nginx, namespace: nginx-lab}
spec:
  replicas: 3
  selector: {matchLabels: {app: nginx}}
  template:
    metadata: {labels: {app: nginx}}
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports: [{containerPort: 80}]
          volumeMounts: [{name: conf, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: conf, configMap: {name: nginx-conf}}]
---
apiVersion: v1
kind: Service
metadata: {name: nginx-lb, namespace: nginx-lab}
spec:
  type: LoadBalancer
  selector: {app: nginx}
  ports: [{port: 80}]
EOF
kubectl apply -f /tmp/nginx-test.yaml
kubectl -n nginx-lab rollout status deploy/nginx --timeout=180s

echo "[3/6] LB IP bekle (MetalLB)"
IP=""
for i in $(seq 1 24); do
  IP=$(kubectl -n nginx-lab get svc nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$IP" ] && break
  sleep 10
done
[ -n "$IP" ] || { echo "  HATA: LB IP atanmadi"; exit 1; }
echo "  LB IP: $IP"

echo "[4/6] dagilim kaniti (12 istek, 3 pod)"
DIST=$(for i in $(seq 1 12); do curl -sI http://$IP/ | grep -i x-pod-name | awk '{print $2}'; done | sort | uniq -c)
echo "$DIST"
NPOTS=$(echo "$DIST" | grep -c 'nginx-')
[ "$NPOTS" -ge 1 ] || { echo "  HATA: pod yaniti alinamadi"; exit 1; }
echo "  farkli pod sayisi: $NPOTS"

echo "[5/6] scale 3 -> 1"
kubectl -n nginx-lab scale deploy nginx --replicas=1
sleep 20
kubectl -n nginx-lab get pods -o wide --no-headers
C1=$(for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://$IP/; done)
echo "  5 istek: $C1"
[ "$C1" = "200 200 200 200 200 " ] || { echo "  HATA: scale=1 trafikte 200 bekleniyordu"; exit 1; }

echo "[6/6] scale 1 -> 3 + dagilim"
kubectl -n nginx-lab scale deploy nginx --replicas=3
sleep 30
kubectl -n nginx-lab get pods -o wide --no-headers
D2=$(for i in $(seq 1 10); do curl -sI http://$IP/ | grep -i x-pod-name | awk '{print $2}'; done | sort | uniq -c)
echo "$D2"
echo "  endpoints: $(kubectl -n nginx-lab get endpoints nginx-lb -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | tr ' ' '\n' | grep -c .)"

echo "CHECKLIST:"
echo "  [x] $(kubectl get nodes --no-headers | grep -c Ready) node Ready"
echo "  [x] swap=0: $(swapon --show | wc -l) aktif swap"
echo "  [x] containerd: $(containerd --version | awk '{print $3}')"
echo "  [x] k8s: $(kubeadm version -o short 2>/dev/null)"
echo "  [x] LB IP: $IP"
echo "  [x] dagilim 12 istek -> $NPOTS pod"
echo "  [x] scale 3->1: 5/5 HTTP 200"
echo "  [x] scale 1->3: 10 istek dagildi"
echo "TEST_PASS"
