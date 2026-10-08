#!/bin/bash
# Installs the ambient player on Raspberry Pi OS (Lite, 64-bit) and starts it
# at boot. Safe to run again after pulling changes.
#   sudo ./install.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

RUN_USER=${SUDO_USER:-pi}
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== Installing SuperCollider, JACK and git"
echo "jackd2 jackd/tweak_rt_limits boolean true" | debconf-set-selections
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  supercollider-server supercollider-supernova supercollider-language jackd2 zita-ajbridge git python3
usermod -aG audio "$RUN_USER"

echo "== Settings"
if [ ! -f /etc/default/ambient ]; then
  cp "$DIR/config.env.example" /etc/default/ambient
  echo "Created /etc/default/ambient (defaults to the Pi's headphone jack)."
else
  echo "Keeping existing /etc/default/ambient."
fi

echo "== Sounds"
SOUNDS_DIR=$(getent passwd "$RUN_USER" | cut -d: -f6)/ambientSounds
if [ ! -d "$SOUNDS_DIR/.git" ]; then
  sudo -u "$RUN_USER" git clone https://github.com/splenguin/ambientSounds.git "$SOUNDS_DIR"
else
  echo "Keeping existing $SOUNDS_DIR."
fi

echo "== Services"
for unit in "$DIR"/systemd/*.service; do
  sed -e "s|@USER@|$RUN_USER|g" -e "s|@DIR@|$DIR|g" "$unit" > "/etc/systemd/system/$(basename "$unit")"
done
# Let the web page restart SuperCollider after an update, and nothing else.
SUDOERS=/etc/sudoers.d/ambient
echo "$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart ambient-sc.service" > "$SUDOERS.tmp"
chmod 440 "$SUDOERS.tmp"
visudo -cf "$SUDOERS.tmp" && mv "$SUDOERS.tmp" "$SUDOERS"

systemctl daemon-reload
systemctl enable ambient-jack.service ambient-bridge.service ambient-sc.service ambient-web.service
systemctl restart ambient-jack.service ambient-bridge.service ambient-sc.service ambient-web.service

echo
echo "== Sound cards (put the right one in /etc/default/ambient):"
aplay -l | grep '^card' || true
echo
echo "Done. Control page: http://$(hostname).local/"
echo "Logs: journalctl -u ambient-sc -f"
