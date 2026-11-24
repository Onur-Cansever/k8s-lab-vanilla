#!/bin/bash
# remote-join.sh — WORKER VM'de calisir
# JOINCMD: controller'dan alinmis tam join komutu | KMODE | KOFD
set -e
echo "[1/3] eski worker state temizle"
kubeadm reset -f >/dev/null 2>&1 || true
rm -rf /var/lib/kubelet /etc/kubernetes

echo "[2/3] imajlari hazirla"
if [ "$KMODE" = "offline" ]; then
  for t in "$KOFD"/vanilla/images/*.tar; do
    echo "    $(basename "$t")"
    ctr -n k8s.io images import "$t" >/dev/null 2>&1 || echo "    UYARI: import basarisiz"
  done
fi

echo "[3/3] kubeadm join"
[ -n "$JOINCMD" ] || { echo "  HATA: JOINCMD bos — controller'dan token alinamadi"; exit 1; }
echo "  cmd: $JOINCMD"
eval "$JOINCMD" > /tmp/kubeadm-join.log 2>&1 || { echo "  HATA:"; tail -15 /tmp/kubeadm-join.log; exit 1; }
grep -E "done|Tried" /tmp/kubeadm-join.log | head -2
echo "JOIN_DONE $(hostname)"
