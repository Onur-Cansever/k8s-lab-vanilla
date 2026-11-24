# 06 — Geri Alma

## Tek komut: tüm lab'ı sıfırla
```bash
MODE=online ./k8s-lab-install.sh teardown 192.168.10.73 192.168.10.74 192.168.10.75 192.168.10.76
```
Çıktı: her VM için `TEARDOWN_DONE`, sonda `TEARDOWN_HEPSI_TAMAM`.

Yapılanlar (her VM):
1. `kubectl delete ns nginx-lab metallb-system --wait=false` (test iş yükü + LB)
2. `kubeadm reset -f` (cluster üyeliği, sertifikalar, kubelet state)
3. `dnf -y remove kubelet kubeadm kubectl`
4. `rm -rf /var/lib/etcd /var/lib/kubelet /etc/kubernetes /root/.kube`
5. `systemctl stop kubelet`

> **containerd KALIR** (hedef: tekrar kurulumda hızlı başlamak; ~200 MB imaj
> deposu istenirse ayrıca temizle: `ctr -n k8s.io images ls -q | xargs -r ctr -n k8s.io images rm`).

## Tek VM'i cluster'dan çıkar (diğerleri çalışsın)
```bash
# controller'dan (k8s 1.31+):
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <worker>
# worker'da:
kubeadm reset -f
```

## Sadece test iş yükünü kaldır
```bash
kubectl delete ns nginx-lab
```

## MetalLB'i geri al (LB IP'lerini serbest bırak)
```bash
kubectl delete ns metallb-system --wait=false
```

## VM'leri hiç silmeden "temiz OS" haline getirmek isterseniz
Teardown + `dnf autoremove` + (isterseniz) containerd uninstall:
```bash
dnf -y remove containerd
rm -rf /var/lib/containerd /etc/containerd /etc/systemd/system/containerd.service.d
systemctl daemon-reload
```

## K3s lab için
`k8s-lab-k3s/scripts/k3s-lab-install.sh teardown <ip...>` (k3s-uninstall.sh tabanlı).
