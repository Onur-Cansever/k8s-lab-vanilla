# 07 — Geri Alma (Rollback) ve VM'leri Temiz Geri Verme

Aynı 4 VM üzerinde ortamı **birebir tekrar kurabilmek** için sıfırlama
işlemi tek script'tir: `scripts/teardown.sh`.

## Sıralama (önemli)

1. **Rancher** kaldırılır (svc → helm uninstall).
2. **MetalLB** namespace + CR'ları silinir.
3. **Test işyükü** silinir (`namespace nginx-lab`).
4. **Calico** silinir (manifest ters apply + operator CR'ları).
5. **kubelet stop + kubeadm reset --force** → 4 VM'nin her biri.
6. Containerd config temizliği (kubeadm'in yazdığı CRI bloğu).
7. Doğrulama: `kubeadm status` → "not initialized".

## Paketleri de silmek isterseniz (opsiyonel)

```bash
dnf -y remove kubelet kubeadm kubectl
# containerd kalabilir (tekrar kurulumda yeniden kullanılır)
```

## Doğrulama Listesi (teardown sonrası)

```bash
for ip in 73 74 75 76; do
  ssh root@192.168.10.$ip \
    'systemctl is-active kubelet; [ -f /etc/kubernetes/admin.conf ] && echo INITED || echo "not initialized"; ls /etc/kubernetes 2>/dev/null | wc -l'
done
# Beklenen: inactive | not initialized | 0
```

## VM'lerin Durumu

- Diski **silinmez**, hostname/SSH/lease'lar korunur → ertesi gün
  `README.md → Hızlı Başlangıç` ile aynı ortam tekrar ayağa kalkar.
- VM'leri tamamen silmek isterseniz (msi): `virsh destroy <ad> && virsh undefine <ad>`
  ve `/home/onur/vms/<ad>/` dizinini silin. (Bu repo için gerekmez.)

## Bilinen Tuzaklar

- `kubeadm reset` çalışmazsa: `systemctl stop kubelet; rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd`
  ardından tekrar `kubeadm reset --force`.
- Calico CRD'leri silinmeden `kubeadm reset` yapılırsa etcd içinde
  kalıntı kalmaz (reset etcd'yi de siler) ama operator pod'ları
  namespace silinmeden temizlenmelidir.
- MetalLB L2Advertisement pool IP'si: servis silinince IP iade olur;
  `kubectl -n metallb-system get pods -o wide` ile hangi node tutuyordu
  görülebilir.
