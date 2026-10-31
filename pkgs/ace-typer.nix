{
  buildPythonPackage,
  setuptools,
  pyserial,
  src,
}:

# ACE Typer (https://github.com/ericsharma/ace-typer), from the `ace-typer`
# flake input. One build for both users: the ace-typer-web service on gmktec
# (hosts/nixos/gmktec/ace-typer.nix) and the ACE panel inside nxbt on trigkey
# (hosts/nixos/trigkey/nxbt.nix). A Python package, not an application, so
# nxbt can import it; ace-typer-web is still installed in bin/.
buildPythonPackage {
  pname = "ace-typer";
  version = "0.1.0";
  pyproject = true;
  inherit src;
  build-system = [ setuptools ];
  # Sunshine renamed its virtual keyboard from "Keyboard passthrough" to
  # "libvirtualhid Keyboard" (sunshine 2026.914, nixos 26.05). ace-typer has
  # the old name hardcoded in find_keyboard(), so live keys found no device and
  # the Moonlight "Switch" app ignored the keyboard. Drop this once upstream
  # matches the new name.
  postPatch = ''
    substituteInPlace ace_typer/keys.py \
      --replace-fail 'name="Keyboard passthrough"' 'name="libvirtualhid Keyboard"' \
      --replace-fail "no 'Keyboard passthrough' device" "no 'libvirtualhid Keyboard' device"
  '';
  # For the wired board on gmktec. nxbt never imports ace_typer.wired.
  dependencies = [ pyserial ];
  # The tests (simulated board, packet loss, stop races) run in the repo's CI
  # and before each push; not repeated here.
  doCheck = false;
  pythonImportsCheck = [
    "ace_typer.server"
    "ace_typer.web"
    "ace_typer.wired"
  ];
}
