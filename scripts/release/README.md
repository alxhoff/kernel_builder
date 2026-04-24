# release/ — Kernel Release & Tagged-Build Workflow

This folder holds the full tagged-release pipeline:

- `build_and_tag.sh` — interactive one-shot **build → package → tag →
  publish**.
- `compile_and_package.sh` — low-level: compile a kernel and produce a `.deb`.
  Used both standalone and under the hood by `build_and_tag.sh`.
- `kernel_tags.sh` — CLI for tracking, listing, promoting, deploying, and
  verifying tagged builds. Maintains `kernel_tags.json` at the repository
  root.
- `kernel_tags_completion.bash` — bash/zsh tab completion for
  `kernel_tags.sh`.

For convenience, the most-used entry points have short aliases under
[`bin/`](../../bin/) at the repo root:

```bash
./bin/build    # -> scripts/release/build_and_tag.sh
./bin/tags     # -> scripts/release/kernel_tags.sh
./bin/package  # -> scripts/release/compile_and_package.sh
```

All scripts in this folder work against the repo-root `kernel_tags.json`,
`kernel_archive/`, and the `production_kernels/` submodule.

## Quick Start — One-Shot Build & Tag

`build_and_tag.sh` interactively guides you through the whole process in a
single command:

```bash
./bin/build
```

It will:
1. Let you pick a kernel source.
2. Ask for the SOC type (`orin` / `xavier`).
3. Auto-generate a localversion (e.g. `cartken5.1.5realsense.130426`).
4. Auto-generate a date-based tag (e.g. `130426`).
5. Ask for a description.
6. Confirm, then **build → package → tag → publish** automatically.

When a SOC type is selected, the built `.deb` is published to the
`production_kernels` submodule under `<soc>/<jetpack_version>/`, committed, and
pushed to the remote.

Pre-fill values to skip prompts:

```bash
./bin/build cartken_5_1_5_realsense --soc orin
./bin/build cartken_5_1_5_realsense --soc orin \
  --description "Added temp sensor I2C driver"
```

After building, deploy and verify:

```bash
./bin/tags deploy 130426 --ip 10.42.0.5
./bin/tags deploy 130426 --robots 1,2,5-8 --robot-ip-prefix "10.42.0."
./bin/tags verify 130426 --ip 10.42.0.5
```

## Manual Build + Tag

```bash
./bin/package cartken_5_1_5_realsense \
  --localversion cartken5.1.5realsense2400 --config defconfig

./bin/tags tag v5.1.5-rs-2400 \
  --kernel cartken_5_1_5_realsense \
  --localversion cartken5.1.5realsense2400 \
  --description "RealSense D435 support for Orin"
```

## What Happens When You Tag

When `kernel_tags.sh tag` runs it performs up to five actions:

1. **Records metadata** in `kernel_tags.json` (tag name, kernel, localversion,
   SOC, jetpack version, builder, git commit, timestamps, …).
2. **Tags source repositories** — creates annotated git tags in all repos
   under `kernels/<kernel>/` so the exact source for any build can be
   recovered.
3. **Archives the `.deb`** — copies the compiled Debian package to
   `kernel_archive/<tag>/` for easy redeployment.
4. **Archives the kernel `.config`** — saves the build configuration to
   `kernel_archive/<tag>/kernel.config` for reproducibility.
5. **Publishes to `production_kernels`** (if `--soc` is given) — copies the
   `.deb` to `production_kernels/<soc>/<jetpack>/`, updates
   `build_log.yaml`, and auto-commits + pushes.

## Command Reference

| Command | Description |
|---------|-------------|
| `tag` | Create a new tagged build |
| `list` | List all tagged builds (with filters) |
| `show` | Show full details for a tag |
| `promote` | Change a tag's deployment status |
| `notes` | Add timestamped notes to a tag |
| `diff` | Compare two tags (metadata + git log) |
| `verify` | Check that a remote device is running the expected kernel |
| `deploy` | Deploy to one or more machines |
| `delete` | Remove a tag and its artifacts |
| `log` | Chronological build log |
| `export` | Export tag data (JSON or text) |
| `get-deb` | Print the path to an archived `.deb` |
| `kernels` | List all kernel sources and their status |

Every command supports `--help`:

```bash
./bin/tags deploy --help
```

## Status Lifecycle

```
development  -->  testing  -->  staging  -->  production
```

Promote with:

```bash
./bin/tags promote v5.1.5-rs-2400 --status staging
```

All status changes are recorded with timestamps and the identity of who made
the change.

## Listing & Inspecting Builds

```bash
./bin/tags list
./bin/tags list --status production
./bin/tags list --kernel cartken_5_1_5_realsense --all
./bin/tags show v5.1.5-rs-2400
./bin/tags kernels
```

## Adding Notes

```bash
./bin/tags notes v5.1.5-rs-2400 \
  --add "Stable after 48h soak test on 3 devices"
```

Notes are timestamped and attributed, and appear in the `show` output.

## Comparing Builds

```bash
./bin/tags diff v5.1.5-base v5.1.5-rs-2400
```

Shows metadata differences, source git log between the two tags (when both
live in the same repo), and a diffstat summary.

## Deploying

The deploy command copies the `.deb` to `~/kernel_debs/` on the target by
default (copy-only). Use `--install` to also run `dpkg -i`. SSH
`ControlMaster` is used to avoid multiple password prompts, and `--password`
with `sshpass` eliminates prompts entirely.

### Single device

```bash
./bin/tags deploy v5.1.5-rs-2400 --ip 10.42.0.5
./bin/tags deploy v5.1.5-rs-2400 --ip 10.42.0.5 --install
./bin/tags deploy v5.1.5-rs-2400 --ip 10.42.0.5 --remote-dir /opt/kernels
./bin/tags deploy v5.1.5-rs-2400 --ip 10.42.0.5 --dry-run
```

### Fleet deploy by robot number

Use `--robots` with comma-separated numbers (ranges supported) and
`--robot-ip-prefix` to construct IPs. Multiple targets are copied **in
parallel** by default.

```bash
./bin/tags deploy v5.1.5-rs-2400 \
  --robots 1,2,5-8 --robot-ip-prefix "10.42.0."

./bin/tags deploy v5.1.5-rs-2400 \
  --robots 1,2,5-8 --robot-ip-prefix "10.42.0." \
  --password "secret"
```

### Fleet deploy by IP or hosts file

```bash
./bin/tags deploy v5.1.5-rs-2400 \
  --ip 10.42.0.10 --ip 10.42.0.11 --ip 10.42.0.12

./bin/tags deploy v5.1.5-rs-2400 --hosts-file fleet.txt

./bin/tags deploy v5.1.5-rs-2400 --hosts-file fleet.txt --sequential
```

Fleet deploys continue to the next machine if one fails and print a summary
at the end. All successful deployments are recorded in the manifest.

## Verifying a Deployment

```bash
./bin/tags verify v5.1.5-rs-2400 --ip 10.42.0.5
```

SSHes into the device, runs `uname -r`, and checks that the output matches
the tag's expected localversion. Also supports `--password` for
non-interactive use.

## Tab Completion

```bash
source ./scripts/release/kernel_tags_completion.bash
```

Add the line to `~/.bashrc` / `~/.zshrc` to make it permanent. Completion
works for commands, tag names, kernel names, status values, and all option
flags, and is wired up for both `kernel_tags.sh` and the `./bin/tags` alias.

## File Layout

```
kernel_builder/
├── kernel_tags.json              # manifest of all tagged builds
├── kernel_archive/               # archived .deb packages and configs (gitignored)
│   └── 170426/
│       ├── linux-custom-5.10.216-cartken5.1.5realsense.170426.deb
│       └── kernel.config
├── production_kernels/           # git submodule: production .deb repository
│   ├── build_log.yaml            # YAML log of all published builds
│   ├── orin/
│   │   └── 5.1.5/
│   │       └── linux-custom-5.10.216-cartken5.1.5realsense.170426.deb
│   └── xavier/
│       └── ...
├── kernels/                      # kernel source directories
│   └── cartken_5_1_5_realsense/
├── bin/                          # short aliases (build, tags, package, …)
└── scripts/
    └── release/
        ├── build_and_tag.sh              # interactive one-shot flow
        ├── compile_and_package.sh        # low-level build + package
        ├── kernel_tags.sh                # tag management CLI
        └── kernel_tags_completion.bash   # bash/zsh tab completion
```

## Production Kernels Repository

The `production_kernels/` directory is a git submodule pointing to
`git@gitlab.com:cartken/kernel-os/production_kernels.git`. It is the single
source of truth for built kernel packages organised by SOC and Jetpack
version.

When a build is tagged with `--soc`, the tool automatically:
1. Copies the `.deb` to `production_kernels/<soc>/<jetpack_version>/`.
2. Appends the build metadata to `production_kernels/build_log.yaml`.
3. Commits and pushes the changes.

To initialise the submodule after cloning the repo:

```bash
git submodule update --init production_kernels
```

## Manifest Schema

Each entry in `kernel_tags.json` contains:

```json
{
  "tag": "170426",
  "kernel_name": "cartken_5_1_5_realsense",
  "localversion": "cartken5.1.5realsense.170426",
  "build_date": "2026-04-17T14:30:00Z",
  "builder": "Alex <alex@example.com>",
  "repo_commit": "abc1234",
  "config": "defconfig",
  "dtb_name": "",
  "description": "Added temp sensor I2C driver",
  "status": "testing",
  "soc": "orin",
  "jetpack_version": "5.1.5",
  "deb_package": "kernel_archive/170426/linux-custom-5.10.216-cartken5.1.5realsense.170426.deb",
  "config_archived": "kernel_archive/170426/kernel.config",
  "production_deb": "production_kernels/orin/5.1.5/linux-custom-5.10.216-cartken5.1.5realsense.170426.deb",
  "source_repos_tagged": ["kernels/cartken_5_1_5_realsense"],
  "notes": [
    { "text": "Stable after soak test", "date": "...", "by": "..." }
  ],
  "deployments": [
    { "target": "cartken@192.168.1.230", "date": "...", "by": "...", "mode": "copy" }
  ],
  "status_history": [
    { "status": "development", "date": "...", "by": "..." },
    { "status": "testing", "date": "...", "by": "..." }
  ]
}
```
