# Jetson Kernel Management Scripts

This README provides an overview of the scripts designed to manage kernel building, deployment, and configuration for Jetson devices. Each script automates a specific workflow, which can save considerable time and reduce errors in kernel management.

## Script Overview

### 1. `clean_jetson_kernel.sh`
- **Purpose**: This script is used to clean the kernel build directory for a Jetson kernel. It runs `make clean` or similar targets to ensure a clean state before starting a new build.
- **Usage**: The script navigates to the appropriate kernel directory and executes the `make clean` command. This ensures that any old artifacts from previous builds are removed before starting a fresh compilation.

### 2. `compile_and_deploy_jetson.sh`
- **Purpose**: This script compiles the kernel for a Jetson device and subsequently deploys the compiled kernel image and modules to the device.
- **Usage**: The script first builds the kernel, generating all necessary binaries and modules. It then uses SCP to transfer the compiled kernel and modules to the Jetson device. The script handles both building and deployment, making it ideal for those who need an end-to-end process.

### 3. `compile_jetson_kernel.sh`
- **Purpose**: This script compiles the kernel for a Jetson device.
- **Usage**: Similar to `compile_and_deploy_jetson.sh`, but without the deployment step. This script is useful when you want to perform testing on your local machine before deploying to the target device.

### 4. `compile_jetson_modules.sh`
- **Purpose**: This script specifically compiles the kernel modules for a Jetson kernel.
- **Usage**: The script targets the compilation of kernel modules only, which is useful for those who want to make changes to drivers or other modular components of the kernel without having to recompile the entire kernel.

### 5. `deploy_only_jetson.sh`
- **Purpose**: Deploys a precompiled kernel image and modules to the Jetson device.
- **Usage**: This script is useful when the kernel has already been compiled and you simply need to transfer the files to the target Jetson device. The script handles copying the kernel image, device tree blobs, and modules to their appropriate locations.

### 6. `example_workflow_jetson.sh`
- **Purpose**: An example script that demonstrates a full workflow, including building, deploying, and configuring a kernel for a Jetson device.
- **Usage**: Use this script as a reference or a basis for creating custom workflows. It encompasses all the major steps involved in kernel building and deployment.

### 7. `menuconfig_jetson_kernel.sh`
- **Purpose**: Opens the `menuconfig` configuration utility for the Jetson kernel.
- **Usage**: The `menuconfig` utility provides an interactive interface for configuring kernel options. This script launches `make menuconfig` within the kernel source tree, allowing users to customize their kernel settings.

### 8. `mrproper_jetson_kernel.sh`
- **Purpose**: Cleans the kernel source tree thoroughly.
- **Usage**: Similar to `clean_jetson_kernel.sh`, but more thorough. This script runs `make mrproper` to remove all generated files, restoring the source tree to its original state. It is especially useful when you encounter persistent build issues and need a truly fresh start.

## Script Usage
- All scripts are intended to be run from the root directory of the repository.
- The scripts will automatically determine their paths and use the appropriate kernel source, toolchain, and Jetson device configurations.
- Some scripts, such as `compile_and_deploy_jetson.sh` and `deploy_only_jetson.sh`, will require the IP address of the target Jetson device, which can either be provided as a command-line argument or sourced from a `device_ip` file if present.

## File Structure and Workflow
The scripts are divided into three main categories:
1. **Docker-Based Scripts** (`docker_` prefix): These scripts perform actions such as compiling and deploying Jetson kernels within a Docker container. The container provides a controlled environment with all dependencies, making the build process more reliable.
2. **Host-Based Scripts** (`host_` prefix): These scripts perform actions directly on the host machine without using Docker.
3. **Jetson Device Scripts** (`jetson_` prefix): These scripts interact directly with the Jetson device, performing operations such as installing tools, deploying kernels, or debugging.

Each script is crafted to target specific parts of the workflow, from configuration (`menuconfig_jetson_kernel.sh`) to building (`compile_jetson_kernel.sh`) to deploying (`deploy_only_jetson.sh`). Using the scripts in combination allows for efficient management of the kernel lifecycle.

## Tips for Usage
- **Device IP and Username**: The scripts can optionally use a `device_ip` or `device_username` file to store the target device's information. If present, this avoids the need to provide these details on every script invocation.
- **Default Values**: Many scripts come with default values for parameters such as the toolchain and kernel name. These values can be overridden via command-line arguments if needed.
- **Safety and Testing**: It is recommended to use the `dry-run` option where applicable to test the commands without executing them on the target device. This can help prevent unintentional changes.

---

## Kernel Tagging & Versioning System

`kernel_tags.sh` is a CLI tool for tracking, versioning, and deploying tagged kernel builds. It maintains a JSON manifest (`kernel_tags.json`) at the repository root and provides commands for the full lifecycle of a kernel build -- from tagging through deployment and verification.

### Quick Start — One-Shot Build & Tag

The easiest way to build and tag a kernel is `build_and_tag.sh`, which
interactively guides you through the entire process in a single command:

```bash
./scripts/kernel_builder/build_and_tag.sh
```

It will:
1. Let you pick a kernel source
2. Auto-generate a localversion (e.g. `cartken5.1.5realsense.130426`)
3. Auto-generate a date-based tag (e.g. `130426`)
4. Ask for a description
5. Confirm, then build + package + tag automatically

You can also pre-fill values to skip prompts:

```bash
# Pre-select kernel, prompt for the rest
./scripts/kernel_builder/build_and_tag.sh cartken_5_1_5_realsense

# Fully non-interactive
./scripts/kernel_builder/build_and_tag.sh cartken_5_1_5_realsense \
  --description "Added temp sensor I2C driver" --yes
```

After building, deploy and verify:

```bash
# Deploy to a device
./scripts/kernel_builder/kernel_tags.sh deploy 130426 --ip 10.42.0.5

# Deploy to a fleet
./scripts/kernel_builder/kernel_tags.sh deploy 130426 \
  --robots 1,2,5-8 --robot-ip-prefix "10.42.0."

# Verify the device is running the correct kernel
./scripts/kernel_builder/kernel_tags.sh verify 130426 --ip 10.42.0.5
```

### Manual Build + Tag (Advanced)

You can still build and tag separately if you need more control:

```bash
# 1. Build
./scripts/kernel_builder/compile_and_package.sh cartken_5_1_5_realsense \
  --localversion cartken5.1.5realsense2400 --config defconfig

# 2. Tag
./scripts/kernel_builder/kernel_tags.sh tag v5.1.5-rs-2400 \
  --kernel cartken_5_1_5_realsense \
  --localversion cartken5.1.5realsense2400 \
  --description "RealSense D435 support for Orin"
```

### What Happens When You Tag

When `kernel_tags.sh tag` is run, it performs four actions:

1. **Records metadata** in `kernel_tags.json` (tag name, kernel, localversion, builder, git commit, timestamps, etc.)
2. **Tags source repositories** -- creates annotated git tags in all repos found under `kernels/<kernel>/` so the exact source for any build can be recovered
3. **Archives the `.deb`** -- copies the compiled Debian package to `kernel_archive/<tag>/` for easy redeployment
4. **Archives the kernel `.config`** -- saves the build configuration to `kernel_archive/<tag>/kernel.config` for reproducibility

### Command Reference

| Command | Description |
|---------|-------------|
| `tag` | Create a new tagged build |
| `list` | List all tagged builds (with filters) |
| `show` | Show full details for a tag |
| `promote` | Change a tag's deployment status |
| `notes` | Add timestamped notes to a tag |
| `diff` | Compare two tags (metadata + git log) |
| `verify` | Check a remote device is running the expected kernel |
| `deploy` | Deploy to one or more machines |
| `delete` | Remove a tag and its artifacts |
| `log` | Chronological build log |
| `export` | Export tag data (JSON or text) |
| `get-deb` | Print the path to an archived `.deb` |
| `kernels` | List all kernel sources and their status |

Every command supports `--help` for detailed usage, e.g.:

```bash
./scripts/kernel_builder/kernel_tags.sh deploy --help
```

### Status Lifecycle

Tags progress through deployment stages:

```
development  -->  testing  -->  staging  -->  production
```

Promote a tag with:

```bash
./scripts/kernel_builder/kernel_tags.sh promote v5.1.5-rs-2400 --status staging
```

All status changes are recorded with timestamps and the identity of who made the change.

### Listing & Inspecting Builds

```bash
# List all tags
./scripts/kernel_builder/kernel_tags.sh list

# Filter by status
./scripts/kernel_builder/kernel_tags.sh list --status production

# Filter by kernel and show all fields
./scripts/kernel_builder/kernel_tags.sh list --kernel cartken_5_1_5_realsense --all

# Full detail view including notes and deployment history
./scripts/kernel_builder/kernel_tags.sh show v5.1.5-rs-2400

# See all kernel source directories and their tags/debs
./scripts/kernel_builder/kernel_tags.sh kernels
```

### Adding Notes

Record observations, test results, or known issues against any tag:

```bash
./scripts/kernel_builder/kernel_tags.sh notes v5.1.5-rs-2400 \
  --add "Stable after 48h soak test on 3 devices"

./scripts/kernel_builder/kernel_tags.sh notes v5.1.5-rs-2400 \
  --add "Known issue: USB3 hotplug unreliable under thermal throttling"
```

Notes are timestamped and attributed, and appear in the `show` output.

### Comparing Builds

```bash
./scripts/kernel_builder/kernel_tags.sh diff v5.1.5-base v5.1.5-rs-2400
```

This displays:
- Metadata differences (localversion, config, status, builder, etc.)
- Source git commit log between the two tags (if both exist in the same repo)
- Diffstat summary of files changed

### Deploying

The deploy command copies the `.deb` to `~/kernel_debs/` on the target by default (copy-only). Use `--install` to also run `dpkg -i`. SSH ControlMaster is used to avoid multiple password prompts, and `--password` with `sshpass` eliminates prompts entirely.

#### Single device

```bash
# Copy to a device (default: copy only to ~/kernel_debs/)
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 --ip 10.42.0.5

# Copy + install + reboot
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --ip 10.42.0.5 --install

# Copy to a custom directory
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --ip 10.42.0.5 --remote-dir /opt/kernels

# Preview without executing
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --ip 10.42.0.5 --dry-run
```

#### Fleet deploy by robot number

Use `--robots` with comma-separated numbers (ranges supported) and `--robot-ip-prefix` to construct IPs. Multiple targets are copied **in parallel** by default.

```bash
# Deploy to robots 1, 2, and 5 through 8
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --robots 1,2,5-8 --robot-ip-prefix "10.42.0."

# Same but with a password (no interactive prompts)
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --robots 1,2,5-8 --robot-ip-prefix "10.42.0." \
  --password "secret"
```

#### Fleet deploy by IP or hosts file

```bash
# Multiple --ip flags
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --ip 10.42.0.10 --ip 10.42.0.11 --ip 10.42.0.12

# From a hosts file (one IP per line, # comments allowed)
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --hosts-file fleet.txt

# Force sequential instead of parallel
./scripts/kernel_builder/kernel_tags.sh deploy v5.1.5-rs-2400 \
  --hosts-file fleet.txt --sequential
```

Fleet deploys continue to the next machine if one fails, and print a summary at the end. All successful deployments are recorded in the manifest.

### Verifying a Deployment

After deploying, confirm the device is running the correct kernel:

```bash
./scripts/kernel_builder/kernel_tags.sh verify v5.1.5-rs-2400 --ip 10.42.0.5
```

This SSHes into the device, runs `uname -r`, and checks that the output matches the tag's expected localversion. Also supports `--password` for non-interactive use.

### Tab Completion

Enable Bash tab completion for faster command entry:

```bash
source ./scripts/kernel_builder/kernel_tags_completion.bash
```

To make it permanent, add the above line to your `~/.bashrc` or `~/.zshrc`. Completion works for commands, tag names, kernel names, status values, and all option flags.

### File Layout

```
kernel_builder/
├── kernel_tags.json              # Version-controlled manifest of all tagged builds
├── kernel_archive/               # Archived .deb packages and configs (git-ignored)
│   └── v5.1.5-rs-2400/
│       ├── linux-custom-5.10.216-cartken5.1.5realsense2400.deb
│       └── kernel.config
├── kernels/                      # Kernel source directories
│   └── cartken_5_1_5_realsense/  # Tagged with git tags matching build tags
└── scripts/kernel_builder/
    ├── build_and_tag.sh          # One-shot interactive build + tag (recommended)
    ├── kernel_tags.sh            # Tag management CLI tool
    ├── kernel_tags_completion.bash  # Bash tab completion
    └── compile_and_package.sh    # Low-level build script
```

### Manifest Schema

Each entry in `kernel_tags.json` contains:

```json
{
  "tag": "v5.1.5-rs-2400",
  "kernel_name": "cartken_5_1_5_realsense",
  "localversion": "cartken5.1.5realsense2400",
  "build_date": "2026-03-23T14:30:00Z",
  "builder": "Alex <alex@example.com>",
  "repo_commit": "abc1234",
  "config": "tegra_defconfig",
  "dtb_name": "tegra234-p3737-0000+p3701-0000.dtb",
  "description": "RealSense D435 support for Orin",
  "status": "testing",
  "deb_package": "kernel_archive/v5.1.5-rs-2400/linux-custom-....deb",
  "config_archived": "kernel_archive/v5.1.5-rs-2400/kernel.config",
  "source_repos_tagged": ["kernels/cartken_5_1_5_realsense"],
  "notes": [
    { "text": "Stable after soak test", "date": "...", "by": "..." }
  ],
  "deployments": [
    { "target": "cartken@192.168.1.230", "date": "...", "by": "...", "mode": "full" }
  ],
  "status_history": [
    { "status": "development", "date": "...", "by": "..." },
    { "status": "testing", "date": "...", "by": "..." }
  ]
}
```
