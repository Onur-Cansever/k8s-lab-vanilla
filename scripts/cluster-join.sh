#!/bin/bash
# cluster-join.sh — worker VM'de: token'ı controller'dan al, katıl
set -uo pipefail
CP=192.168.10.73
export KUBECONFIG=/root/.kube/config 2>/dev/null || true

if [ -d /etc/kubernetes/manifests ] && [ -f /etc/kubernetes/kubelet.conf ]; then
  kubeadm node 2>/dev/null; systemctl is-active kubelet >/dev/null && \
    kubectl get nodes 2>/dev/null | grep -q "$(hostname)" && {
      echo "ALREADY_JOINED"; exit 0; }
fi

JOIN=$(ssh -o BatchMode=yes root@$CP "kubeadm token create --print-join-command --ttl 30m")
eval "$JOIN"
echo JOIN_DONE
