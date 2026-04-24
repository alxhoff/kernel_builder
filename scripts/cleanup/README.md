# cleanup/

Clean build artifacts out of kernel source trees.

- `cleanup_all_kernel_builds.sh` — wipe generated files in every kernel under
  `kernels/`.
- `cleanup_jetson_kernel_builds.sh` — same, scoped to Jetson-style
  `source/kernel/` layouts, and also clears `/tmp/kernel_compile.log`.

These scripts do not touch source control; they only remove generated build
output.
