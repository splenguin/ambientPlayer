# Ambient Player

SuperCollider plays the Halloween night patch (`sc/halloween.scd`) through the
board's USB audio. The board's hardware design lives in
[splenguin/kicad](https://github.com/splenguin/kicad/tree/main/projects/ambientPlayer).
A small web page on the Pi lets you change scenes, set
levels and schedule the nightly fade in and out from your phone.

```
sc/halloween.scd     the sound: crickets, fog, drone, leaves, spirits, whispers, creaks, owls
sc/main.scd          Pi entry point: loads the patch, listens for OSC, writes status
tools/               name-usb-cards.sh: fixed names for USB sound cards
                     diagnose.sh: load, routing and logs to paste when something's wrong
web/server.py        control page and its API (Python standard library only)
web/index.html       the page itself
systemd/*.service    jackd, second-card bridge, sclang and the web page, started at boot
config.env.example   copied to /etc/default/ambient by the installer
install.sh           sets everything up
```

## Setting up a Pi

Target: Raspberry Pi 3B with Raspberry Pi OS Lite (64-bit, Bookworm or Trixie).

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
3. Clone and install. The install takes a while, so run it inside tmux; that
   way a dropped SSH connection can't kill it (`tmux attach -t install` to
   get back in):
   ```
   git clone git@github.com:splenguin/ambientPlayer.git ~/ambientPlayer
   sudo apt install -y tmux && tmux new -s install
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

### Two USB dongles instead of the board

Two cheap stereo USB dongles give the 4 outputs until the board exists. JACK
runs the first one, and `zita-j2a` adds the second as outputs 3 and 4,
resampling so the two clocks don't drift apart.

1. Plug both dongles into the USB ports you'll keep them in, then pin their
   names to those ports. Otherwise identical dongles can swap after a reboot.
   ```
   sudo ~/ambientPlayer/tools/name-usb-cards.sh
   ```
2. In `/etc/default/ambient`, set:
   ```
   AMBIENT_DEVICE=hw:ambA
   AMBIENT_CHANNELS=2
   AMBIENT_DEVICE2=hw:ambB
   AMBIENT_OUTPUTS=4
   ```
3. Run `sudo reboot`.

Outputs: ambA left = ground 1, ambA right = ground 2, ambB left = ground 3,
ambB right = the tree.

### Speaker roles and owls

Each output has a role, set by `AMBIENT_SPEAKERS` in `/etc/default/ambient`,
listed in output order:

- `ground`: on the ground. Crickets, fog, drone, leaves and creaks.
  List them in walking order round the yard; the fog and the gusts move
  from one to the next.
- `birds`: up a tree. Any owl calls here.
- `owlA`, `owlB`, ...: up a tree, and only that owl calls here.

Elevated speakers also get leaves, creaking branches, a little fog and spirits.

```
AMBIENT_SPEAKERS="ground ground ground birds"   # 3 on the ground, 1 tree (default)
AMBIENT_SPEAKERS="ground ground owlA owlB"      # 2 on the ground, one owl in each of 2 trees
```

Owls play recordings from the
[ambientSounds](https://github.com/splenguin/ambientSounds) repo (`owls/`),
which the installer clones to `~/ambientSounds`. Files are grouped into owls by
the letters at the start of their names, so `owlA_01.wav` and `owlA 2.wav`
are both owl `owlA`. An owl calls a few times from its own speaker, and
sometimes the other owl answers from its speaker. An owl with no speaker
assigned stays silent. **Birds** on the control page turns all of them on or
off, and the page lists each speaker's role and the owls it found.

After changing roles, run `sudo systemctl restart ambient-sc`. To add
recordings, commit them to ambientSounds and press **Update from GitHub**.

### Speaker test

On the control page, under **Speaker test**, each speaker beeps its number,
then plays a burst of soft noise. **Test all** goes round all of them;
a number repeats one. The ambience pauses until you press **Stop**.

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
`/solo drone`, `/trim fog 0.5`, `/master 0.6`, `/start 10`, `/stop 10`,
`/birds 0`, `/test 2`.
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
