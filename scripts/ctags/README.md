# ctags/ — Source-index (`ctags`) helpers

Small helpers for generating, locating, and removing `ctags` index files over
kernel source trees. **These are unrelated to the release tagging workflow in
[`../release/`](../release/README.md).**

| Script | What it does |
|--------|--------------|
| `generate_ctags.sh` | Run `ctags` over `kernels/<name>/kernel/` and any overlays. |
| `list_ctags_files.sh` | Find all `tags` files produced by `ctags` under a directory. |
| `delete_ctags_files.sh` | Recursively delete `tags` files under a directory. |

Each script accepts `--help`. They produce / consume the editor-friendly
`tags` file format (used by vim / Emacs / most LSP-less editors); they do
**not** touch `kernel_tags.json` or anything else under
[`../release/`](../release/README.md).

## Example

```bash
# Generate tags for a kernel source tree and its overlays
./scripts/ctags/generate_ctags.sh -k cartken_5_1_5_realsense

# List them
./scripts/ctags/list_ctags_files.sh kernels/cartken_5_1_5_realsense

# Clean them up
./scripts/ctags/delete_ctags_files.sh kernels/cartken_5_1_5_realsense
```
