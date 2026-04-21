# Bash tab completion for kernel_tags.sh
#
# To enable, add one of the following to your ~/.bashrc or ~/.zshrc:
#   source /path/to/kernel_tags_completion.bash
#
# Or for system-wide availability:
#   cp kernel_tags_completion.bash /etc/bash_completion.d/kernel_tags

_kernel_tags_get_tags() {
  local tags_file="${KERNEL_TAGS_JSON:-$(git rev-parse --show-toplevel 2>/dev/null)/kernel_tags.json}"
  if [ -f "$tags_file" ] && command -v jq &>/dev/null; then
    jq -r '.[].tag' "$tags_file" 2>/dev/null
  fi
}

_kernel_tags_get_kernels() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return
  local kernels_dir="$repo_root/kernels"
  if [ -d "$kernels_dir" ]; then
    for d in "$kernels_dir"/*/; do
      [ -d "$d" ] && basename "$d"
    done
  fi
}

_kernel_tags_get_statuses() {
  echo "development testing staging production"
}

_kernel_tags() {
  local cur prev words cword
  _init_completion || return

  local commands="tag list show promote notes diff verify deploy delete log export get-deb kernels help"

  if [ "$cword" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$commands --help" -- "$cur"))
    return
  fi

  local cmd="${words[1]}"

  case "$cmd" in
    tag)
      case "$prev" in
        --kernel)
          COMPREPLY=($(compgen -W "$(_kernel_tags_get_kernels)" -- "$cur"))
          return
          ;;
        --status)
          COMPREPLY=($(compgen -W "$(_kernel_tags_get_statuses)" -- "$cur"))
          return
          ;;
        --soc)
          COMPREPLY=($(compgen -W "orin xavier" -- "$cur"))
          return
          ;;
        --config|--dtb-name|--description|--localversion|--deb-package)
          return
          ;;
      esac
      COMPREPLY=($(compgen -W "--kernel --localversion --description --config --dtb-name --status --soc --deb-package --no-source-tag --no-archive --no-publish --force --help" -- "$cur"))
      ;;
    list)
      case "$prev" in
        --status)
          COMPREPLY=($(compgen -W "$(_kernel_tags_get_statuses)" -- "$cur"))
          return
          ;;
        --kernel)
          COMPREPLY=($(compgen -W "$(_kernel_tags_get_kernels)" -- "$cur"))
          return
          ;;
      esac
      COMPREPLY=($(compgen -W "--status --kernel --all --help" -- "$cur"))
      ;;
    show|delete|get-deb)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "$(_kernel_tags_get_tags) --help" -- "$cur"))
      fi
      ;;
    promote)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "$(_kernel_tags_get_tags) --help" -- "$cur"))
      else
        case "$prev" in
          --status)
            COMPREPLY=($(compgen -W "$(_kernel_tags_get_statuses)" -- "$cur"))
            return
            ;;
        esac
        COMPREPLY=($(compgen -W "--status --help" -- "$cur"))
      fi
      ;;
    notes)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "$(_kernel_tags_get_tags) --help" -- "$cur"))
      else
        COMPREPLY=($(compgen -W "--add --help" -- "$cur"))
      fi
      ;;
    diff)
      if [ "$cword" -le 3 ]; then
        COMPREPLY=($(compgen -W "$(_kernel_tags_get_tags) --help" -- "$cur"))
      fi
      ;;
    verify)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "$(_kernel_tags_get_tags) --help" -- "$cur"))
      else
        case "$prev" in
          --ip|--user|--password)
            return
            ;;
        esac
        COMPREPLY=($(compgen -W "--ip --user --password --help" -- "$cur"))
      fi
      ;;
    deploy)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "$(_kernel_tags_get_tags) --help" -- "$cur"))
      else
        case "$prev" in
          --hosts-file)
            _filedir
            return
            ;;
          --ip|--user|--password|--robots|--robot-ip-prefix|--remote-dir)
            return
            ;;
        esac
        COMPREPLY=($(compgen -W "--ip --robots --robot-ip-prefix --hosts-file --user --password --remote-dir --install --no-reboot --sequential --dry-run --help" -- "$cur"))
      fi
      ;;
    log)
      COMPREPLY=($(compgen -W "--limit --help" -- "$cur"))
      ;;
    export)
      case "$prev" in
        --format)
          COMPREPLY=($(compgen -W "json text" -- "$cur"))
          return
          ;;
        --status)
          COMPREPLY=($(compgen -W "$(_kernel_tags_get_statuses)" -- "$cur"))
          return
          ;;
        --output)
          _filedir
          return
          ;;
      esac
      COMPREPLY=($(compgen -W "--format --status --output --help" -- "$cur"))
      ;;
    kernels)
      COMPREPLY=($(compgen -W "--help" -- "$cur"))
      ;;
  esac
}

complete -F _kernel_tags kernel_tags.sh
complete -F _kernel_tags kernel_tags

# Also complete if invoked via full path
complete -F _kernel_tags ./scripts/kernel_builder/kernel_tags.sh
