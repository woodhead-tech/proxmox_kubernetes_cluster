#!/bin/bash
# Arms (or disarms) the one-shot root shrink on tower1. Run as root ON tower1.
#   ./install.sh          arm: takes effect on the NEXT reboot
#   ./install.sh --disarm remove everything and rebuild the initramfs
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
HOOK=/etc/initramfs-tools/hooks/shrink-root
PRE=/etc/initramfs-tools/scripts/local-premount/zz-shrink-root

if [ "${1:-}" = "--disarm" ]; then
    rm -f "$HOOK" "$PRE" /usr/local/sbin/shrink-root-finalize /etc/systemd/system/shrink-root-finalize.service
    systemctl disable shrink-root-finalize.service 2>/dev/null || true
    systemctl daemon-reload
    update-initramfs -u -k all
    echo "disarmed"; exit 0
fi

# --- guards: only ever run against the exact layout this was written for
[ "$(hostname)" = "tower1" ] || { echo "not tower1"; exit 1; }
[ "$(findmnt -no SOURCE /)" = "/dev/mapper/pve-root" ] || { echo "root is not pve-root"; exit 1; }
[ "$(findmnt -no FSTYPE /)" = "ext4" ] || { echo "root is not ext4"; exit 1; }
root_b=$(lvs --noheadings --nosuffix --units b -o lv_size pve/root | sed 's/[^0-9]//g')
[ "$root_b" -gt 26000000000 ] || { echo "root already small ($root_b); nothing to arm"; exit 1; }
used_kb=$(df -k --output=used / | tail -1 | tr -d ' ')
[ "$used_kb" -lt $((18 * 1024 * 1024)) ] || { echo "root usage too high (${used_kb}K); trim first"; exit 1; }
[ -s /root/pre-resize/pve-vg.conf ] || { echo "missing /root/pre-resize/pve-vg.conf (vgcfgbackup)"; exit 1; }

# Fallback copy of the known-good initrd (GRUB entry unchanged; for manual recovery).
for f in /boot/initrd.img-*; do
    case "$f" in *.pre-shrink) ;; *) [ -e "$f.pre-shrink" ] || cp -p "$f" "$f.pre-shrink" ;; esac
done

install -m 0755 "$D/hook" "$HOOK"
install -m 0755 "$D/premount" "$PRE"
install -m 0755 "$D/finalize" /usr/local/sbin/shrink-root-finalize
install -m 0644 "$D/shrink-root-finalize.service" /etc/systemd/system/shrink-root-finalize.service
systemctl daemon-reload
systemctl enable shrink-root-finalize.service

update-initramfs -u -k all
K=/boot/initrd.img-$(uname -r)
lsinitramfs "$K" > /tmp/initrd.list
for need in usr/sbin/resize2fs usr/sbin/tune2fs usr/sbin/e2fsck usr/sbin/lvm scripts/local-premount/zz-shrink-root; do
    grep -q "$need" /tmp/initrd.list || { echo "MISSING in initramfs: $need"; "$0" --disarm; exit 1; }
done
echo "ARMED. Next reboot will shrink pve/root to 24G and finalize; result: /root/pre-resize/RESULT.txt"
