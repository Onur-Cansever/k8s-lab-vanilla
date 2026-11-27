# 04 — Kurulum Sonrası Checklist

Her kutuyu komutun ÇIKTISI ile işaretleyin; boş kalan kutu = sorun var.
Controller VM'de (kubeconfig ayarlı) çalıştırın.

## A. Paketler / sürümler
```bash
[ ] rpm -q kubelet kubeadm kubectl        # kubelet-1.37.2... x3
[ ] containerd --version                  # containerd v2.0.14
[ ] kubeadm version -o short              # v1.37.2
[ ] ctr -n k8s.io version | head -1       # ctr (2.x)
```

## B. Sistem önkoşulları
```bash
[ ] swapon --show | wc -l                 # 0
[ ] stat -fc %T /sys/fs/cgroup            # cgroup2fs
[ ] sysctl net.ipv4.ip_forward            # = 1
[ ] lsmod | grep -cE "br_netfilter|overlay"  # 2
[ ] systemctl is-active containerd kubelet  # active active
```

## C. Cluster sağlığı
```bash
[ ] kubectl get nodes                     # Tümü Ready (1 CP + N worker)
[ ] kubectl get nodes --no-headers | grep -c Ready   # = toplam node
[ ] kubectl get pods -A                   # kube-system: coredns/cilium OK
[ ] kubectl -n kube-system get ds cilium         # DESIRED=CURRENT=READY
[ ] kubectl -n kube-system get ds kube-proxy  # YOK (kube-proxy replacement)
[ ] iptables-save | grep KUBE-SVC            # bos (eBPF frontend'ler cilium-dbg service list'te)
[ ] kubectl -n metallb-system get deploy controller   # AVAILABLE=1
[ ] kubectl get ipaddresspool -n metallb-system      # lab-pool var
```

## D. Ağ / pod
```bash
[ ] kubectl -n nginx-lab get pods -o wide   # 3 nginx Running, farklı node'lar
[ ] kubectl -n nginx-lab get endpoints nginx-lb   # 3 endpoint IP
```

## E. Trafiğin çalıştığını KANITLA (en önemli kısım)
```bash
IP=$(kubectl -n nginx-lab get svc nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[ ] echo $IP                                # bir LB IP'si (192.168.10.80-84)

# Her isteğin hangi pod'a gittiğini gör (3 farklı pod beklenir):
[ ] for i in $(seq 1 12); do curl -sI http://$IP/ | grep -i x-pod-name; done | sort | uniq -c

# Scale 3 -> 1: trafik kesilmez (5x200 beklenir)
[ ] kubectl -n nginx-lab scale deploy nginx --replicas=1 && sleep 20 \
     && for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://$IP/; done; echo

# Scale 1 -> 3: yeniden dağılım
[ ] kubectl -n nginx-lab scale deploy nginx --replicas=3 && sleep 30 \
     && for i in $(seq 1 10); do curl -sI http://$IP/ | grep -i x-pod-name | awk '{print $2}'; done | sort | uniq -c
```

## F. Kontrol case'leri (arızayı yakalamak için)
| Test | Nasıl | Beklenti |
|---|---|---|
| Pod ölür mü? | `kubectl -n nginx-lab delete pod <nginx-pod>` | 10 sn içinde yeni pod Running; LB'de 200 devam |
| Worker kopar mı? | Bir worker'da `systemctl stop kubelet` | Node NotReady; o pod'un trafiği kalanlara akar (LB 200) |
| LB IP doğru mü? | `arp -n` (worker'da) veya `ip neigh` | LB IP'si bir node'un MAC'ine cevap veriyor (L2) |
| Swap geri geldi mi? | `swapon --show` | 0 (reboot sonrası da!) |

## Başarılı kurulum = A-E'nin tamamı yeşil
Script'in `test` sub-komutu A-E'yi otomatik koşar ve `TEST_PASS` +
CHECKLIST bloğu basar.
