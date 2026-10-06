{
  config,
  lib,
  pkgs,
  ...
}:

# NXBT — emulates a Nintendo Switch Pro Controller over Bluetooth and drives it
# from a web page, a TUI, or a macro. https://github.com/Brikwerk/nxbt
#
# Port: 8170 on 127.0.0.1 (web app, no auth). Reach it through an SSH tunnel,
#       which also makes the page a secure context for the browser Gamepad API.
# Data: /var/lib/nxbt (Flask session secret only).
# NOT backed up — the only state is a random session secret that nxbt
#       regenerates on start.
#
# trigkey-only: it needs trigkey's Bluetooth adapter (hci0, Intel AX200).
# Operating guide and Switch 2 test: docs/services/nxbt.md.

let
  bluez = config.hardware.bluetooth.package;

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

  systemd.services.nxbt = {
    description = "NXBT Switch controller emulator (web app)";
    after = [ "bluetooth.service" ];
    requires = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
    environment.NXBT_STATE_DIR = "/var/lib/nxbt";
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
