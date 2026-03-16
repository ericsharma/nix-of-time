{ pkgs, ... }:

let
  yaml = pkgs.formats.yaml { };

  lovelaceConfig = {
    title = "Home";
    views = [

      # ── Light Identification ────────────────────────────────────────────────
      {
        title = "Lights";
        path  = "lights";
        icon  = "mdi:lightbulb";
        cards = [
          # Known
          { type = "tile"; entity = "switch.fireplace_light";                    name = "Fireplace Light";       icon = "mdi:lightbulb"; }
          { type = "tile"; entity = "switch.dresser_light";                      name = "Dresser Light";         icon = "mdi:lightbulb"; }
          { type = "tile"; entity = "switch.work_power_strip_kasa_smart_plug_d375_3"; name = "Workspace Corner Lamp"; icon = "mdi:lightbulb"; }
          { type = "tile"; entity = "switch.work_power_strip_corner_lamp_light"; name = "Unused (Work Strip Plug)"; icon = "mdi:power-plug-off"; }

          # AC socket lights
          { type = "tile"; entity = "light.a_c_socket_1"; name = "AC Socket 1 (?)"; icon = "mdi:lightbulb-question"; }
          { type = "tile"; entity = "light.a_c_socket_2"; name = "AC Socket 2 (?)"; icon = "mdi:lightbulb-question"; }
          { type = "tile"; entity = "light.a_c_socket_3"; name = "AC Socket 3 (?)"; icon = "mdi:lightbulb-question"; }

          # Router area
          { type = "tile"; entity = "switch.tp_link_power_strip_c7b1_plug_5"; name = "Dining Room Table Lamp"; icon = "mdi:lightbulb"; }
        ];
      }

      # ── Home Lab ────────────────────────────────────────────────────────────
      {
        title = "Lab";
        path  = "lab";
        icon  = "mdi:server";
        cards = [
          # c7b1 strip — computers and routers
          { type = "tile"; entity = "switch.tp_link_power_strip_c7b1_plug_2"; name = "Router";       icon = "mdi:router-network"; }
          { type = "tile"; entity = "switch.tp_link_power_strip_c7b1_plug_3"; name = "Lab Device 3"; icon = "mdi:server"; }
          { type = "tile"; entity = "switch.tp_link_power_strip_c7b1_plug_4"; name = "gmktek-pve";   icon = "mdi:server"; }
          { type = "tile"; entity = "switch.tp_link_power_strip_c7b1_plug_6"; name = "trigkey-pve";  icon = "mdi:server"; }
        ];
      }

      # ── Air Quality ─────────────────────────────────────────────────────────
      {
        title = "Air Quality";
        path  = "air-quality";
        icon  = "mdi:air-filter";
        cards = [
          { type = "tile"; entity = "sensor.airgradient_pm2_5";        name = "PM2.5";       icon = "mdi:blur"; }
          { type = "tile"; entity = "sensor.airgradient_carbon_dioxide"; name = "CO₂";        icon = "mdi:molecule-co2"; }
          { type = "tile"; entity = "sensor.airgradient_temperature";   name = "Temperature"; icon = "mdi:thermometer"; }
          { type = "tile"; entity = "sensor.airgradient_humidity";      name = "Humidity";    icon = "mdi:water-percent"; }
          { type = "tile"; entity = "sensor.airgradient_voc_index";     name = "VOC Index";   icon = "mdi:chemical-weapon"; }
          { type = "tile"; entity = "sensor.airgradient_nox_index";     name = "NOx Index";   icon = "mdi:smog"; }
        ];
      }

    ];  # views
  };  # lovelaceConfig
in
{
  services.home-assistant = {
    enable       = true;
    openFirewall = true;  # opens port 8123

    extraComponents = [
      "tplink"
      "tuya"
      "apple_tv"
      "androidtv_remote"
      "upnp"
      "airgradient"
    ];

    config = {
      default_config = {};

      # Tell HA to use YAML mode for Lovelace (dashboard file managed below)
      lovelace.mode = "yaml";

      # Trust the local newt tunnel client as a reverse proxy so Pangolin
      # requests aren't rejected with 400 Bad Request
      http = {
        use_x_forwarded_for = true;
        trusted_proxies      = [ "127.0.0.1" "::1" ];
      };

      "automation ui" = "!include automations.yaml";
      "scene ui"      = "!include scenes.yaml";
      "script ui"     = "!include scripts.yaml";
    };
  };

  # TP-Link discovery uses UDP broadcasts — open inbound ports so responses
  # aren't dropped by nftables (which Incus requires instead of iptables).
  networking.firewall.allowedUDPPorts = [ 9999 20002 5353 1900 ];

  # Lovelace dashboard YAML + empty include files for automations/scenes/scripts
  systemd.tmpfiles.rules = [
    "L+ /var/lib/hass/ui-lovelace.yaml - - - - ${yaml.generate "ui-lovelace.yaml" lovelaceConfig}"
    "f  /var/lib/hass/automations.yaml 0644 hass hass - -"
    "f  /var/lib/hass/scenes.yaml      0644 hass hass - -"
    "f  /var/lib/hass/scripts.yaml     0644 hass hass - -"
  ];
}
