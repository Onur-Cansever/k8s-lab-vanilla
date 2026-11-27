#!/bin/bash
# rancher-fresh.sh — k8sdig'de sifirdan tek gecis: k8s 1.36 + ingress-nginx + rancher
set -euo pipefail
echo "=== [1/6] k8s state temizle"
systemctl stop kubelet 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true
pkill -9 kubelet 2>/dev/null || true
kubeadm reset -f >/dev/null 2>&1 || true
for t in $(ctr -n k8s.io tasks ls -q 2>/dev/null); do ctr -n k8s.io tasks kill --signal KILL -a "$t" 2>/dev/null; done
sleep 2
for c in $(ctr -n k8s.io containers ls -q 2>/dev/null); do ctr -n k8s.io containers rm "$c" 2>/dev/null; done
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /root/.kube /var/log/pods
echo "=== [2/6] kubeadm init (1.36, kube-proxy atla) + cilium (kube-proxy replacement)"
kubeadm init --apiserver-cert-extra-sans=192.168.10.77 --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock --skip-phases=addon/kube-proxy > /tmp/init.log 2>&1 || { echo "INIT HATA:"; grep -E "ERROR|error" /tmp/init.log | head -5; exit 1; }
mkdir -p /root/.kube; cp /etc/kubernetes/admin.conf /root/.kube/config
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm install cilium cilium/cilium --version 1.20.5 -n kube-system \
  --set kubeProxyReplacement=true --set k8sServiceHost=192.168.10.77 --set k8sServicePort=6443 --set cluster.ipam.cidr=192.168.0.0/16 --wait --timeout 10m >/dev/null 2>&1
kubectl taint nodes k8sdig node-role.kubernetes.io/control-plane- 2>/dev/null
for i in $(seq 1 12); do kubectl get nodes 2>/dev/null | grep -q Ready && break; sleep 10; done
echo "=== [3/6] ingress-nginx (admission webhook kapali)"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.hostNetwork=true --set controller.admissionWebhooks.enabled=false \
  --wait --timeout 5m >/dev/null 2>&1 || true
echo "=== [4/6] rancher meta-cluster"
bash /root/rancher-install.sh 2>&1 | tail -4
echo "=== [5/6] ingress class"
sleep 5
kubectl -n cattle-system patch ingress rancher -p '{"spec":{"ingressClassName":"nginx"}}' 2>/dev/null || true
kubectl -n cattle-system scale deploy rancher --replicas=1 2>/dev/null || true
echo "=== [6/6] login testi"
PW=$(grep -oP "BOOTSTRAP_PW=\K\S+" /root/rancher-pw.txt 2>/dev/null)
sleep 480
echo "login: $(curl -sk -o /tmp/tok.json -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "{\"login\":\"admin\",\"password\":\"$PW\"}" https://k8sdig.lab/v3/tokens)"
head -c 150 /tmp/tok.json; echo
kubectl -n cattle-system get pods --no-headers 2>&1 | grep -v helm-operation | head -4
echo FRESH_DONE
