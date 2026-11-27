# 02 — Adım Adım Kurulum

İki kullanım yolu var:
- **Scriptle (önerilen):** driver makineden tek komutla — çıktı aşağıdaki
  adim adim ile birebir aynidir (her adim echo ile yazilir).
- **Elle:** her adimi VM'e ssh ile kendiniz girerek — script'in ne yaptigi
  satir satir asagidadir.

## Roll senaryolari
| Senaryo | Komutlar |
|---|---|
| **1 CP + 1 worker** | `base <cp> <w1>` → `init <cp>` → `join <cp> <w1>` → `test <cp>` |
| **1 CP + N worker** | aynisi; `join`'a N worker ip'si verilir |

```bash
# driver makine (orion): VM'lere root ssh yetkisi gerekli
cd scripts/

# 1) Alt yapi (her VM)
MODE=online  ./k8s-lab-install.sh base 192.168.10.73 192.168.10.74
# offline:
MODE=offline OFD=/root/offline ./k8s-lab-install.sh base 192.168.10.73 192.168.10.74

# 2) Controller
MODE=online ./k8s-lab-install.sh init 192.168.10.73

# 3) Worker'lar (1..N)
MODE=online ./k8s-lab-install.sh join 192.168.10.73 192.168.10.74 192.168.10.75

# 4) Test (nginx + LB + scale kaniti)
MODE=online ./k8s-lab-install.sh test 192.168.10.73
```

Offline modda `OFD` dizini **her VM'de** aynı yolda olmalı (varsayılan
`/root/offline`); içeriği ve üretimi: `../offline/README.md`.

---

## ADIM 1 — base (her VM)

Script çıktısı:
```
BASE: 192.168.10.74
[0/6] k3s kalintisi varsa kaldir
[1/6] swap kalici kapali
[2/6] cgroup v2
[3/6] containerd 2.0.14
[4/6] k8s paketleri (v1.37.2)
[5/6] sysctl + moduller
[6/6] kontrol
  swap=0 cgroup=cgroup2fs containerd=active kubelet=kubelet-1.37.2...
BASE_DONE worker1
```

Elle karşılıkları (her VM):
```bash
# 1) swap kalıcı kapat (doküman 01)
# 2) cgroup v2 (doküman 01; gerekirse reboot)
# 3) containerd (online):
curl -fsSL -o /tmp/ctd.tar.gz https://github.com/containerd/containerd/releases/download/v2.0.14/containerd-2.0.14-linux-amd64.tar.gz
tar -xzf /tmp/ctd.tar.gz -C /tmp/
install -m755 /tmp/bin/containerd /usr/local/bin/containerd
/usr/local/bin/containerd config default > /etc/containerd/config.toml
# config version 3 olan config'te: sed -i 's/^version = 3/version = 2/'
# OL8'ta containerd.service'in ExecStart'ı /usr/bin/containerd'e bakar:
mkdir -p /etc/systemd/system/containerd.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/local/bin/containerd\n' > /etc/systemd/system/containerd.service.d/override.conf
systemctl daemon-reload && systemctl restart containerd
# 4) k8s paketleri (online):
cat > /etc/yum.repos.d/kubernetes.repo <<'REPO'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/repodata/repomd.xml.key
REPO
dnf -y install kubelet kubeadm kubectl
# (offline: dnf -y install /root/offline/vanilla/rpms/*.rpm)
# 5) sysctl + modüller:
modprobe br_netfilter; modprobe overlay
cat > /etc/sysctl.d/99-k8s.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
SYSCTL
sysctl --system
printf 'br_netfilter\noverlay\n' > /etc/modprobe.d/k8s.conf
```

Başarılı bitiş: `BASE_DONE <hostname>`; `swapon --show` boş,
`kubeadm version -o short` → `v1.37.2`.

## ADIM 2 — init (controller VM)
```
[1/5] eski state temizle
[2/5] imajlari hazirla            (offline: OFD/vanilla/images/*.tar import)
[3/5] kubeadm init (pod-cidr 192.168.0.0/16, san: <cp_ip>)
[4/5] Cilium CNI (kube-proxy replacement)
[5/5] MetalLB (controller ayakta beklenir, sonra pool)
  pool OK (deneme=1)
NAME    STATUS   ROLES           VERSION
controller Ready  control-plane   v1.37.2
INIT_DONE <cp_ip>
```
Elle:
```bash
kubeadm init --apiserver-cert-extra-sans=<cp_ip> --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock --skip-phases=addon/kube-proxy
mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
helm install cilium cilium/cilium --version 1.20.5 -n kube-system \
  --set kubeProxyReplacement=true --set k8sServiceHost=<cp_ip> --set k8sServicePort=6443 \
  --set cluster.ipam.cidr=192.168.0.0/16
# offline: helm install cilium <OFD>/vanilla/cilium-1.20.5.tgz (ayni --set'ler)
# Tek node clusterde: --set operator.replicas=1 ekle (chart default 2; host-port capismasi)
# KPR dogrulamasi:
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep KubeProxyReplacement
iptables-save | grep KUBE-SVC   # bos
kubectl apply -f <metallb-native.yaml>    # offline: OFD/vanilla/metallb-native.yaml
# MetalLB controller'IN available olmasını BEKLE (ayrıksa webhook yarışır):
kubectl -n metallb-system rollout status deploy/controller
# tek node / worker yokken taint'e takılmasın:
kubectl -n metallb-system patch deploy controller -p \
  '{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}}}}'
# pool + L2 (webhook CA gecikebilir → 6x retry):
kubectl apply -f <metallb-pool.yaml>
```
> **DERS:** MetalLB manifesti apply olur olmaz pool apply'si "failed calling
> webhook ... context deadline exceeded" verir. Controller deployment'unun
> `availableReplicas=1` olmasını bekleyip (gerekirse toleration ekleyip)
> pool'u retry ile uygula.

## ADIM 3 — join (her worker)
```
JOIN: 192.168.10.74 ... (cp=192.168.10.73)
  join cmd: kubeadm join 192.168.10.73:6443 --token <gizli> --discovery-token-ca-cert-hash sha256:...
--- 192.168.10.74
[1/3] eski worker state temizle
[2/3] imajlari hazirla
[3/3] kubeadm join
JOIN_DONE worker1
  nodes:
NAME    STATUS   ROLES    VERSION
controller Ready   control-plane v1.37.2
worker1  Ready   <none>    v1.37.2
...
JOIN_HEPSI_TAMAM
```
Elle (worker'da):
```bash
# controller'dan token al (openssl ile hash hesaplamaya calisma — kubeadm
# hash'i kendisi uretir; manuel hash "none of the public keys are pinned" verir):
kubeadm token create --print-join-command
# worker'da:
kubeadm join 192.168.10.73:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

## ADIM 4 — test
Bkz. `03-test-senaryosu.md`. Script çıktısı `TEST_PASS` + CHECKLIST ile biter.

## Geri alma
Bkz. `06-geri-alma.md` (teardown komutu + tek komut).

## Sık görülen sorunlar
| Belirti | Neden | Çözüm |
|---|---|---|
| kubelet 10 sn'de bir crash, "swap on" | fstab swap'ı reboot'ta açıldı | 01 dokümanı: fstab satırını yorumla |
| `unknown service runtime.v1.RuntimeService` | containerd 1.7.x (CRI v1 yok) | containerd 2.0.14 tarball |
| `config version '3' is not supported` | `containerd config default` v3 yazar | `sed s/^version = 3/version = 2/` |
| join: `none of the public keys are pinned` | openssl ile manuel CA hash | `kubeadm token create --print-join-command` |
| MetalLB pool webhook hatası | controller/webhook henüz hazır değil | rollout status bekle + toleration + retry |
| LB IP hiç atanmıyor | speaker pod yok / pool yok | metallb-system pod'ları + pool var mı kontrol et |
