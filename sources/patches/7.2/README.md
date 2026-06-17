# JetPack 7.2 kernel patches

Patches are **generated**, not hand-written. Work in the kernel tree, commit,
then export:

```bash
# 1. Edit storage/kernels/cartken_7_2/
# 2. Commit each logical change
cd storage/kernels/cartken_7_2
git commit -am "describe the change"

# 3. Refresh sources/patches/7.2/ (after build + hardware test pass)
../../../scripts/build/kernel/export_kernel_patches.sh cartken_7_2 7.2
```

`build_kernel.sh` applies these with `patch -p1 -d "$KERNEL_SRC_ROOT"`.

## Base commit

`BASE_COMMIT` records the stock JP7.2 import (`patch-base` tag in
`cartken_7_2`). That commit is not exported as a patch.

## Path mapping (vs JetPack 5.1.5)

| JP5 path | JP7 path |
|----------|----------|
| `kernel/kernel/...` | `kernel/kernel-noble/...` |
| `kernel/nvidia/drivers/media/...` | `nvidia-oot/drivers/media/...` |
| `hardware/nvidia/platform/t23x/concord/kernel-dts/...` | `hardware/nvidia/t23x/nv-public/overlay/...` |

## Port status

Fresh start from `patch-base` (2026-06-17). Port by committing in
`storage/kernels/cartken_7_2` only — reference `sources/patches/5.1.5/` for
triage, do not bulk-apply the series. Export to `sources/patches/7.2/` only
after build + hardware test.

Commit order (5.1.5 reference) — `[x]` done and building on JP7:

1. `[x]` `0012` panic logger
2. `[x]` `0017` Quectel RG255C (option serial + qmi_wwan binding)
3. `[x]` `0003` ISX031 driver (V4L2/i2c-probe/conftest fixes; -Wmissing-prototypes)
4. `[x]` `0002` / `0011` / `0027` board DT (translated to JP7 nv-public labels)
5. `[ ]` `0004`–`0006`, `0010`, `0015`–`0016`, `0025`–`0028` D4xx (one commit per patch after JP7 fixes)
6. `[ ]` `0014` UVC RealSense
7. `[ ]` `0033` rtl8192eu
8. `[ ]` `0013` defconfig → `sources/configs/7.2/defconfig` (also enables CONFIG_CARTKEN_PANIC_LOGGER)

A clean `compile_kernel.sh cartken_7_2` (kernel + OOT modules) builds green
through item 4.

Drop unless hardware needs them: `0007`, `0008`–`0009`, `0018`–`0024`, `0029`–`0032`.

Kernel config fragments live in `sources/configs/7.2/defconfig`, not in patches.
