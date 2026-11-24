# 00 — Plan Tanımı ve Varsayımlar

## Amaç

Bulut (EKS) maliyeti ödemeden, "EKS'tekiyle aynı upstream Kubernetes sürümünde"
çalışan bir test ortamı kurmak; config, deployment ve scale-up/down senaryolarını
yerelde doğrulayabilmek.

## Neden kubeadm (vanilla)?

- Kubeadm, CNCF tarafından korunur ve **upstream Kubernetes'in birebir**
  kurulum aracıdır; k3s veya başka bir dağıtımdan farklı API davranışı yoktur.
- Sürüm seçimi serbesttir: EKS'in o anki stabil sürümüyle (v1.37.x) birebir
  eşitlenebilir → "AWS katmanı" uyumu sağlanır.
- (Opsiyonel) `kubeadm init --image-repository` ile **EKS Distro** imajları
  (AWS'un EKS'te kullandığı binary'ler) kullanılabilir; bkz.
  [03-cluster-kurulumu.md §AWS Uyumu](03-cluster-kurulumu.md).

## Topoloji Kararları

| Karar | Gerekçe |
|---|---|
| 1 CP + 3 worker | 3 worker VM hazır; CP ayrı 4. VM'de → worker kaynakları boşuna CP'ye gitmesin |
| HA yapılmadı | Test ortamı; tek CP kabul edilebilir SPOF. Gerekirse 2-3 küçük CP VM'i ile HA'ya geçilir (kubeadm upgrade/init join --control-plane) |
| Calico (overlay) | AWS VPC CNI ENI gerektirir, yerelde çalışmaz; Calico tüm düğümlerde aynı davranır |
| MetalLB | EKS'teki LoadBalancer servislerinin yerel karşılığı; 192.168.10.80-84 pool |
| Rancher (GUI) | Ücretsiz (Apache-2.0), sektörde standart; aynı GUI k3s ve EKS-A kümeleriyle de kullanılır |
| local-path PV (varsa) | EBS CSI'nin yerel karşılığı (test senaryosu PV gerektirmez, opsiyonel) |

## Kaynak Hesabı

- CP düğümünde (4 vCPU/8 GiB): k8s sistem pod'ları + Rancher ≈ 3-4 GiB → 8 GiB yeter.
- Worker'lar (4×8 GiB): nginx testinde 2 GiB bile kullanılmaz; %100 workload kapasitesi.

## Varsayımlar / Gereksinimler

1. 4 VM: controller(.73) + worker1-3(.74-.76), Oracle Linux 8.10, aynı /24 ağda.
2. SELinux disabled, firewalld disabled (şablon VM'de öyle).
3. VM'lerin internet çıkışı var (paket/manifest indirme).
4. Erişim: `ssh root@192.168.10.7x` (orion üzerinden, SSH anahtarı).
5. MetalLB pool (192.168.10.80-84) DHCP aralığı (.100-.199) dışındadır; çakışma yoktur.

## Kapsam Dışı

- IRSA, VPC CNI, EBS CSI, ALB Controller gibi **AWS API'sine bağımlı** bileşenler
  (yerelde karşılığı yerine geçer; detay: repo README ve 04 belgesi).
- Cluster upgrade otomasyonu (kubeadm upgrade ile elle yapılabilir).
