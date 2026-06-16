# Nix of Time — Website Outline

**Project**: Exploratory, living website for the Nix of Time configuration  
**Tone**: Playful, curious, slightly mystical — "a growing declarative universe managed with Nix"  
**Goal**: Make the configuration feel alive, exploratory, and worth wandering through. Designed from the start to support multiple machines (Linux and macOS) even while only one host is currently active.

---

## Site Structure (Proposed)

### 1. Landing / The Anchor
- Hero with the name "Nix of Time" + forward-looking tagline:  
  **"A growing fleet of machines. One declarative source of truth."**
- Subtle animated background (circuit traces, flowing data, or soft grid)
- Current stats (dynamically presented):
  - 1 active host (Trigkey)
  - 2 macOS machines managed
  - 2 nixosConfigurations
  - 3 runtime tiers
  - 8+ public gateways
- Primary CTAs:
  - "Explore the Fleet" → Machines section
  - "Enter the Public Gateways"
  - "View the Source"

### 2. The Fleet
The machines that make up the Nix of Time universe.

**Current State**
- **Trigkey** — The main headless mini PC (the current anchor)
  - 32 GB RAM, ~15W idle, AMD CPU
  - Runs both the `trigkey` and `docker-services` NixOS configurations
  - Home to the majority of services and all public exposure via Newt

**Future Machines** (designed for from day one)
- Additional headless mini PCs (same pattern as Trigkey)
- macOS machines:
  - Mac Mini (current)
  - MacBook Air (current)
  - Future MacBook

**Design Principle**
- Every machine pulls from the same `hosts/` structure
- `hosts/nixos/` for Linux machines
- `hosts/darwin/` for macOS machines (already scaffolded)
- Shared modules in `common/` and `optional/` where possible
- The website should feel like it's documenting a growing constellation of machines, not a single box

This section should communicate both the current reality and the intentional multi-machine future.

### 3. The Three Realms
A clear, layered view of how services and workloads are organized across machines.

**Core concept**: Services are placed into one of three realms based on their requirements. These realms are not strictly tied to a single machine — they can span the fleet as more hosts come online.

**Visual approach**:
- Clean layered schematic (vertical or horizontal)
- Strong visual distinction between the three realms
- Services shown as cards with config location + public status
- Notes on which machines currently host each realm

**The Three Realms**:

1. **Native NixOS Realm**
   - Best for services with excellent first-class NixOS modules
   - Highest integration and systemd behavior
   - Currently lives on Trigkey
   - Examples: Immich, Vaultwarden, Garage, Home Assistant, Prometheus, Grafana, Syncthing, Newt, TapMap

2. **Podman Realm**
   - Single-container services that don't need complex inter-container networking
   - Lightweight and simple to run on any host
   - Currently on Trigkey
   - Examples: Strava Statistics, Kavita, Memos, Multi-Scrobbler, Termix, WhisperX, PiroueSync

3. **Docker-in-LXC Realm**
   - Complex multi-container stacks that benefit from Docker's DNS
   - Runs inside a dedicated NixOS LXC (`docker-services`)
   - Currently on Trigkey
   - Examples: Koito, Karakeep, Dawarich, City-Gifs, Cobalt, Rybbit, cAdvisor

**Cross-Realm & Cross-Machine Interactions**
- Newt on Trigkey routes all public traffic through Pangolin
- Syncthing (Native) feeding WhisperX (Podman)
- Future: Services potentially distributed across multiple Linux hosts or even macOS where it makes sense

This section should make the architecture feel intentional and scalable.

### 4. The Public Gateways (Live Links)
Exciting section showing everything reachable from the outside.

Known public endpoints:
- https://pangolin.ericsharma.xyz — Pangolin Control Plane
- https://radio.ericsharma.xyz + https://video.ericsharma.xyz — EternaTV streams
- https://vault.ericsharma.xyz — Vaultwarden
- https://d.ericsharma.xyz — Dawarich
- https://tracking.ericsharma.xyz — Rybbit
- https://options.ericsharma.xyz — Options Ledger
- Garage S3 bucket domains
- Additional services exposed via Pangolin as they come online

Future enhancement: Machine-aware gateway list (which host is currently serving each public service).

### 5. Data Flows & Rituals
Visual stories of how data moves through the system:
- Transcription pipeline (Syncthing → WhisperX)
- Location tracking (Dawarich)
- Music analytics (Scrobbler → Koito)
- Photo & media storage (Immich + Garage)
- Future flows as more machines join

### 6. The Source (Repository Explorer)
- "The spellbook" view of the configuration
- Highlighted structure:
  - `hosts/nixos/` — Linux machines (current + future)
  - `hosts/darwin/` — macOS machines (Mac Mini, MacBook Air, future MacBooks)
  - `hosts/nixos/optional/` — shared service library
  - `hosts/nixos/common/` — shared system configuration
- Clear explanation of how new machines are added (see `docs/adding-a-machine.md`)

### 7. Observatory
- Monitoring across the fleet
- Grafana, Prometheus, TapMap
- Future: Per-machine observability

### 8. Footer / Meta
- "Declared with Nix • Currently 1 Linux host + 2 macOS machines • Built to grow"

---

*This outline has been updated to treat the configuration as a multi-machine system from the beginning, even while only Trigkey is currently active.*