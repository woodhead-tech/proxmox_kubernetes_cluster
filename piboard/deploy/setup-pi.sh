#!/usr/bin/env bash
# setup-pi.sh - Bootstrap a Raspberry Pi 3B for piboard kiosk mode
#
# Prerequisites:
#   - Raspberry Pi OS Lite (Bookworm) flashed and SSH accessible
#   - TP-Link WiFi adapter connected and configured
#   - Waveshare 5-inch HDMI display connected
#
# Run as root or with sudo:
#   sudo bash setup-pi.sh
#
# This script installs X11, Chromium, configures the display, and sets up
# piboard as a systemd service with a kiosk browser.

set -euo pipefail

# --- Validate running as root ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run this script with sudo"
    exit 1
fi

PI_USER="${PI_USER:-pi}"

echo "=== Installing display and kiosk packages ==="
apt-get update
# Use chromium or chromium-browser depending on availability
CHROMIUM_PKG="chromium"
if ! apt-cache show chromium >/dev/null 2>&1; then
    CHROMIUM_PKG="chromium-browser"
fi

apt-get install -y --no-install-recommends \
    xserver-xorg \
    x11-xserver-utils \
    xinit \
    xinput \
    xinput-calibrator \
    openbox \
    "${CHROMIUM_PKG}" \
    unclutter \
    curl

echo "=== Configuring Waveshare 5-inch HDMI display ==="
# Force 800x480 HDMI output for the Waveshare display
if ! grep -q "hdmi_group=2" /boot/firmware/config.txt 2>/dev/null; then
    cat >> /boot/firmware/config.txt <<'DISPLAY_EOF'

# Waveshare 5-inch HDMI display (800x480)
hdmi_group=2
hdmi_mode=87
hdmi_cvt=800 480 60 6 0 0 0
hdmi_drive=1
DISPLAY_EOF
    echo "Display config added to /boot/firmware/config.txt"
fi

# XPT2046 touch controller uses SPI -- enable if not already
if ! grep -q "^dtparam=spi=on" /boot/firmware/config.txt 2>/dev/null; then
    echo "dtparam=spi=on" >> /boot/firmware/config.txt
    echo "SPI enabled for touch controller"
fi

if ! grep -q "dtoverlay=ads7846" /boot/firmware/config.txt 2>/dev/null; then
    echo "dtoverlay=ads7846,cs=1,penirq=25,penirq_pull=2,speed=50000,keep_vref_on=0,swapxy=0,pmax=255,xohms=150,xmin=200,xmax=3900,ymin=200,ymax=3900" >> /boot/firmware/config.txt
    echo "ads7846 overlay added to /boot/firmware/config.txt"
fi

echo "=== Configuring auto-login and X11 startup ==="
# Auto-login the pi user to console
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<AUTOLOGIN_EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${PI_USER} --noclear %I \$TERM
AUTOLOGIN_EOF

# Start X on login via .bash_profile
BASH_PROFILE="/home/${PI_USER}/.bash_profile"
if ! grep -q "startx" "${BASH_PROFILE}" 2>/dev/null; then
    cat >> "${BASH_PROFILE}" <<'XSTART_EOF'

# Auto-start X11 on tty1 for kiosk display
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    exec startx -- -nocursor
fi
XSTART_EOF
    chown "${PI_USER}:${PI_USER}" "${BASH_PROFILE}"
fi

# Openbox autostart: hide cursor, prevent screen blanking
OPENBOX_DIR="/home/${PI_USER}/.config/openbox"
mkdir -p "${OPENBOX_DIR}"
cat > "${OPENBOX_DIR}/autostart" <<'OPENBOX_EOF'
# Disable screen saver and power management
xset s off
xset s noblank
xset -dpms

# Hide cursor after 3 seconds of inactivity
unclutter -idle 3 -root &
OPENBOX_EOF
chown -R "${PI_USER}:${PI_USER}" "/home/${PI_USER}/.config"

echo "=== Setting up piboard service user ==="
if ! id piboard &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin piboard
fi

echo "=== Installing piboard binary ==="
if [[ -f /tmp/piboard ]]; then
    install -m 755 /tmp/piboard /usr/local/bin/piboard
    echo "Installed piboard binary to /usr/local/bin/"
else
    echo "WARNING: /tmp/piboard not found -- copy the binary and re-run, or"
    echo "         scp it to /usr/local/bin/piboard manually"
fi

echo "=== Installing piboard config ==="
mkdir -p /etc/piboard
if [[ -f /tmp/config.yaml ]]; then
    install -m 640 -o piboard -g piboard /tmp/config.yaml /etc/piboard/config.yaml
else
    echo "WARNING: /tmp/config.yaml not found -- copy it to /etc/piboard/"
fi

echo "=== Installing systemd services ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "${SCRIPT_DIR}/piboard.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/piboard-kiosk.service" /etc/systemd/system/

# Update kiosk service to use the correct user
sed -i "s/User=pi/User=${PI_USER}/" /etc/systemd/system/piboard-kiosk.service
sed -i "s|/home/pi|/home/${PI_USER}|" /etc/systemd/system/piboard-kiosk.service

systemctl daemon-reload
systemctl enable piboard piboard-kiosk

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy the ARM binary:  scp piboard-arm pi@<ip>:/tmp/piboard"
echo "  2. Copy the config:      scp config.yaml pi@<ip>:/tmp/config.yaml"
echo "  3. Re-run this script if binaries were missing"
echo "  4. Reboot:               sudo reboot"
echo ""
echo "After reboot, the Pi will:"
echo "  - Auto-login to tty1"
echo "  - Start X11 with Openbox"
echo "  - Launch piboard service"
echo "  - Open Chromium in kiosk mode at http://localhost:8080"
