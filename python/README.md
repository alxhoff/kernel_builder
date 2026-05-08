# python/ — kernel_builder Python engine

The CLI engine that the shell wrappers under `scripts/` invoke. Three top-
level entry points and a small shared `utils/` package:

| File | Role |
|------|------|
| `kernel_builder.py` | Build orchestrator (host or Docker). Subcommands: `build`, `clone-kernel`, `clone-toolchain`, `clone-overlays`, `clone-device-tree`, `compile`, `inspect`, `cleanup`. |
| `kernel_deployer.py` | Deploy orchestrator. Subcommands: `deploy-x86`, `deploy-jetson`, `deploy-device`, `deploy-debian`. |
| `kernel_debugger.py` | On-target debug / trace / log harness. `install-trace-cmd`, `list-modules`, `record-trace`, `enable-persistent-logging`, `retrieve-logs`, … |
| `utils/clone_utils.py` | Repo / toolchain / overlay clone helpers (used by `kernel_builder.py`). |
| `utils/docker_utils.py` | Docker image build, inspect, cleanup helpers. |

## Invocation

The shell wrappers under `scripts/` resolve `$REPO_ROOT/python/<file>.py` for
you, but you can also call the engine directly:

```bash
python3 python/kernel_builder.py compile --kernel-name jetson --arch arm64
python3 python/kernel_deployer.py deploy-jetson --kernel-name jetson --ip 10.42.0.5 --user cartken
python3 python/kernel_debugger.py retrieve-logs --ip 10.42.0.5 --user cartken
```

The engine assumes the working directory is the repo root — it looks up
kernel sources under `storage/kernels/<kernel-name>/`, toolchains under
`storage/toolchains/<toolchain-name>/<version>/`, and writes Docker volume
mounts using those absolute paths.

## Layout assumption

When invoked from the repo root, the engine resolves paths like:

```
storage/kernels/<kernel-name>/kernel/kernel/      # kernel source tree
storage/toolchains/<toolchain>/<version>/bin/     # cross-compiler
```

If you ever need to run the engine from somewhere else, `cd` into the repo
root first or wrap the invocation in a script that does the `cd` for you
(this is what `bin/*` and `scripts/build/.../*.sh` do).
