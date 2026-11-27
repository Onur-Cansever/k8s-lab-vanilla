#!/bin/bash
# cluster-init.sh — controller VM'de: kubeadm init (kube-proxy atla) + Cilium CNI (kube-proxy replacement)
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf 2>/dev/null || true

if [ -f /etc/kubernetes/admin.conf ]; then
  echo "CLUSTER_ALREADY_INIT — önce teardown.sh çalıştırın"; exit 1
fi
rmdir /etc/kubernetes/manifests 2>/dev/null || true

kubeadm init \
  --apiserver-cert-extra-sans=192.168.10.73 \
  --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock \
  --skip-phases=addon/kube-proxy

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown -R root:root /root/.kube

echo "CILIUM APLANIYOR (kube-proxy replacement)..."
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm install cilium cilium/cilium --version 1.20.5 -n kube-system \
  --set kubeProxyReplacement=true --set k8sServiceHost=192.168.10.73 --set k8sServicePort=6443 \
  --wait --timeout 10m
for i in $(seq 1 30); do
  kubectl get nodes | grep -q Ready && kubectl -n kube-system get pods | grep -q "cilium.*Running" && break
  sleep 10
done
kubectl get nodes -o wide
echo INIT_DONE
