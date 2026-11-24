# 06 — Rancher GUI (Apache-2.0, self-hosted)

Rancher, sektöründe standart, açık kaynak (Apache-2.0) Kubernetes yönetim
arayüzüdür. Bu lab'da aynı Rancher, vanilla k8s / k3s / EKS Anywhere
kümelerinin üçünün de yönetiminde kullanılır (bkz. k8s-lab-k3s,
k8s-lab-eks-anywhere repoları).

## Kurulum (cluster içi, helm)

```bash
kubectl create namespace cattle-system
helm repo add rancher-stable https://releases.rancher.com/chart
helm repo update
helm upgrade --install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set replicas=1 \
  --set ingress.tls.enabled=false \
  --timeout 15m
```

- Test lab'ı için `replicas=1` (CP düğümü 8 GiB olduğu için; üretimde ≥2).
- Ingress kullanmak yerine Rancher'ın kendi servisini LoadBalancer olarak
  açar:

```bash
kubectl -n cattle-system patch svc rancher --type merge -p \
  '{"spec":{"type":"LoadBalancer"}}'
kubectl -n cattle-system get svc rancher   # EXTERNAL-IP: 192.168.10.8x
```

## İlk Giriş (bootstrap)

```bash
kubectl -n cattle-system get secret bootstrap-password -o jsonpath='{.data.password}' | base64 -d
```

- Tarayıcı: `http://<Rancher-LB-IP>/` → bootstrap parolası → kendi admin
  parolanızı belirleyin.
- Cluster otomatik listelenir (local). Namespace, workload, log, pod terminal
  ve event'ler buradan yönetilir.

## Doğrulama

```bash
kubectl -n cattle-system get pods   # rancher + rancher-webhook (cluster katılınca cattle-cluster-agent)
curl -sk https://<Rancher-LB-IP>/healthz   # {"status":"Pinged"}
```

> `scripts/rancher-install.sh` bu adımı otomatikleştirir: önce LoadBalancer
> servisini açar, sonra helm ile kurar; Rancher UI LoadBalancer IP'si üzerinden
> erişilir. Bootstrap parolayı script çıktısında gösterir.

## Kaldırma

```bash
kubectl -n cattle-system delete svc rancher
helm uninstall rancher -n cattle-system
```

## Mimari Not: Rancher Nerede Calisir?

Rancher, yoneticegi cluster'in **DISINDA** bir "meta-cluster"da calisir.
Bu laboratuvarda: **k8sdig VM (192.168.10.77)** = meta-cluster (tek-node k8s).

- `scripts/rancher-install.sh` k8sdig'de calisir (Helm, self-signed TLS, bootstrap parolasini /root/rancher-pw.txt'e yazar)
- Her cluster (vanilla/k3s) import edilir: cluster tarafinda
  `KUBECONFIG=... kubectl create -f "https://releases.rancher.com/import/import.yaml?name=<cluster>"`
- UI: `https://192.168.10.77` (bootstrap parolasiyla giris)
- Rancher CE = Apache-2.0, ucretsiz, sınırsız cluster/node
