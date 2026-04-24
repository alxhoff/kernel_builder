# Fish completion for the short aliases in kernel_builder/bin/.
#
# Source from your fish config:
#   source /path/to/kernel_builder/completions/kb.fish
#
# The wrappers in bin/ just exec the underlying scripts, so this file only
# provides first-token completion (alias -> description). Flag completion for
# each command comes from whatever completion the underlying script ships
# (e.g. bin/tags delegates to scripts/release/kernel_tags_completion.bash).

# Each line: short alias, one-line description.
# Keep in sync with bin/README.md.

complete -c build       -d "Interactive build -> package -> tag -> publish (scripts/release/build_and_tag.sh)"
complete -c tags        -d "Tag management CLI (scripts/release/kernel_tags.sh)"
complete -c package     -d "Compile kernel + produce .deb (scripts/release/compile_and_package.sh)"
complete -c compile     -d "Compile a kernel (scripts/build/kernel/compile_kernel.sh)"
complete -c deploy      -d "Compile + deploy kernel + modules (scripts/deploy/compile_and_deploy_kernel.sh)"
complete -c menuconfig  -d "make menuconfig (scripts/build/kernel/menuconfig_kernel.sh)"
complete -c mrproper    -d "make mrproper (scripts/build/kernel/mrproper_kernel.sh)"
complete -c clean-builds -d "Clean Jetson kernel build artifacts"
complete -c panic       -d "Resolve kernel panic addresses (scripts/utils/kernel/resolve_kernel_panic.sh)"
complete -c chroot      -d "Enter a chroot into a Jetson rootfs (scripts/utils/chroot/jetson_chroot.sh)"
complete -c dtb         -d "DTB/DTS decompile/search/verify helper"
complete -c logs        -d "Retrieve kernel/system logs over SSH"
complete -c robot-img   -d "Build / manage robot rootfs images"
complete -c tegra-pkg   -d "Download + extract Linux_for_Tegra (Docker)"
complete -c ota-rootfs  -d "Setup rootfs as OTA-ready robot image"
complete -c gen-ctags   -d "Generate ctags index files over kernel source"
