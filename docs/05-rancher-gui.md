# 05 — Rancher GUI (metaküme)

Rancher, cluster yönetimini GUI'ye taşır: node/pod görüntüleme, workload
deploy, log, terminal, rol atama — kubectl bilmeden yönetim için.
(Açık kaynak: Apache-2.0, ücretsiz self-hosted, sınırsız cluster/node.)

## Mimari
Rancher **ayrı bir k8s'de** (metaküme) çalışır ve cluster'ları Fleet/
kubeconfig üzerinden yönetir. Lab'da metaküme: **k8sdig (192.168.10.77,
k8s 1.35)** — tek node VM.

```
orion (driver) ──ssh──> msi (4 VM: lab)
                    └─ssh──> k8sdig (1 VM: metaküme + Rancher)
lab (192.168.10.73)  ── Fleet/kubeconfig ──>  Rancher (k8sdig)
```

## Kurulum (k8sdig, test edilmiş adımlar)
```bash
# metaküme: kubeadm init 1.35 + calico + ingress-nginx (hostNetwork)
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
kubectl create namespace cattle-system
PW=$(tr -dc A-Za-z0-9 </dev/urandom | head -c24)   # bootstrap parolası

# self-signed TLS (UI icin)
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=k8sdig.lab" \
  -addext "subjectAltName=DNS:k8sdig.lab,IP:192.168.10.77" \
  -keyout /tmp/tls.key -out /tmp/tls.crt
kubectl -n cattle-system create secret tls-rancher-ingress \
  --cert=/tmp/tls.crt --key=/tmp/tls.key
kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem=/tmp/tls.crt

helm install rancher rancher-latest/rancher -n cattle-system --version 2.14.3 \
  --set hostname=k8sdig.lab --set ingress.tls.source=secret --set privateCA=true \
  --set "ingress.tls.certificate=$(base64 -w0 /tmp/tls.crt)" \
  --set "ingress.tls.certificateKey=$(base64 -w0 /tmp/tls.key)" \
  --set bootstrapPassword=$PW --wait --timeout 9m

# tarayicida girdi:
echo "192.168.10.77 k8sdig.lab" >> /etc/hosts
# https://k8sdig.lab  →  "Log in with Local User" → admin
```
Her cluster (vanilla/k3s) UI'den `Create → Existing` ile kubeconfig
yapıştırarak import edilir (veya import.yaml yöntemiyle).

## Bu oturumda çözülmüş tuzaklar (24.11.2026)
| Tuzak | Çözüm |
|---|---|
| control-plane **taint** tüm system pod'larını (fleet/turtles/helmops) Pending'da bırakıyor | metaküme'de taint kaldırıldı: `kubectl taint nodes <n> node-role.kubernetes.io/control-plane:NoSchedule-` |
| chart, ingress'e `ingressClassName` yazmıyor → nginx 404 | `kubectl -n cattle-system patch ingress rancher -p '{"spec":{"ingressClassName":"nginx"}}'` |
| telemetry manager sonsuz döngü → API global 401 | `CATTLE_SERVER_URL` + `CATTLE_INSTALL_UUID` env'leri (`kubectl set env deploy/rancher`) |
| webhook/rancher pod taint'e takılıyordu | deploy'lara control-plane toleration (patch) — taint kaldırınca gereksiz kaldı |

## Bilinen açık sorun: bootstrap login (dürüst kayıt)
Üç sürümde (2.14.3 / 2.15.0 / 2.15.3) `--set bootstrapPassword` **login'de
kabul edilmedi**:
- admin kullanıcı otomatik oluşuyor ("Default Admin");
  `cattle-local-user-passwords` ns'indeki secret **farklı (üretilmiş)
  parolanın** hash'ini taşıyor (PBKDF2-SHA512 ile birebir ölçüldü)
- API çalışıyor: `/v3-public` 200, `/v1` 200, UI 200, fleet/turtles Ready —
  ama `/v3/tokens` + UI → "Invalid username or password"
- 2.14 kaynağında (`pkg/data/management/role_data.go`, `BootstrapAdmin`):
  admin yalnızca **"admincreated configmap'i yok VE hiç user yokken"**
  bootstrap parolasıyla seed'lenir; bu metaküme'de sistem hesapları önce
  oluştuğu için farklı yoldan üretilen parola kullanıldı. Üretilen parola
  **ilk boot logunda `Bootstrap Password: <pw>`** satırıyla bir kez yazılır.

**Login için çalışan yol:** temiz ilk boot'ta `kubectl logs -f` açık tutup
`Bootstrap Password: ...` satırını yakalamak (bu oturumda metaküme 6+ kez
sıfırlandığından kaçtı). Yakalanır yakalanmaz login doğrulanıp bu dokümana
işlenecek; parola kalıcı saklanmaz (by design).

## Kaldırma
```bash
helm uninstall rancher -n cattle-system
for ns in $(kubectl get ns -o name | grep -E "cattle|fleet-|^namespace/local" | cut -d/ -f2); do kubectl delete ns $ns --wait=false; done
# Takilan ns dersi: cluster.x-k8s.io CR finalizer'leri (fleet) ns silinmesini
# blocklar — CR finalizer'lari elle kaldirilir:
kubectl -n fleet-local patch cluster local --type=merge -p '{"metadata":{"finalizers":null}}'
```
