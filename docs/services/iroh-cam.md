# iroh-cam

An ESP32-CAM on Wi-Fi streams JPEG frames over iroh (encrypted QUIC, dialed
by endpoint id). The viewer service on trigkey dials it and serves the stream
as MJPEG on the LAN at **http://cam.local**.

- Source: `~/iroh-cam` (firmware, viewer, flash script). Its README has the
  protocol, the build settings and the flash steps.
- Module: `hosts/nixos/optional/iroh-cam.nix`. Port 4230 on 127.0.0.1.
- The camera board is plugged into **gmktec** (`/dev/ttyUSB0`) for flashing
  and power. It reaches the network over Wi-Fi (`slowguy`, 2.4 GHz).

## Use

| URL | What |
|-----|------|
| `http://cam.local/` | Full-window live view |
| `http://cam.local/stream` | Raw MJPEG, for VLC or another player |
| `http://cam.local/snapshot.jpg` | One fresh frame |

The viewer dials the camera only while a page is open, and hangs up 10 s after
the last one closes. The first frame takes about 5 s.

## Access

- **iroh side:** the camera admits only the endpoint ids in its build-time
  `ALLOWED_VIEWERS`. trigkey's viewer key (`~/.config/iroh-cam/viewer.key`,
  id `01764596…0982`) is the only one now. Another viewer (a phone app, a
  laptop) needs its id added and a reflash.
- **LAN side:** plain HTTP with no login. Anyone on the LAN can watch. Do not
  expose it through Pangolin.

## Fix

| Symptom | Check |
|---------|-------|
| Page loads, no picture | `journalctl -u iroh-cam -n 30`. "connect timed out": the camera is off or off Wi-Fi. "refused the stream": the viewer key is not in `ALLOWED_VIEWERS`. |
| Camera state unknown | On gmktec: `~/iroh-cam/scripts/fw.sh monitor` (resets the board) shows Wi-Fi, the endpoint id and errors. |
| Service fails at start | The binary is missing or was built against an old glibc: `cargo build --release` in `~/iroh-cam` (workspace root), then `sudo systemctl restart iroh-cam`. |
| Ticket changed after a firmware rebuild | Update `ticket` in the module from the new "Short ticket" line, then `rebuild`. |
