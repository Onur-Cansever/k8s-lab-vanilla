#!/bin/bash
# remote-base.sh — HER VM'de calisir (driver scp'ler, KMODE/KOFD env ile calistirir)
# KMODE=online|offline  KOFD=offline paket dizini (offline modda)
set -e
echo "[0/6] k3s kalintisi varsa kaldir"
if command -v k3s-uninstall.sh >/dev/null; then k3s-uninstall.sh >/dev/null 2>&1 || true; fi
rm -rf /var/lib/rancher/k3s /etc/rancher 2>/dev/null || true

echo "[1/6] swap kalici kapali"
sed -i -E "s|^([[:alnum:]_/.-]+[[:space:]]+[[:alnum:]_-]+[[:space:]]+)swap\b|\1#K8S-OFF swap|" /etc/fstab
swapoff -a 2>/dev/null || true
[ -z "$(swapon --show=NAME)" ] || { echo "  HATA: swap hala aktif"; exit 1; }
echo "  swap=0"

echo "[2/6] cgroup v2"
if [ "$(stat -fc %T /sys/fs/cgroup)" != "cgroup2fs" ]; then
  grubby --update-kernel=ALL --args=systemd.unified_cgroup_hierarchy=1
  echo "REBOOT_GEREKLI"
  exit 10
fi
echo "  cgroup2fs aktif"

echo "[3/6] containerd 2.0.14"
if [ "$KMODE" = "offline" ]; then
  echo "  offline: $KOFD/vanilla/containerd tarball"
  tar -xzf "$KOFD"/vanilla/containerd-2.0.14*.tar.gz -C /tmp/
else
  [ -s /tmp/ctd.tar.gz ] || curl -fsSL -o /tmp/ctd.tar.gz \
    https://github.com/containerd/containerd/releases/download/v2.0.14/containerd-2.0.14-linux-amd64.tar.gz
  tar -xzf /tmp/ctd.tar.gz -C /tmp/
fi
install -m755 /tmp/bin/containerd /usr/local/bin/containerd
mkdir -p /etc/containerd
grep -q "^version = 3" /etc/containerd/config.toml 2>/dev/null || /usr/local/bin/containerd config default > /etc/containerd/config.toml
mkdir -p /etc/systemd/system/containerd.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/local/bin/containerd\n' > /etc/systemd/system/containerd.service.d/override.conf
systemctl daemon-reload
systemctl restart containerd
sleep 3
systemctl is-active containerd | grep -q active || { echo "  HATA: containerd calismiyor"; exit 1; }
echo "  $(/usr/local/bin/containerd --version | awk '{print $3}')"

echo "[4/6] k8s paketleri (v1.37.2)"
if [ "$KMODE" = "offline" ]; then
  echo "  offline: $KOFD/vanilla/rpms/"
  dnf -y install "$KOFD"/vanilla/rpms/*.rpm
else
  if [ ! -f /etc/yum.repos.d/kubernetes.repo ]; then
    cat > /etc/yum.repos.d/kubernetes.repo <<'REPO'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/repodata/repomd.xml.key
REPO
  fi
  dnf -y install kubelet kubeadm kubectl
fi
kubeadm version -o short | grep -q "v1.37" || { echo "  HATA: kubeadm 1.37 degil"; exit 1; }
echo "  $(kubeadm version -o short)"

echo "[5/6] sysctl + moduller"
modprobe br_netfilter; modprobe overlay
cat > /etc/sysctl.d/99-k8s.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
SYSCTL
sysctl --system >/dev/null
printf 'br_netfilter\noverlay\n' > /etc/modprobe.d/k8s.conf

echo "[6/6] kontrol"
echo "  swap=$(swapon --show=NAME | wc -l) cgroup=$(stat -fc %T /sys/fs/cgroup) containerd=$(systemctl is-active containerd) kubelet=$(rpm -q kubelet | head -1)"
echo "BASE_DONE $(hostname)"
