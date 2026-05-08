#!/bin/bash
# kb-menu-legacy — whiptail/newt UI (deprecated).
#
# Default entry point is ./bin/kb-menu → Textual (python -m kb_menu).
# Run this file directly if you need the old whiptail dialogs:
#   ./scripts/menu/kb-menu-legacy.sh
#
# Persists values in .kb-menu.config (chmod 600, gitignored).

set -uo pipefail

KB_MENU_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
KB_REPO_ROOT="$(cd "$KB_MENU_DIR/../.." && pwd)"
KB_MENU_CONFIG="$KB_MENU_DIR/.kb-menu.config"
KB_MENU_LOG="$KB_MENU_DIR/.kb-menu.last.log"

ROOTFS_PREP="$KB_REPO_ROOT/scripts/flash/rootfs_prep"
OTA_DIR="$KB_REPO_ROOT/scripts/ota"
DEPLOY_DIR="$KB_REPO_ROOT/scripts/deploy"
BUILD_KERNEL_DIR="$KB_REPO_ROOT/scripts/build/kernel"
PYTHON_KERNEL_BUILDER="$KB_REPO_ROOT/python/kernel_builder.py"
KERNEL_TAGS_SCRIPT="$KB_REPO_ROOT/scripts/release/kernel_tags.sh"
STORAGE_KERNEL_TAGS="$KB_REPO_ROOT/storage/kernel_tags.json"
STORAGE_KERNEL_ARCHIVE="$KB_REPO_ROOT/storage/kernel_archive"
STORAGE_PRODUCTION_KERNELS="$KB_REPO_ROOT/storage/production_kernels"
STORAGE_KERNEL_DEBS="$KB_REPO_ROOT/storage/kernel_debs"

# python/kernel_builder.py and several scripts use paths relative to the repo
# root (e.g. storage/kernels). The UI itself uses absolute KB_REPO_ROOT, so
# without this, "Kernel → compile" can appear to do nothing when the shell
# cwd is elsewhere.
cd "$KB_REPO_ROOT" || {
	echo "kb-menu: cannot cd to repo root: $KB_REPO_ROOT" >&2
	exit 1
}

# --- whiptail availability check -----------------------------------------
if ! command -v whiptail >/dev/null 2>&1; then
	cat >&2 <<EOF
kb-menu: whiptail is required and was not found.
  Ubuntu/Debian: sudo apt install whiptail
  Arch/Manjaro:  sudo pacman -S libnewt
EOF
	exit 1
fi

# --- Persisted config ----------------------------------------------------
declare -A CFG=(
	[JETPACK]="5.1.5"
	[SOC]="orin"
	[TAG]=""
	[ACCESS_TOKEN]=""
	[ROBOT_NUMBER]=""
	[ENV]="production"
	[HOST_CERT_VALIDITY]="48h"
	[DOCKER]=0
	[BASE_JETPACK]="5.1.5"
	[TARGET_JETPACK]="5.1.5"
	[LOCALVERSION]="-cartken5.1.5"
	[ADV_NO_DOWNLOAD]=0
	[ADV_JUST_CLONE]=0
	[ADV_SKIP_KERNEL_BUILD]=0
	[ADV_SKIP_DISPLAY_DRIVER_BUILD]=0
	[ADV_SKIP_PINMUX]=0
	[ADV_SKIP_CHROOT_BUILD]=0
	[ADV_PROMPT]=0
	[ADV_REBUILD]=0
	[ADV_INSPECT]=0
	[ADV_SKIP_VPN]=0
	[ADV_SKIP_SSH_CA]=0
	[ADV_CLEAN_ROOTFS]=0
	[ADV_DRY_RUN]=0
	# compile_and_package.sh (bin/package)
	[KERNEL_NAME]="cartken_5_1_5"
	[PACKAGE_CONFIG]=""
	[PACKAGE_THREADS]=""
	[PACKAGE_TOOLCHAIN_NAME]="aarch64-buildroot-linux-gnu"
	[PACKAGE_TOOLCHAIN_VERSION]="9.3"
	[PACKAGE_TAG]=""
	[PACKAGE_DESCRIPTION]=""
	[PACKAGE_TAG_STATUS]="development"
	[PACKAGE_DTB_NAME]=""
	[PACKAGE_OVERLAYS]=""
	[ADV_PKG_DRY_RUN]=0
	[ADV_PKG_BUILD_DTB]=0
	[ADV_PKG_BUILD_MODULES]=0
	# python/kernel_builder.py compile (compile-only, all flags)
	[COMPILE_ARCH]="arm64"
	[COMPILE_BUILD_TARGET]=""
	[COMPILE_DTB_NAME]="tegra234-p3701-0000-p3737-0000.dtb"
	[COMPILE_THREADS]=""
	[COMPILE_CONFIG]=""
	[COMPILE_OVERLAYS]=""
	[ADV_COMPILE_HOST_BUILD]=0
	[ADV_COMPILE_CLEAN]=0
	[ADV_COMPILE_USE_CURRENT_CONFIG]=0
	[ADV_COMPILE_GENERATE_CTAGS]=0
	[ADV_COMPILE_BUILD_DTB]=0
	[ADV_COMPILE_BUILD_MODULES]=0
	[ADV_COMPILE_DRY_RUN]=0
	[ADV_DOCKER_REBUILD]=0
	# kernel_tags.sh (releases / deploy / manifest)
	[KT_TAG_NAME]=""
	[KT_LOG_LIMIT]="20"
	[KT_EXPORT_FORMAT]="json"
	[KT_EXPORT_STATUS_FILTER]=""
	[KT_DEPLOY_REMOTE_DIR]="~/kernel_debs"
	[KT_LIST_STATUS_FILTER]="any"
	[ADV_KT_NO_SOURCE_TAG]=0
	[ADV_KT_NO_ARCHIVE]=0
	[ADV_KT_NO_PUBLISH]=0
	[ADV_KT_FORCE]=0
)

cfg_load() {
	[[ -r "$KB_MENU_CONFIG" ]] || return 0
	# shellcheck source=/dev/null
	. "$KB_MENU_CONFIG"
	for key in "${!CFG[@]}"; do
		var="KB_MENU_$key"
		[[ -n "${!var-}" ]] && CFG[$key]="${!var}"
	done
	# Avoid radiolist with no (*) — e.g. saved aarch64 vs options arm64.
	CFG[COMPILE_ARCH]="$(kb_menu_normalize_arch_tag "${CFG[COMPILE_ARCH]}")"
}

cfg_save() {
	{
		echo "# kb-menu persistence file (auto-generated)"
		echo "# Safe to edit but keys must stay KB_MENU_*."
		echo "# May contain a GitLab access token; chmod 600."
		for key in "${!CFG[@]}"; do
			printf 'KB_MENU_%s=%q\n' "$key" "${CFG[$key]}"
		done
	} > "$KB_MENU_CONFIG"
	chmod 600 "$KB_MENU_CONFIG" 2>/dev/null || true
}

# --- whiptail wrappers ---------------------------------------------------
WT_BACKTITLE="kb-menu — BSP/rootfs vs kernel: use Jetson BSP for L4T; use Kernel for storage/kernels — $(basename "$KB_REPO_ROOT")"
WT_TITLE="kb-menu"

# whiptail writes its result to stderr by default; the 3>&1 1>&2 2>&3 dance
# swaps stdout/stderr so we can capture the result via $().
wt() {
	whiptail --backtitle "$WT_BACKTITLE" --title "$WT_TITLE" "$@" 3>&1 1>&2 2>&3
}

# Mask all but the last 4 chars of a non-empty token for confirm dialogs.
mask_token() {
	local t="$1"
	[[ -z "$t" ]] && { echo "(empty)"; return; }
	local n=${#t}
	if (( n <= 8 )); then
		printf '*%.0s' $(seq 1 "$n")
	else
		printf '%s%s' "${t:0:6}" "$(printf '*%.0s' $(seq 1 $((n-10))))${t:$((n-4))}"
	fi
}

# Discover BSPs that have actually been extracted (rootfs/ exists).
discover_bsps() {
	local out=()
	shopt -s nullglob
	for d in "$ROOTFS_PREP"/bsp/*/Linux_for_Tegra; do
		[[ -d "$d/rootfs" ]] || continue
		out+=("$(basename "$(dirname "$d")")")
	done
	shopt -u nullglob
	printf '%s\n' "${out[@]}"
}

# List kernel trees under storage/kernels/<name>/kernel/kernel (repo-root layout).
discover_kernel_trees() {
	local out=() kd="$KB_REPO_ROOT/storage/kernels"
	shopt -s nullglob
	for d in "$kd"/*/; do
		[[ -d "${d}kernel/kernel" ]] || continue
		out+=("$(basename "$d")")
	done
	shopt -u nullglob
	printf '%s\n' "${out[@]}"
}

# Build a whiptail --radiolist tag-list from the supplied options, marking
# the one matching $current as ON.
make_radio_args() {
	local current="$1"; shift
	local tag desc
	for opt in "$@"; do
		tag="$opt"; desc="$opt"
		if [[ "$opt" == "$current" ]]; then
			printf '%s\n%s\nON\n' "$tag" "$desc"
		else
			printf '%s\n%s\nOFF\n' "$tag" "$desc"
		fi
	done
}

# Map sloppy/persisted --arch values to radiolist tags (arm64 | x86_64 | arm).
# If nothing matches, default to arm64 so whiptail always starts with one (*).
kb_menu_normalize_arch_tag() {
	local a="${1,,}"
	case "$a" in
		arm64 | aarch64) echo arm64 ;;
		x86_64 | amd64) echo x86_64 ;;
		arm | arm32 | armhf) echo arm ;;
		*) echo arm64 ;;
	esac
}

# --- Run dispatcher ------------------------------------------------------
# Closes whiptail (clear) and runs the actual command, tee'd to a log.
# Returns the command's exit code.
run_cmd() {
	clear
	echo "==> Running:"
	# Print a token-masked version of the command line for the log header.
	local masked=()
	local prev=""
	for a in "$@"; do
		if [[ "$prev" == "--access-token" ]]; then
			masked+=("$(mask_token "$a")")
		else
			masked+=("$a")
		fi
		prev="$a"
	done
	printf '    %s\n' "${masked[*]}"
	echo "    (full output also tee'd to $KB_MENU_LOG)"
	echo
	local rc=0
	"$@" 2>&1 | tee "$KB_MENU_LOG"
	rc="${PIPESTATUS[0]}"
	echo
	if (( rc == 0 )); then
		echo "==> Command finished successfully."
	else
		echo "==> Command failed with exit code $rc."
		echo "    Log: $KB_MENU_LOG"
	fi
	echo
	echo "Press Enter to return to the menu..."
	read -r
	return "$rc"
}

confirm_run() {
	local title="$1"; shift
	local body="$1"; shift
	# whiptail already uses global --title "kb-menu"; put the action line in the body.
	wt --yes-button "Run" --no-button "Back" --yesno "${title}"$'\n\n'"${body}" 26 100
}

# --- Shared form pieces --------------------------------------------------

prompt_jetpack() {
	wt --radiolist "JetPack version" 15 60 7 \
		$(make_radio_args "${CFG[JETPACK]}" 5.1.2 5.1.3 5.1.4 5.1.5 6.0DP 6.1 6.2)
}

prompt_soc() {
	wt --radiolist "SoC" 12 60 2 \
		$(make_radio_args "${CFG[SOC]}" orin xavier)
}

prompt_env() {
	wt --radiolist "Backend env" 12 60 3 \
		$(make_radio_args "${CFG[ENV]}" production staging sandbox)
}

prompt_arch() {
	local cur
	cur=$(kb_menu_normalize_arch_tag "${CFG[COMPILE_ARCH]}")
	wt --radiolist "Target architecture (--arch)\n\nPress Space on your choice so it shows (*), then OK." 16 60 3 \
		$(make_radio_args "$cur" arm64 x86_64 arm)
}

# Pick storage/kernels/<name>; sets CFG[KERNEL_NAME] and PK_KERNEL.
pick_kernel_tree() {
	PK_KERNEL=""
	local kname
	local kerns
	mapfile -t kerns < <(discover_kernel_trees)
	if (( ${#kerns[@]} == 0 )); then
		kname=$(prompt_text "Kernel tree name (under storage/kernels/)" "${CFG[KERNEL_NAME]}") || return 1
		[[ -z "$kname" ]] && { wt --msgbox "Kernel name is required." 8 60; return 1; }
	else
		local cur="${CFG[KERNEL_NAME]}" match=0
		for k in "${kerns[@]}"; do
			[[ "$k" == "$cur" ]] && { match=1; break; }
		done
		[[ $match -eq 0 ]] && cur="${kerns[0]}"
		kname=$(wt --radiolist "Kernel source (storage/kernels/)\n\nPress Space on your tree so it shows (*), then OK." 20 70 10 \
			$(make_radio_args "$cur" "${kerns[@]}")) || {
			wt --msgbox "No kernel was confirmed.\n\nTip: move to the line, press Space for (*), then OK. Cancel also exits here." 12 78
			return 1
		}
	fi
	CFG[KERNEL_NAME]="$kname"
	PK_KERNEL="$kname"
	return 0
}

# Sets CFG[COMPILE_BUILD_TARGET] and BT_PICK; empty BT_PICK = omit flag.
pick_compile_build_target() {
	BT_PICK=""
	local c custom
	c=$(wt --menu "--build-target for make / kernel_builder.py" 22 78 11 \
		"def"   "Default (omit — full compile path)" \
		"kernel" "kernel" \
		"modules" "modules" \
		"dtbs"  "dtbs" \
		"kdm"   "kernel,dtbs,modules" \
		"bindeb" "bindeb-pkg" \
		"custom" "Custom (comma-separated)…" \
		"back"  "Cancel") || return 1
	case "$c" in
		def)   BT_PICK="" ;;
		kernel) BT_PICK="kernel" ;;
		modules) BT_PICK="modules" ;;
		dtbs)  BT_PICK="dtbs" ;;
		kdm)   BT_PICK="kernel,dtbs,modules" ;;
		bindeb) BT_PICK="bindeb-pkg" ;;
		custom)
			custom=$(prompt_text "Comma-separated targets (e.g. dtbs,modules)" "${CFG[COMPILE_BUILD_TARGET]}") || return 1
			BT_PICK="$custom"
			;;
		back|"") return 1 ;;
	esac
	CFG[COMPILE_BUILD_TARGET]="$BT_PICK"
	return 0
}

prompt_toolchain_pair() {
	local n v
	# Use saved values from .kb-menu.config; prompt only if either is empty.
	if [[ -n "${CFG[PACKAGE_TOOLCHAIN_NAME]}" && -n "${CFG[PACKAGE_TOOLCHAIN_VERSION]}" ]]; then
		TOOL_NAME="${CFG[PACKAGE_TOOLCHAIN_NAME]}"
		TOOL_VER="${CFG[PACKAGE_TOOLCHAIN_VERSION]}"
		return 0
	fi
	n=$(prompt_text "--toolchain-name" "${CFG[PACKAGE_TOOLCHAIN_NAME]}") || return 1
	v=$(prompt_text "--toolchain-version" "${CFG[PACKAGE_TOOLCHAIN_VERSION]}") || return 1
	TOOL_NAME="$n"
	TOOL_VER="$v"
	return 0
}

# kernel_tags.sh: deployment status (not to confuse with GitLab TAG / flash tag).
prompt_kt_status() {
	wt --radiolist "Deployment status" 14 70 4 \
		$(make_radio_args "${CFG[PACKAGE_TAG_STATUS]}" development testing staging production)
}

prompt_kt_tag_name() {
	prompt_text "Kernel build tag name (e.g. 240426, v5.1.5-rs-2400)" "${CFG[KT_TAG_NAME]:-${CFG[TAG]}}"
}

prompt_text() {
	local label="$1" cur="$2" pwd_mode="${3:-0}"
	if [[ "$pwd_mode" -eq 1 ]]; then
		wt --passwordbox "$label" 10 78 "$cur"
	else
		wt --inputbox "$label" 10 78 "$cur"
	fi
}

# Optional --localversion for compile-like flows. Menu (not a bare inputbox):
# whiptail Cancel/Esc is easy to hit by mistake, so we use --default-item
# skip, --nocancel, and explicit "Exit wizard" instead of a Cancel button.
# Prints suffix to stdout; exit 0 on success, 1 only for "Exit wizard".
prompt_localversion_optional() {
	local action init v
	init="${CFG[LOCALVERSION]#-}"
	action=$(wt --default-item skip --nocancel --menu \
		"--localversion (optional, step after arch)\n\nMost builds: Omit (already selected) + OK. Set = type a suffix. Exit wizard = abort." \
		18 78 4 \
		"skip" "Omit (no --localversion)" \
		"set"  "Enter or edit a suffix..." \
		"back" "Exit compile wizard") || return 1
	case "$action" in
		skip)
			printf '%s' ""
			return 0
			;;
		set)
			v=$(prompt_text "Suffix only (no leading -). Empty + OK still omits." "$init") || return 1
			v="${v#-}"
			printf '%s' "$v"
			return 0
			;;
		back) return 1 ;;
	esac
	return 1
}

# --- Advanced options checklist ------------------------------------------
# $1: comma-separated list of CFG ADV_* keys to expose in this context.

form_advanced_options() {
	local keys_csv="$1"
	IFS=',' read -ra keys <<< "$keys_csv"
	local args=()
	declare -A label=(
		[ADV_NO_DOWNLOAD]="--no-download (use existing tarballs in downloads/)"
		[ADV_JUST_CLONE]="--just-clone (only pull sources, do nothing else)"
		[ADV_SKIP_KERNEL_BUILD]="--skip-kernel-build"
		[ADV_SKIP_DISPLAY_DRIVER_BUILD]="--skip-display-driver-build"
		[ADV_SKIP_PINMUX]="--skip-pinmux"
		[ADV_SKIP_CHROOT_BUILD]="--skip-chroot-build"
		[ADV_PROMPT]="--prompt (pause before each major step)"
		[ADV_REBUILD]="--rebuild (force-rebuild Docker image, --docker only)"
		[ADV_INSPECT]="--inspect (drop into shell instead of running, --docker only)"
		[ADV_SKIP_VPN]="--skip-vpn"
		[ADV_SKIP_SSH_CA]="--skip-ssh-ca"
		[ADV_CLEAN_ROOTFS]="--clean-rootfs (wipe rootfs and rebuild)"
		[ADV_DRY_RUN]="--dry-run"
		[ADV_PKG_DRY_RUN]="--dry-run (package / compile only)"
		[ADV_PKG_BUILD_DTB]="--build-dtb"
		[ADV_PKG_BUILD_MODULES]="--build-modules"
		[ADV_COMPILE_HOST_BUILD]="--host-build (no Docker)"
		[ADV_COMPILE_CLEAN]="--clean (mrproper before build)"
		[ADV_COMPILE_USE_CURRENT_CONFIG]="--use-current-config (/proc/config.gz)"
		[ADV_COMPILE_GENERATE_CTAGS]="--generate-ctags"
		[ADV_COMPILE_BUILD_DTB]="--build-dtb"
		[ADV_COMPILE_BUILD_MODULES]="--build-modules"
		[ADV_COMPILE_DRY_RUN]="--dry-run"
		[ADV_KT_NO_SOURCE_TAG]="tag: --no-source-tag"
		[ADV_KT_NO_ARCHIVE]="tag: --no-archive"
		[ADV_KT_NO_PUBLISH]="tag: --no-publish"
		[ADV_KT_FORCE]="tag: --force (overwrite tag)"
	)
	for k in "${keys[@]}"; do
		local on="OFF"
		[[ "${CFG[$k]}" == "1" ]] && on="ON"
		args+=("$k" "${label[$k]}" "$on")
	done
	# Whiptail returns selected tags space-separated; un-selected keys must
	# be cleared here too.
	local selected
	selected=$(wt --separate-output --checklist \
		"Advanced options (space to toggle, Enter to confirm)" 22 100 13 \
		"${args[@]}") || return 1
	# Reset all exposed keys to 0, then set the selected ones to 1.
	for k in "${keys[@]}"; do CFG[$k]=0; done
	while IFS= read -r k; do
		[[ -n "$k" ]] && CFG[$k]=1
	done <<< "$selected"
	return 0
}

# --- Token helper --------------------------------------------------------
# If we don't yet have a saved token, prompt for one and save it. If we do,
# offer to reuse, replace, or clear it.

ensure_access_token() {
	local label="GitLab access token"
	if [[ -z "${CFG[ACCESS_TOKEN]}" ]]; then
		local t
		t=$(prompt_text "$label (will be saved to .kb-menu.config, chmod 600)" "" 1) || return 1
		[[ -z "$t" ]] && return 1
		CFG[ACCESS_TOKEN]="$t"
		cfg_save
		return 0
	fi
	local choice
	choice=$(wt --menu "Saved $label: $(mask_token "${CFG[ACCESS_TOKEN]}")" 14 70 4 \
		"reuse"   "Use the saved token" \
		"replace" "Enter a new token" \
		"clear"   "Forget the saved token and prompt") || return 1
	case "$choice" in
		reuse) return 0 ;;
		replace)
			local t
			t=$(prompt_text "New $label" "" 1) || return 1
			[[ -z "$t" ]] && return 1
			CFG[ACCESS_TOKEN]="$t"
			cfg_save
			;;
		clear)
			CFG[ACCESS_TOKEN]=""
			cfg_save
			ensure_access_token
			;;
	esac
}

# =========================================================================
# Jetson BSP & rootfs (L4T / Linux_for_Tegra — not kernel tree compile)
# =========================================================================
menu_jetson_bsp_rootfs() {
	while true; do
		local choice
		choice=$(wt --menu "Jetson BSP & rootfs" 22 78 5 \
			"prepare" "Prepare BSP + rootfs (setup_tegra_package.sh)" \
			"flashimg" "Robot flash rootfs (setup_rootfs_as_robot_for_flashing.sh)" \
			"both"    "Prepare BSP, then robot flash rootfs (two steps in a row)" \
			"back"    "Back to main menu") || return
		case "$choice" in
			prepare) menu_build_bsp ;;
			flashimg) menu_flash_robot ;;
			both)    menu_build_and_flash ;;
			back|"") return ;;
		esac
	done
}

# =========================================================================
# 1) Prepare BSP & rootfs (setup_tegra_package.sh)
# =========================================================================
menu_build_bsp() {
	local jp soc tag mode docker_choice
	jp=$(prompt_jetpack) || return
	soc=$(prompt_soc)    || return
	tag=$(prompt_text "GitLab tag (e.g. v7.5.0-sshca8)" "${CFG[TAG]}") || return
	[[ -z "$tag" ]] && { wt --msgbox "Tag is required for setup_tegra_package.sh." 8 60; return; }
	docker_choice=$(wt --radiolist "Run mode" 12 70 2 \
		$(make_radio_args "$([[ ${CFG[DOCKER]} == 1 ]] && echo Docker || echo Native)" Native Docker)) || return
	ensure_access_token || return

	form_advanced_options \
		"ADV_NO_DOWNLOAD,ADV_JUST_CLONE,ADV_SKIP_KERNEL_BUILD,ADV_SKIP_DISPLAY_DRIVER_BUILD,ADV_SKIP_PINMUX,ADV_SKIP_CHROOT_BUILD,ADV_PROMPT,ADV_REBUILD,ADV_INSPECT" \
		|| return

	CFG[JETPACK]="$jp"; CFG[SOC]="$soc"; CFG[TAG]="$tag"
	CFG[DOCKER]=$([[ "$docker_choice" == "Docker" ]] && echo 1 || echo 0)
	cfg_save

	local cmd=( sudo "$ROOTFS_PREP/setup_tegra_package.sh"
		--jetpack "$jp" --soc "$soc"
		--access-token "${CFG[ACCESS_TOKEN]}" --tag "$tag" )
	[[ ${CFG[DOCKER]} == 1 ]]                     && cmd+=( --docker )
	[[ ${CFG[ADV_NO_DOWNLOAD]} == 1 ]]            && cmd+=( --no-download )
	[[ ${CFG[ADV_JUST_CLONE]} == 1 ]]             && cmd+=( --just-clone )
	[[ ${CFG[ADV_SKIP_KERNEL_BUILD]} == 1 ]]      && cmd+=( --skip-kernel-build )
	[[ ${CFG[ADV_SKIP_DISPLAY_DRIVER_BUILD]} == 1 ]] && cmd+=( --skip-display-driver-build )
	[[ ${CFG[ADV_SKIP_PINMUX]} == 1 ]]            && cmd+=( --skip-pinmux )
	[[ ${CFG[ADV_SKIP_CHROOT_BUILD]} == 1 ]]      && cmd+=( --skip-chroot-build )
	[[ ${CFG[ADV_PROMPT]} == 1 ]]                 && cmd+=( --prompt )
	[[ ${CFG[ADV_REBUILD]} == 1 && ${CFG[DOCKER]} == 1 ]] && cmd+=( --rebuild )
	[[ ${CFG[ADV_INSPECT]} == 1 && ${CFG[DOCKER]} == 1 ]] && cmd+=( --inspect )

	local body="Prepare Linux_for_Tegra + rootfs (setup_tegra_package.sh).\n\n  jetpack:       $jp\n  soc:           $soc\n  tag:           $tag\n  mode:          $docker_choice\n  access-token:  $(mask_token "${CFG[ACCESS_TOKEN]}")"
	confirm_run "BSP: prepare rootfs" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 2) Robot flash rootfs (setup_rootfs_as_robot_for_flashing.sh)
# =========================================================================
menu_flash_robot() {
	local target_bsp soc robot env validity tag use_tag
	local bsps; mapfile -t bsps < <(discover_bsps)
	if (( ${#bsps[@]} == 0 )); then
		target_bsp=$(prompt_text "Target BSP (no extracted BSPs found under bsp/; type a version)" "${CFG[JETPACK]}") || return
	else
		target_bsp=$(wt --radiolist "Target BSP (from bsp/)" 14 60 6 \
			$(make_radio_args "${CFG[JETPACK]}" "${bsps[@]}")) || return
	fi
	soc=$(prompt_soc) || return
	robot=$(prompt_text "Robot number" "${CFG[ROBOT_NUMBER]}") || return
	[[ -z "$robot" ]] && { wt --msgbox "Robot number is required." 8 60; return; }
	env=$(prompt_env) || return
	validity=$(prompt_text "Host cert validity (e.g. 48h, 7d)" "${CFG[HOST_CERT_VALIDITY]}") || return
	wt --yesno "Pull a fresh cartken --tag during flash?" 8 70 && use_tag=1 || use_tag=0
	if (( use_tag == 1 )); then
		tag=$(prompt_text "GitLab tag" "${CFG[TAG]}") || return
		ensure_access_token || return
	fi

	form_advanced_options "ADV_SKIP_VPN,ADV_SKIP_SSH_CA,ADV_CLEAN_ROOTFS,ADV_DRY_RUN" || return

	CFG[JETPACK]="$target_bsp"; CFG[SOC]="$soc"; CFG[ROBOT_NUMBER]="$robot"
	CFG[ENV]="$env"; CFG[HOST_CERT_VALIDITY]="$validity"
	[[ -n "${tag-}" ]] && CFG[TAG]="$tag"
	cfg_save

	local cmd=( sudo "$ROOTFS_PREP/setup_rootfs_as_robot_for_flashing.sh"
		--target-bsp "$target_bsp" --soc "$soc"
		--robot-number "$robot" --env "$env"
		--host-cert-validity "$validity" )
	if (( use_tag == 1 )); then
		cmd+=( --tag "$tag" --access-token "${CFG[ACCESS_TOKEN]}" )
	fi
	[[ ${CFG[ADV_SKIP_VPN]}      == 1 ]] && cmd+=( --skip-vpn )
	[[ ${CFG[ADV_SKIP_SSH_CA]}   == 1 ]] && cmd+=( --skip-ssh-ca )
	[[ ${CFG[ADV_CLEAN_ROOTFS]}  == 1 ]] && cmd+=( --clean-rootfs )
	[[ ${CFG[ADV_DRY_RUN]}       == 1 ]] && cmd+=( --dry-run )

	local body="Robot flash rootfs (setup_rootfs_as_robot_for_flashing.sh).\n\n  target-bsp:        $target_bsp\n  soc:               $soc\n  robot:             cart$robot\n  env:               $env\n  host-cert-validity: $validity\n  tag:               ${tag:-(unchanged)}\n\nFlashes the device in recovery mode."
	confirm_run "BSP: robot flash rootfs" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 3) Prepare BSP then robot flash rootfs (chained)
# =========================================================================
menu_build_and_flash() {
	wt --msgbox "Two-step workflow:\n\n  1) Prepare BSP + rootfs (L4T / setup_tegra_package)\n  2) Robot flash rootfs (SSH CA, packages, flash)\n\nStep 2 pre-fills from step 1.\n\n(This is not the same as Kernel → compile.)" 14 75 || return
	menu_build_bsp
	wt --yesno "Step 1 done. Run step 2 (robot flash rootfs)?" 8 60 || return
	menu_flash_robot
}

# =========================================================================
# 4) OTA submenu
# =========================================================================
menu_ota_payload() {
	local tag base target
	tag=$(prompt_text "GitLab tag" "${CFG[TAG]}") || return
	[[ -z "$tag" ]] && { wt --msgbox "Tag is required." 8 60; return; }
	base=$(prompt_text "Base JetPack version" "${CFG[BASE_JETPACK]}") || return
	target=$(prompt_text "Target JetPack version" "${CFG[TARGET_JETPACK]}") || return
	ensure_access_token || return
	form_advanced_options "ADV_DRY_RUN" || return

	CFG[TAG]="$tag"; CFG[BASE_JETPACK]="$base"; CFG[TARGET_JETPACK]="$target"
	cfg_save

	local cmd=( sudo "$OTA_DIR/create_full_ota_update.sh"
		--access-token "${CFG[ACCESS_TOKEN]}" --tag "$tag"
		--base-jetpack "$base" --target-jetpack "$target" )
	[[ ${CFG[ADV_DRY_RUN]} == 1 ]] && cmd+=( --dry-run )

	local body="About to run create_full_ota_update.sh:\n\n  tag:            $tag\n  base-jetpack:   $base\n  target-jetpack: $target"
	confirm_run "OTA payload build" "$body" || return
	run_cmd "${cmd[@]}" || true
}

menu_ota_rootfs() {
	local robot soc tag target base
	robot=$(prompt_text "Robot number" "${CFG[ROBOT_NUMBER]}") || return
	[[ -z "$robot" ]] && { wt --msgbox "Robot number is required." 8 60; return; }
	soc=$(prompt_soc) || return
	tag=$(prompt_text "GitLab tag" "${CFG[TAG]}") || return
	target=$(prompt_text "Target BSP version" "${CFG[TARGET_JETPACK]}") || return
	base=$(prompt_text "Base BSP version"   "${CFG[BASE_JETPACK]}") || return
	form_advanced_options "ADV_SKIP_VPN,ADV_DRY_RUN" || return

	CFG[ROBOT_NUMBER]="$robot"; CFG[SOC]="$soc"; CFG[TAG]="$tag"
	CFG[TARGET_JETPACK]="$target"; CFG[BASE_JETPACK]="$base"
	cfg_save

	local cmd=( sudo "$OTA_DIR/setup_rootfs_as_robot_for_ota.sh"
		--robot-number "$robot" --soc "$soc"
		--tag "$tag" --target-bsp "$target" --base-bsp "$base" )
	[[ ${CFG[ADV_SKIP_VPN]} == 1 ]] && cmd+=( --skip-vpn )
	[[ ${CFG[ADV_DRY_RUN]}  == 1 ]] && cmd+=( --dry-run )

	local body="About to run setup_rootfs_as_robot_for_ota.sh:\n\n  robot:       cart$robot\n  soc:         $soc\n  tag:         $tag\n  target-bsp:  $target\n  base-bsp:    $base"
	confirm_run "OTA rootfs config" "$body" || return
	run_cmd "${cmd[@]}" || true
}

menu_ota() {
	while true; do
		local choice
		choice=$(wt --menu "OTA (over-the-air)" 16 74 4 \
			"payload" "Full OTA payload (create_full_ota_update.sh)" \
			"rootfs"  "OTA-ready rootfs (setup_rootfs_as_robot_for_ota.sh)" \
			"back"    "Back to main menu") || return
		case "$choice" in
			payload) menu_ota_payload ;;
			rootfs)  menu_ota_rootfs  ;;
			back|"") return ;;
		esac
	done
}

# =========================================================================
# 5a) Package kernel .deb (compile_and_package.sh — same as bin/package)
# =========================================================================
menu_kernel_package() {
	local kname lv config threads tc_name tc_ver tag desc tag_status overlays
	pick_kernel_tree || return
	kname="$PK_KERNEL"

	lv=$(prompt_text "--localversion (e.g. cartken5.1.5.4lane)" "${CFG[LOCALVERSION]#-}") || return
	[[ -z "$lv" ]] && { wt --msgbox "--localversion is required." 8 60; return; }

	config=$(prompt_text "--config (e.g. defconfig; empty = omit, use tree default)" "${CFG[PACKAGE_CONFIG]}") || return

	threads=$(prompt_text "Compile threads (empty = script default)" "${CFG[PACKAGE_THREADS]}") || return
	prompt_toolchain_pair || return
	tc_name="$TOOL_NAME"
	tc_ver="$TOOL_VER"

	overlays=$(prompt_text "Optional: --overlays comma-list (empty to skip)" "${CFG[PACKAGE_OVERLAYS]}") || return

	form_advanced_options "ADV_PKG_DRY_RUN,ADV_PKG_BUILD_DTB,ADV_PKG_BUILD_MODULES" || return

	tag=$(prompt_text "Optional: --tag (kernel_tags / archive; empty to skip)" "${CFG[PACKAGE_TAG]}") || return
	desc=$(prompt_text "Optional: --description (with --tag)" "${CFG[PACKAGE_DESCRIPTION]}") || return
	tag_status=$(prompt_text "Optional: --tag-status (default development)" "${CFG[PACKAGE_TAG_STATUS]}") || return

	CFG[KERNEL_NAME]="$kname"
	CFG[LOCALVERSION]="$lv"
	CFG[PACKAGE_CONFIG]="$config"
	CFG[PACKAGE_THREADS]="$threads"
	CFG[PACKAGE_TOOLCHAIN_NAME]="$tc_name"
	CFG[PACKAGE_TOOLCHAIN_VERSION]="$tc_ver"
	CFG[PACKAGE_OVERLAYS]="$overlays"
	CFG[PACKAGE_TAG]="$tag"
	CFG[PACKAGE_DESCRIPTION]="$desc"
	[[ -n "$tag_status" ]] && CFG[PACKAGE_TAG_STATUS]="$tag_status"
	cfg_save

	local cmd=( "$KB_REPO_ROOT/scripts/release/compile_and_package.sh" "$kname"
		--localversion "$lv"
		--toolchain-name "$tc_name"
		--toolchain-version "$tc_ver" )
	[[ -n "$config" ]] && cmd+=( --config "$config" )
	[[ -n "$threads" ]] && cmd+=( --threads "$threads" )
	[[ -n "${CFG[PACKAGE_DTB_NAME]}" ]] && cmd+=( --dtb-name "${CFG[PACKAGE_DTB_NAME]}" )
	[[ -n "$overlays" ]] && cmd+=( --overlays "$overlays" )
	[[ ${CFG[ADV_PKG_DRY_RUN]} == 1 ]] && cmd+=( --dry-run )
	[[ ${CFG[ADV_PKG_BUILD_DTB]} == 1 ]] && cmd+=( --build-dtb )
	[[ ${CFG[ADV_PKG_BUILD_MODULES]} == 1 ]] && cmd+=( --build-modules )
	if [[ -n "$tag" ]]; then
		cmd+=( --tag "$tag" )
		[[ -n "$desc" ]] && cmd+=( --description "$desc" )
		[[ -n "${CFG[PACKAGE_TAG_STATUS]}" ]] && cmd+=( --tag-status "${CFG[PACKAGE_TAG_STATUS]}" )
	fi

	local body
	body=$(
		printf 'compile_and_package.sh (same as bin/package):\n\n'
		printf '  kernel:          %s\n' "$kname"
		printf '  --localversion:  %s\n' "$lv"
		[[ -n "$config" ]] && printf '  --config:        %s\n' "$config"
		printf '  toolchain:       %s / %s\n' "$tc_name" "$tc_ver"
		[[ -n "$threads" ]] && printf '  --threads:       %s\n' "$threads"
		[[ -n "${CFG[PACKAGE_DTB_NAME]}" ]] && printf '  --dtb-name:      %s\n' "${CFG[PACKAGE_DTB_NAME]}"
		[[ -n "$overlays" ]] && printf '  --overlays:      %s\n' "$overlays"
		[[ -n "$tag" ]] && printf '  --tag:           %s\n' "$tag"
	)
	confirm_run "Kernel: build .deb package" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 5b) Compile only — python/kernel_builder.py compile (all flags)
# =========================================================================
menu_kernel_compile() {
	local kname arch lv config threads overlays TOOL_NAME TOOL_VER
	pick_kernel_tree || return
	kname="$PK_KERNEL"
	arch=$(prompt_arch) || {
		wt --msgbox "Architecture was not confirmed.\n\nTip: press Space on arm64 / x86_64 / arm so it shows (*), then OK." 12 78
		return
	}
	lv=$(prompt_localversion_optional) || {
		wt --msgbox "Compile wizard stopped at localversion.\n\nYou chose Exit compile wizard, or the dialog failed to open." 10 72
		return
	}
	config=$(prompt_text "--config (empty to omit)" "${CFG[COMPILE_CONFIG]}") || return
	pick_compile_build_target || return
	threads=$(prompt_text "--threads (empty = all cores)" "${CFG[COMPILE_THREADS]}") || return
	overlays=$(prompt_text "--overlays comma-list (empty to omit)" "${CFG[COMPILE_OVERLAYS]}") || return
	prompt_toolchain_pair || return

	form_advanced_options \
		"ADV_COMPILE_HOST_BUILD,ADV_COMPILE_CLEAN,ADV_COMPILE_USE_CURRENT_CONFIG,ADV_COMPILE_GENERATE_CTAGS,ADV_COMPILE_BUILD_DTB,ADV_COMPILE_BUILD_MODULES,ADV_COMPILE_DRY_RUN" \
		|| return

	CFG[COMPILE_ARCH]="$arch"
	CFG[COMPILE_CONFIG]="$config"
	CFG[COMPILE_THREADS]="$threads"
	CFG[COMPILE_OVERLAYS]="$overlays"
	CFG[PACKAGE_TOOLCHAIN_NAME]="$TOOL_NAME"
	CFG[PACKAGE_TOOLCHAIN_VERSION]="$TOOL_VER"
	[[ -n "$lv" ]] && CFG[LOCALVERSION]="$lv"
	cfg_save

	local cmd=(
		python3 "$PYTHON_KERNEL_BUILDER" compile
		--kernel-name "$kname"
		--arch "$arch"
		--toolchain-name "$TOOL_NAME"
		--toolchain-version "$TOOL_VER"
	)
	[[ -n "$config" ]] && cmd+=( --config "$config" )
	[[ -n "$lv" ]] && cmd+=( --localversion "$lv" )
	[[ -n "$threads" ]] && cmd+=( --threads "$threads" )
	[[ -n "${CFG[COMPILE_BUILD_TARGET]}" ]] && cmd+=( --build-target "${CFG[COMPILE_BUILD_TARGET]}" )
	[[ -n "${CFG[COMPILE_DTB_NAME]}" ]] && cmd+=( --dtb-name "${CFG[COMPILE_DTB_NAME]}" )
	[[ -n "$overlays" ]] && cmd+=( --overlays "$overlays" )
	[[ ${CFG[ADV_COMPILE_HOST_BUILD]} == 1 ]] && cmd+=( --host-build )
	[[ ${CFG[ADV_COMPILE_CLEAN]} == 1 ]] && cmd+=( --clean )
	[[ ${CFG[ADV_COMPILE_USE_CURRENT_CONFIG]} == 1 ]] && cmd+=( --use-current-config )
	[[ ${CFG[ADV_COMPILE_GENERATE_CTAGS]} == 1 ]] && cmd+=( --generate-ctags )
	[[ ${CFG[ADV_COMPILE_BUILD_DTB]} == 1 ]] && cmd+=( --build-dtb )
	[[ ${CFG[ADV_COMPILE_BUILD_MODULES]} == 1 ]] && cmd+=( --build-modules )
	[[ ${CFG[ADV_COMPILE_DRY_RUN]} == 1 ]] && cmd+=( --dry-run )

	local body
	body=$(
		printf 'python/kernel_builder.py compile\n\n'
		printf '  kernel:     %s\n' "$kname"
		printf '  arch:       %s\n' "$arch"
		printf '  toolchain:  %s / %s\n' "$TOOL_NAME" "$TOOL_VER"
		[[ -n "$lv" ]] && printf '  localversion: %s\n' "$lv"
		[[ -n "$config" ]] && printf '  config:     %s\n' "$config"
		[[ -n "${CFG[COMPILE_BUILD_TARGET]}" ]] && printf '  build-target: %s\n' "${CFG[COMPILE_BUILD_TARGET]}"
		[[ -n "$threads" ]] && printf '  threads:    %s\n' "$threads"
		[[ -n "${CFG[COMPILE_DTB_NAME]}" ]] && printf '  dtb-name:   %s\n' "${CFG[COMPILE_DTB_NAME]}"
		[[ -n "$overlays" ]] && printf '  overlays:   %s\n' "$overlays"
	)
	confirm_run "Kernel: compile (no .deb)" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 5c) modules-only shortcut (--build-target modules)
# =========================================================================
menu_kernel_modules_only() {
	local kname arch lv config threads TOOL_NAME TOOL_VER
	pick_kernel_tree || return
	kname="$PK_KERNEL"
	arch=$(prompt_arch) || {
		wt --msgbox "Architecture was not confirmed.\n\nTip: press Space on your choice so it shows (*), then OK." 12 78
		return
	}
	prompt_toolchain_pair || return
	lv=$(prompt_localversion_optional) || {
		wt --msgbox "Modules-only wizard stopped at localversion.\n\nYou chose Exit compile wizard, or the dialog failed." 10 72
		return
	}
	config=$(prompt_text "--config (empty to omit)" "${CFG[COMPILE_CONFIG]}") || return
	threads=$(prompt_text "--threads (empty = all cores)" "${CFG[COMPILE_THREADS]}") || return
	form_advanced_options "ADV_COMPILE_HOST_BUILD,ADV_COMPILE_DRY_RUN" || return

	CFG[COMPILE_ARCH]="$arch"
	CFG[COMPILE_CONFIG]="$config"
	CFG[COMPILE_THREADS]="$threads"
	CFG[PACKAGE_TOOLCHAIN_NAME]="$TOOL_NAME"
	CFG[PACKAGE_TOOLCHAIN_VERSION]="$TOOL_VER"
	[[ -n "$lv" ]] && CFG[LOCALVERSION]="$lv"
	cfg_save

	local cmd=(
		python3 "$PYTHON_KERNEL_BUILDER" compile
		--kernel-name "$kname"
		--arch "$arch"
		--toolchain-name "$TOOL_NAME"
		--toolchain-version "$TOOL_VER"
		--build-target modules
	)
	[[ -n "$config" ]] && cmd+=( --config "$config" )
	[[ -n "$lv" ]] && cmd+=( --localversion "$lv" )
	[[ -n "$threads" ]] && cmd+=( --threads "$threads" )
	[[ ${CFG[ADV_COMPILE_HOST_BUILD]} == 1 ]] && cmd+=( --host-build )
	[[ ${CFG[ADV_COMPILE_DRY_RUN]} == 1 ]] && cmd+=( --dry-run )

	confirm_run "Kernel: modules only" "kernel_builder.py compile … --build-target modules\n\n  kernel: $kname  arch: $arch" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 5d) Kconfig UIs (scripts/build/kernel/*config*.sh)
# =========================================================================
menu_kernel_kconfig() {
	while true; do
		local ui script
		ui=$(wt --menu "Kernel: Kconfig editors" 20 74 6 \
			"menuconfig" "make menuconfig (menuconfig_kernel.sh)" \
			"nconfig"    "make nconfig (nconfig_kernel.sh)" \
			"xconfig"    "make xconfig (xconfig_kernel.sh, needs DISPLAY)" \
			"savedef"    "make savedefconfig (savedefconfig.sh)" \
			"back"       "Back") || return
		case "$ui" in
			back|"") return ;;
		esac
		pick_kernel_tree || continue
		local TOOL_NAME TOOL_VER
		prompt_toolchain_pair || continue
		case "$ui" in
			menuconfig) script="menuconfig_kernel.sh" ;;
			nconfig)    script="nconfig_kernel.sh" ;;
			xconfig)    script="xconfig_kernel.sh" ;;
			savedef)    script="savedefconfig.sh" ;;
			*) continue ;;
		esac
		local body
		body="Run $script\n\n  kernel:    $PK_KERNEL\n  toolchain: $TOOL_NAME / $TOOL_VER"
		confirm_run "Kconfig: $ui" "$body" || continue
		run_cmd "$BUILD_KERNEL_DIR/$script" \
			--toolchain-name "$TOOL_NAME" \
			--toolchain-version "$TOOL_VER" \
			"$PK_KERNEL" || true
	done
}

# =========================================================================
# 5e) make clean / mrproper
# =========================================================================
menu_kernel_clean() {
	local arch dry=0 TOOL_NAME TOOL_VER
	pick_kernel_tree || return
	arch=$(prompt_arch) || return
	prompt_toolchain_pair || return
	if wt --yesno "Dry-run only? (print commands, do not run make)" 8 70; then
		dry=1
	fi
	local cmd=(
		"$BUILD_KERNEL_DIR/clean_kernel.sh"
		--kernel-name "$PK_KERNEL"
		--arch "$arch"
		--toolchain-name "$TOOL_NAME"
		--toolchain-version "$TOOL_VER"
	)
	[[ "$dry" == 1 ]] && cmd+=( --dry-run )
	confirm_run "make clean" "clean_kernel.sh --kernel-name $PK_KERNEL --arch $arch" || return
	run_cmd "${cmd[@]}" || true
}

menu_kernel_mrproper() {
	local arch dry=0 TOOL_NAME TOOL_VER
	pick_kernel_tree || return
	arch=$(prompt_arch) || return
	prompt_toolchain_pair || return
	if wt --yesno "Dry-run only?" 8 70; then
		dry=1
	fi
	local cmd=(
		"$BUILD_KERNEL_DIR/mrproper_kernel.sh"
		--kernel-name "$PK_KERNEL"
		--arch "$arch"
		--toolchain-name "$TOOL_NAME"
		--toolchain-version "$TOOL_VER"
	)
	[[ "$dry" == 1 ]] && cmd+=( --dry-run )
	confirm_run "make mrproper" "mrproper_kernel.sh --kernel-name $PK_KERNEL --arch $arch\n\nThis wipes the kernel build tree." || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 5f) Docker image for kernel_builder.py
# =========================================================================
menu_kernel_docker() {
	while true; do
		local d
		d=$(wt --menu "Kernel: Docker image" 16 74 5 \
			"build"   "python kernel_builder.py build" \
			"rebuild" "python kernel_builder.py build --rebuild" \
			"inspect" "python kernel_builder.py inspect" \
			"cleanup" "python kernel_builder.py cleanup" \
			"back"    "Back") || return
		case "$d" in
			build)
				confirm_run "Docker build" "Build the kernel_builder image (may take a while)." || continue
				run_cmd python3 "$PYTHON_KERNEL_BUILDER" build || true
				;;
			rebuild)
				confirm_run "Docker rebuild" "Rebuild the kernel_builder image without cache." || continue
				run_cmd python3 "$PYTHON_KERNEL_BUILDER" build --rebuild || true
				;;
			inspect)
				run_cmd python3 "$PYTHON_KERNEL_BUILDER" inspect || true
				;;
			cleanup)
				confirm_run "Docker cleanup" "Remove kernel_builder Docker image and prune." || continue
				run_cmd python3 "$PYTHON_KERNEL_BUILDER" cleanup || true
				;;
			back|"") return ;;
		esac
	done
}

# =========================================================================
# 5) Kernel submenu
# =========================================================================
menu_kernel_workflows() {
	while true; do
		local choice
		choice=$(wt --menu "Kernel (storage/kernels/…)" 26 78 12 \
			"compile"  "Compile kernel — no .deb (kernel_builder.py compile)" \
			"package"  "Compile + Debian package (compile_and_package.sh)" \
			"modules"  "Compile out-of-tree modules only (make modules)" \
			"kconfig"  "Edit configuration — menuconfig / nconfig / xconfig / savedefconfig" \
			"clean"    "make clean — drop build artifacts (clean_kernel.sh)" \
			"mrproper" "make mrproper — full tree reset (mrproper_kernel.sh)" \
			"docker"   "Kernel-builder container — image build / inspect / cleanup" \
			"rebuild"  "Rebuild inside BSP tree (Linux_for_Tegra/build_kernel.sh)" \
			"back"     "Back to main menu") || return
		case "$choice" in
			compile)  menu_kernel_compile ;;
			package)  menu_kernel_package ;;
			modules)  menu_kernel_modules_only ;;
			kconfig)  menu_kernel_kconfig ;;
			clean)    menu_kernel_clean ;;
			mrproper) menu_kernel_mrproper ;;
			docker)   menu_kernel_docker ;;
			rebuild)  menu_kernel_rebuild ;;
			back|"")  return ;;
		esac
	done
}

menu_kernel_rebuild() {
	local target_bsp localversion
	local bsps; mapfile -t bsps < <(discover_bsps)
	if (( ${#bsps[@]} == 0 )); then
		wt --msgbox "No extracted BSPs found under bsp/. Build one first." 8 70
		return
	fi
	target_bsp=$(wt --radiolist "Target BSP" 14 60 6 \
		$(make_radio_args "${CFG[JETPACK]}" "${bsps[@]}")) || return
	localversion=$(prompt_text "--localversion (kernel suffix)" "${CFG[LOCALVERSION]}") || return

	CFG[JETPACK]="$target_bsp"; CFG[LOCALVERSION]="$localversion"; cfg_save

	local tegra_dir="$ROOTFS_PREP/bsp/$target_bsp/Linux_for_Tegra"
	if [[ ! -x "$tegra_dir/build_kernel.sh" ]]; then
		wt --msgbox "$tegra_dir/build_kernel.sh not found.\nDid setup_tegra_package.sh stage the helpers into this BSP?" 10 70
		return
	fi

	local cmd=( sudo "$tegra_dir/build_kernel.sh"
		--patch "$target_bsp" --localversion "$localversion" )

	local body="About to rebuild the kernel against:\n\n  $tegra_dir\n\n  --patch:        $target_bsp\n  --localversion: $localversion"
	confirm_run "Kernel: rebuild in BSP tree" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 5g) Kernel releases — kernel_tags.json, deploy, production_kernels
# =========================================================================
menu_kt_paths_help() {
	local msg
	msg=$(
		printf '%s\n' "Tracked manifest + artifacts (see storage/README.md):"
		printf '\n'
		printf '  %s\n' "$STORAGE_KERNEL_TAGS"
		printf '  %s/\n' "$STORAGE_KERNEL_ARCHIVE"
		printf '  %s/  (submodule)\n' "$STORAGE_PRODUCTION_KERNELS"
		printf '  %s/\n' "$STORAGE_KERNEL_DEBS"
		printf '\n'
		printf '%s\n' "CLI: scripts/release/kernel_tags.sh (same as bin/tags)."
	)
	wt --msgbox "$msg" 22 85
}

menu_kt_list() {
	local st kernel
	st=$(wt --radiolist "Filter: deployment status" 14 72 5 \
		$(make_radio_args "${CFG[KT_LIST_STATUS_FILTER]}" any development testing staging production)) || return
	kernel=$(prompt_text "Filter: kernel tree name (empty = all)" "${CFG[KERNEL_NAME]}") || return
	CFG[KT_LIST_STATUS_FILTER]="$st"
	[[ -n "$kernel" ]] && CFG[KERNEL_NAME]="$kernel"
	cfg_save
	local cmd=( "$KERNEL_TAGS_SCRIPT" list )
	[[ "$st" != "any" ]] && cmd+=( --status "$st" )
	[[ -n "$kernel" ]] && cmd+=( --kernel "$kernel" )
	if wt --yesno "Verbose output (--all)?" 8 70; then
		cmd+=( --all )
	fi
	confirm_run "kernel_tags: list" "${cmd[*]}" || return
	run_cmd "${cmd[@]}" || true
}

menu_kt_show() {
	local t
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && { wt --msgbox "Tag name is required." 8 60; return; }
	CFG[KT_TAG_NAME]="$t"
	cfg_save
	confirm_run "kernel_tags: show" "$KERNEL_TAGS_SCRIPT show $t" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" show "$t" || true
}

menu_kt_log() {
	local lim
	lim=$(prompt_text "Max entries (default 20)" "${CFG[KT_LOG_LIMIT]}") || return
	CFG[KT_LOG_LIMIT]="$lim"
	cfg_save
	local cmd=( "$KERNEL_TAGS_SCRIPT" log )
	[[ -n "$lim" ]] && cmd+=( --limit "$lim" )
	confirm_run "kernel_tags: log" "${cmd[*]}" || return
	run_cmd "${cmd[@]}" || true
}

menu_kt_kernels_status() {
	confirm_run "kernel_tags: kernels" "$KERNEL_TAGS_SCRIPT kernels" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" kernels || true
}

menu_kt_get_deb() {
	local t
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && return
	CFG[KT_TAG_NAME]="$t"
	cfg_save
	confirm_run "kernel_tags: get-deb" "$KERNEL_TAGS_SCRIPT get-deb $t" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" get-deb "$t" || true
}

menu_kt_export() {
	local fmt st out
	fmt=$(wt --radiolist "Export format" 12 60 2 \
		$(make_radio_args "${CFG[KT_EXPORT_FORMAT]}" json text)) || return
	st=$(wt --radiolist "Filter: status (optional)" 14 72 5 \
		$(make_radio_args "${CFG[KT_EXPORT_STATUS_FILTER]:-any}" any development testing staging production)) || return
	out=$(prompt_text "Output file (empty = stdout)" "") || return
	CFG[KT_EXPORT_FORMAT]="$fmt"
	CFG[KT_EXPORT_STATUS_FILTER]="$st"
	cfg_save
	local cmd=( "$KERNEL_TAGS_SCRIPT" export --format "$fmt" )
	[[ "$st" != "any" ]] && cmd+=( --status "$st" )
	[[ -n "$out" ]] && cmd+=( --output "$out" )
	confirm_run "kernel_tags: export" "${cmd[*]}" || return
	run_cmd "${cmd[@]}" || true
}

menu_kt_tag_create() {
	local tname kname lv desc cfg dtb st soc debpath
	tname=$(prompt_text "New tag name (unique id)" "${CFG[KT_TAG_NAME]}") || return
	[[ -z "$tname" ]] && { wt --msgbox "Tag name is required." 8 60; return; }
	pick_kernel_tree || return
	kname="$PK_KERNEL"
	lv=$(prompt_text "--localversion (required)" "${CFG[LOCALVERSION]#-}") || return
	[[ -z "$lv" ]] && { wt --msgbox "localversion is required for tag." 8 60; return; }
	desc=$(prompt_text "--description" "${CFG[PACKAGE_DESCRIPTION]}") || return
	cfg=$(prompt_text "--config (empty to omit)" "") || return
	dtb="${CFG[COMPILE_DTB_NAME]}"
	st=$(prompt_kt_status) || return
	soc=$(wt --radiolist "Publish to production_kernels (--soc, optional)" 14 72 3 \
		$(make_radio_args "_none" _none orin xavier)) || return
	debpath=$(prompt_text "--deb-package path (empty = auto from localversion)" "") || return

	form_advanced_options "ADV_KT_NO_SOURCE_TAG,ADV_KT_NO_ARCHIVE,ADV_KT_NO_PUBLISH,ADV_KT_FORCE" || return

	CFG[KT_TAG_NAME]="$tname"
	CFG[LOCALVERSION]="$lv"
	CFG[PACKAGE_DESCRIPTION]="$desc"
	CFG[PACKAGE_TAG_STATUS]="$st"
	cfg_save

	local cmd=( "$KERNEL_TAGS_SCRIPT" tag "$tname" --kernel "$kname" --localversion "$lv" --description "$desc" --status "$st" )
	[[ -n "$cfg" ]] && cmd+=( --config "$cfg" )
	[[ -n "$dtb" ]] && cmd+=( --dtb-name "$dtb" )
	[[ "$soc" != "_none" ]] && cmd+=( --soc "$soc" )
	[[ -n "$debpath" ]] && cmd+=( --deb-package "$debpath" )
	[[ ${CFG[ADV_KT_NO_SOURCE_TAG]} == 1 ]] && cmd+=( --no-source-tag )
	[[ ${CFG[ADV_KT_NO_ARCHIVE]} == 1 ]] && cmd+=( --no-archive )
	[[ ${CFG[ADV_KT_NO_PUBLISH]} == 1 ]] && cmd+=( --no-publish )
	[[ ${CFG[ADV_KT_FORCE]} == 1 ]] && cmd+=( --force )

	confirm_run "kernel_tags: tag (creates manifest + archive + optional publish)" \
		"Tag: $tname  kernel: $kname  localversion: $lv\nRequires jq." || return
	run_cmd "${cmd[@]}" || true
}

menu_kt_promote() {
	local t st
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && return
	st=$(prompt_kt_status) || return
	CFG[KT_TAG_NAME]="$t"
	CFG[PACKAGE_TAG_STATUS]="$st"
	cfg_save
	confirm_run "kernel_tags: promote" "$t → $st" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" promote "$t" --status "$st" || true
}

menu_kt_notes() {
	local t note
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && return
	note=$(prompt_text "Note text (--add)" "") || return
	[[ -z "$note" ]] && { wt --msgbox "Note text is required." 8 60; return; }
	CFG[KT_TAG_NAME]="$t"
	cfg_save
	confirm_run "kernel_tags: notes" "Append note to $t" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" notes "$t" --add "$note" || true
}

menu_kt_diff() {
	local a b
	a=$(prompt_text "First tag name" "${CFG[KT_TAG_NAME]}") || return
	b=$(prompt_text "Second tag name" "") || return
	[[ -z "$a" || -z "$b" ]] && { wt --msgbox "Two tag names are required." 8 60; return; }
	confirm_run "kernel_tags: diff" "$a vs $b" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" diff "$a" "$b" || true
}

menu_kt_verify() {
	local t ip user
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && return
	ip=$(prompt_text "Device IP (empty = scripts/config/device_ip)" "") || return
	user=$(prompt_text "SSH user (empty = scripts/config/device_username or cartken)" "") || return
	CFG[KT_TAG_NAME]="$t"
	cfg_save
	local cmd=( "$KERNEL_TAGS_SCRIPT" verify "$t" )
	[[ -n "$ip" ]] && cmd+=( --ip "$ip" )
	[[ -n "$user" ]] && cmd+=( --user "$user" )
	confirm_run "kernel_tags: verify" "${cmd[*]}" || return
	run_cmd "${cmd[@]}" || true
}

menu_kt_deploy() {
	local t mode ip robots prefix hosts user rdir pass
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && return
	mode=$(wt --menu "Deploy target selection" 18 78 5 \
		"default" "device_ip + device_username from scripts/config/" \
		"ip"      "Single --ip" \
		"fleet"   "--robots + --robot-ip-prefix" \
		"hosts"   "--hosts-file" \
		"back"    "Cancel") || return
	[[ "$mode" == "back" || -z "$mode" ]] && return

	user=$(prompt_text "--user (empty = config default)" "") || return
	rdir=$(prompt_text "--remote-dir" "${CFG[KT_DEPLOY_REMOTE_DIR]}") || return
	pass=$(prompt_text "SSH password (empty; uses sshpass if set)" "" 1) || return
	CFG[KT_TAG_NAME]="$t"
	CFG[KT_DEPLOY_REMOTE_DIR]="$rdir"
	cfg_save

	local cmd=( "$KERNEL_TAGS_SCRIPT" deploy "$t" )
	[[ -n "$user" ]] && cmd+=( --user "$user" )
	[[ -n "$rdir" ]] && cmd+=( --remote-dir "$rdir" )
	[[ -n "$pass" ]] && cmd+=( --password "$pass" )

	case "$mode" in
		default) ;;
		ip)
			ip=$(prompt_text "Device IP" "") || return
			[[ -z "$ip" ]] && { wt --msgbox "IP is required." 8 60; return; }
			cmd+=( --ip "$ip" )
			;;
		fleet)
			robots=$(prompt_text "Robot numbers (e.g. 1,2,5-8)" "${CFG[ROBOT_NUMBER]}") || return
			prefix=$(prompt_text "IP prefix (e.g. 10.42.0.)" "10.42.0.") || return
			[[ -z "$robots" || -z "$prefix" ]] && { wt --msgbox "robots and prefix required." 8 60; return; }
			cmd+=( --robots "$robots" --robot-ip-prefix "$prefix" )
			;;
		hosts)
			hosts=$(prompt_text "Path to hosts file (one IP per line)" "") || return
			[[ -z "$hosts" ]] && return
			cmd+=( --hosts-file "$hosts" )
			;;
	esac

	local extra
	extra=$(wt --separate-output --checklist "Deploy options" 16 78 5 \
		INSTALL    "Also run dpkg -i (--install)" OFF \
		NOREBOOT   "Skip reboot after install (--no-reboot)" OFF \
		SEQUENTIAL "One host at a time (--sequential)" OFF \
		DRYRUN     "Dry run" OFF) || return
	while IFS= read -r f; do
		[[ -z "$f" ]] && continue
		case "$f" in
			INSTALL)    cmd+=( --install ) ;;
			NOREBOOT)   cmd+=( --no-reboot ) ;;
			SEQUENTIAL) cmd+=( --sequential ) ;;
			DRYRUN)     cmd+=( --dry-run ) ;;
		esac
	done <<< "$extra"

	confirm_run "kernel_tags: deploy" "${cmd[*]}\n\nCopy-only unless --install checked." || return
	run_cmd "${cmd[@]}" || true
}

menu_kt_delete() {
	local t
	t=$(prompt_kt_tag_name) || return
	[[ -z "$t" ]] && return
	if ! wt --yesno "Delete tag '$t' from kernel_tags.json and remove its archive?\n\nThis cannot be undone." 12 75; then
		return
	fi
	confirm_run "kernel_tags: delete" "Removing tag $t" || return
	run_cmd "$KERNEL_TAGS_SCRIPT" delete "$t" || true
}

menu_kernel_releases() {
	if ! command -v jq >/dev/null 2>&1; then
		wt --msgbox "kernel_tags.sh requires 'jq'.\n  pacman -S jq   or   apt install jq" 10 70
		return
	fi
	while true; do
		local choice
		choice=$(wt --menu "Kernel releases & tags (kernel_tags.sh)" 28 80 16 \
			"list"    "List tags — filters, optional verbose" \
			"show"    "Show one tag — full JSON record" \
			"log"     "Chronological build log" \
			"kernels" "Kernel trees — status & tag counts" \
			"get-deb" "Print path to archived .deb" \
			"export"  "Export manifest (JSON/text)" \
			"tag"     "Create tag — archive, optional production_kernels" \
			"promote" "Change deployment status" \
			"notes"   "Append a note to a tag" \
			"diff"    "Compare two tags" \
			"verify"  "Check device kernel vs tag" \
			"deploy"  "Copy .deb to robot(s) / fleet" \
			"delete"  "Remove tag + archive" \
			"paths"   "Where manifest & artifacts live" \
			"back"    "Back to main menu") || return
		case "$choice" in
			list)    menu_kt_list ;;
			show)    menu_kt_show ;;
			log)     menu_kt_log ;;
			kernels) menu_kt_kernels_status ;;
			get-deb) menu_kt_get_deb ;;
			export)  menu_kt_export ;;
			tag)     menu_kt_tag_create ;;
			promote) menu_kt_promote ;;
			notes)   menu_kt_notes ;;
			diff)    menu_kt_diff ;;
			verify)  menu_kt_verify ;;
			deploy)  menu_kt_deploy ;;
			delete)  menu_kt_delete ;;
			paths)   menu_kt_paths_help ;;
			back|"") return ;;
		esac
	done
}

# =========================================================================
# 6) Deploy submenu
# =========================================================================
menu_deploy_bootloader() {
	local target_bsp ip extra
	local bsps; mapfile -t bsps < <(discover_bsps)
	if (( ${#bsps[@]} == 0 )); then
		target_bsp=$(prompt_text "Target BSP folder name" "${CFG[JETPACK]}") || return
	else
		target_bsp=$(wt --radiolist "Target BSP folder" 14 60 6 \
			$(make_radio_args "${CFG[JETPACK]}" "${bsps[@]}")) || return
	fi
	ip=$(prompt_text "Device IP (blank to use scripts/config/device_ip)" "") || return
	extra=$(wt --separate-output --checklist "Optional flags" 14 70 5 \
		FORCE       "--force (regenerate payload)" OFF \
		CHECK_VAR   "--check-var (only print OsIndications and exit)" OFF \
		SWAP_SLOT   "--swap-slot" OFF \
		BOTH_SLOTS  "--both-slots (requires --target-bsp)" OFF \
		BUILD_ONLY  "--build-only" OFF) || return

	local cmd=( sudo "$DEPLOY_DIR/update_bootloader.sh" --target-bsp "$target_bsp" )
	[[ -n "$ip" ]] && cmd+=( --ip "$ip" )
	while IFS= read -r flag; do
		[[ -z "$flag" ]] && continue
		case "$flag" in
			FORCE)      cmd+=( --force ) ;;
			CHECK_VAR)  cmd+=( --check-var ) ;;
			SWAP_SLOT)  cmd+=( --swap-slot ) ;;
			BOTH_SLOTS) cmd+=( --both-slots ) ;;
			BUILD_ONLY) cmd+=( --build-only ) ;;
		esac
	done <<< "$extra"

	confirm_run "Update bootloader" "About to run update_bootloader.sh on $target_bsp${ip:+ (ip=$ip)}." || return
	run_cmd "${cmd[@]}" || true
}

menu_deploy_uefi() {
	local target_version
	target_version=$(prompt_text "--target-version (default 5.1.5)" "${CFG[JETPACK]}") || return
	local cmd=( sudo "$DEPLOY_DIR/update_uefi.sh" --target-version "$target_version" )
	confirm_run "Update UEFI" "About to run update_uefi.sh --target-version $target_version." || return
	run_cmd "${cmd[@]}" || true
}

menu_deploy_ekb() {
	local l4t
	l4t=$(prompt_text "--l4t-version (e.g. 5.1.5)" "${CFG[JETPACK]}") || return
	local cmd=( sudo "$DEPLOY_DIR/create_ekb_update.sh" --l4t-version "$l4t" )
	confirm_run "Create EKB update .deb" "About to run create_ekb_update.sh --l4t-version $l4t." || return
	run_cmd "${cmd[@]}" || true
}

menu_deploy() {
	while true; do
		local choice
		choice=$(wt --menu "Device: firmware (running Jetson over SSH)" 16 76 5 \
			"bootloader" "Bootloader update (update_bootloader.sh)" \
			"uefi"       "UEFI firmware (update_uefi.sh)" \
			"ekb"        "EKB update .deb (create_ekb_update.sh)" \
			"back"       "Back to main menu") || return
		case "$choice" in
			bootloader) menu_deploy_bootloader ;;
			uefi)       menu_deploy_uefi ;;
			ekb)        menu_deploy_ekb ;;
			back|"")    return ;;
		esac
	done
}

# =========================================================================
# 7) Utilities
# =========================================================================
menu_util_list_bsps() {
	local txt=""
	local bsps; mapfile -t bsps < <(discover_bsps)
	if (( ${#bsps[@]} == 0 )); then
		txt="No extracted BSPs under $ROOTFS_PREP/bsp/."
	else
		txt="Extracted BSPs (rootfs/ present):\n\n"
		for b in "${bsps[@]}"; do
			txt+="  - $b  ($ROOTFS_PREP/bsp/$b/Linux_for_Tegra)\n"
		done
	fi
	wt --msgbox "$(echo -e "$txt")" 20 90
}

menu_util_chroot() {
	local target_bsp soc
	local bsps; mapfile -t bsps < <(discover_bsps)
	if (( ${#bsps[@]} == 0 )); then
		wt --msgbox "No extracted BSPs found under bsp/." 8 60
		return
	fi
	target_bsp=$(wt --radiolist "BSP to chroot into" 14 60 6 \
		$(make_radio_args "${CFG[JETPACK]}" "${bsps[@]}")) || return
	soc=$(prompt_soc) || return
	local rootfs="$ROOTFS_PREP/bsp/$target_bsp/Linux_for_Tegra/rootfs"
	confirm_run "jetson_chroot" "About to drop into a chroot at:\n  $rootfs\n  soc=$soc" || return
	run_cmd sudo "$KB_REPO_ROOT/scripts/utils/chroot/jetson_chroot.sh" "$rootfs" "$soc" || true
}

menu_util_view_log() {
	if [[ ! -f "$KB_MENU_LOG" ]]; then
		wt --msgbox "No log yet. Run a command first." 8 50
		return
	fi
	wt --textbox "$KB_MENU_LOG" 30 120
}

menu_utilities() {
	while true; do
		local choice
		choice=$(wt --menu "Workspace" 16 74 6 \
			"bsps"   "List BSPs under bsp/ (extracted rootfs)" \
			"chroot" "Enter Jetson rootfs chroot (jetson_chroot.sh)" \
			"log"    "View last command log (.kb-menu.last.log)" \
			"back"   "Back to main menu") || return
		case "$choice" in
			bsps)   menu_util_list_bsps ;;
			chroot) menu_util_chroot ;;
			log)    menu_util_view_log ;;
			back|"") return ;;
		esac
	done
}

# =========================================================================
# 8) Settings - edit persisted defaults directly
# =========================================================================
# Update CFG[<key>] only if the prompt completes AND yields a non-empty
# string. Hitting Cancel on a settings sub-prompt should leave the existing
# value alone, not nuke it.
set_if_nonempty() {
	local key="$1"; shift
	local v
	if v=$("$@") && [[ -n "$v" ]]; then
		CFG[$key]="$v"
	fi
}

menu_settings() {
	while true; do
		local choice
		choice=$(wt --menu "Settings (persisted in .kb-menu.config)" 30 80 19 \
			"jp"        "Default JetPack:        ${CFG[JETPACK]}" \
			"soc"       "Default SoC:            ${CFG[SOC]}" \
			"env"       "Default env:            ${CFG[ENV]}" \
			"tag"       "Default tag:            ${CFG[TAG]:-(unset)}" \
			"token"     "Access token:           $(mask_token "${CFG[ACCESS_TOKEN]}")" \
			"robot"     "Default robot number:   ${CFG[ROBOT_NUMBER]:-(unset)}" \
			"validity"  "Host cert validity:     ${CFG[HOST_CERT_VALIDITY]}" \
			"localver"  "Default localversion:   ${CFG[LOCALVERSION]}" \
			"kname"     "Kernel tree name:       ${CFG[KERNEL_NAME]}" \
			"arch"      "Compile --arch:         ${CFG[COMPILE_ARCH]}" \
			"toolchain" "Toolchain name / ver:   ${CFG[PACKAGE_TOOLCHAIN_NAME]} / ${CFG[PACKAGE_TOOLCHAIN_VERSION]}" \
			"pkgcfg"    "Package --config:       ${CFG[PACKAGE_CONFIG]}" \
			"ccfg"      "Compile --config:       ${CFG[COMPILE_CONFIG]:-(empty)}" \
			"dtbc"      "Compile --dtb-name:     ${CFG[COMPILE_DTB_NAME]:-(empty)}" \
			"dtbp"      "Package --dtb-name:     ${CFG[PACKAGE_DTB_NAME]:-(empty)}" \
			"clear"     "Clear all persisted values" \
			"back"      "Back to main menu") || return
		case "$choice" in
			jp)       set_if_nonempty JETPACK            prompt_jetpack ;;
			soc)      set_if_nonempty SOC                prompt_soc ;;
			env)      set_if_nonempty ENV                prompt_env ;;
			tag)      set_if_nonempty TAG                prompt_text "Default tag" "${CFG[TAG]}" ;;
			token)    ensure_access_token ;;
			robot)    set_if_nonempty ROBOT_NUMBER       prompt_text "Default robot" "${CFG[ROBOT_NUMBER]}" ;;
			validity) set_if_nonempty HOST_CERT_VALIDITY prompt_text "Validity" "${CFG[HOST_CERT_VALIDITY]}" ;;
			localver) set_if_nonempty LOCALVERSION       prompt_text "localversion" "${CFG[LOCALVERSION]}" ;;
			kname)    set_if_nonempty KERNEL_NAME        prompt_text "Kernel tree name" "${CFG[KERNEL_NAME]}" ;;
			arch)     set_if_nonempty COMPILE_ARCH       prompt_arch ;;
			toolchain)
				local tn tv
				tn=$(prompt_text "--toolchain-name" "${CFG[PACKAGE_TOOLCHAIN_NAME]}") || continue
				tv=$(prompt_text "--toolchain-version" "${CFG[PACKAGE_TOOLCHAIN_VERSION]}") || continue
				CFG[PACKAGE_TOOLCHAIN_NAME]="$tn"
				CFG[PACKAGE_TOOLCHAIN_VERSION]="$tv"
				;;
			pkgcfg)   set_if_nonempty PACKAGE_CONFIG     prompt_text "defconfig name" "${CFG[PACKAGE_CONFIG]}" ;;
			ccfg)     set_if_nonempty COMPILE_CONFIG     prompt_text "Compile --config" "${CFG[COMPILE_CONFIG]}" ;;
			dtbc)
				local dv
				dv=$(prompt_text "Compile --dtb-name (empty omit)" "${CFG[COMPILE_DTB_NAME]}") || continue
				CFG[COMPILE_DTB_NAME]="$dv"
				;;
			dtbp)
				local pv
				pv=$(prompt_text "Package --dtb-name (empty omit)" "${CFG[PACKAGE_DTB_NAME]}") || continue
				CFG[PACKAGE_DTB_NAME]="$pv"
				;;
			clear)
				if wt --yesno "Delete $KB_MENU_CONFIG and reset all defaults?" 10 70; then
					rm -f "$KB_MENU_CONFIG"
					wt --msgbox "Cleared. Restart kb-menu to start fresh." 8 60
					exit 0
				fi
				;;
			back|"") return ;;
		esac
		cfg_save
	done
}

# =========================================================================
# Main loop
# =========================================================================
main() {
	cfg_load
	while true; do
		local choice
		choice=$(wt --menu "Main menu — categories" 24 78 9 \
			"bsp"      "Jetson BSP & rootfs — L4T extract, flash image (not kernel compile)" \
			"kernel"   "Kernel trees — compile, .deb, Kconfig, clean, Docker" \
			"releases" "Kernel tags — manifest, production_kernels, deploy (kernel_tags.sh)" \
			"ota"      "OTA — payloads and OTA rootfs" \
			"device"   "Running device — bootloader, UEFI, EKB" \
			"workspace" "Inspect — BSP list, chroot, logs" \
			"settings" "Saved defaults (.kb-menu.config)" \
			"quit"     "Quit") || break
		case "$choice" in
			bsp)      menu_jetson_bsp_rootfs ;;
			kernel)   menu_kernel_workflows ;;
			releases) menu_kernel_releases ;;
			ota)      menu_ota ;;
			device)   menu_deploy ;;
			workspace) menu_utilities ;;
			settings) menu_settings ;;
			quit|"")  break ;;
		esac
	done
	clear
	echo "kb-menu: bye."
}

main "$@"
