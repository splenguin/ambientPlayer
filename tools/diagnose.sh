#!/bin/bash
# Prints what's needed to debug sound and load problems. Paste the output into the chat.
#
#   ~/ambientPlayer/tools/diagnose.sh            report only, sound keeps running
#   ~/ambientPlayer/tools/diagnose.sh --speakers also stops the player and plays
#                                                "Front Left"/"Front Right" on each
#                                                card straight through ALSA, then
#                                                restarts the player

section() { echo; echo "===== $1"; }

section "load and power"
uptime
command -v vcgencmd >/dev/null && { vcgencmd measure_temp; vcgencmd get_throttled; }
top -bn1 -o %CPU | sed -n '7,17p'

section "services"
for u in ambient-jack ambient-bridge ambient-sc ambient-web; do
	printf '%-16s %s\n' "$u" "$(systemctl is-active $u)"
done

section "config"
grep -v '^\s*#' /etc/default/ambient | grep -v '^\s*$'

section "cards"
aplay -l | grep '^card'

section "card volumes"
. /etc/default/ambient
for d in "$AMBIENT_DEVICE" $AMBIENT_DEVICE2; do
	echo "--- $d"; amixer -c "${d#*:}" 2>&1 | grep -E "control|Playback.*\[" | head -8
done

section "JACK connections"
jack_lsp -c 2>&1 | head -40

section "SuperCollider status"
cat /run/ambient/status.json 2>/dev/null | head -c 600; echo

section "logs"
journalctl -u ambient-jack -u ambient-bridge -u ambient-sc --since "-15 min" --no-pager -o cat 2>/dev/null \
	| grep -iv '^$' | tail -40

if [ "$1" = "--speakers" ]; then
	section "speaker test without SuperCollider"
	sudo systemctl stop ambient-sc ambient-bridge ambient-jack
	for dev in "$AMBIENT_DEVICE" $AMBIENT_DEVICE2; do
		echo "--- ${dev}: you should hear Front Left, then Front Right"
		speaker-test -D "plug${dev#plug}" -c 2 -t wav -l 1 2>&1 | grep -i 'front\|error'
	done
	sudo systemctl start ambient-jack ambient-bridge ambient-sc
	echo "player restarted"
fi
