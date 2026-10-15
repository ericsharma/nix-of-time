{ pkgs, ... }:

# ACE Typer — types Pokémon FireRed ACE box codes into the PC box names through
# the ESP32-S3 board that Pokémon Automation uses as a wired Pro Controller
# (./pokemon-automation.nix). https://github.com/ericsharma/ace-typer
#
# Port: 8171 on 127.0.0.1; the LAN reaches it as http://ace.local through
#       portless (inventory.nix). No auth: anyone on the LAN can type on the
#       Switch.
# Also: live keys for the Moonlight "Switch" app (./sunshine.nix turns them
#       on and off) — the keyboard drives the Switch with PA's key map.
# Data: none. NOT backed up — stateless; codes are pasted into the page.
#
# eric's *user* service, like pokemon-automation: it opens /dev/pa-esp32s3
# (owned by eric through the udev rule there) and stops or starts
# pokemon-automation with `systemctl --user` from the page. Only one program
# can use the board, so the page refuses to type while PA runs. It holds the
# board during a check or a run, and while live keys are on; otherwise it
# closes the port, so PA can have it.
#
# Package: pkgs.ace-typer (pkgs/ace-typer.nix), shared with nxbt on trigkey.

{
  systemd.user.services.ace-typer = {
    description = "ACE Typer web page (wired Switch controller)";
    wantedBy = [ "default.target" ];
    # A user unit runs in every user's manager; only eric owns the board.
    unitConfig.ConditionUser = "eric";
    # The board check refuses while pokemon-automation runs (systemctl --user).
    path = [ pkgs.systemd ];
    serviceConfig = {
      # --keyboard: live keys from Sunshine's "Keyboard passthrough" (eric owns
      # it, see ./sunshine.nix); the Switch app turns them on and off.
      # --mpv-socket: the key legend and status on that app's mpv. %t is
      # $XDG_RUNTIME_DIR.
      ExecStart = "${pkgs.ace-typer}/bin/ace-typer-web --host 127.0.0.1 --port 8171 --board /dev/pa-esp32s3 --systemctl ${pkgs.systemd}/bin/systemctl --keyboard --mpv-socket %t/mpv-switch.sock";
      # SIGTERM clears the board's queue and releases every button first.
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
    };
  };
}
