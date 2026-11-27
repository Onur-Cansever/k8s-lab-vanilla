#!/bin/bash
# k8s-lab-install.sh — Vanilla Kubernetes laboratuvar kurulumu (1 CP + 1..N worker)
# OL8.10, k8s 1.37.2, containerd 2.0.14, Cilium (kube-proxy replacement), MetalLB
#
# KULLANIM (driver makine, orion gibi — VM'lere ssh yetkili):
#   MODE=online  ./k8s-lab-install.sh base     192.168.10.73 192.168.10.74 ...
#   MODE=online  ./k8s-lab-install.sh init     192.168.10.73
#   MODE=online  ./k8s-lab-install.sh join     192.168.10.73 192.168.10.74 192.168.10.75 ...
#   MODE=online  ./k8s-lab-install.sh test     192.168.10.73
#   MODE=online  ./k8s-lab-install.sh teardown 192.168.10.73 ...
#
# OFFLINE (OFD dizini her VM'de ayni yolda olmalidir; hedef ortamda internet YOK):
#   MODE=offline OFD=/root/offline ./k8s-lab-install.sh base <ip...>
#   OFD icinde: vanilla/{rpms/, images/, cilium-1.20.5.tgz, metallb-native.yaml, containerd-2.0.14-linux-amd64.tar.gz}
#
# Senaryolar: 1 CP + 1 worker → base+init+join(1 ip)+test ; 1 CP + N worker → join'e N ip
# Her adim echo ile yazilir; basarisiz adim non-zero exit verir.

set -uo pipefail
MODE="${MODE:-online}"
OFD="${OFD:-/root/offline}"
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"
SCPN="scp -o BatchMode=yes"

# remote scripti VM'e kopyala + env ile calistir (setsid: ssh kopsa bile script devam)
rsh() { # rsh <ip> <script> <ENV=VAL...>
  local ip=$1 script=$2; shift 2
  $SCPN "$DIR/$script" "root@$ip:/root/$script" 2>/dev/null
  local envstr=""; for e in "$@"; do envstr+="$(printf '%q' "$e") "; done
  local log="/root/.rsh-$script.log"
  $SSH "root@$ip" "env $envstr setsid bash /root/$script </dev/null > $log 2>&1; rc=\$?; cat $log; exit \$rc"
}

# ============================= base =============================
do_base() {
  local fail=0
  for ip in "$@"; do
    echo "=================================================="
    echo "BASE: $ip"
    if rsh "$ip" remote-base.sh "KMODE=$MODE" "KOFD=$OFD" > /tmp/base-$ip.log 2>&1; then rc=0; else rc=$?; fi
    cat /tmp/base-$ip.log
    if [ $rc -eq 10 ]; then
      echo "  >> $ip: REBOOT GEREKIYOR (cgroup v2) — yeniden baslatip 'base'i tekrar calistir"
    elif [ $rc -ne 0 ]; then
      echo "  >> $ip: BASE BASARISIZ (rc=$rc)"
      fail=1
    fi
  done
  [ $fail -eq 0 ] || exit 1
  echo "BASE_HEPSI_TAMAM"
}

# ============================= init =============================
do_init() {
  local cp=$1
  echo "=================================================="
  echo "INIT (controller): $cp"
  rsh "$cp" remote-init.sh "KMODE=$MODE" "KOFD=$OFD" "CP_IP=$cp"
  [ $? -eq 0 ] || exit 1
}

# ============================= join =============================
do_join() {
  local cp=$1; shift
  echo "=================================================="
  echo "JOIN: $* (cp=$cp)"
  local jcmd
  jcmd=$($SSH "root@$cp" 'kubeadm token create --print-join-command | grep kubeadm | head -1')
  echo "  join cmd: $jcmd"
  for ip in "$@"; do
    echo "--- $ip"
    rsh "$ip" remote-join.sh "KMODE=$MODE" "KOFD=$OFD" "JOINCMD=$jcmd"
    [ $? -eq 0 ] || { echo "  >> $ip: JOIN BASARISIZ"; exit 1; }
  done
  echo "  nodes:"
  $SSH "root@$cp" 'kubectl get nodes'
  echo "JOIN_HEPSI_TAMAM"
}

# ============================= test =============================
do_test() {
  local cp=$1
  echo "=================================================="
  echo "TEST (nginx + MetalLB + scale 3->1->3): $cp"
  rsh "$cp" remote-test.sh "KMODE=$MODE" "KOFD=$OFD"
  [ $? -eq 0 ] || { echo ">> TEST BASARISIZ"; exit 1; }
}

# ============================= teardown =============================
do_teardown() {
  for ip in "$@"; do
    echo "TEARDOWN: $ip"
    $SSH "root@$ip" '
kubectl delete ns nginx-lab metallb-system --wait=false 2>/dev/null || true
kubeadm reset -f >/dev/null 2>&1 || true
dnf -y remove kubelet kubeadm kubectl >/dev/null 2>&1 || true
rm -rf /var/lib/etcd /var/lib/kubelet /etc/kubernetes /root/.kube
systemctl stop kubelet 2>/dev/null || true
echo TEARDOWN_DONE' || echo "  >> $ip: sorunlu (devam)"
  done
  echo "TEARDOWN_HEPSI_TAMAM"
}

case "${1:-help}" in
  base)     shift; [ $# -ge 1 ] || { echo "base: en az 1 ip"; exit 2; }; do_base "$@" ;;
  init)     shift; [ $# -ge 1 ] || { echo "init: cp ip gerekli"; exit 2; }; do_init "$@" ;;
  join)     shift; [ $# -ge 2 ] || { echo "join: <cp_ip> <worker_ip...>"; exit 2; }; do_join "$@" ;;
  test)     shift; [ $# -ge 1 ] || { echo "test: cp ip gerekli"; exit 2; }; do_test "$@" ;;
  teardown) shift; do_teardown "$@" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
