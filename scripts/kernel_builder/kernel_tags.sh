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

show_help() {
  cat <<'HELP'
Kernel Build Tagging Tool
=========================

Usage: kernel_tags.sh <command> [options]

Commands:

  tag       Create a new kernel build tag (tags source repos + archives .deb)
  list      List tagged kernel builds (with optional filters)
  show      Show full details of a specific tag
  promote   Change the deployment status of a tagged build
  delete    Remove a tag from the manifest
  log       Show a chronological build log
  export    Export tag data (JSON or human-readable)
  get-deb   Print the archived .deb path for a tag (useful for redeployment)

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

  When tagging, this tool will:
    1. Record the build metadata in kernel_tags.json
    2. Create a git tag in all source repos under kernels/<kernel>/ (unless --no-source-tag)
    3. Copy the .deb to kernel_archive/<tag>/ for redeployment (unless --no-archive)

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
  if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "Error: Tag name is required."
    echo "Usage: kernel_tags.sh tag <TAG_NAME> [options]"
    exit 1
  fi

  local tag_name="$1"
  shift

  if tag_exists "$tag_name"; then
    echo "Error: Tag '$tag_name' already exists. Use 'delete' first to re-tag."
    exit 1
  fi

  local kernel_name="" localversion="" description="" config="" dtb_name=""
  local status="development" deb_package=""
  local skip_source_tag=false skip_archive=false

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
      *) echo "Error: Unknown option '$1' for 'tag' command"; exit 1 ;;
    esac
  done

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

  # Use the archived path if we have one, otherwise keep the original deb_package
  local final_deb="${archived_deb:-$deb_package}"

  # ── Step 3: Record in manifest ──
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
    --argjson source_repos "$source_repos_json" \
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
      source_repos_tagged: $source_repos,
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
    "\nDeb Package:   " + .deb_package +
    "\nSource Repos:  " + (if .source_repos_tagged then (.source_repos_tagged | join(", ")) else "none" end) +
    "\nDescription:   " + .description' "$TAGS_FILE"

  echo ""
  echo "Status History:"
  jq -r --arg tag "$tag_name" '.[] | select(.tag == $tag) |
    .status_history[] |
    "  " + .date + "  " + .status + "  (" + .by + ")"' "$TAGS_FILE"
}

# ── promote ──────────────────────────────────────────────────────────────────

cmd_promote() {
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

# ── get-deb ──────────────────────────────────────────────────────────────────

cmd_get_deb() {
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
  delete)  cmd_delete "$@" ;;
  log)     cmd_log "$@" ;;
  export)  cmd_export "$@" ;;
  get-deb) cmd_get_deb "$@" ;;
  --help|-h|help) show_help ;;
  *) echo "Error: Unknown command '$COMMAND'. Run with --help for usage."; exit 1 ;;
esac
