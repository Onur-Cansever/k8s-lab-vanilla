# 04 — CNI (Calico) ve MetalLB

## 4.1 Calico

Calico, 03. belgedeki `kubectl apply` ile kuruldu (tigera operator + daemonset).

- Overlay mod: her düğümde veth pair + IPIP (varsayılan). Pod trafiği
  192.168.0.0/16 üzerinden akar, VM ağının kendisini kullanmaz.
- AWS'deki VPC CNI ENI tabanlıdır; yerel ortamda **ENI yoktur**, bu yüzden
  overlay seçilir. Pod servisleri (ClusterIP/LoadBalancer) davranışı aynıdır.

Doğrulama:

```bash
kubectl get pods -n calico-system
kubectl exec -it -n calico-system calico-node-xxxxx -- calicoctl node status
```

## 4.2 MetalLB (LoadBalancer)

MetalLB, resmî v0.16.2 manifest'inden kurulur (CRD'leri dahil); bu repodaki
`scripts/metallb.yaml` yalnızca **bu lab'a özel IP pool + L2 reklamı** içerir:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.2/config/manifests/metallb-native.yaml
kubectl apply -f scripts/metallb.yaml
kubectl -n metallb-system get pods
```

Pool tanımı (bu lab'a özel, `scripts/metallb.yaml`):

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
spec:
  addresses:
    - 192.168.10.80-192.168.10.84
---
kind: L2Advertisement
metadata:
  name: lab-l2
spec:
  ipAddressPools: [lab-pool]
```

- L2 mod (ARP tabanlı): bu /24 iç ağda yeterlidir; EKS'teki ELB'nin yerel karşılığı.
- Pool aralığı DHCP aralığı (.100-.199) ve statik lease'lerin (.25, .70-.76) dışındadır.
- LoadBalancer servisi oluşturulduğunda pool'dan 1 IP alınır (ör. 192.168.10.80);
  servis silinince iade edilir.

> **Not:** MetalLB, servis silinse bile IP'yi kısa süre tutabilir;
> test arasında `kubectl delete svc` + `kubectl get svc` beklemesi yeterlidir.
