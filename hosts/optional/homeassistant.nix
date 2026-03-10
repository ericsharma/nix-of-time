{ ... }:

{
  services.home-assistant = {
    enable      = true;
    openFirewall = true;  # opens port 8123

    # Components beyond what default_config already provides:
    #   tplink — TP-Link smart plugs/strips (auto-discovered on LAN, no credentials needed)
    #   tuya   — Tuya smart devices (finish setup via UI: requires Tuya IoT Platform credentials)
    extraComponents = [
      "tplink"
      "tuya"
    ];

    config = {
      # Loads core integrations: sun, met (weather), mobile_app, history,
      # logbook, energy, map, person, etc.
      default_config = {};

      # UI-managed automations/scenes/scripts — files created via tmpfiles below
      "automation ui" = "!include automations.yaml";
      "scene ui"      = "!include scenes.yaml";
      "script ui"     = "!include scripts.yaml";
    };
  };

  # TP-Link discovery uses UDP broadcasts — open inbound ports so responses
  # aren't dropped by nftables (which Incus requires instead of iptables).
  #   9999  — older Kasa protocol (HS300, most plugs)
  #   20002 — newer KLAP protocol (KP125M and recent devices)
  # mDNS (5353) and SSDP (1900) are used by default_config's zeroconf/ssdp components.
  networking.firewall.allowedUDPPorts = [ 9999 20002 5353 1900 ];

  # Create empty include files so HA doesn't error on first start
  systemd.tmpfiles.rules = [
    "f /var/lib/hass/automations.yaml 0644 hass hass - -"
    "f /var/lib/hass/scenes.yaml      0644 hass hass - -"
    "f /var/lib/hass/scripts.yaml     0644 hass hass - -"
  ];
}
