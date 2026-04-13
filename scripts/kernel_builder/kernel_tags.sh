#!/bin/bash

# Kernel build tagging and tracking tool
# Maintains a version-controlled manifest (kernel_tags.json) of tagged kernel builds
# for deployment tracking, auditing, and release management.
#
# Usage: ./kernel_tags.sh <command> [options]
# Commands: tag, list, show, promote, delete, log, export

set -e

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
REPO_ROOT="$(realpath "$SCRIPT_DIR/..")"
TAGS_FILE="$REPO_ROOT/kernel_tags.json"
KERNELS_DIR="$REPO_ROOT/kernels"
KERNEL_DEBS_DIR="$REPO_ROOT/kernel_debs"
ARCHIVE_DIR="$REPO_ROOT/kernel_archive"

# Status lifecycle: development -> testing -> staging -> production
VALID_STATUSES=("development" "testing" "staging" "production")

ensure_jq() {
  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required but not installed."
    echo "Install it with: sudo pacman -S jq (Arch/Manjaro) or sudo apt install jq (Debian/Ubuntu)"
    exit 1
  fi
}

ensure_tags_file() {
  if [ ! -f "$TAGS_FILE" ]; then
    echo "[]" > "$TAGS_FILE"
  fi
}

validate_status() {
  local status="$1"
  for valid in "${VALID_STATUSES[@]}"; do
    if [ "$status" == "$valid" ]; then
      return 0
    fi
  done
  echo "Error: Invalid status '$status'. Valid statuses: ${VALID_STATUSES[*]}"
  exit 1
}

tag_exists() {
  local tag="$1"
  jq -e --arg tag "$tag" '.[] | select(.tag == $tag)' "$TAGS_FILE" > /dev/null 2>&1
}

get_repo_commit() {
  if git -C "$REPO_ROOT" rev-parse HEAD &> /dev/null 2>&1; then
    git -C "$REPO_ROOT" rev-parse --short HEAD
  else
    echo "unknown"
  fi
}

get_builder() {
  local name
  name=$(git -C "$REPO_ROOT" config user.name 2>/dev/null || echo "")
  local email
  email=$(git -C "$REPO_ROOT" config user.email 2>/dev/null || echo "")
  if [ -n "$name" ] && [ -n "$email" ]; then
    echo "$name <$email>"
  elif [ -n "$name" ]; then
    echo "$name"
  else
    echo "${USER:-unknown}"
  fi
}

# ── source repo tagging ──────────────────────────────────────────────────────

find_git_repos() {
  local kernel_name="$1"
  local kernel_dir="$KERNELS_DIR/$kernel_name"
  local repos=()

  if [ ! -d "$kernel_dir" ]; then
    return
  fi

  # Check top-level kernel directory
  if [ -d "$kernel_dir/.git" ]; then
    repos+=("$kernel_dir")
  fi

  # Check kernel/kernel subdirectory (inner kernel source)
  if [ -d "$kernel_dir/kernel/kernel/.git" ]; then
    repos+=("$kernel_dir/kernel/kernel")
  fi

  # Check hardware subdirectory (device tree)
  if [ -d "$kernel_dir/hardware/.git" ]; then
    repos+=("$kernel_dir/hardware")
  fi

  echo "${repos[@]}"
}

tag_source_repos() {
  local tag_name="$1"
  local kernel_name="$2"
  local description="$3"
  local tagged_repos=()

  if [ -z "$kernel_name" ]; then
    echo "  Skipping source tagging: no kernel name provided"
    return
  fi

  local kernel_dir="$KERNELS_DIR/$kernel_name"
  if [ ! -d "$kernel_dir" ]; then
    echo "  Skipping source tagging: kernel directory '$kernel_dir' not found"
    return
  fi

  local repos
  repos=($(find_git_repos "$kernel_name"))

  if [ ${#repos[@]} -eq 0 ]; then
    echo "  Skipping source tagging: no git repositories found under '$kernel_dir'"
    return
  fi

  local tag_message="Kernel build tag: $tag_name"
  if [ -n "$description" ]; then
    tag_message="$tag_message

$description"
  fi

  for repo in "${repos[@]}"; do
    local repo_rel="${repo#$REPO_ROOT/}"
    local repo_name=$(basename "$repo")

    if git -C "$repo" rev-parse "refs/tags/$tag_name" &>/dev/null; then
      echo "  Source tag '$tag_name' already exists in $repo_rel, skipping"
      tagged_repos+=("$repo_rel")
      continue
    fi

    if git -C "$repo" tag -a "$tag_name" -m "$tag_message" 2>/dev/null; then
      local commit
      commit=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo "unknown")
      echo "  Tagged source repo: $repo_rel (commit: $commit)"
      tagged_repos+=("$repo_rel")
    else
      echo "  Warning: Failed to tag source repo: $repo_rel"
    fi
  done

  # Return the list of tagged repos as a JSON array for storage in the manifest
  if [ ${#tagged_repos[@]} -gt 0 ]; then
    local json_array="["
    local first=true
    for r in "${tagged_repos[@]}"; do
      if [ "$first" = true ]; then
        first=false
      else
        json_array+=","
      fi
      json_array+="\"$r\""
    done
    json_array+="]"
    echo "$json_array"
  else
    echo "[]"
  fi
}

# ── deb archiving ────────────────────────────────────────────────────────────

find_deb_package() {
  local localversion="$1"
  local deb_path="$2"

  # If an explicit path was given, use it
  if [ -n "$deb_path" ] && [ -f "$deb_path" ]; then
    echo "$deb_path"
    return
  fi

  # If explicit path is relative, try from repo root
  if [ -n "$deb_path" ] && [ -f "$REPO_ROOT/$deb_path" ]; then
    echo "$REPO_ROOT/$deb_path"
    return
  fi

  # Auto-detect from kernel_debs/ by localversion
  if [ -n "$localversion" ] && [ -d "$KERNEL_DEBS_DIR" ]; then
    local matches
    matches=$(ls -t "$KERNEL_DEBS_DIR"/linux-custom-*"-${localversion}.deb" 2>/dev/null | head -1)
    if [ -n "$matches" ]; then
      echo "$matches"
      return
    fi
  fi

  return 1
}

archive_deb_package() {
  local tag_name="$1"
  local localversion="$2"
  local deb_path="$3"

  local source_deb
  source_deb=$(find_deb_package "$localversion" "$deb_path") || true

  if [ -z "$source_deb" ] || [ ! -f "$source_deb" ]; then
    echo "  Skipping deb archive: no matching .deb found"
    if [ -n "$localversion" ]; then
      echo "    (looked for kernel_debs/*-${localversion}.deb)"
    fi
    echo ""
    return
  fi

  local archive_tag_dir="$ARCHIVE_DIR/$tag_name"
  mkdir -p "$archive_tag_dir"

  local deb_filename
  deb_filename=$(basename "$source_deb")

  cp "$source_deb" "$archive_tag_dir/$deb_filename"
  echo "  Archived: $deb_filename -> kernel_archive/$tag_name/"

  # Return the archive path (relative to repo root)
  echo "kernel_archive/$tag_name/$deb_filename"
}

# ── config archiving ─────────────────────────────────────────────────────────

archive_kernel_config() {
  local tag_name="$1"
  local kernel_name="$2"

  if [ -z "$kernel_name" ]; then
    echo "  Skipping config archive: no kernel name provided"
    return
  fi

  local config_path=""
  local search_paths=(
    "$KERNELS_DIR/$kernel_name/kernel/kernel/.config"
    "$KERNELS_DIR/$kernel_name/kernel/.config"
    "$KERNELS_DIR/$kernel_name/.config"
  )

  for p in "${search_paths[@]}"; do
    if [ -f "$p" ]; then
      config_path="$p"
      break
    fi
  done

  if [ -z "$config_path" ]; then
    echo "  Skipping config archive: no .config found under kernels/$kernel_name/"
    return
  fi

  local archive_tag_dir="$ARCHIVE_DIR/$tag_name"
  mkdir -p "$archive_tag_dir"
  cp "$config_path" "$archive_tag_dir/kernel.config"
  echo "  Archived kernel config -> kernel_archive/$tag_name/kernel.config"
  echo "kernel_archive/$tag_name/kernel.config"
}

show_help() {
  cat <<'HELP'
Kernel Build Tagging Tool
=========================

Usage: kernel_tags.sh <command> [options]

Commands:

  tag       Create a new kernel build tag (tags source repos + archives .deb + config)
  list      List tagged kernel builds (with optional filters)
  show      Show full details of a specific tag
  promote   Change the deployment status of a tagged build
  notes     Add notes to an existing tag
  diff      Compare two tagged builds
  verify    Check that a remote device is running a specific tagged kernel
  deploy    Deploy a tagged kernel to a remote machine (supports fleet deploy)
  delete    Remove a tag from the manifest
  log       Show a chronological build log
  export    Export tag data (JSON or human-readable)
  get-deb   Print the archived .deb path for a tag (useful for redeployment)
  kernels   List all available kernel sources with their status and tags

--- tag ---

  kernel_tags.sh tag <TAG_NAME> [options]

  Required:
    <TAG_NAME>                 Unique identifier for this build (e.g. v5.1.5-realsense-2400)

  Options:
    --kernel <name>            Kernel source directory name (e.g. cartken_5_1_5_realsense)
    --localversion <str>       LOCALVERSION string used in the build
    --description <text>       What this build adds/changes/fixes
    --config <file>            Kernel config used (e.g. defconfig, tegra_defconfig)
    --dtb-name <name>          Device tree blob filename
    --status <status>          Initial status (default: development)
                               Valid: development, testing, staging, production
    --deb-package <path>       Path to the generated .deb package (auto-detected from localversion)
    --no-source-tag            Skip tagging the kernel source git repositories
    --no-archive               Skip archiving the .deb package to kernel_archive/
    --force                    Overwrite existing tag (preserves notes & deploy history)

  When tagging, this tool will:
    1. Record the build metadata in kernel_tags.json
    2. Create a git tag in all source repos under kernels/<kernel>/ (unless --no-source-tag)
    3. Copy the .deb to kernel_archive/<tag>/ for redeployment (unless --no-archive)
    4. Archive the kernel .config for reproducibility

  Example:
    kernel_tags.sh tag v5.1.5-rs-2400 \
      --kernel cartken_5_1_5_realsense \
      --localversion cartken5.1.5realsense2400 \
      --description "Added RealSense D435 support for Orin" \
      --status testing

--- list ---

  kernel_tags.sh list [options]

  Options:
    --status <status>          Filter by deployment status
    --kernel <name>            Filter by kernel name
    --all                      Show all fields (verbose)

--- show ---

  kernel_tags.sh show <TAG_NAME>

--- promote ---

  kernel_tags.sh promote <TAG_NAME> --status <new_status>

  Moves a tagged build to a new deployment stage.

--- delete ---

  kernel_tags.sh delete <TAG_NAME>

--- log ---

  kernel_tags.sh log [--limit N]

  Shows a chronological build log, most recent first. Default limit: 20.

--- export ---

  kernel_tags.sh export [--format json|text] [--status <status>] [--output <file>]

  Export tag data. Default format: json, output: stdout.

--- notes ---

  kernel_tags.sh notes <TAG_NAME> --add <text>

  Add timestamped notes to an existing tag.

--- diff ---

  kernel_tags.sh diff <TAG_1> <TAG_2>

  Compare two tagged builds: metadata differences and source git log.

--- verify ---

  kernel_tags.sh verify <TAG_NAME> --ip <address> [--user <user>]

  SSH into a device and check that uname -r matches the tag's kernel version.

--- deploy ---

  kernel_tags.sh deploy <TAG_NAME> [target options] [options]

  Copy a tagged kernel to remote machine(s). Default is copy-only; use
  --install for dpkg -i + optional reboot. Multiple targets run in parallel.

  Target selection (at least one required):
    --ip <address>             Direct IP (repeatable)
    --robots <list>            Comma-separated robot numbers (e.g. 1,2,5-8)
    --robot-ip-prefix <prefix> IP prefix for robots (e.g. "10.42.0.")
    --hosts-file <file>        File with one IP per line

  Options:
    --user <user>              SSH user (default: cartken)
    --password <pass>          SSH password (uses sshpass, no interactive prompts)
    --remote-dir <path>        Remote destination directory (default: ~/kernel_debs)
    --install                  Also run dpkg -i after copying
    --no-reboot                Skip reboot (only with --install)
    --sequential               Disable parallel copy for fleet deploys
    --dry-run                  Show what would be done without executing

  Examples:
    kernel_tags.sh deploy v5.1.5-rs-2400 --ip 10.42.0.5
    kernel_tags.sh deploy v5.1.5-rs-2400 --robots 1,2,5-8 --robot-ip-prefix "10.42.0."
    kernel_tags.sh deploy v5.1.5-rs-2400 --hosts-file fleet.txt --password "pw"

--- get-deb ---

  kernel_tags.sh get-deb <TAG_NAME>

  Prints the absolute path to the archived .deb for the given tag.
  Useful for scripted redeployment, e.g.:
    scp $(kernel_tags.sh get-deb v5.1.5-rs-2400) user@device:/tmp/

HELP
  exit 0
}

# ── tag ──────────────────────────────────────────────────────────────────────

cmd_tag() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh tag <TAG_NAME> [options]

Create a new kernel build tag. Tags the source repo(s) and archives the .deb.

Required:
  <TAG_NAME>                 Unique identifier for this build (e.g. v5.1.5-realsense-2400)

Options:
  --kernel <name>            Kernel source directory name (e.g. cartken_5_1_5_realsense)
  --localversion <str>       LOCALVERSION string used in the build
  --description <text>       What this build adds/changes/fixes
  --config <file>            Kernel config used (e.g. defconfig, tegra_defconfig)
  --dtb-name <name>          Device tree blob filename
  --status <status>          Initial status (default: development)
                             Valid: development, testing, staging, production
  --deb-package <path>       Path to the .deb package (auto-detected from localversion)
  --no-source-tag            Skip tagging the kernel source git repositories
  --no-archive               Skip archiving the .deb package to kernel_archive/
  --force                    Overwrite an existing tag (preserves notes & deployment history)

Example:
  kernel_tags.sh tag v5.1.5-rs-2400 \
    --kernel cartken_5_1_5_realsense \
    --localversion cartken5.1.5realsense2400 \
    --description "Added RealSense D435 support for Orin" \
    --status testing
EOF
    exit 0
  fi

  if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh tag <TAG_NAME> [options]"
    echo "Run 'kernel_tags.sh tag --help' for full usage."
    exit 1
  fi

  local tag_name="$1"
  shift

  local kernel_name="" localversion="" description="" config="" dtb_name=""
  local status="development" deb_package=""
  local skip_source_tag=false skip_archive=false force=false

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --kernel)         kernel_name="$2"; shift 2 ;;
      --localversion)   localversion="$2"; shift 2 ;;
      --description)    description="$2"; shift 2 ;;
      --config)         config="$2"; shift 2 ;;
      --dtb-name)       dtb_name="$2"; shift 2 ;;
      --status)         status="$2"; shift 2 ;;
      --deb-package)    deb_package="$2"; shift 2 ;;
      --no-source-tag)  skip_source_tag=true; shift ;;
      --no-archive)     skip_archive=true; shift ;;
      --force)          force=true; shift ;;
      *) echo "Error: Unknown option '$1' for 'tag' command"; exit 1 ;;
    esac
  done

  # Handle existing tag
  local preserved_notes="[]" preserved_deployments="[]"
  if tag_exists "$tag_name"; then
    if [ "$force" = false ]; then
      echo "Error: Tag '$tag_name' already exists."
      echo "  Use --force to overwrite (notes and deployment history are preserved)."
      echo "  Use 'delete' to remove it entirely."
      exit 1
    fi

    echo "Tag '$tag_name' exists, overwriting (--force)..."

    # Preserve notes and deployment history from the old entry
    preserved_notes=$(jq --arg tag "$tag_name" \
      '[.[] | select(.tag == $tag)][0] | (.notes // [])' "$TAGS_FILE")
    preserved_deployments=$(jq --arg tag "$tag_name" \
      '[.[] | select(.tag == $tag)][0] | (.deployments // [])' "$TAGS_FILE")

    local old_note_count old_deploy_count
    old_note_count=$(echo "$preserved_notes" | jq 'length')
    old_deploy_count=$(echo "$preserved_deployments" | jq 'length')
    echo "  Preserving $old_note_count note(s) and $old_deploy_count deployment record(s)"

    # Clean up old source tags
    local old_kernel
    old_kernel=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | .kernel_name' "$TAGS_FILE")
    if [ -n "$old_kernel" ]; then
      local repos
      repos=($(find_git_repos "$old_kernel"))
      for repo in "${repos[@]}"; do
        if git -C "$repo" rev-parse "refs/tags/$tag_name" &>/dev/null; then
          git -C "$repo" tag -d "$tag_name" 2>/dev/null && \
            echo "  Removed old source tag from: ${repo#$REPO_ROOT/}"
        fi
      done
    fi

    # Clean up old archive
    if [ -d "$ARCHIVE_DIR/$tag_name" ]; then
      rm -rf "$ARCHIVE_DIR/$tag_name"
      echo "  Removed old archive: kernel_archive/$tag_name/"
    fi

    # Remove old entry from manifest
    jq --arg tag "$tag_name" 'del(.[] | select(.tag == $tag))' "$TAGS_FILE" > "$TAGS_FILE.tmp" \
      && mv "$TAGS_FILE.tmp" "$TAGS_FILE"

    echo ""
  fi

  validate_status "$status"

  local build_date repo_commit builder
  build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  repo_commit=$(get_repo_commit)
  builder=$(get_builder)

  echo "Tagging kernel build: $tag_name"
  echo "  Kernel:       $kernel_name"
  echo "  Localversion: $localversion"
  echo "  Status:       $status"
  echo "  Date:         $build_date"
  echo "  Commit:       $repo_commit"
  if [ -n "$description" ]; then
    echo "  Description:  $description"
  fi
  echo ""

  # ── Step 1: Tag source repositories ──
  local source_repos_json="[]"
  if [ "$skip_source_tag" = false ] && [ -n "$kernel_name" ]; then
    echo "Tagging source repositories..."

    local tag_output
    tag_output=$(tag_source_repos "$tag_name" "$kernel_name" "$description" 2>&1)

    # The last line of output is the JSON array, preceding lines are status messages
    local last_line
    last_line=$(echo "$tag_output" | tail -1)

    # Print all lines except the last (status messages)
    echo "$tag_output" | head -n -1

    # Check if last line looks like a JSON array
    if [[ "$last_line" == "["* ]]; then
      source_repos_json="$last_line"
    fi
    echo ""
  elif [ "$skip_source_tag" = true ]; then
    echo "Skipping source tagging (--no-source-tag)"
    echo ""
  fi

  # ── Step 2: Archive the .deb package ──
  local archived_deb=""
  if [ "$skip_archive" = false ]; then
    echo "Archiving .deb package..."

    local archive_output
    archive_output=$(archive_deb_package "$tag_name" "$localversion" "$deb_package" 2>&1)

    # Print status lines, capture the archive path from the last line
    local last_line
    last_line=$(echo "$archive_output" | tail -1)

    echo "$archive_output" | head -n -1

    # If last line looks like an archive path, use it
    if [[ "$last_line" == kernel_archive/* ]]; then
      archived_deb="$last_line"
    fi
    echo ""
  elif [ "$skip_archive" = true ]; then
    echo "Skipping deb archiving (--no-archive)"
    echo ""
  fi

  # ── Step 3: Archive kernel config ──
  local archived_config=""
  if [ "$skip_archive" = false ] && [ -n "$kernel_name" ]; then
    local config_output
    config_output=$(archive_kernel_config "$tag_name" "$kernel_name" 2>&1)
    local config_last_line
    config_last_line=$(echo "$config_output" | tail -1)
    echo "$config_output" | head -n -1
    if [[ "$config_last_line" == kernel_archive/* ]]; then
      archived_config="$config_last_line"
    fi
    echo ""
  fi

  # Use the archived path if we have one, otherwise keep the original deb_package
  local final_deb="${archived_deb:-$deb_package}"

  # ── Step 4: Record in manifest ──
  local new_entry
  new_entry=$(jq -n \
    --arg tag "$tag_name" \
    --arg kernel "$kernel_name" \
    --arg lv "$localversion" \
    --arg desc "$description" \
    --arg conf "$config" \
    --arg dtb "$dtb_name" \
    --arg status "$status" \
    --arg deb "$final_deb" \
    --arg date "$build_date" \
    --arg commit "$repo_commit" \
    --arg builder "$builder" \
    --arg config_archived "$archived_config" \
    --argjson source_repos "$source_repos_json" \
    --argjson prev_notes "$preserved_notes" \
    --argjson prev_deploys "$preserved_deployments" \
    '{
      tag: $tag,
      kernel_name: $kernel,
      localversion: $lv,
      build_date: $date,
      builder: $builder,
      repo_commit: $commit,
      config: $conf,
      dtb_name: $dtb,
      description: $desc,
      status: $status,
      deb_package: $deb,
      config_archived: $config_archived,
      source_repos_tagged: $source_repos,
      notes: $prev_notes,
      deployments: $prev_deploys,
      status_history: [
        {
          status: $status,
          date: $date,
          by: $builder
        }
      ]
    }')

  jq --argjson entry "$new_entry" '. += [$entry]' "$TAGS_FILE" > "$TAGS_FILE.tmp" \
    && mv "$TAGS_FILE.tmp" "$TAGS_FILE"

  echo "Tag '$tag_name' created successfully."
  if [ -n "$archived_deb" ]; then
    echo "  Archived deb: $archived_deb"
  fi
  if [ "$source_repos_json" != "[]" ]; then
    echo "  Source repos tagged: $source_repos_json"
  fi
}

# ── list ─────────────────────────────────────────────────────────────────────

cmd_list() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh list [options]

List tagged kernel builds with optional filters.

Options:
  --status <status>          Filter by deployment status
                             Valid: development, testing, staging, production
  --kernel <name>            Filter by kernel name
  --all                      Show all fields (verbose)

Examples:
  kernel_tags.sh list
  kernel_tags.sh list --status production
  kernel_tags.sh list --kernel cartken_5_1_5_realsense --all
EOF
    exit 0
  fi

  local filter_status="" filter_kernel="" verbose=false

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --status) filter_status="$2"; shift 2 ;;
      --kernel) filter_kernel="$2"; shift 2 ;;
      --all)    verbose=true; shift ;;
      *) echo "Error: Unknown option '$1' for 'list' command"; exit 1 ;;
    esac
  done

  local filter="."
  if [ -n "$filter_status" ]; then
    validate_status "$filter_status"
    filter="$filter | select(.status == \"$filter_status\")"
  fi
  if [ -n "$filter_kernel" ]; then
    filter="$filter | select(.kernel_name == \"$filter_kernel\")"
  fi

  local count
  count=$(jq "[.[] | $filter] | length" "$TAGS_FILE")

  if [ "$count" -eq 0 ]; then
    echo "No tagged kernel builds found."
    return
  fi

  if [ "$verbose" = true ]; then
    jq -r "[.[] | $filter] | sort_by(.build_date) | reverse[] |
      \"═══════════════════════════════════════════════════\" +
      \"\nTag:          \" + .tag +
      \"\nKernel:       \" + .kernel_name +
      \"\nLocalversion: \" + .localversion +
      \"\nStatus:       \" + .status +
      \"\nDate:         \" + .build_date +
      \"\nBuilder:      \" + .builder +
      \"\nCommit:       \" + .repo_commit +
      \"\nConfig:       \" + .config +
      \"\nDTB:          \" + .dtb_name +
      \"\nDeb:          \" + .deb_package +
      \"\nDescription:  \" + .description" "$TAGS_FILE"
  else
    printf "%-28s %-14s %-30s %s\n" "TAG" "STATUS" "LOCALVERSION" "DATE"
    printf "%-28s %-14s %-30s %s\n" "---" "------" "------------" "----"
    jq -r "[.[] | $filter] | sort_by(.build_date) | reverse[] |
      [.tag, .status, .localversion, .build_date] | @tsv" "$TAGS_FILE" |
    while IFS=$'\t' read -r tag status lv date; do
      printf "%-28s %-14s %-30s %s\n" "$tag" "$status" "$lv" "$date"
    done
  fi
}

# ── show ─────────────────────────────────────────────────────────────────────

cmd_show() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh show <TAG_NAME>

Show full details of a specific tagged kernel build, including metadata,
source repo info, and status history.

Example:
  kernel_tags.sh show v5.1.5-rs-2400
EOF
    exit 0
  fi

  if [ -z "$1" ]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh show <TAG_NAME>"
    exit 1
  fi

  local tag_name="$1"

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found."
    exit 1
  fi

  jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) |
    "Tag:           " + .tag +
    "\nKernel:        " + .kernel_name +
    "\nLocalversion:  " + .localversion +
    "\nStatus:        " + .status +
    "\nBuild Date:    " + .build_date +
    "\nBuilder:       " + .builder +
    "\nRepo Commit:   " + .repo_commit +
    "\nConfig:        " + .config +
    "\nDTB Name:      " + .dtb_name +
    "\nDeb Package:   " + (.deb_package // "none") +
    "\nConfig Archive:" + (if .config_archived and .config_archived != "" then " " + .config_archived else " none" end) +
    "\nSource Repos:  " + (if .source_repos_tagged then (.source_repos_tagged | join(", ")) else "none" end) +
    "\nDescription:   " + .description' "$TAGS_FILE"

  echo ""
  echo "Status History:"
  jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) |
    .status_history[] |
    "  " + .date + "  " + .status + "  (" + .by + ")"' "$TAGS_FILE"

  # Notes
  local note_count
  note_count=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | (.notes // []) | length' "$TAGS_FILE")
  if [ "$note_count" -gt 0 ]; then
    echo ""
    echo "Notes:"
    jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) |
      (.notes // [])[] |
      "  [" + .date + "] (" + .by + ")\n    " + .text' "$TAGS_FILE"
  fi

  # Deployments
  local deploy_count
  deploy_count=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | (.deployments // []) | length' "$TAGS_FILE")
  if [ "$deploy_count" -gt 0 ]; then
    echo ""
    echo "Deployment History:"
    jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) |
      (.deployments // [])[] |
      "  " + .date + "  " + .target + "  (" + .by + ")" +
      (if .mode then "  [" + .mode + "]" else "" end)' "$TAGS_FILE"
  fi
}

# ── promote ──────────────────────────────────────────────────────────────────

cmd_promote() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh promote <TAG_NAME> --status <new_status>

Change the deployment status of a tagged build.

Status lifecycle: development -> testing -> staging -> production

Options:
  --status <status>          New status to assign
                             Valid: development, testing, staging, production

Example:
  kernel_tags.sh promote v5.1.5-rs-2400 --status staging
  kernel_tags.sh promote v5.1.5-rs-2400 --status production
EOF
    exit 0
  fi

  if [ -z "$1" ]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh promote <TAG_NAME> --status <new_status>"
    exit 1
  fi

  local tag_name="$1"
  shift

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found."
    exit 1
  fi

  local new_status=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --status) new_status="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for 'promote' command"; exit 1 ;;
    esac
  done

  if [ -z "$new_status" ]; then
    echo "Error: --status is required for promote."
    exit 1
  fi

  validate_status "$new_status"

  local old_status
  old_status=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | .status' "$TAGS_FILE")

  if [ "$old_status" == "$new_status" ]; then
    echo "Tag '$tag_name' is already at status '$new_status'."
    return
  fi

  local now builder
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  builder=$(get_builder)

  jq --arg tag "$tag_name" \
     --arg status "$new_status" \
     --arg date "$now" \
     --arg by "$builder" \
    '(.[] | select(.tag == $tag)) |=
      (.status = $status |
       .status_history += [{status: $status, date: $date, by: $by}])' \
    "$TAGS_FILE" > "$TAGS_FILE.tmp" && mv "$TAGS_FILE.tmp" "$TAGS_FILE"

  echo "Promoted '$tag_name': $old_status -> $new_status"
}

# ── delete ───────────────────────────────────────────────────────────────────

cmd_delete() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh delete <TAG_NAME>

Remove a tag from the manifest. Also removes:
  - Git tags from source repositories
  - Archived .deb from kernel_archive/

Prompts for confirmation if the tag is in production status.

Example:
  kernel_tags.sh delete v5.1.5-rs-2400
EOF
    exit 0
  fi

  if [ -z "$1" ]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh delete <TAG_NAME>"
    exit 1
  fi

  local tag_name="$1"

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found."
    exit 1
  fi

  local status
  status=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | .status' "$TAGS_FILE")

  if [ "$status" == "production" ]; then
    echo "Warning: Tag '$tag_name' is in production status."
    read -rp "Are you sure you want to delete it? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  # Remove git tags from source repos
  local kernel_name
  kernel_name=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | .kernel_name' "$TAGS_FILE")
  if [ -n "$kernel_name" ]; then
    local repos
    repos=($(find_git_repos "$kernel_name"))
    for repo in "${repos[@]}"; do
      if git -C "$repo" rev-parse "refs/tags/$tag_name" &>/dev/null; then
        git -C "$repo" tag -d "$tag_name" 2>/dev/null && \
          echo "  Removed source tag from: ${repo#$REPO_ROOT/}"
      fi
    done
  fi

  # Remove archived deb directory
  if [ -d "$ARCHIVE_DIR/$tag_name" ]; then
    rm -rf "$ARCHIVE_DIR/$tag_name"
    echo "  Removed archive: kernel_archive/$tag_name/"
  fi

  jq --arg tag "$tag_name" 'del(.[] | select(.tag == $tag))' "$TAGS_FILE" > "$TAGS_FILE.tmp" \
    && mv "$TAGS_FILE.tmp" "$TAGS_FILE"

  echo "Deleted tag: $tag_name"
}

# ── log ──────────────────────────────────────────────────────────────────────

cmd_log() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh log [--limit N]

Show a chronological build log, most recent first.

Options:
  --limit <N>                Number of entries to show (default: 20)

Example:
  kernel_tags.sh log
  kernel_tags.sh log --limit 5
EOF
    exit 0
  fi

  local limit=20

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for 'log' command"; exit 1 ;;
    esac
  done

  local count
  count=$(jq 'length' "$TAGS_FILE")

  if [ "$count" -eq 0 ]; then
    echo "No tagged kernel builds."
    return
  fi

  echo "Kernel Build Log (most recent first, showing up to $limit):"
  echo ""

  jq -r "sort_by(.build_date) | reverse | .[:$limit][] |
    .tag as \$t |
    \"  \" + .build_date[:10] + \"  \" +
    \"[\(.status | if . == \"production\" then \"PROD\" elif . == \"staging\" then \"STAG\" elif . == \"testing\" then \"TEST\" else \"DEV \" end)]\" +
    \"  \" + .tag +
    (if .description != \"\" then \"\n              \" + .description else \"\" end)" "$TAGS_FILE"
}

# ── export ───────────────────────────────────────────────────────────────────

cmd_export() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh export [options]

Export tag data in JSON or human-readable text format.

Options:
  --format <json|text>       Output format (default: json)
  --status <status>          Filter by deployment status
  --output <file>            Write to file instead of stdout

Examples:
  kernel_tags.sh export
  kernel_tags.sh export --format text --status production
  kernel_tags.sh export --output releases.json
EOF
    exit 0
  fi

  local format="json" filter_status="" output=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --format) format="$2"; shift 2 ;;
      --status) filter_status="$2"; shift 2 ;;
      --output) output="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for 'export' command"; exit 1 ;;
    esac
  done

  local filter="."
  if [ -n "$filter_status" ]; then
    validate_status "$filter_status"
    filter="select(.status == \"$filter_status\")"
  fi

  local result
  if [ "$format" == "json" ]; then
    result=$(jq "[.[] | $filter]" "$TAGS_FILE")
  elif [ "$format" == "text" ]; then
    result=$(jq -r "[.[] | $filter] | sort_by(.build_date) | reverse[] |
      \"Tag:          \" + .tag +
      \"\nKernel:       \" + .kernel_name +
      \"\nLocalversion: \" + .localversion +
      \"\nStatus:       \" + .status +
      \"\nBuild Date:   \" + .build_date +
      \"\nBuilder:      \" + .builder +
      \"\nDescription:  \" + .description +
      \"\n\"" "$TAGS_FILE")
  else
    echo "Error: Unknown format '$format'. Use 'json' or 'text'."
    exit 1
  fi

  if [ -n "$output" ]; then
    echo "$result" > "$output"
    echo "Exported to: $output"
  else
    echo "$result"
  fi
}

# ── kernels ──────────────────────────────────────────────────────────────────

cmd_kernels() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh kernels

List all available kernel sources under kernels/ with their status.

Shows for each kernel:
  - Git repo info (branch, commit, remote)
  - Source git tags
  - Matching built .deb packages in kernel_debs/
  - Tagged builds from the manifest
  - Archived .deb count in kernel_archive/

Example:
  kernel_tags.sh kernels
EOF
    exit 0
  fi

  if [ ! -d "$KERNELS_DIR" ]; then
    echo "No kernels/ directory found."
    return
  fi

  local found=false
  for kernel_dir in "$KERNELS_DIR"/*/; do
    [ -d "$kernel_dir" ] || continue

    local name
    name=$(basename "$kernel_dir")

    # Skip .gitkeep and non-directory entries
    [ "$name" = ".gitkeep" ] && continue
    # Skip files that aren't directories (e.g. extracted_active.dts)
    [ ! -d "$kernel_dir" ] && continue

    found=true
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Kernel: $name"

    # Git info
    if [ -d "$kernel_dir/.git" ]; then
      local branch commit remote
      branch=$(git -C "$kernel_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
      commit=$(git -C "$kernel_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
      remote=$(git -C "$kernel_dir" remote get-url origin 2>/dev/null || \
               git -C "$kernel_dir" remote get-url "$(git -C "$kernel_dir" remote | head -1)" 2>/dev/null || \
               echo "none")
      echo "  Source: git repo (branch: $branch, commit: $commit)"
      echo "  Remote: $remote"

      local source_tags
      source_tags=$(git -C "$kernel_dir" tag -l 2>/dev/null | head -10)
      if [ -n "$source_tags" ]; then
        local tag_count
        tag_count=$(git -C "$kernel_dir" tag -l 2>/dev/null | wc -l)
        echo "  Git tags: $(echo "$source_tags" | tr '\n' ', ' | sed 's/,$//')$([ "$tag_count" -gt 10 ] && echo " ... (+$((tag_count - 10)) more)")"
      fi
    elif [ -d "$kernel_dir/kernel/kernel/.git" ]; then
      local branch commit
      branch=$(git -C "$kernel_dir/kernel/kernel" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
      commit=$(git -C "$kernel_dir/kernel/kernel" rev-parse --short HEAD 2>/dev/null || echo "unknown")
      echo "  Source: git repo at kernel/kernel/ (branch: $branch, commit: $commit)"
    else
      echo "  Source: not a git repository"
    fi

    # Built debs — match by localversion from tags, or by heuristic from kernel name
    if [ -d "$KERNEL_DEBS_DIR" ]; then
      # Collect known localversions for this kernel from the manifest
      local known_lvs
      known_lvs=$(jq -r --arg kernel "$name" \
        '[.[] | select(.kernel_name == $kernel) | .localversion] | unique | .[]' "$TAGS_FILE" 2>/dev/null)

      local matched_debs=()

      # Match by known localversions from tags
      if [ -n "$known_lvs" ]; then
        while IFS= read -r lv; do
          [ -z "$lv" ] && continue
          for f in "$KERNEL_DEBS_DIR"/linux-custom-*"-${lv}.deb"; do
            [ -f "$f" ] && matched_debs+=("$(basename "$f")")
          done
        done <<< "$known_lvs"
      fi

      # Heuristic: transform kernel dir name to a likely localversion prefix
      # e.g. cartken_5_1_5 -> cartken5.1.5, cartken_6_2 -> cartken6.2
      local heuristic_prefix
      heuristic_prefix=$(echo "$name" | sed 's/_\([0-9]\)/\.\1/g; s/\.\([0-9]\)/\1/1')
      for f in "$KERNEL_DEBS_DIR"/linux-custom-*".deb"; do
        [ -f "$f" ] || continue
        local bn
        bn=$(basename "$f")
        if [[ "$bn" == *"-${heuristic_prefix}"* ]]; then
          # Avoid duplicates
          local dup=false
          for existing in "${matched_debs[@]}"; do
            [ "$existing" = "$bn" ] && { dup=true; break; }
          done
          [ "$dup" = false ] && matched_debs+=("$bn")
        fi
      done

      if [ ${#matched_debs[@]} -gt 0 ]; then
        echo "  Built debs: (${#matched_debs[@]} in kernel_debs/)"
        for d in "${matched_debs[@]}"; do
          echo "    $d"
        done
      fi
    fi

    # Tags from manifest
    local tag_count
    tag_count=$(jq --arg kernel "$name" '[.[] | select(.kernel_name == $kernel)] | length' "$TAGS_FILE" 2>/dev/null)
    if [ "$tag_count" -gt 0 ]; then
      echo "  Tagged builds:"
      jq -r --arg kernel "$name" '[.[] | select(.kernel_name == $kernel)] | sort_by(.build_date) | reverse[] |
        "    " + .tag + "  [" + .status + "]  " + .build_date[:10] +
        (if .description != "" then "  - " + .description else "" end)' "$TAGS_FILE"
    else
      echo "  Tagged builds: none"
    fi

    # Archived debs
    local archive_count=0
    for tag_dir in "$ARCHIVE_DIR"/*/; do
      [ -d "$tag_dir" ] || continue
      local tag_name
      tag_name=$(basename "$tag_dir")
      local is_this_kernel
      is_this_kernel=$(jq -r --arg tag "$tag_name" --arg kernel "$name" \
        '.[] | select(.tag == $tag and .kernel_name == $kernel) | .tag' "$TAGS_FILE" 2>/dev/null)
      if [ -n "$is_this_kernel" ]; then
        archive_count=$((archive_count + 1))
      fi
    done
    if [ "$archive_count" -gt 0 ]; then
      echo "  Archived debs: $archive_count (in kernel_archive/)"
    fi

    echo ""
  done

  if [ "$found" = false ]; then
    echo "No kernel source directories found under kernels/"
  fi
}

# ── notes ────────────────────────────────────────────────────────────────────

cmd_notes() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh notes <TAG_NAME> --add <text>

Add timestamped notes to an existing tag. Useful for recording observations
after deployment, known issues, or test results.

Options:
  --add <text>               Note text to add

Examples:
  kernel_tags.sh notes v5.1.5-rs-2400 --add "Stable after 2 weeks on fleet"
  kernel_tags.sh notes v5.1.5-rs-2400 --add "Known issue: USB3 hotplug fails under load"
EOF
    exit 0
  fi

  if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh notes <TAG_NAME> --add <text>"
    exit 1
  fi

  local tag_name="$1"
  shift

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found."
    exit 1
  fi

  local note_text=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --add) note_text="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for 'notes' command"; exit 1 ;;
    esac
  done

  if [ -z "$note_text" ]; then
    echo "Error: --add <text> is required."
    exit 1
  fi

  local now builder
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  builder=$(get_builder)

  jq --arg tag "$tag_name" \
     --arg text "$note_text" \
     --arg date "$now" \
     --arg by "$builder" \
    '(.[] | select(.tag == $tag)) |=
      (.notes = ((.notes // []) + [{text: $text, date: $date, by: $by}]))' \
    "$TAGS_FILE" > "$TAGS_FILE.tmp" && mv "$TAGS_FILE.tmp" "$TAGS_FILE"

  echo "Note added to '$tag_name':"
  echo "  [$now] $note_text"
}

# ── diff ─────────────────────────────────────────────────────────────────────

cmd_diff() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh diff <TAG_1> <TAG_2>

Compare two tagged builds. Shows:
  - Metadata differences (kernel, localversion, status, config, etc.)
  - Git commit log between the two tags in source repos

Examples:
  kernel_tags.sh diff v5.1.5-base v5.1.5-rs-2400
EOF
    exit 0
  fi

  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Two tag names are required."
    echo "Usage: kernel_tags.sh diff <TAG_1> <TAG_2>"
    exit 1
  fi

  local tag1="$1" tag2="$2"

  if ! tag_exists "$tag1"; then
    echo "Error: Tag '$tag1' not found."
    exit 1
  fi
  if ! tag_exists "$tag2"; then
    echo "Error: Tag '$tag2' not found."
    exit 1
  fi

  echo "Comparing: $tag1 -> $tag2"
  echo "════════════════════════════════════════════════════"
  echo ""

  # Metadata comparison
  local fields=("kernel_name" "localversion" "status" "config" "dtb_name" "builder" "build_date")
  local field_labels=("Kernel" "Localversion" "Status" "Config" "DTB" "Builder" "Build Date")

  echo "Metadata:"
  local i=0
  local has_diff=false
  for field in "${fields[@]}"; do
    local val1 val2
    val1=$(jq -r --arg tag "$tag1" --arg f "$field" '.[] | select(.tag == $tag) | .[$f] // ""' "$TAGS_FILE")
    val2=$(jq -r --arg tag "$tag2" --arg f "$field" '.[] | select(.tag == $tag) | .[$f] // ""' "$TAGS_FILE")

    if [ "$val1" != "$val2" ]; then
      printf "  %-14s %s -> %s\n" "${field_labels[$i]}:" "$val1" "$val2"
      has_diff=true
    fi
    i=$((i + 1))
  done

  if [ "$has_diff" = false ]; then
    echo "  (no metadata differences)"
  fi

  # Description comparison
  local desc1 desc2
  desc1=$(jq -r --arg tag "$tag1" '.[] | select(.tag == $tag) | .description // ""' "$TAGS_FILE")
  desc2=$(jq -r --arg tag "$tag2" '.[] | select(.tag == $tag) | .description // ""' "$TAGS_FILE")
  echo ""
  echo "Descriptions:"
  echo "  $tag1: ${desc1:-"(none)"}"
  echo "  $tag2: ${desc2:-"(none)"}"

  # Git log between tags in source repos
  local kernel1 kernel2
  kernel1=$(jq -r --arg tag "$tag1" '.[] | select(.tag == $tag) | .kernel_name // ""' "$TAGS_FILE")
  kernel2=$(jq -r --arg tag "$tag2" '.[] | select(.tag == $tag) | .kernel_name // ""' "$TAGS_FILE")

  # Try to find git log if both tags exist in the same repo
  if [ -n "$kernel1" ]; then
    local repos
    repos=($(find_git_repos "$kernel1"))

    for repo in "${repos[@]}"; do
      local repo_rel="${repo#$REPO_ROOT/}"
      local has_tag1 has_tag2
      has_tag1=$(git -C "$repo" rev-parse "refs/tags/$tag1" 2>/dev/null) || true
      has_tag2=$(git -C "$repo" rev-parse "refs/tags/$tag2" 2>/dev/null) || true

      if [ -n "$has_tag1" ] && [ -n "$has_tag2" ]; then
        echo ""
        echo "Source changes ($repo_rel): $tag1..$tag2"
        echo "────────────────────────────────────────────────────"
        local log_output
        log_output=$(git -C "$repo" log --oneline --no-decorate "$tag1..$tag2" 2>/dev/null | head -30)
        if [ -n "$log_output" ]; then
          echo "$log_output"
          local total
          total=$(git -C "$repo" rev-list --count "$tag1..$tag2" 2>/dev/null || echo "?")
          if [ "$total" -gt 30 ] 2>/dev/null; then
            echo "  ... ($total commits total, showing first 30)"
          fi
        else
          # Try reverse direction
          log_output=$(git -C "$repo" log --oneline --no-decorate "$tag2..$tag1" 2>/dev/null | head -30)
          if [ -n "$log_output" ]; then
            echo "(reverse: $tag2..$tag1)"
            echo "$log_output"
          else
            echo "  (no commits between tags, or tags point to the same commit)"
          fi
        fi

        local stat_output
        stat_output=$(git -C "$repo" diff --stat "$tag1" "$tag2" 2>/dev/null | tail -1)
        if [ -n "$stat_output" ]; then
          echo ""
          echo "  $stat_output"
        fi
      fi
    done
  fi

  # If different kernels, also check the second kernel's repos
  if [ -n "$kernel2" ] && [ "$kernel1" != "$kernel2" ]; then
    echo ""
    echo "Note: Tags are from different kernel sources ($kernel1 vs $kernel2)."
    echo "Git log comparison only works within the same source tree."
  fi
}

# ── verify ───────────────────────────────────────────────────────────────────

cmd_verify() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh verify <TAG_NAME> --ip <address> [--user <user>]

SSH into a remote device and verify that the running kernel matches the
tagged build by checking uname -r against the expected localversion.

Required:
  <TAG_NAME>                 The tag to verify against
  --ip <address>             IP address of the target machine

Options:
  --user <user>              SSH user (default: cartken)

Examples:
  kernel_tags.sh verify v5.1.5-rs-2400 --ip 192.168.1.230
  kernel_tags.sh verify v5.1.5-rs-2400 --ip 192.168.1.230 --user root
EOF
    exit 0
  fi

  if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh verify <TAG_NAME> --ip <address> [--user <user>]"
    exit 1
  fi

  local tag_name="$1"
  shift

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found."
    exit 1
  fi

  local device_ip="" user="cartken" password=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --ip)       device_ip="$2"; shift 2 ;;
      --user)     user="$2"; shift 2 ;;
      --password) password="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for 'verify' command"; exit 1 ;;
    esac
  done

  if [ -z "$device_ip" ]; then
    echo "Error: --ip is required."
    exit 1
  fi

  if [ -n "$password" ] && ! command -v sshpass &>/dev/null; then
    echo "Error: --password requires 'sshpass' but it is not installed."
    exit 1
  fi

  local expected_lv
  expected_lv=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | .localversion' "$TAGS_FILE")

  local remote="$user@$device_ip"

  echo "Verifying '$tag_name' on $remote..."
  echo "  Expected localversion: $expected_lv"

  local remote_uname
  if [ -n "$password" ]; then
    remote_uname=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$remote" "uname -r" 2>/dev/null) || {
      echo "  Error: Cannot SSH into $remote."
      exit 1
    }
  else
    remote_uname=$(ssh -o ConnectTimeout=10 "$remote" "uname -r" 2>/dev/null) || {
      echo "  Error: Cannot SSH into $remote."
      exit 1
    }
  fi

  echo "  Remote uname -r:       $remote_uname"
  echo ""

  if [[ "$remote_uname" == *"$expected_lv" ]]; then
    echo "  MATCH - Device is running the expected kernel."
    return 0
  else
    echo "  MISMATCH - Device is NOT running the expected kernel."
    echo "  Expected suffix: $expected_lv"
    echo "  Actual:          $remote_uname"
    return 1
  fi
}

# ── get-deb ──────────────────────────────────────────────────────────────────

cmd_get_deb() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh get-deb <TAG_NAME>

Print the absolute path to the archived .deb for the given tag.
Useful for scripted redeployment or manual inspection.

Examples:
  kernel_tags.sh get-deb v5.1.5-rs-2400
  scp $(kernel_tags.sh get-deb v5.1.5-rs-2400) user@device:/tmp/
EOF
    exit 0
  fi

  if [ -z "$1" ]; then
    echo "Error: Tag name is required." >&2
    echo "Usage: kernel_tags.sh get-deb <TAG_NAME>" >&2
    exit 1
  fi

  local tag_name="$1"

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found." >&2
    exit 1
  fi

  local deb_path
  deb_path=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) | .deb_package' "$TAGS_FILE")

  if [ -z "$deb_path" ] || [ "$deb_path" = "null" ] || [ "$deb_path" = "" ]; then
    echo "Error: No .deb package recorded for tag '$tag_name'." >&2
    exit 1
  fi

  # Resolve to absolute path
  if [[ "$deb_path" != /* ]]; then
    deb_path="$REPO_ROOT/$deb_path"
  fi

  if [ ! -f "$deb_path" ]; then
    echo "Error: Archived .deb not found at: $deb_path" >&2
    exit 1
  fi

  echo "$deb_path"
}

# ── deploy helpers ────────────────────────────────────────────────────────────

_expand_robot_numbers() {
  local input="$1"
  local numbers=()
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    part=$(echo "$part" | xargs)
    if [[ "$part" == *-* ]]; then
      local range_start="${part%-*}"
      local range_end="${part#*-}"
      for ((i=range_start; i<=range_end; i++)); do
        numbers+=("$i")
      done
    else
      numbers+=("$part")
    fi
  done
  echo "${numbers[@]}"
}

_ssh_cmd() {
  local password="$1"; shift
  if [ -n "$password" ]; then
    sshpass -p "$password" ssh -o StrictHostKeyChecking=accept-new "$@"
  else
    ssh "$@"
  fi
}

_scp_cmd() {
  local password="$1"; shift
  if [ -n "$password" ]; then
    sshpass -p "$password" scp -o StrictHostKeyChecking=accept-new "$@"
  else
    scp "$@"
  fi
}

_deploy_to_target() {
  local tag_name="$1" deb_path="$2" user="$3" device_ip="$4"
  local remote_dir="$5" password="$6" do_install="$7" do_reboot="$8"

  local remote="$user@$device_ip"
  local deb_filename
  deb_filename=$(basename "$deb_path")
  local deb_size
  deb_size=$(du -h "$deb_path" | cut -f1)
  local remote_dest="$remote_dir/$deb_filename"
  local ssh_ctrl="/tmp/kernel-deploy-$$-$device_ip"
  local ssh_opts="-o ControlMaster=auto -o ControlPath=$ssh_ctrl -o ControlPersist=60 -o ConnectTimeout=10"

  echo "  Target: $remote"
  echo "  Dest:   $remote:$remote_dest"
  echo ""

  # Establish SSH connection + create remote directory (single auth prompt)
  echo "  Connecting and preparing $remote_dir..."
  if ! _ssh_cmd "$password" $ssh_opts "$remote" "mkdir -p $remote_dir" 2>/dev/null; then
    echo "  Error: Cannot connect to $remote."
    ssh -o ControlPath="$ssh_ctrl" -O exit "$remote" 2>/dev/null || true
    return 1
  fi
  echo "  Connected."

  # Copy .deb (reuses ControlMaster — no re-authentication)
  echo "  Copying $deb_filename ($deb_size)..."
  if ! _scp_cmd "$password" -o "ControlPath=$ssh_ctrl" -C "$deb_path" "$remote:$remote_dest"; then
    echo "  Error: Failed to copy .deb to $remote."
    ssh -o ControlPath="$ssh_ctrl" -O exit "$remote" 2>/dev/null || true
    return 1
  fi
  echo "  Copy complete."
  echo ""

  if [ "$do_install" = true ]; then
    echo "  Installing: sudo dpkg -i $remote_dest"
    if ! _ssh_cmd "$password" $ssh_opts "$remote" "sudo dpkg -i $remote_dest"; then
      echo "  Error: dpkg -i failed on $remote"
      ssh -o ControlPath="$ssh_ctrl" -O exit "$remote" 2>/dev/null || true
      return 1
    fi
    echo "  Install complete."

    if [ "$do_reboot" = true ]; then
      echo "  Rebooting $remote..."
      _ssh_cmd "$password" $ssh_opts "$remote" "sudo reboot" 2>/dev/null || true
      echo "  Reboot command sent."
    fi
  else
    echo "  Copied to $remote:$remote_dest"
    echo "  To install manually:"
    echo "    sudo dpkg -i $remote_dest"
  fi

  # Tear down ControlMaster
  ssh -o ControlPath="$ssh_ctrl" -O exit "$remote" 2>/dev/null || true
  return 0
}

_record_deployment() {
  local tag_name="$1" target="$2" mode="$3"
  local now builder
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  builder=$(get_builder)

  jq --arg tag "$tag_name" \
     --arg target "$target" \
     --arg date "$now" \
     --arg by "$builder" \
     --arg mode "$mode" \
    '(.[] | select(.tag == $tag)) |=
      (.deployments = ((.deployments // []) + [{target: $target, date: $date, by: $by, mode: $mode}]))' \
    "$TAGS_FILE" > "$TAGS_FILE.tmp" && mv "$TAGS_FILE.tmp" "$TAGS_FILE"
}

# ── deploy ───────────────────────────────────────────────────────────────────

cmd_deploy() {
  if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: kernel_tags.sh deploy <TAG_NAME> [target options] [options]

Copy a tagged kernel's .deb to one or more remote machines. By default only
copies the file; use --install to also run dpkg -i and optionally reboot.

Uses SSH ControlMaster to avoid multiple password prompts per target. Provide
--password to avoid being prompted at all (requires sshpass).

Target selection (at least one required):
  --ip <address>             Target IP (can be repeated)
  --robots <list>            Comma-separated robot numbers, supports ranges
                             e.g. --robots 1,2,5-8
  --robot-ip-prefix <prefix> IP prefix for robots (e.g. "10.42.0.")
                             Robot IP = prefix + number (e.g. 10.42.0.5)
  --hosts-file <file>        File with one IP per line (# comments allowed)

Options:
  --user <user>              SSH user (default: cartken)
  --password <pass>          SSH password (uses sshpass, avoids interactive prompts)
  --remote-dir <path>        Where to put the .deb on the remote (default: ~/kernel_debs)
  --install                  Also install with dpkg -i after copying
  --no-reboot                Skip reboot after install (only relevant with --install)
  --sequential               Copy to targets one at a time (default: parallel for 2+ targets)
  --dry-run                  Show what would be done without executing

Examples:
  # Copy to a single robot
  kernel_tags.sh deploy v5.1.5-rs-2400 --ip 10.42.0.5

  # Copy to robots 1, 2, and 5 through 8 using password
  kernel_tags.sh deploy v5.1.5-rs-2400 \
    --robots 1,2,5-8 --robot-ip-prefix "10.42.0." \
    --password "secret"

  # Copy to a list of hosts from a file
  kernel_tags.sh deploy v5.1.5-rs-2400 --hosts-file fleet.txt

  # Full install + reboot
  kernel_tags.sh deploy v5.1.5-rs-2400 --ip 10.42.0.5 --install

  # Dry run to preview
  kernel_tags.sh deploy v5.1.5-rs-2400 --robots 1,2,3 \
    --robot-ip-prefix "10.42.0." --dry-run
EOF
    exit 0
  fi

  if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh deploy <TAG_NAME> [target options] [options]"
    echo "Run 'kernel_tags.sh deploy --help' for full usage."
    exit 1
  fi

  local tag_name="$1"
  shift

  if ! tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' not found."
    exit 1
  fi

  local device_ips=() user="cartken" password="" do_install=false do_reboot=true
  local dry_run=false hosts_file="" remote_dir="~/kernel_debs" sequential=false
  local robot_numbers_raw="" robot_ip_prefix=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --ip)              device_ips+=("$2"); shift 2 ;;
      --robots)          robot_numbers_raw="$2"; shift 2 ;;
      --robot-ip-prefix) robot_ip_prefix="$2"; shift 2 ;;
      --hosts-file)      hosts_file="$2"; shift 2 ;;
      --user)            user="$2"; shift 2 ;;
      --password)        password="$2"; shift 2 ;;
      --remote-dir)      remote_dir="$2"; shift 2 ;;
      --install)         do_install=true; shift ;;
      --no-reboot)       do_reboot=false; shift ;;
      --sequential)      sequential=true; shift ;;
      --dry-run)         dry_run=true; shift ;;
      --copy-only)       shift ;;  # no-op, copy is already the default
      *) echo "Error: Unknown option '$1' for 'deploy' command"; exit 1 ;;
    esac
  done

  # Resolve robot numbers to IPs
  if [ -n "$robot_numbers_raw" ]; then
    if [ -z "$robot_ip_prefix" ]; then
      echo "Error: --robot-ip-prefix is required when using --robots."
      echo "  Example: --robots 1,2,5-8 --robot-ip-prefix \"10.42.0.\""
      exit 1
    fi
    local numbers
    numbers=($(_expand_robot_numbers "$robot_numbers_raw"))
    for num in "${numbers[@]}"; do
      device_ips+=("${robot_ip_prefix}${num}")
    done
  fi

  # Load IPs from hosts file
  if [ -n "$hosts_file" ]; then
    if [ ! -f "$hosts_file" ]; then
      echo "Error: Hosts file '$hosts_file' not found."
      exit 1
    fi
    while IFS= read -r line; do
      line=$(echo "$line" | sed 's/#.*//' | xargs)
      [ -n "$line" ] && device_ips+=("$line")
    done < "$hosts_file"
  fi

  if [ ${#device_ips[@]} -eq 0 ]; then
    echo "Error: No targets specified. Use --ip, --robots, or --hosts-file."
    echo "Run 'kernel_tags.sh deploy --help' for full usage."
    exit 1
  fi

  # Check sshpass availability when --password is used
  if [ -n "$password" ] && ! command -v sshpass &>/dev/null; then
    echo "Error: --password requires 'sshpass' but it is not installed."
    echo "Install it with: sudo pacman -S sshpass (Arch/Manjaro) or sudo apt install sshpass (Debian/Ubuntu)"
    exit 1
  fi

  # Resolve the deb path
  local deb_path
  deb_path=$(cmd_get_deb "$tag_name") || exit 1
  local deb_filename
  deb_filename=$(basename "$deb_path")
  local deb_size
  deb_size=$(du -h "$deb_path" | cut -f1)

  local mode="copy"
  if [ "$do_install" = true ]; then
    mode="install"
  fi

  local fleet_mode=false
  if [ ${#device_ips[@]} -gt 1 ]; then
    fleet_mode=true
  fi

  # Show deployment plan
  local tag_info
  tag_info=$(jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) |
    "  Tag:          " + .tag +
    "\n  Kernel:       " + .kernel_name +
    "\n  Localversion: " + .localversion +
    "\n  Status:       " + .status' "$TAGS_FILE")

  echo "Deploy Plan"
  echo "==========="
  echo "$tag_info"
  echo "  Deb:          $deb_filename ($deb_size)"
  echo "  Remote dir:   $remote_dir"
  if [ "$fleet_mode" = true ]; then
    echo "  Targets:      ${#device_ips[@]} machines (user: $user)"
    for ip in "${device_ips[@]}"; do
      echo "                  - $ip"
    done
    if [ "$sequential" = false ]; then
      echo "  Parallel:     yes"
    else
      echo "  Parallel:     no (sequential)"
    fi
  else
    echo "  Target:       $user@${device_ips[0]}"
  fi
  echo "  Mode:         $mode$([ "$mode" = "install" ] && [ "$do_reboot" = true ] && echo " + reboot")"
  [ -n "$password" ] && echo "  Auth:         password (sshpass)"
  echo ""

  if [ "$dry_run" = true ]; then
    for device_ip in "${device_ips[@]}"; do
      local remote="$user@$device_ip"
      echo "[dry-run] ssh $remote 'mkdir -p $remote_dir'"
      echo "[dry-run] scp -C $deb_path $remote:$remote_dir/$deb_filename"
      if [ "$do_install" = true ]; then
        echo "[dry-run] ssh $remote 'sudo dpkg -i $remote_dir/$deb_filename'"
        if [ "$do_reboot" = true ]; then
          echo "[dry-run] ssh $remote 'sudo reboot'"
        fi
      fi
      echo ""
    done
    return
  fi

  # ── Single target: deploy inline with live output ──
  if [ "$fleet_mode" = false ]; then
    if _deploy_to_target "$tag_name" "$deb_path" "$user" "${device_ips[0]}" \
         "$remote_dir" "$password" "$do_install" "$do_reboot"; then
      _record_deployment "$tag_name" "$user@${device_ips[0]}" "$mode"
      echo ""
      echo "Done."
    else
      echo ""
      echo "Deploy to $user@${device_ips[0]} failed."
      exit 1
    fi
    return
  fi

  # ── Fleet deploy ──
  local success_count=0 fail_count=0
  local tmpdir
  tmpdir=$(mktemp -d "/tmp/kernel-fleet-$$-XXXXXX")

  if [ "$sequential" = true ]; then
    # Sequential fleet deploy
    for device_ip in "${device_ips[@]}"; do
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      if _deploy_to_target "$tag_name" "$deb_path" "$user" "$device_ip" \
           "$remote_dir" "$password" "$do_install" "$do_reboot"; then
        _record_deployment "$tag_name" "$user@$device_ip" "$mode"
        success_count=$((success_count + 1))
      else
        fail_count=$((fail_count + 1))
      fi
      echo ""
    done
  else
    # Parallel fleet deploy
    local pids=()
    echo "Starting parallel copy to ${#device_ips[@]} targets..."
    echo ""

    for device_ip in "${device_ips[@]}"; do
      local logfile="$tmpdir/$device_ip.log"
      (
        _deploy_to_target "$tag_name" "$deb_path" "$user" "$device_ip" \
          "$remote_dir" "$password" "$do_install" "$do_reboot" > "$logfile" 2>&1
        echo $? > "$tmpdir/$device_ip.exit"
      ) &
      pids+=($!)
    done

    # Wait for all background jobs
    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done

    # Collect results
    for device_ip in "${device_ips[@]}"; do
      local logfile="$tmpdir/$device_ip.log"
      local exitfile="$tmpdir/$device_ip.exit"
      local exit_code
      exit_code=$(cat "$exitfile" 2>/dev/null || echo "1")

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      if [ "$exit_code" -eq 0 ]; then
        echo "  ✓ $user@$device_ip"
        _record_deployment "$tag_name" "$user@$device_ip" "$mode"
        success_count=$((success_count + 1))
      else
        echo "  ✗ $user@$device_ip (FAILED)"
        fail_count=$((fail_count + 1))
      fi

      # Show log output indented
      if [ -f "$logfile" ]; then
        sed 's/^/    /' "$logfile"
      fi
      echo ""
    done
  fi

  rm -rf "$tmpdir"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Fleet Summary: $success_count succeeded, $fail_count failed (${#device_ips[@]} total)"
}

# ── main ─────────────────────────────────────────────────────────────────────

ensure_jq
ensure_tags_file

if [ -z "$1" ]; then
  show_help
fi

COMMAND="$1"
shift

case "$COMMAND" in
  tag)     cmd_tag "$@" ;;
  list)    cmd_list "$@" ;;
  show)    cmd_show "$@" ;;
  promote) cmd_promote "$@" ;;
  notes)   cmd_notes "$@" ;;
  diff)    cmd_diff "$@" ;;
  verify)  cmd_verify "$@" ;;
  delete)  cmd_delete "$@" ;;
  log)     cmd_log "$@" ;;
  export)  cmd_export "$@" ;;
  get-deb) cmd_get_deb "$@" ;;
  deploy)  cmd_deploy "$@" ;;
  kernels) cmd_kernels "$@" ;;
  --help|-h|help) show_help ;;
  *) echo "Error: Unknown command '$COMMAND'. Run with --help for usage."; exit 1 ;;
esac
