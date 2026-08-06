# MeshLLM

Local, OpenAI-compatible LLM inference on `gmktec`. Added 2026-08-06.

[MeshLLM](https://meshllm.cloud) is a peer-to-peer inference runtime built on
llama.cpp. Here it runs **standalone** — the peer-to-peer half is deliberately
switched off (see [Mesh participation](#mesh-participation)).

| Item | Value |
|------|-------|
| Host | `gmktec` (192.168.0.51) |
| Module | `hosts/nixos/gmktec/meshllm.nix` |
| Package | `pkgs/mesh-llm.nix` (local derivation, wired in `flake.nix`) |
| Version | 0.74.0 |
| API | `127.0.0.1:9337/v1` — OpenAI-compatible |
| Console | `127.0.0.1:3131` — management API |
| Model | `unsloth/Qwen3-4B-GGUF@main:Q4_K_M` (~2.5 GB, CPU) |
| State | `/var/lib/mesh-llm/` |
| Service user | `mesh-llm` (static, **not** DynamicUser — see below) |

## Why a local package

MeshLLM is not in nixpkgs (the nearest name match, `meshlab`, is unrelated), and
upstream ships only prebuilt binaries. The normal install is
`curl https://meshllm.cloud/install.sh | sh`, which drops a binary in
`~/.local/bin` and then downloads a matching native runtime on first run.

`pkgs/mesh-llm.nix` pins both halves instead:

1. The `mesh-llm` binary, patched with `autoPatchelfHook` (needs openssl 3,
   libgcc, libstdc++, libgomp).
2. The **native runtime** — patched llama.cpp shared libraries — fetched at build
   time into `$out/share/mesh-llm/native-runtimes/`.

The unit's `ExecStartPre` installs that runtime from the store with
`mesh-llm runtime install --bundle-dir`, which is completely offline. Nothing
reaches the network at service start except the one-time model download.

Both archives are version-locked: the runtime carries a `skippy_abi` field that
the host binary checks before loading. **Bump `version` and both hashes
together.** The hashes are upstream's own published `.sha256` sidecars converted
to SRI.

## Using it

There is no LAN or public exposure, so from any machine other than gmktec, open
an SSH tunnel first and keep it running:

```bash
ssh -N -L 9337:127.0.0.1:9337 eric@192.168.0.51
```

All the commands below then work unchanged from gmktec itself or through the
tunnel.

### Routes

`/v1` is a **base URL, not an endpoint**. Requesting it directly returns
`route not found: /v1`. That error still proves the tunnel works — the reply
comes from mesh-llm. Give `/v1` to a client library and it appends the rest.

| Path | Method | Result |
|------|--------|--------|
| `/health` | GET | `200` — cheapest check that the tunnel is up |
| `/v1/models` | GET | `200` — lists the loaded model |
| `/v1/chat/completions` | POST | `200`. A GET returns `405` |
| `/v1` | — | `404`, always. This is expected |

### Examples

```bash
curl http://127.0.0.1:9337/v1/models
```

```bash
curl http://127.0.0.1:9337/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"unsloth/Qwen3-4B-GGUF:Q4_K_M","messages":[{"role":"user","content":"say hi"}],"chat_template_kwargs":{"enable_thinking":false}}'
```

Expect a few seconds. This is CPU inference on a Ryzen 7 5825U.

Use the `id` field from `/v1/models` as the model name —
`unsloth/Qwen3-4B-GGUF:Q4_K_M`, with no `@main`. The fully-qualified ref from the
config file also works.

Qwen3 is a thinking model. Without `enable_thinking: false` it emits its
reasoning before the answer.

### From a client library

Any OpenAI-compatible SDK works. The API key is unused but most clients demand
one, so pass any string:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:9337/v1", api_key="unused")
client.chat.completions.create(
    model="unsloth/Qwen3-4B-GGUF:Q4_K_M",
    messages=[{"role": "user", "content": "say hi"}],
)
```

### Changing the model

Swap the model by editing `configToml` in the module:

```bash
ssh eric@192.168.0.51 'mesh-llm models search --catalog qwen3'
```

The `ref:` line printed by that command is what goes in the `model =` field.

## Exposure

Bound to `127.0.0.1` with no firewall rule. Newt/Pangolin runs on trigkey only,
so gmktec has no tunnel — publishing this would mean proxying through trigkey or
adding a tunnel client here. Neither is done. Verified unreachable from trigkey.

## Mesh participation

Off on purpose. The unit passes no `--publish`, `--auto`, or `--join`, so this
host neither advertises its compute to the public mesh nor discovers peers.
Turning discovery on is a real bandwidth and privacy decision about your home
connection — make it explicitly.

## Traps

Both of these cost time during the initial setup. They are recorded in the module
as comments too.

### 1. `DynamicUser` breaks it — `failed to map segment from shared object`

`DynamicUser = true` makes systemd bind-mount `StateDirectory` **`noexec`**:

```
/var/lib/private/mesh-llm rw,nosuid,nodev,noexec,relatime,idmapped
```

MeshLLM `dlopen()`s the llama.cpp libraries out of that directory, so the exec
mapping is refused and the server dies at startup. The fix is the static
`mesh-llm` system user. Every other hardening directive still applies; only the
per-restart UID isolation is lost.

Note `MemoryDenyWriteExecute` is also deliberately **not** set — llama.cpp maps
executable pages for its compute kernels.

### 2. A startup model is mandatory

`mesh-llm serve` with no `[[models]]` entry logs *"needs at least one startup
model"* and exits **0** immediately. Upstream's docs describe a `ready_idle`
state with no models loaded; that only holds for an interactive TTY session, not
under systemd. Verified against 0.74.0 in all three modes (`serve`, `on_demand`,
`client`).

So removing the `[[models]]` block does not give an idle daemon — it gives a unit
that will not stay running.

### 3. First start downloads the model

`TimeoutStartSec = 30min` exists because the default 90 s would kill the initial
~2.5 GB download. Later restarts hit the cache and take ~15 s.

## Backups

**Not backed up, by design.** Everything under `/var/lib/mesh-llm/` is a
re-derivable cache: the native runtime comes from the Nix store, and the model
re-downloads from Hugging Face. There is no user-generated state.

Do **not** point this service's storage at `/mnt/backup` — that disk is the only
off-machine copy of trigkey's data. See [backup.md](backup.md).

## Verify

```bash
ssh eric@192.168.0.51 'systemctl is-active mesh-llm; sudo ss -lntp | grep 9337'
ssh eric@192.168.0.51 'curl -s http://127.0.0.1:9337/v1/models'
ssh eric@192.168.0.51 'sudo journalctl -u mesh-llm -n 50 --no-pager'
```
