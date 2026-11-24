#!/bin/bash
# test-nginx.sh — LB uzerinden pod dagilimi kaniti + scale 3->1->3
# Kullanim: controller VM'de  (LB_IP otomatik bulunur)
set -uo pipefail
NS=nginx-lab
IP=$(kubectl -n $NS get svc nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[ -z "$IP" ] && { echo "LB IP yok: $(kubectl -n $NS describe svc nginx-lb | tail -5)"; exit 1; }
echo "LB IP: $IP"
podhdr() { curl -sI http://$IP/ | grep -i x-pod-name | awk '{print $2}'; }
echo "=== 12 istek, pod dagilimi:"
for i in $(seq 1 12); do podhdr; done | sort | uniq -c
echo "=== SCALE 3 -> 1"
kubectl -n $NS scale deployment nginx --replicas=1
sleep 25
kubectl -n $NS get pods -o wide --no-headers | awk '{print "  "$1, $3, $7}'
echo -n "  5 istek: "; for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://$IP/; done; echo
echo "=== SCALE 1 -> 3"
kubectl -n $NS scale deployment nginx --replicas=3
sleep 30
kubectl -n $NS get pods -o wide --no-headers | awk '{print "  "$1, $3, $7}'
echo "  10 istek dagilimi:"
for i in $(seq 1 10); do podhdr; done | sort | uniq -c
echo "TEST_DONE"
