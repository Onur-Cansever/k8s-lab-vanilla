#!/bin/bash
# cluster-init.sh — controller VM'de: kubeadm init + Calico CNI
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf 2>/dev/null || true

if [ -f /etc/kubernetes/admin.conf ]; then
  echo "CLUSTER_ALREADY_INIT — önce teardown.sh çalıştırın"; exit 1
fi
rmdir /etc/kubernetes/manifests 2>/dev/null || true

kubeadm init \
  --apiserver-cert-extra-sans=192.168.10.73 \
  --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown -R root:root /root/.kube

echo "CALICO_APLANIYOR..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.1/manifests/calico.yaml

for i in $(seq 1 30); do
  kubectl get nodes | grep -q Ready && kubectl -n calico-system get pods | grep -q Running && break
  sleep 10
done
kubectl get nodes -o wide
echo INIT_DONE
