# MeshLLM

Local OpenAI-compatible LLM inference on gmktec. CPU only, loopback only.

## Use it

1. From any other machine, open a tunnel and leave it running:
   ```bash
   ssh -N -L 9337:127.0.0.1:9337 eric@192.168.0.51
   ```
2. Check it: `curl http://127.0.0.1:9337/v1/models`
3. Send a prompt. A reply takes a few seconds.
   ```bash
   curl http://127.0.0.1:9337/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"unsloth/Qwen3-4B-GGUF:Q4_K_M","messages":[{"role":"user","content":"say hi"}],"chat_template_kwargs":{"enable_thinking":false}}'
   ```

- SDK base URL: `http://127.0.0.1:9337/v1`. Pass any string as the API key.
- Model name: the `id` from `/v1/models`, without `@main`.
- `enable_thinking: false` stops Qwen3 from printing its reasoning first.
- `GET /v1` returns `route not found: /v1`. That's expected, and it proves the tunnel works. `GET /health` is the cheapest check.

| Item | Value |
|------|-------|
| Module | `hosts/nixos/gmktec/meshllm.nix` |
| Package | `pkgs/mesh-llm.nix`, version 0.74.0 |
| API, console | `127.0.0.1:9337/v1`, `127.0.0.1:3131` |
| Model | `unsloth/Qwen3-4B-GGUF@main:Q4_K_M`, ~2.5 GB |
| State | `/var/lib/mesh-llm/`, static user `mesh-llm` |
| Backup | None. The model re-downloads and the runtime comes from the Nix store. |

## Change the model

1. Find one: `ssh eric@192.168.0.51 'mesh-llm models search --catalog qwen3'`
2. Put the printed `ref:` value into `model =` in `configToml` in the module.
3. Deploy gmktec. The first start downloads the model; `TimeoutStartSec = 30min` allows for it. Later restarts take ~15 s.

## Upgrade

Bump `version` and **both** hashes in `pkgs/mesh-llm.nix` together. The binary checks the runtime's `skippy_abi` before loading it. The hashes are upstream's `.sha256` files converted to SRI.

The package exists because MeshLLM isn't in nixpkgs and upstream's installer downloads a native runtime on first run. The package pins the binary and the runtime, and `ExecStartPre` installs the runtime offline with `mesh-llm runtime install --bundle-dir`.

## Traps

- **No `DynamicUser`.** It mounts the state directory `noexec`, and loading llama.cpp fails with `failed to map segment from shared object`. That's why the user is static.
- **No `MemoryDenyWriteExecute`.** llama.cpp maps executable pages.
- **Keep a `[[models]]` entry.** Without one, `mesh-llm serve` exits 0 immediately under systemd.
- **Never put its storage on `/mnt/backup`.** That disk holds trigkey's only backup.

## Exposure

Loopback, no firewall rule, no Pangolin route, and the API has no auth. Mesh participation is off: the unit passes no `--publish`, `--auto`, or `--join`. Turning it on shares this machine's compute and home bandwidth with the public mesh, so decide that explicitly.

## Verify

```bash
ssh eric@192.168.0.51 'systemctl is-active mesh-llm; sudo ss -lntp | grep 9337'
ssh eric@192.168.0.51 'curl -s http://127.0.0.1:9337/v1/models'
ssh eric@192.168.0.51 'sudo journalctl -u mesh-llm -n 50 --no-pager'
```
