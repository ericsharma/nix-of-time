{ ... }:

{
  # ── Networking Toolbox ───────────────────────────────────────────────────────
  # Port: 3069

  virtualisation.oci-containers.containers.networking-tools = {
    image = "lissy93/networking-toolbox:latest";
    ports = [ "127.0.0.1:3069:3069" ];
    environment = {
      NODE_ENV = "production";
      PORT     = "3069";
      HOST     = "0.0.0.0";
    };
  };
}
