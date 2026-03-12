{ ... }:

{
  virtualisation.oci-containers.containers.cadvisor = {
    image = "gcr.io/cadvisor/cadvisor:latest";
    ports = [ "9101:8080" ];
    volumes = [
      "/:/rootfs:ro"
      "/run/docker.sock:/var/run/docker.sock:ro"
      "/run/docker/containerd/containerd.sock:/run/containerd/containerd.sock:ro"
      "/sys:/sys:ro"
      "/var/lib/docker:/var/lib/docker:ro"
      "/dev/disk:/dev/disk:ro"
    ];
    extraOptions = [ "--privileged" "--device=/dev/kmsg" ];
  };
}
