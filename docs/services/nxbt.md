# NXBT

NXBT makes trigkey's Bluetooth adapter act as a Nintendo Switch Pro Controller. You control it from a web page, a macro, or a terminal UI. It runs as the `nxbt` systemd service on trigkey.

NXBT is optional. The default controller is a wired board on gmktec, and the video comes from Sunshine there: see [Nintendo Switch](switch.md). NXBT shares nothing with them but the console.

| Item | Value |
|------|-------|
| Web app | `http://nxbt.local` on the LAN (keyboard, ACE panel). A browser gamepad needs the SSH tunnel to `127.0.0.1:8170`. No auth. |
| Module | `hosts/nixos/trigkey/nxbt.nix` |
| Upstream | [Brikwerk/nxbt](https://github.com/Brikwerk/nxbt) at `ec4b800` (2023-07-04), Python 3.13, current nixpkgs dependencies |
| Adapter | `hci0`, Intel AX200, in trigkey |
| State | `/var/lib/nxbt/secrets.txt` (Flask session secret). Not backed up. |

## Test it with a Switch 2

Time: about 10 minutes for the first pairing.

You need:

- The Switch 2 at a maximum of 5 m from trigkey, with no wall between them.
- A laptop that can SSH to trigkey.
- The Switch's Bluetooth address in `switchAddresses` in `hosts/nixos/trigkey/nxbt.nix`. The `nxbt-agent` service accepts pairing only from these addresses. To find a new Switch's address, pair once and read `journalctl -u nxbt-agent` (`reject ... from AA:BB:...`).

### 1. Open the web app

On the laptop:

```bash
ssh -N -L 8170:127.0.0.1:8170 eric@192.168.0.202
```

Keep it open. In a browser on the laptop, open `http://localhost:8170`. Use `localhost`, not the LAN IP. Browsers permit the Gamepad API only on a secure origin, and `localhost` is one. For the keyboard only, open `http://nxbt.local` instead; you need no tunnel.

### 2. Open "Change Grip/Order" on the Switch 2

On the Switch 2 Home screen, select **Controllers**, then **Change Grip/Order**. Keep the Switch on this screen.

### 3. Create the controller

In the web app, select **Pro Controller** under **Create a Controller**.

The adapter changes its name to "Pro Controller" and becomes discoverable.

### 4. Wait for the pairing

The Switch 2 asks the controller to confirm pairing. `nxbt-agent` confirms it for the allowed address (`journalctl -u nxbt-agent` shows `accept confirmation ...`).

The Switch 2 shows a new Pro Controller. The web app shows the controller as `connected`.

### 5. Press buttons

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

### 6. Run a macro (optional)

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

## Type an ACE box code

The page has an **ACE Box Codes** panel below "Controller Macro". It uses [ace-typer](https://github.com/ericsharma/ace-typer) (flake input `ace-typer`).

1. Connect the controller. Open FireRed: PC → **MOVE POKéMON**, cursor on the title of the first box to type, hand empty.
2. Paste the code: [CodeGenerator](https://e-sh4rk.github.io/CodeGenerator/index_frlg.html?lang=eng10) output, a character code, or a Hex Writer code.
3. Select **Preview**. Check the table. With CodeGenerator's "Raw data", every name is checked byte for byte.
4. Choose **Start at**, then select **Type code**. Don't use the keyboard on the page while it types; that pauses the macro.
5. **Stop** cancels the macro and releases all buttons.

To update ace-typer: `nix flake update ace-typer`, then deploy trigkey and gmktec. Both use `pkgs.ace-typer`.

## Problems

### Status "crashed"

This is normal after one of these:

- The Switch went to sleep, or the Bluetooth link dropped.
- The browser lost its socket. The web app then removes the controller. Causes: the tab closed, the laptop went to sleep, or the SSH tunnel stopped.

To connect again:

1. Put the Switch 2 on the **Home** screen. Do not use Change Grip/Order: the Switch already knows this controller. The Switch pairs with "No Bonding", so this is a new pairing each time; `nxbt-agent` confirms it.
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
2. **The Switch stays on "connecting".** Run `journalctl -u nxbt-agent -n 20`. `reject` means the Switch's address is not in `switchAddresses`. No lines at all: check `systemctl status nxbt-agent`, then pair again from Change Grip/Order.
3. **Reconnect from the Home screen fails.** Pair again from Change Grip/Order (steps 2 to 4).
4. **The controller disconnects when you leave Change Grip/Order.** Disconnect the Joy-Con 2 controllers, then pair again. Reports say that the Switch 2 sometimes stops sending pairing requests when other controllers connected first.
5. **Read the logs:** `journalctl -u nxbt -n 50` and `journalctl -u bluetooth -n 50`.

If NXBT cannot pair at all, try [NUXBT](https://github.com/hannahbee91/nuxbt), a maintained fork (last release v3.3.7, 2026-08). It needs a Node build for its React UI, so it is not packaged here.

## Before you change the module

The comments in `hosts/nixos/trigkey/nxbt.nix` explain each change from upstream: the bluetoothd flags, the kernel patch, the pairing agent, the stability patch, the session secret, and the dependencies. These facts are not in the module:

- **Home Assistant's Bluetooth integration is disabled** (HA → Settings → Devices & services → Bluetooth, entry for `E8:C8:29:12:2D:10`, disabled 2026-10-06). HA found the adapter when Bluetooth was turned on and scanned it constantly, and the Switch could not find the controller. HA has no Bluetooth devices. If pairing stops working, check `bluetoothctl show`: `Discovering: yes` means something is scanning again.
- **Do not disable sniff mode** on the link (`hcitool lp ... RSWITCH`). Tried 2026-10-06: the Switch dropped the controller about 70 s after connecting.
- **Effects on trigkey:** a patched kernel that takes about 1.5 h to build, and no Bluetooth peripherals. See [trigkey](../fleet/trigkey.md#rules).
