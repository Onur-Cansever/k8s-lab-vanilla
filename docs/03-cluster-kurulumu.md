# 03 — Cluster Kurulumu (kubeadm)

## 3.1 Control Plane (controller VM)

```bash
ssh root@192.168.10.73 'cat > /root/cluster-init.sh' < scripts/cluster-init.sh
ssh root@192.168.10.73 'bash /root/cluster-init.sh'
```

Script içeriği (kısaca):

```bash
kubeadm init \
  --apiserver-cert-extra-sans=192.168.10.73 \
  --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix://run/containerd/containerd.sock \
  --ignore-preflight-errors=SystemVerification
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.1/manifests/calico.yaml
```

Notlar:

- `--pod-network-cidr=192.168.0.0/16` Calico overlay'i için ayıklanır;
  host (.10.x) ve service (.168.0.0/16 değil, varsayılan 10.96.0.0/12)
  aralıklarıyla çakışmaz.
- `--cri-socket` ile containerd kullanılır; kubeadm containerd config'ini
  kendisi yazar (CRI plugin).
- `SystemVerification` preflight'i OL8'te bazı kernel parametre uyarıları
  verebilir; 02. belgedeki sysctl'ler bunları kapatır, yine de hata gelirse
  bu bayrakla geçilir (test ortamı kararı).

## 3.2 Worker Katılımı (.74 / .75 / .76)

init çıktısındaki token'ı script'e sabitlemek yerine her join'de
token alınır (tek komut, controller'dan):

```bash
TOKEN=$(ssh root@192.168.10.73 'kubeadm token create --print-join-command' | awk '{print $NF}')
for ip in 74 75 76; do
  ssh root@192.168.10.$ip "cat > /root/join.sh" < <(ssh root@192.168.10.73 "kubeadm token create --print-join-command | sed 's/--kubeconfig.*//; s/^/kubeadm join 192.168.10.73:6443 /'")
  ssh root@192.168.10.$ip 'bash /root/join.sh'
done
```

> Kolay yol: her VM için `scripts/cluster-join.sh` (aşağıdaki) çalıştırılır;
> token'ı controller'dan kendisi alır.

## 3.3 Doğrulama

```bash
kubectl get nodes -o wide
# Beklenen: controller + 3 worker, tümü Ready, INTERNAL-IP 192.168.10.7x
kubectl get pods -A   # kube-system pod'ları Running (calico dahil)
```

## 3.4 (Opsiyonel) AWS Uyumu — EKS Distro İmajları

EKS'te kullanılan **birebir aynı** binary'lerle kurmak isterseniz init satırını
değiştirin (sürüm etiketi `distro.eks.amazonaws.com` manifest'inden alınır):

```bash
kubeadm init \
  --image-repository public.ecr.aws/eks-distro/kubernetes \
  --kubernetes-version v1.37.x-eks-N \
  --apiserver-cert-extra-sans=192.168.10.73 \
  --pod-network-cidr=192.168.0.0/16 \
  --cri-socket=unix://run/containerd/containerd.sock
```

- Üstteki `--kubernetes-version` **eks etiketi** istediği için `v1.37.2` gibi
  upstream etiket değil, örn. `v1.37.1-eks-1` formatındadır;
  güncel etiketi: `https://eksd-release.aws/manifests/kubernetes-1-37.yaml`.
- join komutları da aynı `--image-repository` argümanıyla üretilmelidir.
- Kalan her şey (CNI, LB, test) birebir aynıdır.
