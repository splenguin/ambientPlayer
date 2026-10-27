#!/bin/bash
# Saves one or two Wi-Fi networks on the Pi (NetworkManager, Bookworm/Trixie).
# With two, a timer checks every 2 minutes and moves to the other network when
# it is clearly stronger. Passwords are typed here and stay on the Pi, in
# /etc/NetworkManager/system-connections; they never go in this repo.
#   sudo ./tools/setup-wifi.sh "SplenguiNet_2.4GHz_EXT"                 # just this one
#   sudo ./tools/setup-wifi.sh "SplenguiNet_2.4GHz_EXT" "Other network" # whichever is stronger
# Safe to run over SSH: an existing connection to the same network is updated
# in place, not dropped.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
command -v nmcli >/dev/null || { echo "NetworkManager (nmcli) not found; this needs Bookworm or later."; exit 1; }
[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,9p' "$0"; exit 1; }

DIR=$(cd "$(dirname "$0")" && pwd)
nmcli radio wifi on

# Drop our old connections for networks no longer listed (e.g. going from two to one).
for c in $(nmcli -g NAME connection show | grep '^ambient-wifi-' || true); do
  ssid=$(nmcli -g 802-11-wireless.ssid connection show "$c")
  keep=0; for s in "$@"; do [ "$s" = "$ssid" ] && keep=1; done
  [ $keep -eq 1 ] || { echo "Removing $c ($ssid)"; nmcli connection delete "$c" >/dev/null; }
done

n=1
for ssid in "$@"; do
  name=ambient-wifi-$n
  # Reuse any saved connection for this network, such as the one Raspberry Pi
  # Imager made ("preconfigured"), so there is only one per network.
  existing=""
  while IFS=: read -r cname ctype; do
    [ "$ctype" = 802-11-wireless ] || continue
    [ "$(nmcli -g 802-11-wireless.ssid connection show "$cname")" = "$ssid" ] && { existing=$cname; break; }
  done < <(nmcli -t -f NAME,TYPE connection show)

  if [ -n "$existing" ]; then
    read -rsp "Password for $ssid (Enter keeps the saved one): " pw; echo
    [ "$existing" = "$name" ] || nmcli connection modify "$existing" connection.id "$name"
  else
    read -rsp "Password for $ssid: " pw; echo
    nmcli connection add type wifi ifname wlan0 con-name "$name" ssid "$ssid" >/dev/null
  fi
  nmcli connection modify "$name" connection.autoconnect yes connection.autoconnect-priority 10 \
    connection.autoconnect-retries 0 802-11-wireless.band bg
  if [ -n "$pw" ]; then
    nmcli connection modify "$name" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pw"
  fi
  echo "Saved $ssid as $name"
  n=$((n + 1))
done
unset pw

# Any other saved Wi-Fi networks go below ours, so they're only a last resort.
while IFS=: read -r cname ctype; do
  [ "$ctype" = 802-11-wireless ] && [[ "$cname" != ambient-wifi-* ]] && \
    nmcli connection modify "$cname" connection.autoconnect-priority 0
done < <(nmcli -t -f NAME,TYPE connection show)

if [ $# -eq 2 ]; then
  cat > /etc/systemd/system/ambient-wifi-pick.service <<UNIT
[Unit]
Description=Move to the stronger of the two saved Wi-Fi networks
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=$DIR/wifi-pick.sh
UNIT
  cat > /etc/systemd/system/ambient-wifi-pick.timer <<UNIT
[Unit]
Description=Check Wi-Fi signal every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload
  systemctl enable --now ambient-wifi-pick.timer
  echo "Picking the stronger network every 2 minutes (journalctl -u ambient-wifi-pick)."
else
  systemctl disable --now ambient-wifi-pick.timer 2>/dev/null || true
  rm -f /etc/systemd/system/ambient-wifi-pick.{service,timer}
  systemctl daemon-reload
fi

echo
nmcli -f NAME,AUTOCONNECT-PRIORITY,DEVICE connection show | grep -E 'NAME|wifi|wlan' || true
