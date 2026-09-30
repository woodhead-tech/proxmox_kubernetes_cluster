#!/bin/bash
# Exercises the REAL premount + finalize scripts against a throwaway loop-device VG
# (scaled-down sizes) using busybox sh, the same shell family as the initramfs.
# Safe to run on tower1: never touches the "pve" VG. Run as root.
set -u
IMG=/var/tmp/tst-shrink.img; VG=tstvg; MNT=/var/tmp/tst-mnt; LOG=/var/tmp/tst-result.txt
MB=$((1024*1024)); pass=0; fail=0
BB="busybox sh"; command -v busybox >/dev/null || BB="sh"
D="$(cd "$(dirname "$0")" && pwd)"

cleanup() {
    mountpoint -q $MNT 2>/dev/null && umount $MNT
    vgchange -an $VG >/dev/null 2>&1; vgremove -ff -y $VG >/dev/null 2>&1
    [ -n "${LOOP:-}" ] && { pvremove -ff -y "$LOOP" >/dev/null 2>&1; losetup -d "$LOOP" 2>/dev/null; }
    rm -f $IMG; rmdir $MNT 2>/dev/null; true
}
trap cleanup EXIT
check() { if [ "$2" = "$3" ]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }
lvb() { lvs --noheadings --nosuffix --units b -o lv_size $VG/$1 | sed 's/[^0-9]//g'; }

setup() {   # $1 = MB of data to write into the root fs
    mountpoint -q $MNT 2>/dev/null && umount $MNT
    lvremove -ff -y $VG/root >/dev/null 2>&1
    lvcreate -y -L 1600M -n root $VG >/dev/null && mkfs.ext4 -q /dev/$VG/root
    mkdir -p $MNT && mount /dev/$VG/root $MNT
    mkdir -p $MNT/d; i=0
    while [ $((i*50)) -lt "$1" ]; do dd if=/dev/urandom of=$MNT/d/f$i bs=1M count=50 status=none; i=$((i+1)); done
    (cd $MNT && find d -type f | sort | xargs md5sum) > /var/tmp/tst-md5.txt
    sync; umount $MNT
}
# Put busybox applets first in PATH: the initramfs provides grep/sed/awk/tr/etc. ONLY as
# busybox applets, whose behaviour differs from the GNU tools on a normal host.
BBDIR=/var/tmp/tst-bb; mkdir -p $BBDIR
if command -v busybox >/dev/null; then
    for t in grep awk sed tr sleep cut expr; do ln -sf "$(command -v busybox)" $BBDIR/$t; done
fi
run_pre() {  # env-scaled: 1000M target, 64M slack, 200M headroom
    PATH=$BBDIR:$PATH VG=$VG TARGET_BYTES=$((1000*MB)) FS_SLACK_BYTES=$((64*MB)) MIN_HEADROOM_BYTES=$((200*MB)) \
    KMSG=/dev/null CMDLINE_FILE=${CMDLINE_FILE:-/proc/cmdline} $BB "$D/premount" 2>&1
}

truncate -s 4G $IMG; LOOP=$(losetup -f --show $IMG)
pvcreate -y "$LOOP" >/dev/null && vgcreate $VG "$LOOP" >/dev/null
lvcreate -y -L 800M -T $VG/data >/dev/null

echo "--- A: normal shrink with 300M of data"
setup 300
out=$(run_pre); echo "$out" | sed 's/^/    /'
check "A root LV shrunk to 1000M" "$(lvb root)" "$((1000*MB))"
mount -o ro /dev/$VG/root $MNT
(cd $MNT && find d -type f | sort | xargs md5sum) > /var/tmp/tst-md5.after
check "A data checksums intact" "$(md5sum < /var/tmp/tst-md5.txt)" "$(md5sum < /var/tmp/tst-md5.after)"
fs_mb=$(df -m --output=size $MNT | tail -1 | tr -d ' '); umount $MNT
check "A fs regrown to fill LV (>=940M)" "$([ "$fs_mb" -ge 940 ] && echo yes || echo no)" "yes"
e2fsck -fn /dev/$VG/root >/dev/null 2>&1; check "A fsck clean" "$?" "0"

echo "--- A2: finalize extends the pool, DRY_RUN"
before=$(lvb data)
VG=$VG TARGET_BYTES=$((1000*MB)) POOL_ADD_BYTES=$((500*MB)) RESERVE_BYTES=$((100*MB)) MIN_ADD_BYTES=$((100*MB)) DRY_RUN=1 RESULT_FILE=$LOG bash "$D/finalize" >/dev/null 2>&1
check "A2 pool grew by 500M" "$(( $(lvb data) - before ))" "$((500*MB))"
check "A2 status OK" "$(grep -c '^STATUS: OK' $LOG)" "1"

echo "--- B: idempotent re-run"
out=$(run_pre); echo "$out" | sed 's/^/    /'
check "B no-op message" "$(echo "$out" | grep -c 'nothing to do')" "1"
check "B root unchanged" "$(lvb root)" "$((1000*MB))"

echo "--- C: fs too full to shrink (1200M data) is refused, LV untouched"
setup 1200
out=$(run_pre); echo "$out" | sed 's/^/    /'
check "C refused" "$(echo "$out" | grep -c 'NOT shrinking')" "1"
check "C root LV still 1600M" "$(lvb root)" "$((1600*MB))"
e2fsck -fn /dev/$VG/root >/dev/null 2>&1; check "C fsck clean" "$?" "0"

echo "--- D: mounted root is refused"
setup 100; mount /dev/$VG/root $MNT
out=$(run_pre); echo "$out" | sed 's/^/    /'
check "D refused (mounted)" "$(echo "$out" | grep -c 'is mounted')" "1"
check "D root LV still 1600M" "$(lvb root)" "$((1600*MB))"
umount $MNT

echo "--- E: noshrink on cmdline skips"
echo "BOOT_IMAGE=x root=/dev/mapper/tstvg-root ro noshrink" > /var/tmp/tst-cmdline
out=$(CMDLINE_FILE=/var/tmp/tst-cmdline run_pre); echo "$out" | sed 's/^/    /'
check "E skipped" "$(echo "$out" | grep -c 'noshrink on cmdline')" "1"
check "E root LV still 1600M" "$(lvb root)" "$((1600*MB))"

rm -rf /var/tmp/tst-cmdline /var/tmp/tst-md5.* $LOG $BBDIR
echo "=== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
