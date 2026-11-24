# 03 — Test Senaryosu (nginx + MetalLB + scale)

Amaç: 3 replica nginx'i LoadBalancer servisi üzerinden trafiğe açıp
(a) isteklerin pod'lar arasında **dağıldığını**, (b) **scale 3→1→3**
işleminde trafiğin kesilmediğini **kanıtla**.

Kanıt yöntemi: nginx.conf'a `add_header X-Pod-Name $HOSTNAME` eklenir;
her istek kendi pod'unu yanıt header'ında söyler.

## Manuel adımlar (controller'da)
```bash
# 1) deploy (namespace + ConfigMap + 3 replica + LB Service)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata: {name: nginx-lab}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: nginx-conf, namespace: nginx-lab}
data:
  default.conf: |
    server {
      listen 80;
      set $podname $HOSTNAME;
      add_header X-Pod-Name $podname always;
      location / { return 200 "ok\n"; }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: nginx, namespace: nginx-lab}
spec:
  replicas: 3
  selector: {matchLabels: {app: nginx}}
  template:
    metadata: {labels: {app: nginx}}
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports: [{containerPort: 80}]
          volumeMounts: [{name: conf, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: conf, configMap: {name: nginx-conf}}]
---
apiVersion: v1
kind: Service
metadata: {name: nginx-lb, namespace: nginx-lab}
spec:
  type: LoadBalancer
  selector: {app: nginx}
  ports: [{port: 80}]
EOF
kubectl -n nginx-lab rollout status deploy/nginx --timeout=180s

# 2) LB IP + dağılım kanıtı
IP=$(kubectl -n nginx-lab get svc nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for i in $(seq 1 12); do curl -sI http://$IP/ | grep -i x-pod-name; done | sort | uniq -c

# 3) scale 3 -> 1 (trafik kesilmeyecek)
kubectl -n nginx-lab scale deploy nginx --replicas=1 && sleep 20
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://$IP/; done; echo

# 4) scale 1 -> 3 + dağılım
kubectl -n nginx-lab scale deploy nginx --replicas=3 && sleep 30
for i in $(seq 1 10); do curl -sI http://$IP/ | grep -i x-pod-name | awk '{print $2}'; done | sort | uniq -c
```

## Beklenen sonuç (başarı kriterleri)
1. 3 pod `Running`, 3 endpoint (Endpoints objesinde 3 IP)
2. 12 isteğin **≥2 farklı pod**'a dağılması (ideal: 3 pod'a)
3. scale=1 iken 5/5 HTTP 200
4. scale=3 sonrası 10 istek **>1 pod**'a dağılması

## ÖLÇÜLMÜŞ SONUÇLAR — online (24.11.2026, k8s v1.37.2, 1CP+3W)
```
LB IP: 192.168.10.80
12 istek dagilimi:      3 pod (X-Pod-Name: 3 farkli)
scale 3->1:             200 200 200 200 200
scale 1->3 dagilim:     5 nginx-...9krzg / 1 nginx-...jrch6 / 4 nginx-...zxt22
endpoints: 3
TEST_PASS
```
Aynı senaryo K3s cluster'ında da ölçülmüştür: bkz. `k8s-lab-k3s/docs/03-test-senaryosu.md`
(12 istek: 7/2/3; scale 1→3: 2/4/4).

## ÖLÇÜLMÜŞ SONUÇ — OFFLINE (24.11.2026)
Aynı VM'ler; önce teardown + **imaj store'u tamamen silindi**
(`ctr -n k8s.io images ls` = 0), ardından kurulum **yalnızca
`/root/offline` cache'inden** yapıldı (RPM + containerd tarball + 13 imaj tar'ı):

```
base:  4/4 VM  (offline: /root/offline/vanilla/rpms/ + containerd tarball)
init:  imaj import 13/13 → kubeadm init v1.37.2 → Calico → MetalLB (pool deneme=1)
join:  3 worker (imaj import + kubeadm join)
test:
  LB IP: 192.168.10.80
  dagilim 12 istek:  5 nginx-...898jg / 3 nginx-...9vsq5 / 4 nginx-...d5ssv
  scale 3->1:        200 200 200 200 200
  scale 1->3:        10 istek dagildi
  CHECKLIST: 4 node Ready, swap=0, containerd v2.0.14, endpoints=3
  TEST_PASS
```
