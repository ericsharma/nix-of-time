# Nintendo Switch

One physical Switch sits in its dock. HDMI goes into a USB capture card on gmktec, and an ESP32-S3 board on gmktec acts as a wired Pro Controller. Three programs share these two devices: mpv, Pokémon Automation (PA) and ACE Typer. This page tells you which program holds which device, and how they hand over.

| To do this | Use |
|------------|-----|
| Play from a laptop | Moonlight → **Switch**. The keyboard drives the Switch. See [Sunshine](sunshine.md) |
| Run a shiny hunt | Moonlight → **Automation**. See [Pokémon Automation](pokemon-automation.md) |
| Type FireRed ACE box codes | `http://ace.local` ([ACE Typer](https://github.com/ericsharma/ace-typer)) |
| Use a Bluetooth controller (optional) | [NXBT](nxbt.md) on trigkey |

## Who holds what

Only one program can use a device at a time.

| Device | Users | Handoff |
|--------|-------|---------|
| Capture card, `/dev/video0` | mpv in the **Switch** app, or PA | When you launch **Automation**, Sunshine quits **Switch** first. While PA runs, **Switch** refuses to start with "Failed to start the specified application" (`cardFree` in `sunshine.nix`), so a habit click does not end a hunt. Any holder blocks it, also a **Switch** session that you left without quitting: see [Troubleshooting](sunshine.md#troubleshooting). PA shows the same video in its own window. To use **Switch** again, stop PA |
| ESP32-S3 board, `/dev/pa-esp32s3` | PA, the ACE Typer page, or ACE Typer live keys | ACE Typer refuses to type while PA runs. Its page can stop and start PA. ACE Typer holds the board during a check, during a run, and while live keys are on. Quitting **Switch** turns live keys off and frees the board |
| Bluetooth `hci0` on trigkey | NXBT | Separate from the two devices above |

The Switch must read the board as player 1. A new session does not re-plug the board, so the Switch keeps it as the same player.

## Keyboard in the Switch app

The **Switch** app's second prep-cmd turns on ACE Typer's live keys (`POST http://127.0.0.1:8171/api/live`). Its undo turns them off. ACE Typer reads Sunshine's `Keyboard passthrough` device directly and uses PA's key map:

| Switch | Key |
|--------|-----|
| D-pad | Arrow keys |
| A, B | `Enter`, `Shift` |
| X, Y | `'`, `/` |
| L, R | `Q`, `E` |
| +, − | `=`, `-` |
| HOME | `Home`, `Esc`, or `H` |

- ACE Typer draws a key legend and a status line on mpv through `$XDG_RUNTIME_DIR/mpv-switch.sock`. `F1` hides the legend.
- mpv ignores the keyboard (`--input-vo-keyboard=no --no-input-default-bindings`), so `q` does not quit the player.
- Keys pause while ACE Typer types a code. They do nothing while PA runs.

## Where the parts are

| Part | Host | Module |
|------|------|--------|
| Sunshine, headless sway, mpv (**Switch** app) | gmktec | `gmktec/sunshine.nix` |
| Pokémon Automation (**Automation** app) | gmktec | `gmktec/pokemon-automation.nix` |
| ACE Typer (`ace.local`, live keys) | gmktec | `gmktec/ace-typer.nix` |
| NXBT and its ACE panel | trigkey | `trigkey/nxbt.nix` |

- On gmktec, all of these parts run as eric's systemd **user** units. Check them: `systemctl --user status sway-headless sunshine pokemon-automation ace-typer`.
- The `ace-typer` flake input feeds gmktec and trigkey. After `nix flake update ace-typer`, deploy both hosts.
