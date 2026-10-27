#!/bin/bash
# Run by ambient-wifi-pick.timer (set up by setup-wifi.sh). Connects to
# whichever saved ambient-wifi-* network is strongest, but only leaves the
# current one when the other is MARGIN points stronger (signal is 0-100), so
# it doesn't flip back and forth.
set -uo pipefail
MARGIN=15
IF=wlan0

declare -A conn_for   # SSID -> our connection name
for c in $(nmcli -g NAME connection show | grep '^ambient-wifi-'); do
  conn_for[$(nmcli -g 802-11-wireless.ssid connection show "$c")]=$c
done
[ ${#conn_for[@]} -ge 1 ] || exit 0

nmcli device wifi rescan ifname "$IF" 2>/dev/null && sleep 5

declare -A signal     # SSID -> strongest access point seen
current=""
while IFS=: read -r sig active ssid; do
  [ -n "${conn_for[$ssid]+x}" ] || continue
  [ "${signal[$ssid]:-0}" -ge "$sig" ] || signal[$ssid]=$sig
  [ "$active" = yes ] && current=$ssid
done < <(nmcli -t -e no -f SIGNAL,ACTIVE,SSID device wifi list ifname "$IF")

best=""
for s in "${!signal[@]}"; do
  [ -z "$best" ] || [ "${signal[$s]}" -gt "${signal[$best]}" ] && best=$s
done
[ -n "$best" ] || { echo "Neither network in range"; exit 0; }

if [ -z "$current" ]; then
  echo "Not connected; joining $best (${signal[$best]})"
elif [ "$best" != "$current" ] && [ "${signal[$best]}" -ge $(( ${signal[$current]:-0} + MARGIN )) ]; then
  echo "Moving from $current (${signal[$current]:-0}) to $best (${signal[$best]})"
else
  exit 0
fi
nmcli connection up "${conn_for[$best]}" ifname "$IF"
