# k8s-lab-vanilla — 1 CP + 3 Worker Vanilla Kubernetes Test Ortamı

Oracle Linux 8.10 VM'leri üzerinde, **kubeadm** ile kurulan; 1 control plane + 3 worker
düzeninde, Calico CNI + MetalLB LoadBalancer + Rancher (GUI) içeren, tam geri alınabilir
bir test ortamı.

Amaç: EKS'e benzer (aynı upstream sürüm) bir Kubernetes katmanında config, deployment
ve scale senaryolarını bulut maliyeti olmadan test edebilmek.

## Mimari

| VM | Ad | IP | Rol | Donanım |
|---|---|---|---|---|
| 1 | controller | 192.168.10.73 | Control Plane | 4 vCPU / 8 GiB / 40 GiB |
| 2 | worker1 | 192.168.10.74 | Worker | 4 vCPU / 8 GiB / 40 GiB |
| 3 | worker2 | 192.168.10.75 | Worker | 4 vCPU / 8 GiB / 40 GiB |
| 4 | worker3 | 192.168.10.76 | Worker | 4 vCPU / 8 GiB / 40 GiB |

VM'ler KVM/libvirt (msi noteri) üzerinde UEFI/q35 ile çalışır; ağ 192.168.10.0/24
(libvirt `default` network), statik DHCP lease'ler üzerinden sabitlenir.

## Sürümler (kurulum tarihi itibarıyla stabil)

| Bileşen | Sürüm |
|---|---|
| Kubernetes (kubeadm/kubelet/kubectl) | v1.37.2 |
| Calico CNI | v3.33.1 |
| MetalLB | v0.16.2 |
| Rancher (GUI) | en yeni stable (cattle-system) |
| OS | Oracle Linux 8.10 (SELinux disabled, firewalld off) |

## Dokümantasyon

| # | Belge | İçerik |
|---|---|---|
| 0 | [docs/00-planimiz.md](docs/00-planimiz.md) | Plan, varsayımlar, kaynak hesabı |
| 1 | [docs/01-vm-hazirligi.md](docs/01-vm-hazirligi.md) | VM'lerin libvirt üzerindeki durumu |
| 2 | [docs/02-altyapi-kurulumu.md](docs/02-altyapi-kurulumu.md) | containerd + kubeadm paketleri, sysctl |
| 3 | [docs/03-cluster-kurulumu.md](docs/03-cluster-kurulumu.md) | kubeadm init / join |
| 4 | [docs/04-cni-metallb.md](docs/04-cni-metallb.md) | Calico + MetalLB pool |
| 5 | [docs/05-test-senaryosu.md](docs/05-test-senaryosu.md) | nginx deploy, scale 3→1, trafik doğrulama |
| 6 | [docs/06-rancher-gui.md](docs/06-rancher-gui.md) | Rancher kurulumu ve kullanımı |
| 7 | [docs/07-geri-alma.md](docs/07-geri-alma.md) | **Rollback:** cluster'ı sıfırlama, VM'leri tekrar kullanılabilir hâle getirme |

## Hızlı Başlangıç (kısaltılmış)

```bash
# 1) Tüm 4 VM'de altyapı (docs/02):
for ip in 73 74 75 76; do
  ssh root@192.168.10.$ip 'cat > /root/k8s-base.sh' < scripts/k8s-base.sh
  ssh root@192.168.10.$ip 'bash /root/k8s-base.sh'   # 1. çalıştırmada cgroup v2 için reboot yapar
done
# 2) Control plane + Calico (docs/03, 04):
ssh root@192.168.10.73 'cat > /root/cluster-init.sh' < scripts/cluster-init.sh
ssh root@192.168.10.73 'bash /root/cluster-init.sh'
# 3) Worker'ları kat (docs/03):
for ip in 74 75 76; do
  ssh root@192.168.10.$ip 'cat > /root/cluster-join.sh' < scripts/cluster-join.sh
  ssh root@192.168.10.$ip 'bash /root/cluster-join.sh'
done
# 4) MetalLB + test işyükü (docs/04, 05):
ssh root@192.168.10.73 'kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.2/config/manifests/metallb-native.yaml'
ssh root@192.168.10.73 'cat > /root/metallb.yaml' < scripts/metallb.yaml
ssh root@192.168.10.73 'kubectl apply -f /root/metallb.yaml'
ssh root@192.168.10.73 'cat > /root/nginx-deploy.yaml' < scripts/nginx-deploy.yaml
ssh root@192.168.10.73 'kubectl apply -f /root/nginx-deploy.yaml'
# 5) Scale testi (docs/05) ve GUI (docs/06):
bash scripts/test-nginx.sh
bash scripts/rancher-install.sh
```

## Test Senaryosu (her kurulumdan sonra zorunlu)

nginx Deployment 3 replika ile ayağa kaldırılır; LoadBalancer servisi üzerinden
isteklerin **tüm pod'lara dağıldığı** gözlenir. Ardından 1 replikaya scale down
edilir, trafik yine kesintisiz akar. Detay: [docs/05-test-senaryosu.md](docs/05-test-senaryosu.md).

## Sıfırlama / Yineleme

Aynı 4 VM üzerinde bu ortamı tekrar sıfırdan kurmak için tek komut:
`bash scripts/teardown.sh` (docs/07). VM'lerin diski silinmez; yalnızca
k8s bileşenleri kaldırılır.
