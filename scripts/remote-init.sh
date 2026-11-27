#!/bin/bash
# remote-init.sh — CONTROLLER VM'de calisir
# CP_IP: kendi IP'si (cert SAN) | KMODE | KOFD
set -e
echo "[1/5] eski state temizle"
kubeadm reset -f >/dev/null 2>&1 || true
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /root/.kube

echo "[2/5] imajlari hazirla"
if [ "$KMODE" = "offline" ]; then
  echo "  offline: $KOFD/vanilla/images/ (tumu import)"
  FAIL=0
  for t in "$KOFD"/vanilla/images/*.tar; do
    echo "    $(basename "$t")"
    ctr -n k8s.io images import "$t" >/dev/null 2>&1 || { echo "    UYARI: import basarisiz"; FAIL=1; }
  done
  [ $FAIL -eq 0 ] || echo "  (devam; eksik imaj pod aksaminda hata verir)"
fi

echo "[3/5] kubeadm init (pod-cidr 192.168.0.0/16, san: $CP_IP, kube-proxy atla)"
kubeadm init --apiserver-cert-extra-sans=$CP_IP --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock --skip-phases=addon/kube-proxy > /tmp/kubeadm-init.log 2>&1 \
  || { echo "  HATA — son satirlar:"; tail -15 /tmp/kubeadm-init.log; exit 1; }
grep -E "Your control plane|kubeadm join" /tmp/kubeadm-init.log | head -2
mkdir -p /root/.kube; cp /etc/kubernetes/admin.conf /root/.kube/config

echo "[4/5] Cilium CNI (kube-proxy replacement)"
if [ "$KMODE" = "offline" ]; then
  helm install cilium "$KOFD/vanilla/cilium-1.20.5.tgz" -n kube-system \
    --set kubeProxyReplacement=true --set k8sServiceHost=$CP_IP --set k8sServicePort=6443 --wait --timeout 10m
else
  helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
  helm install cilium cilium/cilium --version 1.20.5 -n kube-system \
    --set kubeProxyReplacement=true --set k8sServiceHost=$CP_IP --set k8sServicePort=6443 --wait --timeout 10m
fi
for i in $(seq 1 24); do kubectl -n kube-system get pods 2>/dev/null | grep -q "cilium" && kubectl get nodes 2>/dev/null | grep -q Ready && break; sleep 10; done

echo "[5/5] MetalLB (controller ayakta beklenir, sonra pool)"
if [ "$KMODE" = "offline" ]; then kubectl apply -f "$KOFD/vanilla/metallb-native.yaml"; else kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.2/config/manifests/metallb-native.yaml; fi
# worker yokken controller pod taint'e takilir → toleration ekle
D=$(kubectl -n metallb-system get deploy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
kubectl -n metallb-system patch deploy "$D" -p '{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}}}}' >/dev/null 2>&1 || true
for i in $(seq 1 30); do
  [ "$(kubectl -n metallb-system get deploy "$D" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "1" ] && break
  sleep 10
done
# webhook CA patch'i gecikmeli olabileceginden pool apply retry
cat > /tmp/metallb-pool.yaml <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: lab-pool, namespace: metallb-system}
spec: {addresses: ["192.168.10.80-192.168.10.84"]}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: lab-l2, namespace: metallb-system}
spec: {ipAddressPools: [lab-pool]}
EOF
for i in 1 2 3 4 5 6; do
  kubectl apply -f /tmp/metallb-pool.yaml 2>&1 | grep -qE "created|unchanged" && { echo "  pool OK (deneme=$i)"; break; }
  sleep 15
done
kubectl get nodes
echo "INIT_DONE $CP_IP"
