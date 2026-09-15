# Nix of Time — website outline

Design brief for docs.ericsharma.xyz. This is not documentation, and `sync-docs.mjs` skips it.

- **Tone:** playful, curious, slightly mystical. "A growing declarative universe managed with Nix."
- **Tagline:** "A growing fleet of machines. One declarative source of truth."
- **Goal:** make the config worth wandering through, and present it as a multi-machine system (Linux and macOS).

## Core pages

1. **Landing.** Name, tagline, a subtle animated background (circuit traces or a soft grid). Stats: 2 Linux hosts, 1 LXC, 1 macOS host, 3 runtime tiers, 9+ public routes. Buttons: Explore the fleet · Public gateways · View the source.
2. **The fleet.** trigkey (the anchor), gmktec (backup, media, inference), docker-services (the LXC), m1-mini (nix-darwin). Leave room for more: every machine uses the same `hosts/` layout.
3. **The three realms.** A layered diagram of the runtime tiers. Services as cards with config path and public status.
   - Native NixOS: Immich, Vaultwarden, Garage, Home Assistant, Grafana
   - Podman: Kavita, Memos, Multi-Scrobbler, WhisperX, Dreeve
   - Docker in LXC: Koito, Karakeep, Dawarich, Rybbit, Endurain
4. **Public gateways.** Live links to every Pangolin route. Later: which host serves each one.
5. **The source.** A repo explorer ("the spellbook") highlighting `hosts/nixos/common/`, `hosts/nixos/optional/`, `hosts/nixos/<host>/`, `hosts/darwin/`, and how to add a machine.

## Later

- **Data flows:** Syncthing → WhisperX transcription · Scrobbler → Koito · Immich and Garage storage · Dawarich location.
- **Observatory:** Prometheus, Grafana, TapMap, per-machine views.
- **Footer:** "Declared with Nix • 2 Linux hosts + 1 Mac • Built to grow"
