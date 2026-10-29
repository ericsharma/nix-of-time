# Claude Code skills

Repeatable workflows for this repo, stored as Claude Code skills in `~/.claude/skills/<name>/SKILL.md` (outside the repo). Type a trigger in a session to run one.

## Skills

| Trigger | Runs on | Does |
|---------|---------|------|
| `/new-service` | both hosts | Adds a service end to end: tier, module, sops, exposure, backup decision, docs row, deploy, verify |
| `/garage` | trigkey | Creates a Garage bucket and key, stores the credentials in sops, wires them into a module |
| `/dvd-rip` | trigkey | DVD → lossless ISO → per-chapter MKVs → `guitar` bucket → Jellyfin |
| `/media-to-ascii` | trigkey | Renders a clip as ASCII video with its original audio, uploads to `guitar/ascii/` |
| `/add-book` | trigkey + gmktec | Finds an ebook by title and/or author through Prowlarr + SABnzbd and installs it into Kavita's `books/a/`, bypassing Chaptarr |
| `/cobalt-dl` | trigkey + LXC | Downloads a URL through Cobalt into the `general-media` bucket |
| `/karakeep-organize` | trigkey + LXC | Files unlisted Karakeep bookmarks into lists by editing its SQLite DB |
| `/pangolin-expose` | trigkey + Pangolin nodes | Exposes a service on a public hostname: applies a one-resource blueprint through the Pangolin API, verifies it on both nodes, keeps the blueprint in `pangolin/blueprints/` |
| `/gmktec` | gmktec | Operating gmktec from trigkey: SSH, remote deploys, deploy key, git sync, nftables, known traps |
| `/diff-context <N> <issue>` | any repo | Loads the last N commits' diffs as context for the issue you describe |
| `/improve` | any repo | Read-only audit that writes prioritized plans to `plans/` ([shadcn/improve](https://github.com/shadcn/improve)) |

## Traps the skills already handle

- rclone against Garage needs `ENV_AUTH=true`, or Garage answers `AccessDenied`.
- `/srv/jellyfin/media` is read-only. Rename or delete in the bucket with the `-rw` key.
- A new `.nix` file is invisible to the flake until you `git add` it.
- Karakeep's DB uses a rollback journal, not WAL. Stop `docker-karakeep-web` and back up `db.db` before writing.
- Cobalt returning 0-byte YouTube files means the pinned image is stale. Bump the tag.

## Add a skill

1. Write `~/.claude/skills/<name>/SKILL.md`: frontmatter (`name`, `description`, `trigger`), then ordered steps. Mark destructive steps as needing confirmation. If it only works on one host, say so at the top (see `/garage`).
2. Add a row to the table above.
3. In `~/.claude/skills`: `git add -A && git commit && git push`. The pre-commit hook runs gitleaks.
4. Start a new Claude Code session. Skills load at session start.

## Sync across hosts

`~/.claude/skills` is a clone of the private repo `github:ericsharma/claude-skills` on trigkey, gmktec, and m1-mini. The repo is the source of truth and the off-machine copy.

| Piece | File |
|-------|------|
| Clone-or-pull script (`claude-skills-sync`) | `pkgs/claude-skills-sync.nix` |
| NixOS hosts: clone at activation, user timer pulls every 15 min | `home/optional/claude-skills.nix` |
| m1-mini: clone at activation, launchd agent pulls every 15 min | `hosts/darwin/optional/claude-skills.nix` |

- Pulls are fast-forward only. Unpushed local work is never overwritten; the sync logs and skips.
- Each host authenticates to GitHub with its own account SSH key.
- `synced/`, `gstack/`, `i-have-adhd/` are tool-managed and ignored by the repo.
- The skills stay out of this public repo because they contain host names and paths. Never put a secret value in a skill; point to the sops path.
- Pull now: `claude-skills-sync`. Timer log: `journalctl --user -u claude-skills-sync` (m1-mini: `/tmp/claude-skills-sync.log`).

## Always-on ADHD output rules

[i-have-adhd](https://github.com/ayghri/i-have-adhd) ships as an opt-in skill. This repo loads it in every session instead:

- `pkgs/claude-adhd.nix` strips the skill frontmatter.
- `home/optional/claude-adhd.nix` links the rules to `~/.claude/adhd-rules.md` and puts `@adhd-rules.md` at the top of `~/.claude/CLAUDE.md`.
- `hosts/darwin/optional/claude-adhd.nix` does the same on m1-mini with an activation script, because m1-mini has no home-manager.

Only the import line is managed. `~/.claude/CLAUDE.md` stays writable. To update: `nix flake update i-have-adhd`, then redeploy trigkey, gmktec, and m1-mini.
