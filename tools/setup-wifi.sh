#!/bin/bash
# Saves one or two Wi-Fi networks on the Pi (NetworkManager, Bookworm/Trixie).
# A timer checks every 2 minutes: it rejoins if the Pi has dropped off (the 3B
# can fail a handshake on a weak signal, after which NetworkManager stops
# trying), and with two networks it moves to the other one when it is clearly
# stronger. Passwords are typed here and stay on the Pi, in
# /etc/NetworkManager/system-connections; they never go in this repo.
#   sudo ./tools/setup-wifi.sh "SplenguiNet_2.4GHz_EXT"                 # just this one
#   sudo ./tools/setup-wifi.sh "SplenguiNet_2.4GHz_EXT" "Other network" # whichever is stronger
# It also turns off Wi-Fi power saving, which makes the 3B's Wi-Fi drop off
# and not come back, and tells NetworkManager to never stop retrying.
# Safe to run over SSH: an existing connection to the same network is updated
# in place, not dropped.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
command -v nmcli >/dev/null || { echo "NetworkManager (nmcli) not found; this needs Bookworm or later."; exit 1; }
[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,11p' "$0"; exit 1; }

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
    connection.autoconnect-retries 0 802-11-wireless.band bg 802-11-wireless.powersave 2
  if [ -n "$pw" ]; then
    nmcli connection modify "$name" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pw"
  fi
  # The 3B's Wi-Fi chip handles protected management frames badly, which shows
  # up as handshake timeouts with some routers and extenders.
  if [ "$(nmcli -g 802-11-wireless-security.key-mgmt connection show "$name")" = wpa-psk ]; then
    nmcli connection modify "$name" wifi-sec.pmf disable
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

cat > /etc/systemd/system/ambient-wifi-pick.service <<UNIT
[Unit]
Description=Rejoin Wi-Fi, or move to the stronger saved network
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
echo "Checking Wi-Fi every 2 minutes (journalctl -u ambient-wifi-pick)."

echo
nmcli -f NAME,AUTOCONNECT-PRIORITY,DEVICE connection show | grep -E 'NAME|wifi|wlan' || true
