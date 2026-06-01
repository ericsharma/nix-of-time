{ config, lib, pkgs, ... }:
let
  cfg = config.services.pai-sho;
in
{
  options.services.pai-sho = {
    enable = lib.mkEnableOption "pai-sho tunnel daemon";
    exposedPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Local ports to expose to peers on startup.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.pai-sho = {
      description = "pai-sho tunnel daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart =
          let
            portArgs = lib.concatMapStringsSep " " (p: "-e ${toString p}") cfg.exposedPorts;
          in
          "${pkgs.pai-sho}/bin/pai-sho --socket /run/pai-sho/pai-sho.sock daemon ${portArgs}";
        RuntimeDirectory = "pai-sho";
        RuntimeDirectoryMode = "0755";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
