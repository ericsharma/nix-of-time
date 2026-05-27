# Claude Code skills

Custom [Claude Code](https://claude.com/claude-code) skills live in `~/.claude/skills/<name>/SKILL.md` (outside this repo, in the user's home). Each is a single Markdown file: YAML frontmatter (`name`, `description`, `trigger`) followed by a prose playbook the agent follows when the trigger is typed. They're discovered at session start, so a newly added skill becomes invokable in the next session.

This page indexes the skills relevant to operating this configuration.

## Skills

| Skill | Trigger | Scope | What it does |
|-------|---------|-------|--------------|
| garage | `/garage` | This repo (trigkey) | End-to-end recipe for adding S3-backed storage: create a Garage bucket + key, attach permissions, wire credentials through sops, and reference them from a NixOS module. |
| diff-context | `/diff-context <N> <issue>` | Any git repo (current dir) | Loads the diffs of the last N commits as working context, then helps with the issue you describe against those changes. |

## garage

Tied to this repository. It's the canonical workflow for the four-step provisioning dance against Garage on trigkey (`127.0.0.1:3900`, region `garage`):

1. List existing buckets/keys (`sudo garage bucket list` / `key list`) to avoid name collisions.
2. Create the bucket + key and attach permissions (`bucket create`, `key create`, `bucket allow`). Key naming convention: `<bucket>-ro` / `<bucket>-rw`.
3. Add credentials to `secrets/secrets.yaml` via `sops --set`, env-file shape (`<service>.rclone-env`) by default.
4. Reference the secret from the service `.nix` module (`sops.secrets."<service>/rclone-env"` + `EnvironmentFile=`).

It also carries the rclone env conventions (the easily-forgotten `ENV_AUTH=true`), patterns to crib from (`radio.nix`, `radio-video.nix`, `backup.nix`), inspection/debug commands, and a destructive-operations section that requires confirmation.

See [secrets.md](secrets.md) for the broader sops model and [services/README.md](services/README.md) for the Garage service entry.

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
