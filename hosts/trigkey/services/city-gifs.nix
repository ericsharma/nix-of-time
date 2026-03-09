{ ... }:
{
  virtualisation.oci-containers.containers.city-gifs = {
    image = "ghcr.io/ericsharma/city-gifs:latest";
    ports = [ "3070:80" ];
    extraOptions = [
      "--read-only"
      "--cap-drop=ALL"
      "--memory=512m"
    ];
  };
}
