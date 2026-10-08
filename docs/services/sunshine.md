# Sunshine

Sunshine streams a screen on gmktec to a Moonlight client over the LAN. gmktec is headless, so `gmktec/sunshine.nix` also runs a headless sway session for Sunshine to capture, and a USB capture card puts a physical Nintendo Switch into that session.

Sunshine is the **host**, Moonlight is the **client**. There is no web player — the client is a native app on the machine you want to watch from. `moonlight-embedded` is installed on gmktec only so `moonlight list 127.0.0.1` can verify the host from an SSH shell.

| Item | Value |
|------|-------|
| Web UI | `https://192.168.0.51:47990`, HTTPS only, self-signed, HTTP basic auth |
| Ports | 47984, 47989, 47990, 48010 TCP; 47998-48000, 48002, 48010 UDP. LAN only |
| Module | `hosts/nixos/gmktec/sunshine.nix` |
| Capture card | UltraSemi "USB3 Video", UVC + USB Audio, `/dev/video0`, on a 5 Gbps port |
| Session | `sway-headless.service`, one virtual output at 1920x1080 |
| Encoder | `h264_vaapi` / `hevc_vaapi` on `/dev/dri/renderD128` |
| State | `~eric/.config/sunshine/`. Not backed up — re-pairing takes under a minute |

Use the IP, not `gmktec.local`. Avahi announces per interface and the name can resolve to the podman bridge (`10.88.0.1`) instead of the LAN address.

No portless alias: portless runs with `tls = false` and proxies plain HTTP, and 47990 speaks TLS only, so an alias would serve a protocol error. No Pangolin route either — streaming is latency-bound UDP and the tunnel adds a round trip to a VPS in another city.

## Watch the Switch from a laptop

Time: about 5 minutes, most of it installing the client.

1. On the client, install Moonlight — `brew install --cask moonlight`, or a build from [moonlight-stream.org](https://moonlight-stream.org).
2. Open `https://192.168.0.51:47990`, accept the self-signed certificate, and log in as `eric`.
3. Open Moonlight. gmktec appears over mDNS; if it does not, add `192.168.0.51` by hand.
4. Click the gmktec tile for a PIN, then type that PIN into the web UI's **PIN** tab. It expires in about a minute.
5. Pick **Switch** for the capture card, **Desktop** for the bare sway session, or **Automation** for [Pokémon Automation](pokemon-automation.md). **Switch** and **Automation** both need the capture card, so only one of them can run. If another program holds `/dev/video0`, **Switch** refuses to start (see Troubleshooting).

All three apps are declared in `services.sunshine.applications` (**Automation** in `gmktec/pokemon-automation.nix`), which turns off app editing in the web UI. Add an app by editing the module, not the browser.

The generated config points `file_apps` at a store path, so `~/.config/sunshine/apps.json` is not read. If one appears there, Sunshine wrote it before the apps were declarative and it is dead — delete it rather than editing it.

## Controlling the Switch too

Sunshine only carries video and audio *out* of the Switch. [NXBT](nxbt.md) on trigkey is the other half — it makes trigkey's Bluetooth adapter act as a Pro Controller, so the two together are remote play of a physical console. They share nothing but the Switch itself, and neither needs the other to work.

In the **Switch** app, the keyboard drives the Switch through the ESP32-S3 wired controller. The app's second prep-cmd turns on ace-typer's live keys (`POST http://127.0.0.1:8171/api/live`), and its undo turns them off, which also frees the board's serial port for Pokémon Automation. ace-typer reads the `Keyboard passthrough` device directly and uses PA's key map: arrows = D-pad, `Enter` = A, `Shift` = B, `'` = X, `/` = Y, `Q`/`E` = L/R, `=`/`-` = +/−, `Home`/`Esc`/`H` = HOME. A legend and a status line are drawn on mpv through its IPC socket (`$XDG_RUNTIME_DIR/mpv-switch.sock`); `F1` hides the legend. mpv runs with `--input-vo-keyboard=no --no-input-default-bindings`, so `q` no longer quits the player. Keys pause while ace-typer types a code, and do nothing while PA runs: PA holds the board. See [Pokémon Automation](pokemon-automation.md#one-device-two-users).

## Capture card

The card presents two UVC video interfaces, two USB Audio interfaces and a HID interface. `/dev/video0` is the capture node; `/dev/video1` belongs to the same device and enumerates no formats.

`v4l2-ctl -d /dev/video0 --list-formats-ext` reports `YUYV` and `MJPG`, both up to 1920x1080@60. The module takes **YUYV**, uncompressed: raw 1080p60 4:2:2 needs about 2 Gbps and the port gives 5, so taking it raw drops a JPEG encode on the card and a decode on gmktec. Move the card to a 480 Mbps port and `input_format` has to become `mjpeg`.

`video_size` and `framerate` are both set explicitly. With neither, ffmpeg's v4l2 demuxer takes the driver default of 640x480.

The card has no `VIDIOC_QUERY_DV_TIMINGS`, so there is no way to ask it whether an HDMI signal is present. Looking at the stream is the only test.

### Check the capture without a client

```bash
mpv --no-config --ao=null --frames=1 --o=/tmp/frame.png \
  --demuxer-lavf-o=input_format=yuyv422,video_size=1920x1080,framerate=60 \
  av://v4l2:/dev/video0
```

A working 1080p60 capture writes a PNG of roughly 1 MB. A few KB means the frame is flat black: the Switch is off, asleep, undocked, or the HDMI cable is in the card's `OUT`.

`ioctl(VIDIOC_QBUF): Bad file descriptor` repeated on exit is the v4l2 demuxer returning buffers after the fd closed. It is teardown noise, not a capture failure.

## Audio

HDMI carries the Switch's audio, so the card exposes it as a USB Audio source. Sunshine only ever reads `sunshine-sink.monitor`, so a PipeWire loopback plays that source into the null sink:

```
alsa_input.usb-UltraSemi_USB3_Video_20210623-02.analog-stereo
  → capture-card-loopback-in → capture-card-loopback-out → sunshine-sink
```

`pw-link -l` shows the whole chain. `target.object` in the module is the node name WirePlumber derives from the card's USB serial, so a different capture card means a new name — and the symptom is video with silence.

The Switch home menu has no background music. Silence there is normal; start a game before concluding anything is broken.

## The `audio` group

gmktec is the only host in the fleet where `eric` needs the `audio` group.

`/dev/snd/*` is `root:audio` mode 0660. On a desktop, logind grants the logged-in user access through a uaccess ACL and the group never matters. This host has no seat and nobody logs in, so no ACL is ever applied — WirePlumber enumerates **zero** devices and Sunshine streams silence, while `/proc/asound/cards` shows every card fine.

A group change does not reach the running services. The systemd **user manager** caches its credentials from when it started, and PipeWire inherits them, so restarting `pipewire` or `sway-headless` keeps the old group list:

```bash
sudo systemctl restart user@1000.service   # linger brings sway + sunshine back
```

Confirm it took with `grep ^Groups /proc/$(pgrep -u eric -x pipewire)/status`. The `audio` gid is 17.

## Why these units exist

Nothing on a headless box starts `graphical-session.target`, which is what the upstream `sunshine.service` is wanted by. So `autoStart = false`, and sway's config `exec`s a script that hands `WAYLAND_DISPLAY` to the user manager and starts Sunshine itself. `users.users.eric.linger` in `../common` is what gives eric a user manager at boot with nobody logged in.

Two consequences that look like bugs:

- **`path = [ pkgs.bash ]` on `sway-headless`.** sway runs every `exec` through `execlp("sh", ...)`, and NixOS gives systemd user units a minimal PATH with no shell. Without it: `execve failed: No such file or directory`.
- **`sunshine.service` `wants` pipewire.** PipeWire's user units are socket-activated, so nothing starts them without a login. `after` alone does not pull them up, and Sunshine would come up first and find zero sinks.

`hardware.uinput.enable` is also load-bearing. The nixpkgs sunshine derivation patches out `find_package(Udev)` and ships no `rules.d`, so the module's `services.udev.packages` is a no-op; without uinput enabled, `/dev/uinput` is root-only and Moonlight's mouse, keyboard and gamepad silently do nothing while video streams fine.

uinput alone is not enough. Sunshine creates its devices (`Mouse passthrough`, `Mouse passthrough (absolute)`, `Keyboard passthrough`) when it starts, but sway reads them only through its libinput backend. With `WLR_BACKENDS=headless` alone, `swaymsg -t get_inputs` printed `[]` and no click reached a window. So:

- `WLR_BACKENDS=headless,libinput` adds the backend.
- `LIBSEAT_BACKEND=noop` lets it open devices without a logind seat, with eric's own permissions.
- A udev rule makes eric the `OWNER` of every `* passthrough*` event node. The `input` group would also give sway the power button, and it reaches the user manager only after a restart.

Check: `swaymsg -t get_seats` shows `capabilities: 3` (pointer + keyboard). `Permission denied` lines for other `/dev/input/event*` in the sway log are expected.

Gamepads take a second udev rule. Sunshine names them `Sunshine X-Box One (virtual) pad`, `Sunshine Nintendo (virtual) pad` or `Sunshine PS5 (virtual) pad`, so none of them match `* passthrough*`, and it creates the node only when a client with a gamepad connects — so the node is absent until then and the gap does not show in `ls /dev/input`. sway is not what reads it (libinput ignores joysticks); the rule is for whatever reads evdev inside the session. Nothing on gmktec uses a gamepad today.

## Expect this latency

Roughly 50-90 ms end to end on the LAN: the card's own digitising, then one VAAPI encode, the network, and the client's decode. Fine for most single-player games, wrong for anything needing frame-accurate input.

Taking the capture raw removed the JPEG round trip that would otherwise add to this. The remaining big variable is the card.

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| Host never appears in Moonlight | mDNS blocked. Add `192.168.0.51` by hand |
| PIN rejected | It expired. Click the tile for a new one |
| Mouse and keyboard do nothing | `swaymsg -t get_inputs` is empty. Restart `sunshine` after `sway-headless`, so its devices appear after sway's libinput backend is up, and check the udev rule gave eric the `* passthrough*` nodes |
| Blank grey screen on **Desktop** | Expected. `swayConfig` replaces sway's shipped `/etc/sway/config`, bindings included, and the session has no terminal |
| **Switch** fails: "Failed to start the specified application" | Another program holds `/dev/video0` and the `cardFree` prep-cmd refused the launch. `journalctl --user -t switch-capture-card-free` names the holder. `mpv` is a **Switch** session you disconnected from without quitting — Moonlight keeps the app running so you can resume it, and it keeps the card: quit the app from Moonlight, or `systemctl --user restart sunshine`. `AppRun.wrapped` is Pokémon Automation: `systemctl --user stop pokemon-automation`. Sunshine's own log says only `failed with code [1]` — it discards a prep-cmd's output. Without this check, mpv exited at once and Sunshine crashed (SEGV in its encoder) |
| Black screen on **Switch**, Desktop fine | No HDMI signal. Check the Switch is docked and awake, and that the cable is in the card's `IN` |
| Video but no audio | Either the home menu (silent by design) or `target.object` no longer matches the card's node name |
| Stutter under load | Jellyfin shares `/dev/dri/renderD128`. A transcode and a stream compete |
| Keys do nothing on **Switch** | The overlay's status line says why. "Pokémon Automation has the board": stop PA. No overlay at all: `systemctl --user status ace-typer`, and check that the app was launched after the last Sunshine restart (the prep-cmd turns keys on). The Switch must read the board as player 1 |
