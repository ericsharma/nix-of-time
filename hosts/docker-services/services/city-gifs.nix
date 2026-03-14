{ ... }:

{
  # ── City-Gifs (timelapse GIF gallery) ──────────────────────────────────────
  # Port: 3070
  # No persistent data — static nginx site

  virtualisation.oci-containers.containers.city-gifs = {
    image = "docker.io/blindjoe/city-gifs:latest";
    ports = [ "3070:80" ];
    extraOptions = [
      "--read-only"
      "--tmpfs=/run:uid=101,gid=101"
      "--tmpfs=/var/cache/nginx:uid=101,gid=101"
      "--tmpfs=/tmp:uid=101,gid=101"
      "--user=101:101"
      "--security-opt=no-new-privileges:true"
      "--cap-drop=ALL"
      "--memory=512m"
      "--cpus=1"
    ];
  };
}
