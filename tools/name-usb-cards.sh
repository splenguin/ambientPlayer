#!/bin/bash
# Gives each plugged-in USB sound card a fixed name tied to the USB port it's
# in: the first becomes ambA, the second ambB, and so on. Identical dongles
# otherwise get "Device" and "Device_1" in whatever order they start, which
# can swap your speakers after a reboot.
#
# Plug the dongles into the ports you'll keep them in, then:
#   sudo ./tools/name-usb-cards.sh && sudo reboot
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

RULES=/etc/udev/rules.d/85-ambient-usb-cards.rules
names=(ambA ambB ambC ambD)
i=0
: > "$RULES.tmp"
for card in $(ls -d /sys/class/sound/card[0-9]* | sort -V); do
  usbdev=$(dirname "$(readlink -f "$card/device")")
  [ -f "$usbdev/idVendor" ] || continue          # not a USB card
  port=$(basename "$usbdev")
  name=${names[$i]}
  echo "SUBSYSTEM==\"sound\", KERNEL==\"card*\", KERNELS==\"$port\", ATTR{id}=\"$name\"" >> "$RULES.tmp"
  echo "$(cat "$card/id") on USB port $port -> hw:$name"
  i=$((i + 1))
  [ $i -lt ${#names[@]} ] || break
done
if [ $i -eq 0 ]; then
  rm -f "$RULES.tmp"; echo "No USB sound cards found."; exit 1
fi
mv "$RULES.tmp" "$RULES"
echo "Wrote $RULES. Reboot for the names to take effect."
