#!/bin/bash
# teardown.sh — orion'dan çalıştır: tüm k8s state'i kaldır, VM'leri temiz bırak
# (docs/07). VM diski silinmez, hostname/SSH/lease korunur.
set -uo pipefail
CP=root@192.168.10.73
WORKERS="root@192.168.10.74 root@192.168.10.75 root@192.168.10.76"
K() { ssh -o BatchMode=yes "$CP" "kubectl $*"; }

echo "[1/5] Rancher kaldırılıyor..."
ssh -o BatchMode=yes "$CP" "helm uninstall rancher -n cattle-system" 2>/dev/null || true
K delete ns cattle-system --ignore-not-found --timeout=300s || true

echo "[2/5] Test işyükü + MetalLB..."
K delete ns nginx-lab --ignore-not-found --timeout=120s || true
K delete ns metallb-system --ignore-not-found --timeout=120s || true

echo "[3/5] Calico..."
K delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.1/manifests/calico.yaml --ignore-not-found 2>/dev/null || true

echo "[4/5] kubeadm reset (4 VM)..."
for h in $CP $WORKERS; do
  ssh -o BatchMode=yes "$h" '
    systemctl stop kubelet 2>/dev/null || true
    kubeadm reset -f --cri-socket=unix://run/containerd/containerd.sock 2>&1 | tail -1
    rm -rf /etc/kubernetes /root/.kube /root/cluster-init.sh /root/join.sh
    # containerd: kubeadm CRI config bloğunu geri al
    CT=/etc/containerd/config.toml
    if [ -f "$CT" ] && grep -q "kubelet_config" "$CT"; then
      sed -i "/\[plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runc.options\]/,/^$/d" "$CT"
      systemctl restart containerd
    fi
  ' &
done
wait

echo "[5/5] Doğrulama..."
for h in $CP $WORKERS; do
  st=$(ssh -o BatchMode=yes "$h" 'systemctl is-active kubelet 2>/dev/null; [ -f /etc/kubernetes/admin.conf ] && echo "INITED" || echo "not initialized"')
  echo "$h => $st"
done
echo TEARDOWN_DONE
