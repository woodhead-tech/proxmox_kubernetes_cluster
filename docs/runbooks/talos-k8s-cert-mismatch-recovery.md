# Runbook: Talos K8s Cluster — Cert Mismatch / Cannot Connect

**Date:** 2026-06-06  
**Symptom:** `talosctl` and `kubectl` both fail to connect to the cluster. `talosctl version` returns `certificate signed by unknown authority` or `certificate required`.

---

## Root Cause

`talos/_out/talosconfig` and the cluster's running PKI are out of sync. This happens when:

- `talosctl gen config` is re-run (regenerates PKI), overwriting `talos/_out/talosconfig` with new credentials that don't match the running cluster's machine CA
- The old credentials were never stored in Vaultwarden before regeneration
- Worker VMs had their disks wiped (via previous recovery attempt) and are in Talos maintenance mode with no IPs

The cluster's PKI lives in the Talos STATE partition on each node's disk (`/dev/pve/vm-XXX-disk-0`, partition 5 at offset sector 4306944). It is NOT in git (gitignored).

---

## Diagnosis

```bash
# 1. Test talosctl — expect cert error if PKI mismatch
talosctl version --nodes 192.168.86.101

# 2. Test if the running cluster uses TLS (mTLS = disk boot, not maintenance mode)
openssl s_client -connect 192.168.86.101:50000 < /dev/null 2>&1 | grep -E 'CN=|issuer'

# 3. Check if K8s API is responding
timeout 3 bash -c "echo '' > /dev/tcp/192.168.86.100/6443" && echo "API up" || echo "API down"

# 4. Check what IPs the worker VMs have (wiped disks = IPv6 only, no IPv4)
for host in 192.168.86.30 192.168.86.31 192.168.86.147; do
  ssh -i ~/.ssh/id_ansible root@$host "ip neigh show | grep '192.168.86.1[01][0-9]'"
done
```

---

## Recovery: Case A — Cluster Running, talosconfig Wrong PKI

The cluster is up (port 50000 speaks mTLS) but our local credentials don't match. Workers may or may not be healthy.

### Step 1: Extract machine CA from CP's STATE partition

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.130   # tower1, hosts CP (VM400)

# Mount the Talos STATE partition (p5, offset sector 4306944)
mkdir -p /mnt/talos-state
mount -o ro,offset=2205155328,sizelimit=$((204800*512)) /dev/pve/vm-400-disk-0 /mnt/talos-state

ls /mnt/talos-state/   # should show: config.yaml  encryption-salt.yaml  node-identity.yaml
```

### Step 2: Generate new admin cert from the running machine CA

Run this Python script on tower1:

```python
python3 << 'PYEOF'
import base64, yaml, datetime
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

with open("/mnt/talos-state/config.yaml", "r") as f:
    cfg = yaml.safe_load(f)

machine_ca = cfg["machine"]["ca"]
ca_crt_pem = base64.b64decode(machine_ca["crt"])
key_pem = base64.b64decode(machine_ca["key"]).decode()

# ED25519 key: raw 32-byte seed embedded in the PEM body (48 bytes total with header)
lines = key_pem.strip().split("\n")
raw_bytes = base64.b64decode("".join(lines[1:-1]))
seed = raw_bytes[-32:]

ca_key = Ed25519PrivateKey.from_private_bytes(seed)
ca_cert = x509.load_pem_x509_certificate(ca_crt_pem)

admin_key = Ed25519PrivateKey.generate()
now = datetime.datetime.utcnow()
admin_cert = (
    x509.CertificateBuilder()
    .subject_name(x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, "os:admin")]))
    .issuer_name(ca_cert.subject)
    .public_key(admin_key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(now)
    .not_valid_after(now + datetime.timedelta(days=3650))
    .add_extension(x509.KeyUsage(
        digital_signature=True, content_commitment=False, key_encipherment=False,
        data_encipherment=False, key_agreement=False, key_cert_sign=False,
        crl_sign=False, encipher_only=False, decipher_only=False
    ), critical=True)
    .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH]), critical=False)
    .sign(ca_key, None)
)

ca_b64 = machine_ca["crt"]
crt_b64 = base64.b64encode(admin_cert.public_bytes(serialization.Encoding.PEM)).decode()
key_b64 = base64.b64encode(admin_key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
)).decode()

talosconfig = f"""context: talos-proxmox
contexts:
    talos-proxmox:
        endpoints:
            - 192.168.86.101
        nodes:
            - 192.168.86.101
        ca: {ca_b64}
        crt: {crt_b64}
        key: {key_b64}
"""

with open("/tmp/new-talosconfig.yaml", "w") as f:
    f.write(talosconfig)
import os; os.chmod("/tmp/new-talosconfig.yaml", 0o600)
print("Written /tmp/new-talosconfig.yaml")
PYEOF
```

### Step 3: Copy and test new talosconfig

```bash
# From local machine
scp -i ~/.ssh/id_ansible root@192.168.86.130:/tmp/new-talosconfig.yaml \
  ~/Workspace/proxmox_kubernetes_cluster/talos/_out/talosconfig
chmod 600 ~/Workspace/proxmox_kubernetes_cluster/talos/_out/talosconfig

# Verify connection
export TALOSCONFIG=~/Workspace/proxmox_kubernetes_cluster/talos/_out/talosconfig
talosctl version --nodes 192.168.86.101
```

### Step 4: Unmount STATE partition

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.130 "umount /mnt/talos-state"
```

---

## Recovery: Case B — etcd Failed / K8s API Not Responding

After the talosconfig is fixed (Case A), if etcd is in "Failed" state:

```bash
# Check etcd state
talosctl services --nodes 192.168.86.101 | grep etcd
# Expected if broken: "Failed  pre stage: failed to build initial etcd cluster"
```

**Bootstrap etcd** (only run this ONCE — it initializes the cluster):

```bash
talosctl bootstrap --nodes 192.168.86.101
```

Wait ~10-15s for etcd to start, then fetch kubeconfig:

```bash
talosctl kubeconfig talos/_out/kubeconfig --nodes 192.168.86.101 --force
export KUBECONFIG=~/Workspace/proxmox_kubernetes_cluster/talos/_out/kubeconfig
kubectl get nodes
```

---

## Recovery: Case C — Worker VMs in Maintenance Mode (wiped disks)

Workers with wiped disks only have IPv6 link-local addresses. Port 50000 is open via socat relay on each Proxmox host.

### Set up socat relay on port 50000 of each host

```bash
# On thinkcentre2 (worker-0):
socat TCP-LISTEN:50000,bind=192.168.86.30,fork,reuseaddr 'TCP6:[fe80::be24:11ff:fe89:798c%vmbr0]:50000' &

# On thinkcentre3 (worker-1):
socat TCP-LISTEN:50000,bind=192.168.86.31,fork,reuseaddr 'TCP6:[fe80::be24:11ff:fe11:6948%vmbr0]:50000' &

# On zotac (worker-2):
socat TCP-LISTEN:50000,bind=192.168.86.147,fork,reuseaddr 'TCP6:[fe80::be24:11ff:fefd:921f%vmbr0]:50000' &
```

**Worker IPv6 addresses** (derived from MAC via EUI-64):
- VM410 / thinkcentre2: `fe80::be24:11ff:fe89:798c`
- VM411 / thinkcentre3: `fe80::be24:11ff:fe11:6948`
- VM412 / zotac: `fe80::be24:11ff:fefd:921f`

### Apply worker configs via maintenance mode

```bash
cd ~/Workspace/proxmox_kubernetes_cluster
# talosctl --insecure uses --nodes as the direct connection target (port 50000)
# The relay maps host:50000 → VM IPv6:50000
talosctl apply-config --insecure --nodes 192.168.86.30 --file talos/_out/worker-0.yaml
talosctl apply-config --insecure --nodes 192.168.86.31 --file talos/_out/worker-1.yaml
talosctl apply-config --insecure --nodes 192.168.86.147 --file talos/_out/worker-2.yaml
```

Wait ~90s for workers to install Talos and reboot to disk, then verify IPs:

```bash
for ip in 192.168.86.111 192.168.86.112 192.168.86.113; do
  ping -c 1 -W 2 $ip > /dev/null 2>&1 && echo "$ip: up" || echo "$ip: down"
done
```

Kill the socat relays after workers are up:

```bash
for host in 192.168.86.30 192.168.86.31 192.168.86.147; do
  ssh -i ~/.ssh/id_ansible root@$host "pkill socat" 2>/dev/null || true
done
```

---

## Post-Recovery: Approve Kubelet CSRs

After workers join, their kubelet serving CSRs need approval. The `kubelet-csr-approver` CronJob (in `k8s/base/kubelet-csr-approver.yml`) handles this automatically every 5 minutes.

For immediate approval:

```bash
make approve-csrs
# or:
kubectl get csr --no-headers | grep Pending | awk '{print $1}' | xargs kubectl certificate approve
```

---

## Post-Recovery: Apply Base Manifests

```bash
make k8s-base-metallb   # namespaces + kubelet CSR approver + MetalLB
```

---

## Post-Recovery: Push Certs to Vaultwarden

```bash
export BW_SESSION=$(bw unlock --raw)
make certs-push
```

Verify they're stored correctly:

```bash
make certs-check
```

---

## Guardrails Added (from this incident)

1. `scripts/certs-vault.sh` — push/pull/check Vaultwarden cert backup (item IDs hardcoded)
2. `scripts/recover-k8s.sh` — automated re-bootstrap workflow
3. `k8s/base/kubelet-csr-approver.yml` — CronJob auto-approves kubelet serving CSRs
4. `make certs-check` — verify talosctl + kubectl connectivity after restore
5. `make approve-csrs` — manually approve all pending CSRs

---

## Key Facts About the Talos STATE Partition

- Location: partition 5 of each VM disk (`/dev/pve/vm-XXX-disk-0p5`)
- Offset: sector 4306944 (byte offset 2,205,155,328) 
- Size: 204800 sectors (100 MiB)
- Mount: `mount -o ro,offset=2205155328,sizelimit=104857600 /dev/pve/vm-XXX-disk-0 /mnt/point`
- Contains: `config.yaml` (machine config with CAs), `node-identity.yaml`, `encryption-salt.yaml`
- The machine CA key format is `BEGIN ED25519 PRIVATE KEY` (not PKCS8); extract 32-byte seed from the last 32 bytes of the decoded PEM body
