# Pokémon Automation

[Pokémon Automation](https://pokemonautomation.github.io/) (PA, "Computer Control", formerly SerialPrograms) runs Switch automation programs: shiny hunts, resets, farmers. It reads the capture card on gmktec and drives the Switch through an ESP32-S3 board on USB. It runs in the headless sway session that [Sunshine](sunshine.md) streams, so you watch and control it from Moonlight.

| Item | Value |
|------|-------|
| Module | `hosts/nixos/gmktec/pokemon-automation.nix` |
| Release | v0.70.9-beta, Ubuntu x64 AppImage, run with `appimageTools.wrapType2` |
| Unit | `pokemon-automation.service` (eric's **user** unit). Not started at boot |
| Start | Moonlight → **Automation**, or `systemctl --user start pokemon-automation` |
| Stop | `systemctl --user stop pokemon-automation` (SSH). Quitting in Moonlight does not stop it |
| State | `~/.local/state/pokemon-automation/` — `UserSettings/`, `Screenshots/`, `AppRun.wrapped.log`. Not backed up |
| Controller | ESP32-S3 DevKitC-1, wired. `COM`/`UART` port → gmktec, `USB`/`OTG` port → Switch dock |
| Flash tool | `pa-flash-esp32s3 [port]`, default port `/dev/pa-esp32s3` |

PA upstream does not support Linux officially. The FAQ blames video flicker. That flicker came from Qt's FFmpeg backend ([PR #1140](https://github.com/PokemonAutomation/Arduino-Source/pull/1140)). The AppImage uses GStreamer, and the log confirms it: `Using Qt multimedia with GStreamer version: "GStreamer 1.24.2"`.

## One device, two users

PA and the Sunshine **Switch** app (mpv) both read `/dev/video0`. Only one program can stream from it at a time.

- Launch **Automation** in Moonlight. Sunshine quits the **Switch** app first, which frees the card. Then PA starts.
- While PA runs, the **Switch** app shows nothing. PA shows the same video in its own window.
- To use the **Switch** app again, stop PA first.

## Set up a new ESP32-S3

Time: about 15 minutes.

1. Find the labels next to the two USB-C ports on the back of the board: `COM` and `USB` (or `UART` and `OTG`).
2. Connect `COM`/`UART` to gmktec with a USB data cable. Do not connect the other port yet.
3. Check the port: `ssh eric@192.168.0.51 'ls -l /dev/pa-esp32s3'`. If it is missing, run `lsusb` and add the bridge's ID to `services.udev.extraRules` in the module.
4. Flash: `ssh eric@192.168.0.51 pa-flash-esp32s3`. If it prints `...` and stops, hold `BOOT`, press and release `RESET`/`EN`, then release `BOOT`, and run it again.
5. Press `RESET`/`EN` on the board.
6. On the Switch: **System Settings → Controllers and Accessories → Pro Controller Wired Communication → On**.
7. Connect `USB`/`OTG` to a USB port on the Switch dock.

The firmware comes from the same release as the program (`Firmware/PABotBase2-ESP32-S3-*.bin`). After a PA version update, flash the board again.

## Connect PA to the Switch

1. Disconnect the nxbt controller on trigkey. FireRed is a one-player game, so the ESP32-S3 must be controller 1.
2. In Moonlight, launch **Automation**.
3. Close the first-run **Warning** dialog.
4. Video: select the capture card at 1920x1080.
5. Controller: `Serial: PABotBase2` → the `ttyACM0` or `ttyUSB0` port → `NS1: Wired Pro Controller`.
6. Click the video, then press Enter. A Pro Controller appears on the Switch.

If `NS1: Wired Pro Controller` does not connect, try `NS2: Wired Controller`.

## Run Gift Reset (FireRed/LeafGreen)

Program page: [Gift Reset](https://pokemonautomation.github.io/Programs/PokemonFRLG/GiftReset.html).

1. Switch: screen size 100%, HDR off. Use the first user profile.
2. Game options: text speed Fast, button mode not `L=A`, frame type 1.
3. Stand in front of the Poké Ball of the starter.
4. Save. Open the menu on the top option, then close it.
5. In PA, open **Pokémon FRLG → Gift Reset**, select the target, and select **Start**.

Check progress at any time from Moonlight → **Automation** (or **Desktop**). Disconnecting does not stop the program.

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| **Automation** is not in Moonlight | Sunshine was not restarted after the deploy. `systemctl --user restart sunshine` ends the current stream |
| Black video in PA | mpv still had the card when PA started. Select **Reset Video** in PA |
| Port missing in PA | Board is on the `OTG` port, or its bridge chip is not in the udev rules |
| `Connected: No` | Bad cable or dock port, or the Pro Controller Wired Communication setting is off |
| Buttons do nothing in FireRed | Another controller is controller 1. Disconnect nxbt and any Joy-Con |
| `Unable to set process priority` in the log | Normal. The service is not allowed to raise its priority |
