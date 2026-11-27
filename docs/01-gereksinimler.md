# 01 — Gereksinimler

Kurulumdan önce her VM için bu listenin tamamı sağlanmış olmalı. Script'ler
(`scripts/k8s-lab-install.sh base`) bu kontrollerin çoğunu otomatik yapar;
ancak **boot argümanı** ve **donanım** kalemlerini elle doğrulayın.

## Donanım / Sanallaştırma
| Kaleme | Minimum | Lab'ta kullanılan |
|---|---|---|
| VM sayısı | 2 (1 CP + 1W) | 4 (1 CP + 3W) |
| CPU | 2 vCPU / VM | 4 vCPU / VM |
| RAM | 4 GB / VM (2 GB CP) | 8 GB / VM |
| Disk | 20 GB / VM | 40 GB / VM |
| Ağı | Tüm VM'ler aynı L2 ağı (LB + join için) | 192.168.10.0/24 |
| LB IP havuzu | 5 boş IP (MetalLB L2) | 192.168.10.80-84 |

## İşletim Sistemi
- **Oracle Linux 8.10** (RHEL8-compatible) — dnf tabanlı
- x86_64
- SELinux: `enforcing` kalsa bile çalışır; lab'da `disabled`
- firewalld: kapalı (veya lab trafiğine açık)

## Boot / Çekirdek (elle doğrula)
```bash
# cgroup v2 aktif mi?  (k8s 1.34+ gerektirir)
stat -fc %T /sys/fs/cgroup        # beklenen: cgroup2fs
# Değilse:
grubby --update-kernel=ALL --args=systemd.unified_cgroup_hierarchy=1
# → VM'i YENİDEN BAŞLAT
```

## Swap (k8s için KALICI olarak kapalı olmalı)
```bash
# fstab'daki swap satırını kalıcı kapat:
sed -i -E "s|^([[:alnum:]_/.-]+[[:space:]]+[[:alnum:]_-]+[[:space:]]+)swap\b|\1#K8S-OFF swap|" /etc/fstab
swapoff -a
swapon --show | wc -l            # beklenen: 0
```
> **DERS (24.11.2026):** fstab'daki swap, her reboot'ta geri açılır; kubelet
> 10 sn'de bir "running with swap on" ile crash-loop'a girer. fstab satırını
> YORUMLAMADAN swapoff -a yaparsanız sorun reboot'ta geri gelir.

## İnternet gereksinimi
- **Online mod:** VM'ler `pkgs.k8s.io`, `github.com` (containerd),
  `quay.io`/`registry.k8s.io`/`docker.io` (imajlar) adreslerine erişebilmeli.
- **Offline mod:** Hiçbiri gerekmez; paketler `OFD` dizininden gelir
  (bkz. `offline/README.md`). Kurulum ortamında internet OLMAYABİLİR —
  script iki modu da destekler.

## Sürüm matrisi (test edilmiş)
| Bileşen | Sürüm |
|---|---|
| Kubernetes | v1.37.2 |
| containerd | 2.0.14 (CRI v1) |
| Cilium | v1.20.5 (kube-proxy replacement) |
| MetalLB | v0.16.2 |
| nginx (test iş yükü) | 1.25 |

> **Neden containerd 2.0.14?** k8s 1.37'nin kubeadm preflight'i CRI v1
> (`runtime.v1.RuntimeService`) ister; containerd 1.7.x bunu sunmaz.
> OL8 deposunda containerd paketi yoktur → GitHub tarball +
> `/usr/local/bin` + systemd override (script bunu yapar).
