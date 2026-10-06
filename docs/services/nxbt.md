# NXBT

NXBT makes trigkey's Bluetooth adapter act as a Nintendo Switch Pro Controller. You control it from a web page, a macro, or a terminal UI. It runs as the `nxbt` systemd service on trigkey.

| Item | Value |
|------|-------|
| Web app | `127.0.0.1:8170`, no auth. Use an SSH tunnel. |
| Module | `hosts/nixos/trigkey/nxbt.nix` |
| Upstream | [Brikwerk/nxbt](https://github.com/Brikwerk/nxbt) at `ec4b800` (2023-07-04), Python 3.13, current nixpkgs dependencies |
| Adapter | `hci0`, Intel AX200, in trigkey |
| State | `/var/lib/nxbt/secrets.txt` (Flask session secret). Not backed up. |

## Test it with a Switch 2

Time: about 10 minutes for the first pairing.

You need:

- The Switch 2 at a maximum of 5 m from trigkey, with no wall between them.
- A laptop that can SSH to trigkey.
- A second terminal on trigkey (SSH is fine).

### 1. Open the web app

On the laptop:

```bash
ssh -N -L 8170:127.0.0.1:8170 eric@192.168.0.202
```

Keep it open. In a browser on the laptop, open `http://localhost:8170`. Use `localhost`, not the LAN IP. Browsers permit the Gamepad API only on a secure origin, and `localhost` is one.

### 2. Start a pairing agent on trigkey

The Switch 2 asks the controller to accept pairing. NXBT does not accept it. You must accept it yourself.

In the second terminal:

```bash
sudo bluetoothctl
```

At the `[bluetooth]#` prompt:

```
agent on
default-agent
```

Keep this terminal open.

### 3. Open "Change Grip/Order" on the Switch 2

On the Switch 2 Home screen, select **Controllers**, then **Change Grip/Order**. Keep the Switch on this screen.

### 4. Create the controller

In the web app, select **Pro Controller** under **Create a Controller**.

The adapter changes its name to "Pro Controller" and becomes discoverable.

### 5. Accept the pairing

Look at the `bluetoothctl` terminal. When a prompt such as `Accept pairing (yes/no):` or `Authorize service ... (yes/no):` appears, type:

```
yes
```

Find the Switch's MAC address in a line like `[NEW] Device AA:BB:CC:DD:EE:FF Nintendo Switch`. Then trust it, so that it reconnects without a prompt:

```
trust AA:BB:CC:DD:EE:FF
```

The Switch 2 shows a new Pro Controller. The web app shows the controller as `connected`.

### 6. Press buttons

Click the web page so that it has focus. Then use the keyboard:

| Switch | Key |
|--------|-----|
| A, B, X, Y | `L`, `K`, `I`, `J` |
| Left stick | `W` `A` `S` `D`, press `T` |
| Right stick | Arrow keys, press `Y` |
| D-pad up, left, down, right | `G`, `V`, `B`, `N` |
| L, ZL, R, ZR | `1`, `2`, `9`, `8` |
| Plus, Minus | `6`, `7` |
| Home, Capture | `[`, `]` |

Test: press `K` (B). The Switch 2 leaves the Change Grip/Order screen. Press `[` (Home). The Home screen opens.

A browser gamepad also works. Select it under **Input Device**.

### 7. Run a macro (optional)

The web app has a **Controller Macro** box. Paste this and select **Run Macro**. It presses Home, waits, then moves right twice:

```
HOME 0.1s
1.0s
DPAD_RIGHT 0.1s
0.3s
DPAD_RIGHT 0.1s
0.3s
```

To run a macro from the terminal, stop the service first. Two NXBT instances cannot share the adapter:

```bash
sudo systemctl stop nxbt
sudo nxbt macro -r -c "HOME 0.1s
1.0s"
sudo systemctl start nxbt
```

`-r` reconnects to a Switch that paired before. For a reconnect, the Switch must be on the Home screen, not on Change Grip/Order.

## Problems

### Status "crashed"

This is normal after one of these:

- The Switch went to sleep, or the Bluetooth link dropped.
- The browser lost its socket. The web app then removes the controller. Causes: the tab closed, the laptop went to sleep, or the SSH tunnel stopped.

To connect again:

1. Put the Switch 2 on the **Home** screen. Do not use Change Grip/Order: the Switch already knows this controller.
2. Reload `http://localhost:8170`. If the tunnel stopped, start it again first.
3. Select **Pro Controller**. NXBT reconnects to the last Switch.

If the page shows `No adapters available`, or nothing changes, restart the service:

```bash
sudo systemctl restart nxbt
```

Then do steps 1 to 3 again. To keep the tunnel open while you are away, add `-o ServerAliveInterval=30` to the `ssh` command.

### Other problems

Try these in order:

1. **The Switch shows nothing.** Run `bluetoothctl show`. You must see `Alias: Pro Controller` and `Discoverable: yes`. If not, select **Recreate Controller** in the web app.
2. **The Switch stays on "connecting".** Look for a pairing prompt in `bluetoothctl` (step 2). The agent must be on before you create the controller.
3. **The Switch forgets the controller after a disconnect.** Do steps 3 to 5 again, and do the `trust` step.
4. **The controller disconnects when you leave Change Grip/Order.** Disconnect the Joy-Con 2 controllers, then pair again. Reports say that the Switch 2 sometimes stops sending pairing requests when other controllers connected first.
5. **Read the logs:** `journalctl -u nxbt -n 50` and `journalctl -u bluetooth -n 50`.

If NXBT cannot pair at all, try [NUXBT](https://github.com/hannahbee91/nuxbt), a maintained fork (last release v3.3.7, 2026-08). It needs a Node build for its React UI, so it is not packaged here.

## How the module differs from upstream

- **bluetoothd flags.** NXBT needs `--compat --noplugin=*`. Upstream writes a systemd override from `/lib/systemd/system/bluetooth.service`, which does not exist on NixOS. The module sets the flags in `systemd.services.bluetooth` and patches the runtime toggle out.
- **All bluetoothd plugins are off on trigkey.** Bluetooth keyboards, mice, and audio do not work on trigkey. Nothing else on trigkey uses Bluetooth.
- **Session secret.** Upstream writes it next to its source, in the read-only Nix store. A patch moves it to `NXBT_STATE_DIR` (`/var/lib/nxbt`).
- **Dependencies.** Upstream pins 2021 versions. The package uses current nixpkgs versions. `pynput` is removed: only the TUI's direct-keyboard mode uses it, and that mode needs X11.
- **Stability patch** (`hosts/nixos/trigkey/nxbt-stability.patch`). Without it, one crashed controller can make the web app show `No adapters available` until a restart. The patch keeps the command manager running when one request fails and makes controller removal safe to run twice. A failed controller create now ends as `crashed` (30 s limit) instead of freezing the web app. Each process now opens its own D-Bus connection, because a connection shared across a fork was closed by dbus-daemon ("Connection is closed"). It also fixes the SIGTERM handler, removes a call to a method that does not exist (`BlueZ.reset_address`), and ignores a D-Bus race when a device disappears. If the shared state is lost anyway, the web process exits and systemd restarts it.
