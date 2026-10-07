{ pkgs, ace-typer, ... }:

# ACE Typer — types Pokémon FireRed ACE box codes into the PC box names through
# the ESP32-S3 board that Pokémon Automation uses as a wired Pro Controller
# (./pokemon-automation.nix). https://github.com/ericsharma/ace-typer
#
# Port: 8171 on 127.0.0.1; the LAN reaches it as http://ace.local through
#       portless (inventory.nix). No auth: anyone on the LAN can type on the
#       Switch.
# Data: none. NOT backed up — stateless; codes are pasted into the page.
#
# eric's *user* service, like pokemon-automation: it opens /dev/pa-esp32s3
# (owned by eric through the udev rule there) and stops or starts
# pokemon-automation with `systemctl --user` from the page. Only one program
# can use the board, so the page refuses to type while PA runs. It opens the
# board only for a check or a run, so PA can have it between runs.

let
  aceTyper = pkgs.python3Packages.buildPythonApplication {
    pname = "ace-typer";
    version = "0.1.0";
    pyproject = true;
    src = ace-typer;
    build-system = [ pkgs.python3Packages.setuptools ];
    dependencies = [ pkgs.python3Packages.pyserial ];
    # The tests (simulated board, packet loss, stop races) run in the repo's
    # CI and before each push; not repeated here.
    doCheck = false;
    pythonImportsCheck = [
      "ace_typer.server"
      "ace_typer.wired"
    ];
  };
in
{
  systemd.user.services.ace-typer = {
    description = "ACE Typer web page (wired Switch controller)";
    wantedBy = [ "default.target" ];
    # A user unit runs in every user's manager; only eric owns the board.
    unitConfig.ConditionUser = "eric";
    serviceConfig = {
      ExecStart = "${aceTyper}/bin/ace-typer-web --host 127.0.0.1 --port 8171 --board /dev/pa-esp32s3 --systemctl ${pkgs.systemd}/bin/systemctl";
      # SIGTERM clears the board's queue and releases every button first.
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
    };
  };
}
