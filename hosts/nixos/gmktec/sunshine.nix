{ pkgs, ... }:

let
  # Nothing on a headless box starts graphical-session.target, so sway hands
  # WAYLAND_DISPLAY to the user manager itself and then starts Sunshine. This is
  # why services.sunshine.autoStart is false below — the upstream unit is
  # `wantedBy = graphical-session.target`, which never fires here.
  #
  # Absolute systemctl path, because sway's `exec` inherits the unit's PATH and
  # NixOS gives systemd user units a minimal one (coreutils, findutils, grep,
  # sed, systemd). `path = [ pkgs.bash ]` on the unit is the other half of this:
  # sway runs every `exec` through execlp("sh", ...), which fails with
  # "execve failed: No such file or directory" when no sh is on that PATH.
  startSunshine = pkgs.writeShellScript "sunshine-session-start" ''
    set -eu
    ${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    ${pkgs.systemd}/bin/systemctl --user start sunshine.service
  '';

  # The USB capture card is a plain UVC device, so mpv can show it inside the
  # sway session Sunshine already captures. This is the path for the Switch and
  # anything else with its own HDMI out; a game that could run on this host
  # natively should, since that skips the card and its latency entirely.
  #
  # --no-config so a stray ~/.config/mpv can never change what the stream shows.
  # --untimed drops mpv's output queue; without it mpv buffers a few frames for
  # smoothness, which is the wrong trade when a controller is on the other end.
  # It is safe here only because this player carries no audio — see the loopback
  # under services.pipewire below. Give mpv an audio track and --untimed fights
  # A/V sync instead.
  #
  # yuyv422, not the card's mjpeg mode. The card is on a 5 Gbps port and raw
  # 1080p60 4:2:2 needs about 2, so the bandwidth is there, and taking it raw
  # drops a JPEG encode on the card plus a decode here — two fewer passes on
  # every frame. Fall back to `input_format=mjpeg` only if the USB bus ever
  # moves to a 480 Mbps port. video_size and framerate are not optional: with
  # neither set, ffmpeg's v4l2 demuxer takes the driver default, which is 640x480.
  #
  # Both modes come from `v4l2-ctl -d /dev/video0 --list-formats-ext`. /dev/video1
  # is the same device's second node and enumerates no formats; ignore it.
  #
  # The keyboard drives the Switch here (ace-typer's live keys, see liveKeys
  # below), so mpv must not act on it: --input-vo-keyboard=no and
  # --no-input-default-bindings, or `q` would quit the player and `=` would
  # change the window. The IPC socket is where ace-typer draws the key legend
  # and status (osd-overlay).
  captureCard = pkgs.writeShellScript "switch-capture" ''
    exec ${pkgs.mpv}/bin/mpv \
      --no-config \
      --profile=low-latency \
      --untimed \
      --fullscreen \
      --no-osc \
      --no-audio \
      --cursor-autohide=always \
      --no-input-default-bindings \
      --input-vo-keyboard=no \
      --input-ipc-server="$XDG_RUNTIME_DIR/mpv-switch.sock" \
      --demuxer-lavf-o=input_format=yuyv422,video_size=1920x1080,framerate=60 \
      av://v4l2:/dev/video0
  '';

  # Live keys on while the Switch app runs: ace-typer (./ace-typer.nix) reads
  # the "Keyboard passthrough" device and drives the ESP32-S3 board with
  # Pokémon Automation's key map. Off again when the app quits, which also
  # closes the board's serial port, so "Automation" (PA) can open it next.
  # Never fails the launch: without ace-typer the app is still a viewer.
  liveKeys =
    on:
    pkgs.writeShellScript "switch-live-keys-${if on then "on" else "off"}" ''
      ${pkgs.curl}/bin/curl -fsS -m 10 -o /dev/null \
        -H 'Content-Type: application/json' -d '{"on": ${if on then "true" else "false"}}' \
        http://127.0.0.1:8171/api/live || true
    '';

  # The card streams to one reader at a time. When something else holds it
  # (Pokémon Automation during a hunt, ./pokemon-automation.nix), mpv fails to
  # open it and exits at once, and an app that exits while Sunshine is still
  # starting its encoder crashed Sunshine (SEGV in ff_hw_base_encode_receive_packet,
  # 2026-10-07). A prep-cmd that exits non-zero makes Sunshine cancel the launch,
  # so Moonlight shows a launch error instead. Refusing, not stopping the holder,
  # is deliberate: picking "Switch" out of habit must not end a hunt.
  #
  # systemd-cat, not stderr. Sunshine discards a prep-cmd's stdout and stderr and
  # logs only `failed with code [1]`, so an echo here reaches nobody. Read it with
  # `journalctl --user -t switch-capture-card-free`.
  #
  # PA is not the only holder, and usually not the one. A Moonlight client that
  # disconnects without quitting the app leaves this very mpv on the card, which
  # is Moonlight working as designed — the app session survives so you can resume
  # it (seen 2026-10-08). The manual capture check in docs/services/sunshine.md
  # leaves one behind too. So print the holder instead of guessing at it. Two
  # things to know when reading that output: `fuser -v` names PA's AppImage
  # `AppRun.wrapped`, and running as eric it only sees eric's own processes — a
  # holder owned by another user would read as free, which nothing here is.
  cardFree = pkgs.writeShellScript "switch-capture-card-free" ''
    if ${pkgs.psmisc}/bin/fuser -s /dev/video0; then
      {
        echo "/dev/video0 is in use; not starting the Switch app."
        echo "Holder below. Pokémon Automation's AppImage shows as AppRun.wrapped."
        ${pkgs.psmisc}/bin/fuser -v /dev/video0 2>&1
      } | ${pkgs.systemd}/bin/systemd-cat -t switch-capture-card-free -p err
      exit 1
    fi
  '';

  # Headless sway: one virtual output, no seat, no DRM master. Moonlight
  # negotiates its own resolution per client, so this is the ceiling.
  swayConfig = pkgs.writeText "sway-headless.conf" ''
    output HEADLESS-1 mode 1920x1080@60Hz

    # The capture player is the only window that ever opens in this session.
    for_window [app_id="mpv"] fullscreen enable

    exec ${startSunshine}
  '';
in
{
  # ── Sunshine (game/desktop stream host for Moonlight) ────────────────────────
  # Ports: 47984, 47989, 47990 (web UI, HTTPS), 48010 TCP; 47998-48000, 48002,
  #        48010 UDP. All LAN-scoped.
  # State: /home/eric/.config/sunshine — pairing certs and web UI credentials.
  #        Apps and settings come from the store, see applications below.
  # NOT backed up. Re-pairing a client takes under a minute.
  #
  # Runs as eric's *user* service, not a system one. `users.users.eric.linger`
  # in ../common already starts eric's systemd user instance at boot, so this
  # works with nobody logged in.
  #
  # No portless alias on purpose. Portless runs with `tls = false` and proxies
  # plain HTTP to localhost:<port>; Sunshine's 47990 speaks TLS only, so a
  # `sunshine.local` name would serve a protocol error rather than the UI.
  # Reach it at https://192.168.0.51:47990 and accept the self-signed cert.
  #
  # No Pangolin route either. Moonlight is latency-bound UDP, and the tunnel
  # sends every packet to a VPS in another city and back — the same round trip
  # ./jellyfin.nix already documents as the bug worth avoiding.

  services.sunshine = {
    enable = true;
    # The module's openFirewall opens on every interface. gmktec house rule is
    # a scoped extraInputRules — see docs/networking.md#firewall.
    openFirewall = false;
    # Sway's wlr-screencopy path is used, not DRM/KMS, so CAP_SYS_ADMIN is not
    # needed. Flip this only if you move to `capture = "kms"`.
    capSysAdmin = false;
    # See swayConfig above.
    autoStart = false;

    settings = {
      sunshine_name = "gmktec";
      capture = "wlr";
      # VCN 2.2 on the 5825U's Vega iGPU does H.264 and HEVC. Same render node
      # Jellyfin transcodes on — a stream and a transcode will compete.
      encoder = "vaapi";
      adapter_name = "/dev/dri/renderD128";
      # The virtual sink declared below. Sunshine appends `.monitor` itself.
      audio_sink = "sunshine-sink";
    };

    # Setting this turns off app editing in the web UI — the same trade the rest
    # of this repo makes, and the reason `settings` above exists.
    applications.apps = [
      {
        name = "Switch";
        # cmd, not detached: Sunshine then owns mpv's lifetime, so quitting from
        # Moonlight stops the player instead of leaving it running on the iGPU.
        cmd = "${captureCard}";
        auto-detach = "false";
        # See cardFree above.
        prep-cmd = [
          {
            do = "${cardFree}";
            undo = "";
          }
          {
            do = "${liveKeys true}";
            undo = "${liveKeys false}";
          }
        ];
      }
      # Kept so there is still a way in when the card is unplugged.
      { name = "Desktop"; }
    ];
  };

  # ── The session being streamed ───────────────────────────────────────────────
  # WLR_BACKENDS=headless means wlroots invents an output instead of looking for
  # a CRTC, so no HDMI dummy plug and no forced `video=` kernel param.
  # WLR_RENDERER=gles2 composites on the iGPU via the render node; swap to
  # `pixman` for software compositing if that ever misbehaves.
  #
  # `libinput` is the other half of WLR_BACKENDS, and it is what makes
  # Moonlight's mouse and keyboard work. Sunshine injects input through uinput
  # devices ("Mouse passthrough", "Keyboard passthrough", ...); the headless
  # backend has no input of its own, so with `headless` alone the seat had zero
  # devices and every click went nowhere. The libinput backend needs a session
  # to open devices, and this host has no logind seat, so LIBSEAT_BACKEND=noop
  # makes it open them directly with eric's own permissions — see the udev rule
  # under Input injection for why that is enough.
  systemd.user.services.sway-headless = {
    description = "Headless sway session for Sunshine to capture";
    wantedBy = [ "default.target" ];
    after = [ "pipewire.service" ];
    # See startSunshine above: sway shells out for every `exec`, and the default
    # systemd user PATH has no sh.
    path = [ pkgs.bash ];
    environment = {
      WLR_BACKENDS = "headless,libinput";
      LIBSEAT_BACKEND = "noop";
      WLR_RENDERER = "gles2";
      WLR_LIBINPUT_NO_DEVICES = "1";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "sway";
    };
    serviceConfig = {
      ExecStart = "${pkgs.sway}/bin/sway --config ${swayConfig}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # PipeWire's user units are socket-activated, so nothing starts them on a box
  # with no login and no graphical session — Sunshine would come up first, find
  # zero sinks, and stream silence until something else happened to touch the
  # pulse socket. `wants` is what actually pulls them up; `after` alone does not.
  systemd.user.services.sunshine = {
    wants = [
      "pipewire.service"
      "wireplumber.service"
    ];
    after = [
      "pipewire.service"
      "wireplumber.service"
    ];
  };

  # ── Input injection ──────────────────────────────────────────────────────────
  # The nixpkgs sunshine derivation patches out `find_package(Udev)` and ships
  # no rules.d, so the module's `services.udev.packages = [ cfg.package ]` is a
  # no-op. Without this, /dev/uinput is root-only and Moonlight's mouse,
  # keyboard and gamepad silently do nothing while video streams fine.
  hardware.uinput.enable = true;

  # Sunshine creates its uinput devices as eric, but the event nodes they get
  # are root:input 0660, so sway's libinput backend (opening devices itself via
  # LIBSEAT_BACKEND=noop) could not read them. OWNER, not the `input` group:
  # the group would also hand sway the box's own power button and AT keyboard,
  # and like `audio` it would only reach the user manager after a restart.
  # Sunshine names every virtual device "<kind> passthrough" (mouse, absolute
  # mouse, keyboard, touch, pen).
  #
  # Gamepads need the second line. Sunshine names those "Sunshine X-Box One
  # (virtual) pad", "Sunshine Nintendo (virtual) pad" and "Sunshine PS5 (virtual)
  # pad" (string literals in the binary), none of which match the first rule, and
  # it creates them when a client with a gamepad connects rather than at startup,
  # so the gap does not show in `ls /dev/input`. sway is not the reader here —
  # libinput ignores joysticks — so this is for whatever reads evdev inside the
  # session. Nothing on this host does yet; the rule is here so a native game
  # finds the pad instead of EACCES.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="* passthrough*", OWNER="eric"
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Sunshine * (virtual) pad", OWNER="eric"
  '';

  # ── Audio ────────────────────────────────────────────────────────────────────
  # No sound card on this box, so PipeWire comes up with zero sinks and Sunshine
  # streams silence. A null sink gives it a monitor source to capture.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    extraConfig.pipewire."99-sunshine-sink"."context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = "sunshine-sink";
          "node.description" = "Sunshine stream sink";
          "media.class" = "Audio/Sink";
          "audio.position" = "FL,FR";
        };
      }
    ];

    # HDMI carries the Switch's audio, so the capture card exposes it as a USB
    # Audio Class source alongside the video interface. Sunshine only ever reads
    # sunshine-sink.monitor, so that source has to be played *into* the null sink
    # to be heard — hence a loopback rather than any Sunshine-side setting.
    #
    # target.object is the node name wireplumber derives from the card's USB
    # serial, from `wpctl inspect` on the source. Swapping in a different capture
    # card changes it, and the symptom is video with silence.
    #
    # Deliberately not `node.passive`: a passive link lets both ends suspend, and
    # the first second of audio after a stream starts would be missing while the
    # card spins back up. Holding the card open costs nothing on a box whose job
    # this is.
    extraConfig.pipewire."99-capture-card-loopback"."context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "Capture card into Sunshine";
          "capture.props" = {
            "node.name" = "capture-card-loopback-in";
            "target.object" = "alsa_input.usb-UltraSemi_USB3_Video_20210623-02.analog-stereo";
            "audio.position" = [
              "FL"
              "FR"
            ];
          };
          "playback.props" = {
            "node.name" = "capture-card-loopback-out";
            "target.object" = "sunshine-sink";
            "stream.dont-remix" = true;
            "audio.position" = [
              "FL"
              "FR"
            ];
          };
        };
      }
    ];
  };
  security.rtkit.enable = true;

  users.users.eric.extraGroups = [
    "video"
    "render"
    "uinput"
    # `audio` is needed here and nowhere else in the fleet. /dev/snd/* is
    # root:audio 0660, and on a normal desktop logind grants the logged-in user
    # access through a uaccess ACL instead of the group. This host has no seat
    # and nobody logs in, so no ACL is ever applied and WirePlumber enumerates
    # zero devices — including the capture card's audio interface. The symptom
    # is `wpctl status` listing no Sources at all while /proc/asound/cards shows
    # the card fine.
    "audio"
  ];

  # Moonlight on gmktec is the CLI build, not the Qt GUI: on a headless host the
  # GUI would only be visible inside the very session Sunshine is streaming.
  # `moonlight list 127.0.0.1` and `moonlight pair` verify the host from a plain
  # SSH shell. The real client belongs on a machine with a screen.
  environment.systemPackages = [ pkgs.moonlight-embedded ];

  # LAN subnet only, like every other service here. Sunshine's pairing is a PIN
  # typed into the web UI, and the UI itself is HTTP-basic over self-signed TLS.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport { 47984, 47989, 47990, 48010 } accept comment "sunshine from LAN"
    ip saddr 192.168.0.0/24 udp dport { 47998-48000, 48002, 48010 } accept comment "sunshine streams from LAN"
  '';
}
