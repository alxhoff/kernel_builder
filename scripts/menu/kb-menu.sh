#!/bin/bash
# kb-menu - menuconfig-style TUI over the kernel_builder workflows
#
# whiptail-based front end for the rootfs_prep / ota / build / deploy entry
# points. Persists the last-used values in .kb-menu.config (chmod 600,
# gitignored) so re-running pre-fills your previous build settings, the same
# way `make menuconfig` keeps a .config.
#
# Run: ./bin/kb-menu          (no arguments)

set -uo pipefail

KB_MENU_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
KB_REPO_ROOT="$(cd "$KB_MENU_DIR/../.." && pwd)"
KB_MENU_CONFIG="$KB_MENU_DIR/.kb-menu.config"
KB_MENU_LOG="$KB_MENU_DIR/.kb-menu.last.log"

ROOTFS_PREP="$KB_REPO_ROOT/scripts/flash/rootfs_prep"
OTA_DIR="$KB_REPO_ROOT/scripts/ota"
DEPLOY_DIR="$KB_REPO_ROOT/scripts/deploy"

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
)

cfg_load() {
	[[ -r "$KB_MENU_CONFIG" ]] || return 0
	# shellcheck source=/dev/null
	. "$KB_MENU_CONFIG"
	for key in "${!CFG[@]}"; do
		var="KB_MENU_$key"
		[[ -n "${!var-}" ]] && CFG[$key]="${!var}"
	done
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
WT_BACKTITLE="kernel_builder TUI - $(basename "$KB_REPO_ROOT")"
WT_TITLE="kernel_builder"

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
	wt --yes-button "Run" --no-button "Back" --yesno "$body" 24 100
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

prompt_text() {
	local label="$1" cur="$2" pwd_mode="${3:-0}"
	if [[ "$pwd_mode" -eq 1 ]]; then
		wt --passwordbox "$label" 10 78 "$cur"
	else
		wt --inputbox "$label" 10 78 "$cur"
	fi
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
# 1) Build BSP rootfs (setup_tegra_package.sh)
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

	local body="About to run setup_tegra_package.sh:\n\n  jetpack:       $jp\n  soc:           $soc\n  tag:           $tag\n  mode:          $docker_choice\n  access-token:  $(mask_token "${CFG[ACCESS_TOKEN]}")"
	confirm_run "Build BSP rootfs" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 2) Configure & flash robot (setup_rootfs_as_robot_for_flashing.sh)
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

	local body="About to run setup_rootfs_as_robot_for_flashing.sh:\n\n  target-bsp:        $target_bsp\n  soc:               $soc\n  robot:             cart$robot\n  env:               $env\n  host-cert-validity: $validity\n  tag:               ${tag:-(unchanged)}\n\nThis will flash the device currently in recovery mode."
	confirm_run "Configure & flash robot" "$body" || return
	run_cmd "${cmd[@]}" || true
}

# =========================================================================
# 3) Build + flash (chain)
# =========================================================================
menu_build_and_flash() {
	wt --msgbox "Step 1/2: Build BSP rootfs.\nStep 2/2: Configure & flash robot.\n\nValues you set in step 1 will pre-fill step 2." 12 70 || return
	menu_build_bsp
	wt --yesno "Step 1 finished. Proceed to step 2 (flash)?" 8 60 || return
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
		choice=$(wt --menu "OTA workflows" 14 70 4 \
			"payload" "Build full OTA payload (create_full_ota_update.sh)" \
			"rootfs"  "Configure rootfs as OTA-ready (setup_rootfs_as_robot_for_ota.sh)" \
			"back"    "Back to main menu") || return
		case "$choice" in
			payload) menu_ota_payload ;;
			rootfs)  menu_ota_rootfs  ;;
			back|"") return ;;
		esac
	done
}

# =========================================================================
# 5) Kernel rebuild (helpers/build_kernel.sh)
# =========================================================================
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
	confirm_run "Kernel rebuild" "$body" || return
	run_cmd "${cmd[@]}" || true
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
		choice=$(wt --menu "Deploy / update" 14 70 5 \
			"bootloader" "Update bootloader (update_bootloader.sh)" \
			"uefi"       "Update UEFI (update_uefi.sh)" \
			"ekb"        "Create EKB update .deb (create_ekb_update.sh)" \
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
		choice=$(wt --menu "Utilities" 16 70 6 \
			"bsps"   "List extracted BSPs" \
			"chroot" "Drop into a Jetson rootfs (scripts/utils/chroot)" \
			"log"    "View last command log" \
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
		choice=$(wt --menu "Settings (persisted in .kb-menu.config)" 22 80 12 \
			"jp"        "Default JetPack:        ${CFG[JETPACK]}" \
			"soc"       "Default SoC:            ${CFG[SOC]}" \
			"env"       "Default env:            ${CFG[ENV]}" \
			"tag"       "Default tag:            ${CFG[TAG]:-(unset)}" \
			"token"     "Access token:           $(mask_token "${CFG[ACCESS_TOKEN]}")" \
			"robot"     "Default robot number:   ${CFG[ROBOT_NUMBER]:-(unset)}" \
			"validity"  "Host cert validity:     ${CFG[HOST_CERT_VALIDITY]}" \
			"localver"  "Default localversion:   ${CFG[LOCALVERSION]}" \
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
		choice=$(wt --menu "Main menu" 22 80 10 \
			"build"   "Build BSP rootfs               (setup_tegra_package.sh)" \
			"flash"   "Configure & flash robot        (setup_rootfs_as_robot_for_flashing.sh)" \
			"chain"   "Build + flash                  (chain the two above)" \
			"ota"     "OTA workflows                  (scripts/ota/...)" \
			"kernel"  "Kernel rebuild                 (helpers/build_kernel.sh in a BSP)" \
			"deploy"  "Update bootloader / UEFI / EKB (scripts/deploy/...)" \
			"util"    "Utilities                      (list BSPs, chroot, view log)" \
			"settings" "Settings                       (persisted defaults)" \
			"quit"    "Quit") || break
		case "$choice" in
			build)    menu_build_bsp ;;
			flash)    menu_flash_robot ;;
			chain)    menu_build_and_flash ;;
			ota)      menu_ota ;;
			kernel)   menu_kernel_rebuild ;;
			deploy)   menu_deploy ;;
			util)     menu_utilities ;;
			settings) menu_settings ;;
			quit|"")  break ;;
		esac
	done
	clear
	echo "kb-menu: bye."
}

main "$@"
