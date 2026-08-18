{ pkgs, ... }:

let
  yaml = pkgs.formats.yaml { };

  # ── Helpers ───────────────────────────────────────────────────────────────
  # Every "light" in this house is a smart plug, so the entities live in the
  # switch domain, not the light domain. tapping the card body toggles it.
  lightTile = entity: name: {
    type = "tile";
    inherit entity name;
    icon = "mdi:lightbulb";
    tap_action.action = "toggle";
  };

  tile = entity: name: icon: {
    type = "tile";
    inherit entity name icon;
  };

  section = heading: icon: cards: {
    type = "grid";
    cards = [
      {
        type = "heading";
        inherit heading;
        heading_style = "title";
        icon = icon;
      }
    ]
    ++ cards;
  };

  # Every switch that drives a light. Used by the "all off" button.
  allLightSwitches = [
    "switch.a_c_socket_1"
    "switch.a_c_socket_2"
    "switch.a_c_socket_3"
    "switch.fireplace_light"
    "switch.dresser_light"
    "switch.tp_link_power_strip_c7b1_plug_5"
    "switch.work_power_strip_kasa_smart_plug_d375_3"
    "switch.work_power_strip_corner_lamp_light"
  ];

  lovelaceConfig = {
    title = "Home";
    views = [

      # ── 1. Lights — the main screen ─────────────────────────────────────
      {
        title = "Lights";
        path = "lights";
        icon = "mdi:lightbulb-group";
        type = "sections";
        max_columns = 3;

        badges = [
          {
            type = "entity";
            entity = "person.eric";
            name = "Eric";
          }
          {
            type = "entity";
            entity = "person.belle";
            name = "Belle";
          }
          {
            type = "entity";
            entity = "sensor.sun_next_setting";
            name = "Sunset";
          }
        ];

        sections = [
          (section "Living Room" "mdi:sofa" [
            (lightTile "switch.a_c_socket_1" "Eric's Light")
            (lightTile "switch.a_c_socket_2" "Couch Light")
            (lightTile "switch.fireplace_light" "Fireplace Light")
          ])

          (section "Kitchen & Dining" "mdi:silverware-fork-knife" [
            (lightTile "switch.a_c_socket_3" "Kitchen Lights")
            (lightTile "switch.tp_link_power_strip_c7b1_plug_5" "Dining Table Lamp")
          ])

          (section "Bedroom" "mdi:bed" [
            (lightTile "switch.dresser_light" "Dresser Light")
          ])

          (section "Workspace" "mdi:desk" [
            (lightTile "switch.work_power_strip_kasa_smart_plug_d375_3" "Corner Lamp")
            (lightTile "switch.work_power_strip_corner_lamp_light" "Desk Lamp")
          ])

          (section "Everything" "mdi:power" [
            {
              type = "button";
              name = "All Lights Off";
              icon = "mdi:lightbulb-off-outline";
              show_state = false;
              tap_action = {
                action = "perform-action";
                perform_action = "switch.turn_off";
                target.entity_id = allLightSwitches;
              };
            }
          ])
        ];
      }

      # ── 2. Media ─────────────────────────────────────────────────────────
      {
        title = "Media";
        path = "media";
        icon = "mdi:television";
        type = "sections";
        max_columns = 2;

        sections = [
          (section "Living Room" "mdi:television" [
            {
              type = "media-control";
              entity = "media_player.apple_tv";
            }
            (tile "remote.apple_tv" "Apple TV Remote" "mdi:remote-tv")
            (tile "media_player.43s450g" "TV" "mdi:television")
          ])
        ];
      }

      # ── 3. Power — strips, lab machines, live draw ───────────────────────
      {
        title = "Power";
        path = "power";
        icon = "mdi:flash";
        type = "sections";
        max_columns = 3;

        badges = [
          {
            type = "entity";
            entity = "sensor.tp_link_power_strip_c7b1_current_consumption";
            name = "Server Strip";
          }
          {
            type = "entity";
            entity = "sensor.work_power_strip_current_consumption";
            name = "Work Strip";
          }
          {
            type = "entity";
            entity = "sensor.linux_box_current_consumption";
            name = "trigkey";
          }
        ];

        sections = [
          (section "Home Lab" "mdi:server" [
            (tile "switch.linux_box" "trigkey (KP125M)" "mdi:server")
            (tile "switch.tp_link_power_strip_c7b1_plug_6" "trigkey-pve" "mdi:server")
            (tile "switch.tp_link_power_strip_c7b1_plug_4" "gmktec-pve" "mdi:server")
            (tile "switch.tp_link_power_strip_c7b1_plug_2" "Router" "mdi:router-network")
            (tile "switch.tp_link_power_strip_c7b1_modem" "Modem" "mdi:router-wireless")
            (tile "switch.tp_link_power_strip_c7b1_plug_3" "Server Strip Plug 3 (free)" "mdi:power-socket-us")
          ])

          (section "Workspace" "mdi:desktop-classic" [
            (tile "switch.work_power_strip_mac_mini" "Mac Mini" "mdi:apple")
            (tile "switch.work_power_strip_imac" "iMac" "mdi:desktop-mac")
            (tile "switch.work_power_strip_kasa_smart_plug_d375_4" "Work Strip Plug 5 (free)"
              "mdi:power-socket-us"
            )
            (tile "switch.work_power_strip_kasa_smart_plug_d375_5" "Work Strip Plug 6" "mdi:power-socket-us")
          ])

          (section "Strip Masters" "mdi:power-plug" [
            (tile "switch.tp_link_power_strip_c7b1" "Server Power Strip" "mdi:power-plug")
            (tile "switch.work_power_strip" "Work Power Strip" "mdi:power-plug")
          ])

          (section "Live Draw" "mdi:speedometer" [
            {
              type = "entities";
              entities = [
                {
                  entity = "sensor.linux_box_current_consumption";
                  name = "trigkey";
                }
                {
                  entity = "sensor.tp_link_power_strip_c7b1_plug_4_current_consumption";
                  name = "gmktec-pve";
                }
                {
                  entity = "sensor.tp_link_power_strip_c7b1_plug_6_current_consumption";
                  name = "trigkey-pve";
                }
                {
                  entity = "sensor.tp_link_power_strip_c7b1_plug_2_current_consumption";
                  name = "Router";
                }
                {
                  entity = "sensor.tp_link_power_strip_c7b1_modem_current_consumption";
                  name = "Modem";
                }
                {
                  entity = "sensor.mac_mini_current_consumption";
                  name = "Mac Mini";
                }
                {
                  entity = "sensor.imac_current_consumption";
                  name = "iMac";
                }
              ];
            }
            {
              type = "history-graph";
              hours_to_show = 24;
              title = "24 h Power Draw";
              entities = [
                "sensor.linux_box_current_consumption"
                "sensor.tp_link_power_strip_c7b1_current_consumption"
                "sensor.work_power_strip_current_consumption"
              ];
            }
          ])

          (section "This Month" "mdi:calendar-month" [
            {
              type = "entities";
              entities = [
                {
                  entity = "sensor.linux_box_this_month_s_consumption";
                  name = "trigkey";
                }
                {
                  entity = "sensor.tp_link_power_strip_c7b1_this_month_s_consumption";
                  name = "Server Strip";
                }
                {
                  entity = "sensor.work_power_strip_this_month_s_consumption";
                  name = "Work Strip";
                }
                {
                  entity = "sensor.linux_box_this_month_s_consumption_cost";
                  name = "trigkey Cost";
                }
              ];
            }
          ])
        ];
      }

      # ── 4. System — network, phones, device health ───────────────────────
      {
        title = "System";
        path = "system";
        icon = "mdi:heart-pulse";
        type = "sections";
        max_columns = 3;

        sections = [
          (section "Network" "mdi:wan" [
            (tile "binary_sensor.archer_ax21_wan_status" "WAN" "mdi:wan")
            (tile "sensor.archer_ax21_download_speed" "Download" "mdi:download")
            (tile "sensor.archer_ax21_upload_speed" "Upload" "mdi:upload")
            (tile "sensor.archer_ax21_external_ip" "External IP" "mdi:ip-network")
          ])

          (section "People & Phones" "mdi:account-group" [
            (tile "device_tracker.erics_iphone" "Eric's iPhone" "mdi:cellphone")
            (tile "sensor.erics_iphone_battery_level" "Eric Battery" "mdi:battery")
            (tile "device_tracker.iphone_22" "Belle's iPhone" "mdi:cellphone")
            (tile "sensor.iphone_22_battery_level" "Belle Battery" "mdi:battery")
          ])

          # Reachability of every Kasa plug. When a plug is unavailable, its
          # signal level and cloud-connection rows here say why: dead entities
          # mean the plug is off the network, "unavailable" with the plug on
          # the LAN means the KLAP login failed.
          (section "Plug Health" "mdi:access-point-network" [
            {
              type = "entities";
              title = "Signal";
              entities = [
                {
                  entity = "sensor.linux_box_signal_level";
                  name = "trigkey plug";
                }
                {
                  entity = "sensor.fireplace_light_signal_level";
                  name = "Fireplace Light";
                }
                {
                  entity = "sensor.dresser_light_signal_level";
                  name = "Dresser Light";
                }
              ];
            }
            {
              type = "entities";
              title = "Cloud Connection";
              entities = [
                "binary_sensor.tp_link_power_strip_c7b1_cloud_connection"
                "binary_sensor.work_power_strip_cloud_connection"
                "binary_sensor.linux_box_cloud_connection"
                "binary_sensor.fireplace_light_cloud_connection"
                "binary_sensor.dresser_light_cloud_connection"
              ];
            }
          ])

          (section "Home Assistant" "mdi:home-assistant" [
            (tile "sensor.backup_backup_manager_state" "Backup State" "mdi:backup-restore")
            (tile "sensor.backup_last_successful_automatic_backup" "Last Backup" "mdi:clock-check-outline")
            (tile "todo.shopping_list" "Shopping List" "mdi:cart")
          ])
        ];
      }

    ]; # views
  }; # lovelaceConfig
in
{
  services.home-assistant = {
    enable = true;
    openFirewall = true; # opens port 8123

    extraComponents = [
      "tplink"
      "tuya"
      "apple_tv"
      "androidtv_remote"
      "upnp"
      # Kept for when an AirGradient is on the network again. It currently
      # has no config entry and no entities, so it has no dashboard view.
      "airgradient"
    ];

    config = {
      default_config = { };

      # Tell HA to use YAML mode for Lovelace (dashboard file managed below)
      lovelace.mode = "yaml";

      # Trust the local newt tunnel client as a reverse proxy so Pangolin
      # requests aren't rejected with 400 Bad Request
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };

      # The kasa library logs one ERROR line per module per poll for a plug it
      # cannot authenticate against. That filled home-assistant.log with 1.3 GB
      # of noise. Keep the first failure visible, drop the repeats.
      logger = {
        default = "info";
        logs."kasa.smart.smartdevice" = "critical";
      };

      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";
    };
  };

  # TP-Link discovery uses UDP broadcasts — open inbound ports so responses
  # aren't dropped by nftables (which Incus requires instead of iptables).
  networking.firewall.allowedUDPPorts = [
    9999
    20002
    5353
    1900
  ];

  # Lovelace dashboard YAML + empty include files for automations/scenes/scripts
  systemd.tmpfiles.rules = [
    "L+ /var/lib/hass/ui-lovelace.yaml - - - - ${yaml.generate "ui-lovelace.yaml" lovelaceConfig}"
    "f  /var/lib/hass/automations.yaml 0644 hass hass - -"
    "f  /var/lib/hass/scenes.yaml      0644 hass hass - -"
    "f  /var/lib/hass/scripts.yaml     0644 hass hass - -"
  ];
}
