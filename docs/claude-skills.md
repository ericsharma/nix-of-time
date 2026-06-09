# Claude Code skills

Custom [Claude Code](https://claude.com/claude-code) skills live in `~/.claude/skills/<name>/SKILL.md` (outside this repo, in the user's home). Each is a single Markdown file: YAML frontmatter (`name`, `description`, `trigger`) followed by a prose playbook the agent follows when the trigger is typed. They're discovered at session start, so a newly added skill becomes invokable in the next session.

This page indexes the skills relevant to operating this configuration.

## Skills

| Skill | Trigger | Scope | What it does |
|-------|---------|-------|--------------|
| garage | `/garage` | This repo (trigkey) | End-to-end recipe for adding S3-backed storage: create a Garage bucket + key, attach permissions, wire credentials through sops, and reference them from a NixOS module. |
| dvd-rip | `/dvd-rip` | This repo (trigkey) | Rip a DVD in the USB optical drive to a lossless ISO, split the main title into per-chapter MKVs (no re-encode), upload to a Garage bucket subfolder, and optionally surface in Jellyfin. |
| media-to-ascii | `/media-to-ascii` | This repo (trigkey) | Convert a media file (or a time segment) to an ASCII rendering with the `mediatoascii` CLI, optionally re-attach the original audio, and upload to the `ascii/` prefix of the Garage `guitar` bucket. |
| new-service | `/new-service` | This repo (both hosts) | End-to-end scaffold for a new service: tier selection, module with house conventions (localhost binding, pinned images, tmpfiles, hardening), sops wiring, exposure plan, mandatory backup decision, docs row, deploy + verify. |
| diff-context | `/diff-context <N> <issue>` | Any git repo (current dir) | Loads the diffs of the last N commits as working context, then helps with the issue you describe against those changes. |

## garage

Tied to this repository. It's the canonical workflow for the four-step provisioning dance against Garage on trigkey (`127.0.0.1:3900`, region `garage`):

1. List existing buckets/keys (`sudo garage bucket list` / `key list`) to avoid name collisions.
2. Create the bucket + key and attach permissions (`bucket create`, `key create`, `bucket allow`). Key naming convention: `<bucket>-ro` / `<bucket>-rw`.
3. Add credentials to `secrets/secrets.yaml` via `sops --set`, env-file shape (`<service>.rclone-env`) by default.
4. Reference the secret from the service `.nix` module (`sops.secrets."<service>/rclone-env"` + `EnvironmentFile=`).

It also carries the rclone env conventions (the easily-forgotten `ENV_AUTH=true`), patterns to crib from (`radio.nix`, `radio-video.nix`, `backup.nix`), inspection/debug commands, and a destructive-operations section that requires confirmation.

See [secrets.md](secrets.md) for the broader sops model and [services/README.md](services/README.md) for the Garage service entry.

## dvd-rip

Tied to this repository. The lossless capture pipeline for a physical disc in trigkey's USB optical drive:

1. Detect `/dev/sr0`, mount read-only to inspect `VIDEO_TS/` and grab booklets.
2. Rip to a lossless ISO with `ddrescue` (run as root via `sudo "$(command -v ddrescue)"`).
3. Identify the longest title (`lsdvd -x`) and stream-copy each chapter to its own MKV with ffmpeg's `dvdvideo` demuxer (`-f dvdvideo -title N -chapter_start n -chapter_end n -c copy`, reading the ISO directly).
4. Upload into a per-disc subfolder of a Garage bucket (`guitar` by default) via rclone — `ENV_AUTH=true` required — then `rclone check` and prune the local clips, keeping the ISO as the master.
5. Optionally trigger a Jellyfin scan (the `guitar` bucket is already mounted read-only at `/srv/jellyfin/media` by `hosts/nixos/optional/jellyfin.nix`).

Carries the hard-won gotchas: untracked `.nix` files are invisible to the git flake until `git add`ed; the Jellyfin mount is read-only so renames go against the bucket with the `-rw` key; FUSE/S3 changes need a manual library scan. Defers bucket+key+sops provisioning to [garage](#garage).

## media-to-ascii

Tied to this repository. Turns a video/image — usually a clip already in the `guitar` bucket — into an ASCII rendering and commits it to the bucket's flat `ascii/` prefix:

1. Read the source straight from the read-only Jellyfin mount (`/srv/jellyfin/media/...`) or a local path; probe it with `ffprobe` first.
2. For a sub-clip, pre-extract the range with a *single* `-ss/-t` ffmpeg seek mapping both video and audio (`mediatoascii` can't seek) so the audio stays frame-aligned with the render.
3. Render with `mediatoascii --video-path ... --scale-down N -o out.mp4`. `--scale-down` is the fidelity knob (lower = denser ASCII grid); native fps is best; output is silent greyscale.
4. (Optional) Mux the original audio back from the *same* extraction (AC3→AAC, `-c:v copy -shortest`).
5. Upload to `guitar/ascii/<name>_ascii.mp4` via rclone (`ENV_AUTH=true`, `copyto` for an exact key, same-name overwrites in place), then verify and clean up `/tmp`.

Carries the gotchas: ASCII output is silent so audio must be re-attached from the aligned extraction; the Jellyfin mount is read-only so uploads use the `guitar-rw` key; quality is `--scale-down` not `--font-size`; size/time scale ≈ 1/scale_down². The CLI comes from the in-repo `media-to-ascii` package (`pkgs/media-to-ascii.nix`). Defers key/sops mechanics to [garage](#garage).

## new-service

Tied to this repository, both hosts. The playbook for adding a service so it lands with every house convention applied, not just an evaluating module:

1. Gather facts: nixpkgs module availability, container shape, what state it persists, secrets, a non-colliding port, exposure needs.
2. Pick the tier via [architecture.md](architecture.md#when-to-use-which) — native module / Podman in `hosts/nixos/optional/` (auto-imported), Docker stack in `hosts/nixos/docker-services/services/` (auto-imported), or trigkey-coupled in `hosts/nixos/trigkey/` (manual import).
3. Scaffold from the closest existing pattern (vaultwarden, kavita, strava, koito, pirousync), enforcing: `127.0.0.1` binding, **pinned image tags**, tmpfiles for `/srv` data dirs, systemd hardening for native services. Stateful LXC services get the two-system dance (host dir + Incus disk device in `containers.nix`, then the container module).
4. Wire secrets through sops (env-block vs scalar shape, `docker-services:` namespace for LXC).
5. Plan exposure: Pangolin route (manual dashboard step), justified LAN firewall port, or localhost-only. Garage storage defers to [garage](#garage).
6. **Mandatory backup decision** — every stateful service either gets its path added to a restic job (DBs via dumps, not raw dir copies) or an explicit `# NOT backed up — <reason>` header comment. No silent third state.
7. Add the row to [services/README.md](services/README.md), then `git add` (untracked files are invisible to the flake), `nix fmt`, `nix flake check`, `rebuild` / `rebuild-docker`, and post-deploy `systemctl`/`curl` verification.

## diff-context

Generic and repo-agnostic — useful in this repo or any other. Invoke as:

```
/diff-context <N> <description of the issue>
```

It counts back `<N>` commits from `HEAD` (`HEAD~N..HEAD`), reads their stats and full patches, then answers the issue you describe with those commits as the primary lens — citing short SHA and `file:line`. Reads history only; it won't commit or rewrite anything unless asked as a follow-up. Say "vs main" to switch from a count to a base-branch comparison.

## Adding a new skill

1. Create `~/.claude/skills/<name>/SKILL.md` with frontmatter (`name`, `description`, `trigger`) and a step-by-step body.
2. Write the body as a playbook: when to use it, the ordered commands, conventions, and any destructive steps that need confirmation.
3. Add a row to the table above (and a section if it's non-trivial).
4. Start a new Claude Code session for the skill to be discovered.
