# Dell Networking X1026 — managed switch

A 24-port 1Gb managed switch (Cisco-Small-Business / RASTUTE-derived). Being
converted from **unmanaged mode → managed mode**. First-time CLI setup was done
over the USB serial console; ongoing management is from **tc1** (thinkcentre1 /
pve1, `192.168.86.29`) over SSH via the `x1026` utility in this directory.

## Identity & access

| Field | Value |
|-------|-------|
| Model / firmware | Dell Networking X1026, SW `3.0.1.9` (Oct 2021), Boot `1.0.0.17` |
| MAC | `f4:8e:38:37:70:42` |
| Mgmt IP | `192.168.86.210/24` via **DHCP**, gateway `192.168.86.1` (vlan 1) |
| Admin user | `admin` (factory default `admin/admin` was changed during setup) |
| Open mgmt ports | SSH/22, Telnet/23, HTTPS/443 |
| Mgmt host | **tc1** `192.168.86.29` — `/usr/local/bin/x1026` |
| Password | **not in this repo** — on tc1 at `/etc/x1026.env` (root, 0600) |

## Using the utility (from tc1)

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.29

x1026 run "show version"          # run one command and exit
x1026 run "show running-config"   # pager is auto-advanced
x1026                             # interactive CLI shell
x1026 --debug run "show clock"    # print the login transcript to stderr
```

Password resolution order: `--password-file FILE` → `$X1026_PASSWORD` →
`/etc/x1026.env`. Copy `x1026.env.example` to `/etc/x1026.env` on any new
management host and fill in the password (never commit the real value).

It is pure stdlib Python (pty-driven `ssh`) — no `expect`, `sshpass`, or
`paramiko` needed, since tc1 has none of those.

## Setup already completed

- Logged in over serial, changed `admin` from the factory `admin/admin` to a
  strong password (stored in `/etc/x1026.env` on tc1).
- Enabled the SSH server (`ip ssh server`) and generated a 2048-bit RSA host key
  (`crypto key generate rsa`).
- `copy running-config startup-config` — persisted.

## Gotchas (learned the hard way)

1. **Legacy SSH crypto.** The firmware only speaks old KEX/host-key/ciphers.
   Modern OpenSSH refuses by default; the required `-o` flags are baked into
   `x1026.py`. The host key is **RSA**.
2. **OpenSSH 10 dropped `ssh-dss`.** tc1 runs OpenSSH 10.0 — do **not** add
   `ssh-dss` to `HostKeyAlgorithms` (it errors with "Bad key types"). `ssh-rsa`
   alone is correct; the switch presents an RSA key.
3. **One admin session at a time.** A second login is refused with
   *"A client is already connected"*. **The USB serial console counts as a
   session** — log out of it (send `exit` at the prompt) before using SSH.
4. **CLI login after SSH.** SSH transport auth is effectively open; the real
   gate is the CLI `User Name:` / `Password:` prompt. `x1026.py` drives it.
5. **No `hostname` CLI command** on this firmware. Setting the System Name
   (currently blank) must be done via the web UI (`https://192.168.86.210`).
6. **Clock is wrong** (reads ~2016). Set SNTP / timezone before relying on
   timestamps in logs.

## Serial console fallback

When the network is unavailable, use the USB admin/console port (FTDI FT230X,
appears as `/dev/ttyUSB0`):

- **9600 baud, 8N1, no flow control**
- e.g. `minicom -D /dev/ttyUSB0 -b 9600` or `screen /dev/ttyUSB0 9600`

## Open items / next steps

- Decide static IP vs DHCP reservation for the mgmt address (currently DHCP
  `.210`; homelab convention favors a fixed infra address to avoid ARP overlap).
- Set System Name via web UI (planned: `x1026`).
- Configure SNTP for correct clock.
- Add a landing-site tile if/when a web-managed dashboard URL is exposed.
