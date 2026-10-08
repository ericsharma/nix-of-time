{
  config,
  lib,
  pkgs,
  ace-typer,
  ...
}:

# NXBT — emulates a Nintendo Switch Pro Controller over Bluetooth and drives it
# from a web page, a TUI, or a macro. https://github.com/Brikwerk/nxbt
#
# Port: 8170 on 127.0.0.1 (web app, no auth). The LAN reaches it as
#       http://nxbt.local through portless (inventory.nix). The browser
#       Gamepad API needs a secure context, so a gamepad works only through
#       an SSH tunnel to http://localhost:8170.
# Data: /var/lib/nxbt (Flask session secret only).
# NOT backed up — the only state is a random session secret that nxbt
#       regenerates on start.
#
# trigkey-only: it needs trigkey's Bluetooth adapter (hci0, Intel AX200).
# Operating guide and Switch 2 test: docs/services/nxbt.md.

let
  bluez = config.hardware.bluetooth.package;

  # Switches allowed to pair through nxbt-agent (Bluetooth MAC addresses).
  switchAddresses = [ "A4:C1:E8:E0:74:99" ]; # the Switch 2

  # Parser and planner behind the web page's "ACE Box Codes" panel.
  aceTyper = pkgs.python3Packages.buildPythonPackage {
    pname = "ace-typer";
    version = "0.1.0";
    pyproject = true;
    src = ace-typer;
    build-system = [ pkgs.python3Packages.setuptools ];
    doCheck = false;
    pythonImportsCheck = [ "ace_typer.web" ];
  };

  nxbt = pkgs.python3Packages.buildPythonApplication {
    pname = "nxbt";
    version = "0.1.4-unstable-2023-07-04";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "Brikwerk";
      repo = "nxbt";
      rev = "ec4b800ad6c55de96bb6c7f9f84b5bdc59a4c975";
      hash = "sha256-TC1R5PEni8Gp6Fiv8RJroLkxDlzaCpKIX+hlfpro9ow=";
    };

    # Upstream bugs that left the web app wedged ("No adapters available") after
    # one controller crashed: a failed request stopped the command manager and
    # with it the shared state, removal was not idempotent, the SIGTERM handler
    # had the wrong arity, _on_exit called a missing BlueZ.reset_address, and a
    # D-Bus race killed the watchdog. If shared state is lost anyway, the web
    # process exits so systemd restarts it.
    patches = [ ./nxbt-stability.patch ];

    # Upstream rewrites /lib/systemd/system/bluetooth.service at runtime to add
    # `--compat --noplugin=*`. That file does not exist on NixOS, so the flags
    # are set declaratively below and the runtime toggle is a no-op.
    # The web app also writes its session secret next to its own source, which
    # is the read-only Nix store; move it to NXBT_STATE_DIR.
    postPatch = ''
      substituteInPlace nxbt/bluez.py \
        --replace-fail '    service_path = "/lib/systemd/system/bluetooth.service"' \
                       '    return  # NixOS: bluetoothd flags are set in nxbt.nix
          service_path = "/lib/systemd/system/bluetooth.service"'
      substituteInPlace nxbt/web/app.py \
        --replace-fail 'os.path.dirname(__file__), "secrets.txt"' \
                       'os.environ.get("NXBT_STATE_DIR", os.path.dirname(__file__)), "secrets.txt"'
    '';

    build-system = [ pkgs.python3Packages.setuptools ];

    dependencies = with pkgs.python3Packages; [
      dbus-python
      flask
      flask-socketio
      eventlet
      blessed
      psutil
      cryptography
      jinja2
      itsdangerous
      werkzeug
      aceTyper
    ];

    # Upstream pins 2021-era versions; nixpkgs' current ones are used instead.
    # pynput is only for the TUI's direct keyboard mode and needs X11.
    pythonRelaxDeps = true;
    pythonRemoveDeps = [ "pynput" ];

    # hciconfig, hcitool and sdptool set the adapter MAC/class and clear SDP records.
    makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ bluez ]}" ];

    doCheck = false;
    pythonImportsCheck = [ "nxbt" ];
  };
in
{
  environment.systemPackages = [ nxbt ];

  # Kernel fix for "paired but the controller never connects": right after
  # encryption starts, the kernel reads the key size from the radio. The
  # Switch opens the HID channel within ~3 ms, before that reply, and
  # l2cap_connect() refused it with "security block" (seen in btmon, about
  # every other pairing). The patch answers "pending" in that window;
  # l2cap_security_cfm() gives the real answer once the key size is known,
  # so the 7-byte minimum is still enforced.
  boot.kernelPatches = [
    {
      name = "bluetooth-l2cap-key-size-pending";
      patch = ./bluetooth-l2cap-key-size-pending.patch;
    }
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # NXBT must own the HID control/interrupt L2CAP ports, so every bluetoothd
  # plugin is off. --compat exposes the legacy SDP socket that sdptool needs.
  # Nothing else on trigkey uses Bluetooth.
  systemd.services.bluetooth.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${bluez}/libexec/bluetooth/bluetoothd -f /etc/bluetooth/main.conf --compat --noplugin=*"
  ];

  # The Switch 2 pairs with "No Bonding": no link key is stored, so every
  # reconnect is a new pairing that must be confirmed. This agent confirms it
  # for the listed Switch only and rejects every other device.
  systemd.services.nxbt-agent = {
    description = "Bluetooth pairing agent for nxbt (allowed Switches only)";
    after = [ "bluetooth.service" ];
    bindsTo = [ "bluetooth.service" ];
    wantedBy = [
      "bluetooth.service"
      "multi-user.target"
    ];
    serviceConfig = {
      ExecStart = "${
        pkgs.python3.withPackages (ps: [
          ps.dbus-python
          ps.pygobject3
        ])
      }/bin/python3 ${./nxbt-agent.py} ${lib.concatStringsSep " " switchAddresses}";
      Restart = "always";
      RestartSec = 3;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };

  systemd.services.nxbt = {
    description = "NXBT Switch controller emulator (web app)";
    after = [ "bluetooth.service" ];
    requires = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      NXBT_STATE_DIR = "/var/lib/nxbt";
      PYTHONUNBUFFERED = "1"; # print() lines reach the journal immediately
    };
    serviceConfig = {
      # Root: raw HCI commands (hcitool/hciconfig) and BlueZ adapter control.
      ExecStart = "${nxbt}/bin/nxbt webapp --ip 127.0.0.1 --port 8170";
      StateDirectory = "nxbt";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };
}
