# storage/ — Build outputs and runtime data

Everything that gets created, downloaded, or built lives under here so the
repo root stays clean. Most contents are **gitignored**; only the
`.gitkeep` placeholders, `kernel_tags.json`, and the `production_kernels`
submodule are tracked.

| Path | Contents | Tracked? |
|------|----------|----------|
| `kernels/<kernel-name>/` | Cloned kernel source trees (one per `--kernel-name`). | gitignored (`.gitkeep` only) |
| `toolchains/<toolchain>/<version>/` | Cloned cross-compile toolchains. | gitignored (`.gitkeep` only) |
| `kernel_debs/` | Newly built Debian packages from `compile_and_package.sh` / `bindeb-pkg`. | gitignored |
| `kernel_archive/<tag>/` | Archived `.deb` + `kernel.config` + `patches.tar.gz` per release tag. | gitignored (`.gitkeep` only) |
| `production_kernels/` | Git submodule: `git@gitlab.com:cartken/kernel-os/production_kernels.git`. The single source of truth for production-grade `.deb`s, organised by `<soc>/<jetpack_version>/`. | submodule |
| `kernel_tags.json` | Release-tag manifest written by `scripts/release/kernel_tags.sh`. | tracked |

## Submodule init

After a fresh clone, populate the production submodule:

```bash
git submodule update --init storage/production_kernels
```

## Cleaning

Most of this directory can be safely deleted — it'll be rebuilt on the next
run. The two exceptions are `kernel_tags.json` (needed to know which tags
exist) and the `production_kernels` submodule (the real release artifact
storage; it has its own remote).

```bash
# Wipe a single kernel tree
rm -rf storage/kernels/<kernel-name>/

# Wipe build outputs but keep manifest + submodule
rm -rf storage/kernels/* storage/toolchains/* storage/kernel_debs/* storage/kernel_archive/*
```

`scripts/cleanup/` has higher-level helpers (`clean-builds`, etc.) for the
common cases.
