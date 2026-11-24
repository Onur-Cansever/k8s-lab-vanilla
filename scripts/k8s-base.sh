#!/bin/bash
# k8s-base.sh — Vanilla K8s altyapı hazırlığı (Oracle Linux 8.10) — idempotent
# NOT: k8s v1.35+ cgroup v1'i desteklemiyor → ilk çalıştırmada VM'ler cgroup v2'ye geçer (biri reboot).
# NOT: containerd, GitHub release tarball'ından kurulur (1.7.36):
#      OL8 base repo'sunda containerd paketi YOK; packages.containerd.io bazı ağlarda
#      DNS çözülemiyor; Docker CE'nin containerd.io RPM'i 1.6.32 ile kalır (eski).
set -uxo pipefail
dnf -y install kmod sysctlutils 2>/dev/null || dnf -y install kmod
cd /tmp
[ -f ctd-1.7.36.tar.gz ] || curl -fsSL -m 600 -o ctd-1.7.36.tar.gz \
  https://github.com/containerd/containerd/releases/download/v1.7.36/containerd-1.7.36-linux-amd64.tar.gz
tar -xzf ctd-1.7.36.tar.gz -C /tmp/
install -m755 /tmp/bin/containerd        /usr/local/bin/containerd
install -m755 /tmp/bin/runc               /usr/local/bin/runc
install -m755 /tmp/bin/containerd-shim-runc-v2 /usr/local/bin/containerd-shim-runc-v2
install -m755 /tmp/bin/ctr                /usr/local/bin/ctr 2>/dev/null || true
# Docker CE'nin containerd.io RPM'i kuruluysa, systemd unit'i /usr/local/bin'e çevir
# (unit /usr/bin/containerd'ı ABSOLUT path ile çalıştırır — PATH yetmez!)
if dnf list installed containerd.io >/dev/null 2>&1; then
  mkdir -p /etc/systemd/system/containerd.service.d
  printf '[Service]\nExecStart=\nExecStart=/usr/local/bin/containerd\n' \
    > /etc/systemd/system/containerd.service.d/override.conf
  systemctl daemon-reload
fi
mkdir -p /etc/containerd
[ -f /etc/containerd/config.toml ] || containerd config default > /etc/containerd/config.toml
# Docker CE config'i CRI'yi KAPALI bırakabilir → aç
sed -i '/^disabled_plugins = \["cri"\]/d' /etc/containerd/config.toml
if ! grep -q 'io.containerd.grpc.v1.cri' /etc/containerd/config.toml; then
cat >> /etc/containerd/config.toml <<'CRI'

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.10"
CRI
fi
systemctl enable --now containerd
# 2) Kubernetes resmî deposu
cat > /etc/yum.repos.d/kubernetes.repo <<'REPO'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/repodata/repomd.xml.key
REPO
dnf -y install kubelet kubeadm kubectl
systemctl enable kubelet
# 3) kernel modülleri + sysctl
modprobe br_netfilter
modprobe overlay
cat > /etc/sysctl.d/99-k8s.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
fs.inotify.max_user_instances=8192
kernel.non_detached_threads=1
SYSCTL
sysctl --system >/dev/null
systemctl enable --now containerd
# 4) cgroup v2 (k8s v1.35+ zorunlu): OL8 varsayılanı v1 → kernel arg + tek seferlik reboot
if [ "$(stat -fc %T /sys/fs/cgroup/)" != "cgroup2fs" ]; then
  grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
  touch /root/.k8s-reboot-needed
  systemctl reboot
  exit 0   # reboot sonrası bu script yeniden koşulur (idempotent)
fi
if [ -f /root/.k8s-reboot-needed ]; then rm -f /root/.k8s-reboot-needed; fi
echo "K8S_BASE_DONE $(kubeadm version -o short) containerd=$(containerd --version | awk '{print $3}') cgroup2=yes"
