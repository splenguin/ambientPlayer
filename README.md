# Ambient Player

SuperCollider plays the Halloween night patch (`sc/halloween.scd`) through the
board's USB audio. The board's hardware design lives in
[splenguin/kicad](https://github.com/splenguin/kicad/tree/main/projects/ambientPlayer).
A small web page on the Pi lets you change scenes, set
levels and schedule the nightly fade in and out from your phone.

```
sc/halloween.scd     the sound: crickets, fog, drone, cornfield, spirits, creeper
sc/main.scd          Pi entry point: loads the patch, listens for OSC, writes status
web/server.py        control page and its API (Python standard library only)
web/index.html       the page itself
systemd/*.service    jackd, sclang and the web page, started at boot
config.env.example   copied to /etc/default/ambient by the installer
install.sh           sets everything up
```

## Setting up a Pi

Target: Raspberry Pi 3B with Raspberry Pi OS Lite (64-bit, Bookworm).

1. Flash Raspberry Pi OS Lite (64-bit) with Raspberry Pi Imager. In its
   settings, set the hostname (this guide uses `ambientPlayer`), create your user, enable SSH and
   enter your Wi-Fi.
2. SSH in (`ssh you@ambientPlayer.local`), run `sudo apt install -y git`, and give the Pi read access to this repo,
   which is private:
   ```
   ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
   cat ~/.ssh/id_ed25519.pub
   ```
   On GitHub, open the repo's Settings, then Deploy keys, then Add deploy key.
   Paste the key and leave "Allow write access" off.
3. Clone and install:
   ```
   git clone git@github.com:splenguin/ambientPlayer.git ~/ambientPlayer
   sudo ~/ambientPlayer/install.sh
   ```
4. Open `http://ambientPlayer.local/` on your phone.

It starts on the Pi's headphone jack in stereo, so you can try it before the
board exists. Once the board is plugged in, run `aplay -l` to find its card
name, then edit `/etc/default/ambient`:
```
AMBIENT_DEVICE=hw:<card name>
AMBIENT_CHANNELS=8
AMBIENT_OUTPUTS=4
```
Then run `sudo systemctl restart ambient-jack`. SuperCollider restarts with it.

## Changing the sound

Edit the `.scd` files on your desktop, try them in the SuperCollider IDE, then
commit and push to `main`. On the phone page, press **Update from GitHub**.
The Pi pulls the change and restarts SuperCollider, which takes about 20
seconds of silence.

For quick experiments on the Pi itself, VS Code's Remote-SSH extension can
open `~/ambientPlayer` directly. After editing there, run
`sudo systemctl restart ambient-sc`.

## Controlling it without the page

`sc/main.scd` takes OSC on UDP port 57120: `/scene deepFog`, `/auto`,
`/solo drone`, `/trim fog 0.5`, `/master 0.6`, `/start 10`, `/stop 10`.
Any OSC app (TouchOSC, Open Stage Control) can send these.

The web page has no password. Keep it on your home network. For access from
away, use Tailscale rather than forwarding a port.

## Pi 3B notes

- **Power:** the 3B takes micro-USB, while the board's Pi output is USB-C. Use
  a short, thick USB-C to micro-USB cable. If `vcgencmd get_throttled` prints
  anything other than `throttled=0x0`, the Pi is seeing undervoltage.
- **CPU:** SuperCollider's audio engine runs on one core. The page shows its
  load. Above about 70% peak, expect dropouts. If that happens, lower the
  cricket count in `halloween.scd` (`ground * 3`) first.
- **Clicks:** the 3B's USB port shares its bus with Ethernet. If you hear
  clicks, set `AMBIENT_PERIOD=2048` in `/etc/default/ambient`.
- **Wi-Fi:** the 3B only does 2.4 GHz.

## Logs

```
journalctl -u ambient-sc -f      # SuperCollider: scene changes, errors
journalctl -u ambient-jack -f    # audio device problems
journalctl -u ambient-web -f     # web page
```
