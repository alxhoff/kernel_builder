# Legacy Flash Workflow

This directory contains an isolated legacy flashing path for teams that still
need the pre-SSH-CA workflow with prebuilt L4T tarballs.

It is intentionally separate from `scripts/flash/rootfs_prep/`.

## Entry point

- `robot_image_manager.sh`

## Legacy behavior this keeps

- Google Drive rootfs tarball download via `--rootfs-gid` (or `--tar` local file)
- Rootfs per-robot mutation (hostname, env, legacy `authorized_keys`, VPN certs)
- `flash.sh --no-flash` image generation and per-robot `.img` caching
- Restore + flash from cached image bundles

## Quick Start

From repo root:

```bash
cd scripts/flash/legacy
chmod +x ./robot_image_manager.sh
```

Prepare images:

```bash
sudo ./robot_image_manager.sh prepare \
  --robots 395,396 \
  --credentials-zip /path/to/carts-batch-credentials.zip
```

or, pull the certs from live robots:

```bash
sudo ./robot_image_manager.sh prepare \
  --robots 395,396 \
  --fetch-credentials \
  --password cartken
```

Flash one robot from prepared images:

```bash
sudo ./robot_image_manager.sh flash \
  --robot 395 \
  --password cartken
```

## Notes

- This flow is a compatibility path and does not include the new SSH CA
  provisioning done in the current `rootfs_prep` workflow.
- The default Google Drive id can be overridden with `--rootfs-gid`.
- Default local credentials path is `./robot_credentials`.
- `./robot_credentials` has been seeded from `scripts/flash/rootfs_prep/certs`
  for convenience.
- Generated artifacts in this directory are intentionally ignored by git.
