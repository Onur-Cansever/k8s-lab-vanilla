# 02 — Altyapı Kurulumu (Tüm 4 VM)

Script: [`scripts/k8s-base.sh`](../scripts/k8s-base.sh) — idempotent, her VM'de
aynı komutla çalıştırılır.

```bash
# orion'dan, 4 VM'e paralel:
for ip in 73 74 75 76; do
  ssh root@192.168.10.$ip 'cat > /root/k8s-base.sh' < scripts/k8s-base.sh &
done; wait
for ip in 73 74 75 76; do
  ssh root@192.168.10.$ip 'bash /root/k8s-base.sh' &
done; wait
```

## Script'in yaptığı işler (adım adım)

1. `kmod`, `sysctlutils` kurulur (dnf).
2. **containerd**: OL8 base deposunda `containerd` paketi yoktur; resmî
   Docker CE deposundan `containerd.io` kurulur (k8s dokümantasyonu RHEL8/OL8
   için önerdiği kaynaktır; `pkgs.k8s.io` tarafı da containerd varsayar).
3. Kubernetes resmi deposu eklenir:
   `https://pkgs.k8s.io/core:/stable:/v1.37/rpm/` → `kubeadm kubelet kubectl`.
4. `kubelet` servisi enable edilir (başlatma kubeadm'e bırakılır).
5. Kernel modülleri: `br_netfilter`, `overlay`.
6. `/etc/sysctl.d/99-k8s.conf`:
   - `net.ipv4.ip_forward=1`
   - `net.bridge.bridge-nf-call-iptables=1` (+ ip6tables)
   - `fs.inotify.max_user_instances=8192`
   - `kernel.non_detached_threads=1`
7. `sysctl --system`, `containerd` başlatılır ve enable edilir.
8. **cgroup v2**: k8s v1.35+ cgroup v1 desteklemiyor; OL8 varsayılanı v1.
   Script tek seferlik kernel argümanı ekler (`systemd.unified_cgroup_hierarchy=1`)
   ve VM'i yeniden başlatır; ikinci çalıştırmada `cgroup2fs` doğrulanır.

> **Ön koşul kontrolü:** SELinux `disabled` ve `firewalld` kapalı olmalı
> (şablon VM'de öyle). `dnf list containerd kubelet` ile paketlerin
> kurulduğunu doğrulayın.

## Doğrulama

```bash
ssh root@192.168.10.73 'kubeadm version -o short; containerd --version'
# Beklenen: v1.37.2
```

## Geri Alma (bu adımı)

```bash
dnf -y remove kubelet kubeadm kubectl containerd
rm -f /etc/yum.repos.d/kubernetes.repo /etc/sysctl.d/99-k8s.conf
sysctl --system >/dev/null
```

## Onkosuller (bu ortamda tek tek dogrulandi)

| Onkosul | Neden | Duzeltme |
|---|---|---|
| **Swap KALICI kapali** | k8s 1.35+ kubelet'i swap acikken crash-loop yapar (10 sn'de bir yeniden baslatir, tum pod'lar SIGTERM yer) | `sed -i '/\bswap\b/ s|^\(\S*\s*\S*\s*\)swap|\1#K8S-DISABLED swap|' /etc/fstab && swapoff -a` — reboot sonrasi da kalici |
| **cgroup v2** | k8s 1.35+ zorunlu | `grubby --update-kernel=ALL --args=systemd.unified_cgroup_hierarchy=1` + reboot (OL8 ucuken grub'ta BLS `options` satiri gecersizdir — grubby yeterli) |
| **containerd 2.x** | k8s 1.37 preflight CRI v1 RuntimeService arar; 1.7 ve altinda varsayilan config'de yok | `containerd 2.0.14` tarball + `containerd config default` (v3 config) |
| **CRI etkin** | Docker CE'nin eski config'i CRI'yi kapali birakir | 2.x varsayilan config CRI'yi otomatik acar |

> **Ders (bu laboratuvarda yasandi):** swap bir kez `swapoff -a` ile kapatip fstab'e dokunmamis olmak, sonraki her reboot'ta kubelet'i kill-loop'a soktu ve gunler boyunca "pod dalgalanmasi" olarak kovalandik. Onkosul kontrolu her reboot sonrasinda TEKRAR yapilmalidir: `swapon --show` bos, `free` satirinda swap 0.

## Trafik Kaniti (test-nginx.sh)

nginx deployment 3 replica + LoadBalancer (MetalLB 192.168.10.80-84). Her pod yanitina `X-Pod-Name` header'i ekler (add_header, ek modul gerekmez). Test:

```
$ for i in $(seq 1 12); do curl -sI http://192.168.10.80/ | grep -i x-pod-name; done | sort | uniq -c
      4 nginx-58c8ff48fd-52k4n
      3 nginx-58c8ff48fd-tx4ds
      5 nginx-58c8ff48fd-z54sc
```

Istekler LB uzerinden 3 worker'daki 3 pod'a dagilir. Scale 3→1→3'de her durumda 200 yanitlar.
