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
