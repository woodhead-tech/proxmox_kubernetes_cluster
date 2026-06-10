# Talos K8s Cluster Recovery Runbook

**Cluster:** woodhead.tech homelab (tower1 CP + 3 workers)  
**Last used:** 2026-06-09/10 — full CP recovery after etcd encryption key rotation

---

## Symptom: CP node NotReady, workers can't register

### Root cause tree

```
etcd secrets encrypted with old key
  → API server secrets cacher crash-loops on LIST
    → Bootstrap token authenticator never populated
      → kubelet bootstrap token → 401 Unauthorized
        → CP kubelet can't register → NotReady
```

---

## Step 1: Identify poisoned etcd secrets

Check API server logs for `unable to transform key`:

```bash
talosctl --nodes 192.168.86.101 logs kube-apiserver 2>&1 | grep "unable to transform"
```

Example output:
```
unable to transform key "/registry/secrets/metallb-system/memberlist": output array was not large enough
unable to transform key "/registry/secrets/metallb-system/metallb-webhook-cert": output array was not large enough
```

---

## Step 2: Delete poisoned secrets via etcdctl

Pull etcd certs from CP:

```bash
talosctl --nodes 192.168.86.101 read /system/secrets/etcd/admin.crt > /tmp/etcd-certs/admin.crt
talosctl --nodes 192.168.86.101 read /system/secrets/etcd/admin.key > /tmp/etcd-certs/admin.key
talosctl --nodes 192.168.86.101 read /system/secrets/etcd/ca.crt   > /tmp/etcd-certs/ca.crt
```

Delete via Docker etcdctl (run from pve1 or any host with Docker):

```bash
docker run --rm -it \
  -v /tmp/etcd-certs:/certs \
  gcr.io/etcd-development/etcd:v3.5.0 \
  etcdctl --endpoints=https://192.168.86.101:2379 \
    --cacert=/certs/ca.crt --cert=/certs/admin.crt --key=/certs/admin.key \
    del /registry/secrets/<namespace>/<secret-name>
```

Confirm deletion (output: `1`).

---

## Step 3: Check the bootstrap token in use

The CP kubelet uses the token hardcoded in `/etc/kubernetes/bootstrap-kubeconfig` (Talos read-only):

```bash
talosctl --nodes 192.168.86.101 read /etc/kubernetes/bootstrap-kubeconfig
```

Note the `token:` field. If that token was deleted from K8s (it lives in `kube-system/bootstrap-token-<id>`), recreate it:

```bash
# token format: <id>.<secret> (e.g. beo9lp.72rfoi6uw7cxbed7)
kubectl create secret generic bootstrap-token-<id> \
  --namespace=kube-system \
  --type=bootstrap.kubernetes.io/token \
  --from-literal=token-id=<id> \
  --from-literal=token-secret=<secret> \
  --from-literal=usage-bootstrap-authentication=true \
  --from-literal=usage-bootstrap-signing=true \
  --from-literal=auth-extra-groups=system:bootstrappers:kubeadm:default-node-token
```

---

## Step 4: Verify bootstrap RBAC bindings exist

These three ClusterRoleBindings must exist (they are NOT built-in, must be created):

```bash
kubectl get clusterrolebinding system:node-bootstrapper \
  kubeadm:node-autoapprove-bootstrap \
  kubeadm:node-autoapprove-certificate-rotation
```

If missing, create them:

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:node-bootstrapper
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node-bootstrapper
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:bootstrappers:kubeadm:default-node-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:node-autoapprove-bootstrap
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:bootstrappers:kubeadm:default-node-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:node-autoapprove-certificate-rotation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:nodes
EOF
```

---

## Step 5: Fix MetalLB webhook cert (if metallb-webhook-cert was deleted)

MetalLB controller is in a chicken-and-egg: it needs the cert to start, and creates the cert when it starts.

Generate a self-signed cert and create the secret manually:

```bash
mkdir -p /tmp/metallb-certs && cd /tmp/metallb-certs

cat > webhook-cert.conf <<'CONF'
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = metallb-webhook-service.metallb-system.svc
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = metallb-webhook-service
DNS.2 = metallb-webhook-service.metallb-system
DNS.3 = metallb-webhook-service.metallb-system.svc
DNS.4 = metallb-webhook-service.metallb-system.svc.cluster.local
CONF

openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 3650 -nodes \
  -subj "/CN=metallb-webhook-service.metallb-system.svc" \
  -extensions v3_req -config webhook-cert.conf 2>/dev/null

kubectl create secret tls metallb-webhook-cert \
  -n metallb-system \
  --cert=/tmp/metallb-certs/tls.crt \
  --key=/tmp/metallb-certs/tls.key
```

Then delete all MetalLB pods so they restart with the new secret:

```bash
kubectl delete pod -n metallb-system --all
```

---

## Step 6: Fix stale Flannel cni0 bridge

If pods on a worker are stuck with:
```
"cni0" already has an IP address different from 10.244.X.1/24
```

Run a privileged pod on that node to delete the stale bridge:

```bash
kubectl run cni-fix --rm -it --restart=Never \
  --namespace=kube-system \
  --image=busybox \
  --overrides='{"spec":{"nodeName":"<node-name>","hostNetwork":true,"hostPID":true,"containers":[{"name":"cni-fix","image":"busybox","command":["sh","-c","ip link delete cni0 && echo deleted || echo not_found"],"securityContext":{"privileged":true}}]}}'
```

Note: must use `kube-system` namespace (default namespace has PodSecurity `baseline` which blocks privileged).

---

## Verify recovery

```bash
kubectl get nodes          # all Ready
kubectl get pods -A | grep -Ev 'Running|Completed'   # no output = all healthy
```
