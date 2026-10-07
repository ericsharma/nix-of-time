{ pkgs, ... }:

let
  version = "0.70.9";

  # One release zip holds the AppImage, its Resources folder (inference models,
  # templates, OCR data) and the PABotBase2 firmware for every board. Flash the
  # firmware from the same release as the program, so both ends speak the same
  # protocol version.
  release = pkgs.fetchzip {
    url = "https://github.com/PokemonAutomation/ComputerControl/releases/download/v${version}-beta/PA-SerialPrograms-Ubuntu-x64-${version}-20260926.zip";
    hash = "sha256-VWY9Qjq0RMaCUCF+MPT1J6Xt78NueOT8A8rha6UHGZg=";
  };

  # appimageTools runs the AppImage's own AppRun inside an FHS sandbox. AppRun
  # does two things this module relies on:
  #
  # - QT_MEDIA_BACKEND=gstreamer. Qt's FFmpeg backend is what made the video
  #   flicker on Linux (upstream PR #1140); GStreamer is the fix.
  # - PA_APPIMAGE_DIR=$(dirname "$APPIMAGE"). PA reads and writes everything
  #   (UserSettings/, Screenshots/, its log, the Resources/ lookup) relative to
  #   that directory. The wrapper leaves APPIMAGE empty, so it resolves to the
  #   working directory — which is how the state directory below becomes PA's
  #   install directory instead of a read-only store path.
  serialPrograms = pkgs.appimageTools.wrapType2 {
    pname = "pokemon-automation";
    inherit version;
    src = "${release}/SerialPrograms.AppImage";
  };

  # esptool, not Espressif's Windows flash tool. The image is a merged binary,
  # so it goes to offset 0x0 — the "right-most box should be a zero" step of
  # upstream's ESP32-S3 guide.
  flashEsp32s3 = pkgs.writeShellApplication {
    name = "pa-flash-esp32s3";
    runtimeInputs = [
      pkgs.esptool
      pkgs.systemd
    ];
    text = ''
      port=''${1:-/dev/pa-esp32s3}
      if systemctl --user is-active --quiet pokemon-automation.service; then
        echo "pokemon-automation holds the serial port. Stop it first:" >&2
        echo "  systemctl --user stop pokemon-automation" >&2
        exit 1
      fi
      firmware=(${release}/Firmware/PABotBase2-ESP32-S3-*.bin)
      echo "flashing ''${firmware[0]} to $port"
      exec esptool --chip esp32s3 --port "$port" --baud 460800 write-flash 0x0 "''${firmware[0]}"
    '';
  };
in
{
  # ── Pokémon Automation (Computer Control / SerialPrograms) ───────────────────
  # Runs in the headless sway session from ./sunshine.nix, so Moonlight's
  # "Desktop" or "Automation" app shows its window: the live video, the program
  # status and its counters. It reads the capture card directly and drives the
  # Switch through an ESP32-S3 on USB. No ports.
  #
  # State: ~/.local/state/pokemon-automation — UserSettings/ (video source,
  #        controller, program options), Screenshots/, the log.
  # NOT backed up. The settings take about 5 minutes to choose again, and a
  # shiny it finds is in the game's own save.
  #
  # Not wantedBy anything: it owns /dev/video0 while it runs, and the Sunshine
  # "Switch" app (mpv) needs the same device. The "Automation" app below starts
  # it; nothing stops it except `systemctl --user stop pokemon-automation`, so a
  # hunt keeps running after Moonlight disconnects.
  systemd.user.services.pokemon-automation = {
    description = "Pokémon Automation in the headless sway session";
    after = [ "sway-headless.service" ];
    # Its window has nowhere to go without the compositor.
    bindsTo = [ "sway-headless.service" ];
    environment = {
      # Set here rather than relying on sway's import-environment, so a manual
      # start before Sunshine is up still finds the compositor. Without it,
      # AppRun falls back to QT_QPA_PLATFORM=xcb and there is no X server.
      WAYLAND_DISPLAY = "wayland-1";
    };
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.coreutils}/bin/ln -sfn ${release}/Resources %S/pokemon-automation/Resources"
        "${pkgs.coreutils}/bin/ln -sfn ${release}/Firmware %S/pokemon-automation/Firmware"
      ];
      ExecStart = "${serialPrograms}/bin/pokemon-automation";
      StateDirectory = "pokemon-automation";
      WorkingDirectory = "%S/pokemon-automation";
      # A crash ends the hunt either way: PA does not resume a program on start.
      # Restarting only brings the window back so it can be started again.
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  services.sunshine.applications.apps = [
    {
      name = "Automation";
      # detached, not cmd: Sunshine does not track a detached process, so
      # quitting the app in Moonlight leaves the hunt running. systemctl start
      # is a no-op when it already runs, so reconnecting never starts a second
      # copy. Launching this app also makes Sunshine quit the "Switch" app,
      # which frees /dev/video0 for PA.
      detached = [ "${pkgs.systemd}/bin/systemctl --user start pokemon-automation.service" ];
    }
  ];

  # ── ESP32-S3 serial port ─────────────────────────────────────────────────────
  # The board's "COM"/"UART" port is a USB-serial bridge; which chip depends on
  # the board maker, so all three common ones are listed. ttyUSB*/ttyACM* are
  # root:dialout 0660, and the `dialout` group would not reach PA: the systemd
  # user manager caches its groups from boot (see the `audio` note in
  # ./sunshine.nix), and restarting it ends the sway session. OWNER applies the
  # moment the board is plugged in.
  #
  # /dev/pa-esp32s3 is for pa-flash-esp32s3. PA lists ports itself and shows
  # the real ttyACM0/ttyUSB0 name.
  services.udev.extraRules = ''
    # WCH CH343
    SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", OWNER="eric", SYMLINK+="pa-esp32s3"
    # WCH CH340
    SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", OWNER="eric", SYMLINK+="pa-esp32s3"
    # Silicon Labs CP210x
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", OWNER="eric", SYMLINK+="pa-esp32s3"
  '';

  environment.systemPackages = [ flashEsp32s3 ];
}
