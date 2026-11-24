# 05 — Test Senaryosu: nginx Deployment + Scale

## Amaç

- 3 worker node'lu kümeye nginx Deployment (3 replika) devreye alınır.
- LoadBalancer servisi üzerinden gönderilen isteklerin **pod'lara dağıldığı**
  doğrulanır (her istekte farklı pod IP'si görülmeli).
- 1 replikaya **scale down** edilir; trafik kesintisiz devam eder.
- (Geri dönüşte) tekrar 3'e **scale up** edilir.

## Adımlar

```bash
kubectl apply -f scripts/nginx-deploy.yaml
kubectl rollout status deploy/nginx
kubectl get svc nginx-lb          # EXTERNAL-IP dolu olmalı (192.168.10.80-84)
```

`scripts/nginx-deploy.yaml` içinde her pod kendi IP'sini `X-Pod` header'ı
olarak döndürür (nginx `more_headers` modu yerine basit bir env + config
yaklaşımı: pod IP'si `POD_IP` env ile alınıp response'da basılır).

Trafik doğrulaması (orion'dan):

```bash
bash scripts/test-nginx.sh
```

Script yaptığı iş:

1. `LB=$(kubectl get svc nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')`
2. Scale-up durumu: 50 istek → kaç **farklı pod** yanıtladı? (Beklenen: 3)
3. `kubectl scale deploy nginx --replicas=1` → bekleme → 50 istek
   (Beklenen: hepsi aynı pod, yanıt 200, hata yok)
4. `kubectl scale deploy nginx --replicas=3` → bekleme → 50 istek
   (Beklenen: tekrar 3 farklı pod)
5. Sonuç tablosu yazdırır: `durum / farklı pod sayısı / 200 sayısı / hata`.

### Kabul Kriteri

Her iki durumda da **%100 HTTP 200** ve scale-up durumlarında
**3 farklı pod IP'si** görülmelidir.

## Olcum Kaniti (24.11.2026, bu laboratuvarda calistirildi)

| Adim | Sonuc |
|---|---|
| 1 CP (.73) + 3 worker (.74-.76) | 4 node `Ready`, `v1.37.2`, `containerd://2.0.14` |
| Calico + MetalLB | LB IP **192.168.10.80** |
| nginx 3 replica | pod'lar 3 worker'a yayildi |
| 12 istek LB'den | **4 / 3 / 5** pod'lara dagildi (X-Pod-Name header kaniti) |
| scale 3→1 | 1 pod'a 5/5 `HTTP 200` |
| scale 1→3 | 3 pod'a 10 istek: **1 / 2 / 7** dagilim |

> **Ders (bu turda yasandi):** kubelet'i 10 sn'de bir yeniden baslatan
> "swap on is not supported" hatasi, pod dalgalanmasi olarak gorunur.
> Swap KALICI kapatilmalidir (fstab satiri yorumlanmis + `swapon --show` bos),
> her reboot sonrasinda yeniden dogrulanmalidir.
