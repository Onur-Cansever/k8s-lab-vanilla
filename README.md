# k8s-lab-vanilla — 1 CP + N Worker Vanilla Kubernetes Lab

Oracle Linux 8.10 VM'leri üzerinde **kubeadm** ile kurulan; 1 control plane +
1..N worker, Cilium CNI (kube-proxy replacement), MetalLB (LoadBalancer), nginx LB/scale testi ve
(ayrılabilir) Rancher GUI içeren, **tam geri alınabilir** test ortamı.

> **Durum (24.11.2026): KURULDU + TEST EDİLDİ (online VE offline).**
> Online: 1CP+3W, nginx LB dağılım kanıtlı (docs/03).
> Offline: imaj store'u sıfırlanmış VM'ler **yalnızca yerel cache'ten**
> kurulu + aynı test `TEST_PASS` (docs/03, offline bölümü).

## Tek giriş noktası

```bash
cd scripts
MODE=online  ./k8s-lab-install.sh base  192.168.10.73 192.168.10.74 ...   # her VM
MODE=online  ./k8s-lab-install.sh init  192.168.10.73                     # controller
MODE=online  ./k8s-lab-install.sh join  192.168.10.73 192.168.10.74 ...    # 1..N worker
MODE=online  ./k8s-lab-install.sh test  192.168.10.73                     # nginx+LB+scale+checklist
MODE=online  ./k8s-lab-install.sh teardown <ip...>                        # geri alma
```

**Offline** (hedef ortamda internet yoksa) — `OFD` dizini her VM'de aynı yolda:
```bash
MODE=offline OFD=/root/offline ./k8s-lab-install.sh base <ip...>
# OFD icerigi + uretim: ../offline/README.md
```
Her sub-komut adım adım echo yazar; başarısız adım non-zero exit verir.
`1 CP + 1 worker` için `join`'a tek ip verilir; `1 CP + N worker` için N ip.

## Mimari (bu lab)

| VM | IP | Rol |
|---|---|---|
| controller | 192.168.10.73 | Control Plane |
| worker1-3 | 192.168.10.74-76 | Worker |

4 vCPU / 8 GiB / 40 GiB, libvirt `default` ağı (192.168.10.0/24),
MetalLB havuzu 192.168.10.80-84 (L2).

## Sürümler (test edilmiş)

| Bileşen | Sürüm |
|---|---|
| Kubernetes | v1.37.2 |
| containerd | 2.0.14 (CRI v1; OL8 deposunda yok → tarball) |
| Cilium | v1.20.5 (kube-proxy replacement) |
| MetalLB | v0.16.2 |
| nginx (test) | 1.25 |

## Dokümantasyon

| # | Belge | İçerik |
|---|---|---|
| 00 | [docs/00-planimiz.md](docs/00-planimiz.md) | Plan, varsayımlar |
| 01 | [docs/01-gereksinimler.md](docs/01-gereksinimler.md) | Donanım/OS/swap/cgroup/internet |
| 02 | [docs/02-adim-adim-kurulum.md](docs/02-adim-adim-kurulum.md) | Script çıktılarının elle karşılığı |
| 03 | [docs/03-test-senaryosu.md](docs/03-test-senaryosu.md) | nginx+LB+scale; **ölçülmüş online+offline sonuçlar** |
| 04 | [docs/04-checklist.md](docs/04-checklist.md) | Paket/node/LB/trafik kontrol case'leri |
| 05 | [docs/05-rancher-gui.md](docs/05-rancher-gui.md) | Rancher GUI (metakümese) |
| 06 | [docs/06-geri-alma.md](docs/06-geri-alma.md) | Teardown, tek VM çıkarma, sıfırlama |

## Dersler (kurulumda yaşandı, script'e işlendi)
- swap → fstab'da KALICI yorumlanmazsa reboot'ta geri açılır, kubelet crash-loop
- containerd 1.7 → CRI v1 yok; 2.0.14 tarball + `/usr/local/bin` + unit override
- `containerd config default` v3 yazar → `version = 2` yapılmalı
- join token: `kubeadm token create --print-join-command` (manuel hash çalışmaz)
- MetalLB: controller `available` olmadan pool apply'si webhook'ta düşer → bekle+retry
- tek node CP'de MetalLB/Rancher pod'ları control-plane taint'e takılır → toleration
