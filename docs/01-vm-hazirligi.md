# 01 — VM Hazırlığı (libvirt / msi)

Bu ortamın 4 VM'i, msi noteri üzerindeki libvirt'te `default` (192.168.10.0/24)
ağında çalışır. VM'ler bu repo'da **yeniden kurulmaz**; hazır durumda kabul edilir.
Yeniden kurulum gerekiyorsa bu bölüm talimat içerir.

## Mevcut Durum (24.11.2026 itibarıyla)

| VM | IP | MAC | Konum (disk) |
|---|---|---|---|
| controller | 192.168.10.73 | 52:54:00:aa:bb:49 | /home/onur/vms/controller/ |
| worker1 | 192.168.10.74 | 52:54:00:aa:bb:4a | /home/onur/vms/worker1/ |
| worker2 | 192.168.10.75 | 52:54:00:aa:bb:4b | /home/onur/vms/worker2/ |
| worker3 | 192.168.10.76 | 52:54:00:aa:bb:4c | /home/onur/vms/worker3/ |

- Şablon: `/home/onur/vms/templates/OL8U10_x86_64-kvm-b287_original.qcow2`
- Makine tipi: q35 + UEFI (OVMF_CODE_4M.fd), virtio disk/ağ
- Root erişimi: orion SSH anahtarı + parola `1` (yalnızca bu test ağı)
- Zaman dilimi: Europe/Istanbul

## Yeni VM Açma (gerekiyorsa)

msi üzerinde çalışan script: `/home/onur/vms/provision-controller.sh`
(controller için), worker'lar için `provision-workers.sh`. Örneği README'deki
mimariyle birebir aynı XML/lease üretir:

```bash
# msi üzerinde:
bash /home/onur/vms/provision-controller.sh
# Yapılanlar: qcow2 klonla + 40G resize, /etc/hosts+hostname, root ssh-key+parola,
# firewalld off, SELinux disabled, extend-root.service (bir seferlik LV genişletme),
# domain define + start, statik DHCP lease (.73).
```

> **Not:** Lease eklemede `virsh net-update` host bölümünü desteklemediği için
> network XML'si düzenlenip `net-define` + `net-destroy/start` uygulanır;
> çalışandaki VM'lerin ağı ~30 sn kopar ve aynı statik IP'leri geri alır.

## Bilinen Dikkat Noktası: NetworkManager ↔ virbr0

msi'de NetworkManager, libvirt ağının yeniden başlatılmasından sonra
`virbr0` üzerindeki vnet portlarını düşürebilir (symptom: tüm VM'ler
"No route to host", `ip link`'te vnet'ler UP ama bridge'de port yok).
Çözüm (sudo gerektirmez):

```bash
virsh destroy worker1 worker2 worker3 controller
virsh start   worker1 worker2 worker3 controller
```

Kalıcı çözüm için (sudo ile) virbr0'yu NM'den izole edin:
`/etc/NetworkManager/conf.d/99-libvirt-nm.conf` → `unmanaged-devices=interface-name:virbr0`.
