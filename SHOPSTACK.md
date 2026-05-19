# ShopStack Management Hub

This document outlines the architecture and workflows for managing distributed ShopStack customer sites using the central homelab as a Command & Control (C2) Hub.

## Architecture: Hub-and-Spoke

The management plane uses a dedicated WireGuard interface (`wg1`) on the central WireGuard LXC (192.168.86.39) to provide isolated access to remote customer sites.

| Component | Detail |
| :--- | :--- |
| **Hub IP** | 10.99.0.1 |
| **Interface** | `wg1` |
| **Listen Port** | 51821 |
| **Subnet** | 10.99.0.0/24 |
| **Spoke Subnet** | 10.99.0.x/32 |

### Network Isolation
- `wg0` (10.10.0.0/24): Personal VPN for homelab administration.
- `wg1` (10.99.0.0/24): Management hub for remote customer infrastructure.

## Workflows

### 1. Hub Initialization
To set up the `wg1` interface on the homelab:
```bash
make wireguard-shopstack
```
This generates the hub's private key and fetches the public key to `ansible/files/wireguard/shopstack-hub.pubkey`.

### 2. Local Operator Setup
To reach the management subnet from your local machine via the primary VPN:
```bash
sudo ip route add 10.99.0.0/24 via 192.168.86.39
```

### 3. Onboarding a Customer Spoke
1. Provision the customer box using the `shopstack` repository.
2. Register the peer on the hub:
   ```bash
   make shopstack-add-peer CLIENT=<name> WG_IP=10.99.0.X
   ```
   This performs a zero-downtime `wg syncconf` to add the new peer.

### 4. Direct Management
Once onboarded, SSH directly to the customer site via the management tunnel:
```bash
ssh admin@10.99.0.X
```

## Security Guardrails
- **Pre-shared Keys (PSK):** Every client tunnel uses a unique PSK for post-quantum resistance.
- **Persistent Keepalive:** Spokes maintain the tunnel from behind NAT/firewalls using a 25-second keepalive.
- **Isolated Routing:** The hub does not route between spokes by default; it is a management re-entry point only.
