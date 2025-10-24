#!/usr/bin/env bash
set -e

repo_url="https://github.com/IntelRealSense/librealsense.git"
branch=""
use_docker=false
all_args=($@)
repo_name=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --docker)
            use_docker=true
            shift
            ;;
        --cartken)
            repo_url="git@gitlab.com:cartken/librealsense_cartken.git"
            shift
            ;;
        --branch)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --branch option requires a value."
                exit 1
            fi
            branch="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
done

repo_name=$(basename "$repo_url" .git)


# --- Git Operations Function ---
run_git_ops() {

    if [[ ! -d "$repo_name" ]]; then
        git clone "$repo_url" "$repo_name"
    fi

    cd "$repo_name" || exit 1

    git fetch --all

    local_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$local_branch" == "HEAD" ]]; then
        remote_default=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d' ' -f5)
        if [[ -n "$remote_default" ]]; then
             git reset --hard "origin/$remote_default"
        else
             git reset --hard "origin/$local_branch"
        fi # <-- This was the missing 'fi'
    fi

    if [[ -n "$branch" ]]; then
        git checkout "$branch"
        git pull origin "$branch"
    fi

    cd ..
}


# --- Build-Only Function ---
run_build_only() {
    cd "$repo_name" || exit 1

    mkdir -p build
    cd build

    cmake ..
    make -j"$(nproc)"
    cd ../..
}


# --- Install & Build Function ---
run_install_and_build() {
    SETUP_DONE_FLAG="/opt/realsense_build_setup_done"

    if [[ ! -f "$SETUP_DONE_FLAG" ]]; then
        if [[ "$(id -u)" == "0" ]]; then
            apt-get update
            apt-get install -y \
                libssl-dev libusb-1.0-0-dev libudev-dev pkg-config libgtk-3-dev \
                git wget cmake build-essential \
                libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev at \
                libxrandr-dev \
                openssh-client

            touch "$SETUP_DONE_FLAG"
        fi
    fi

    run_build_only
}


CONTAINER_NAME="realsense-builder"

# --- Main Execution Logic ---

if [[ ! -f "/.dockerenv" ]]; then
    run_git_ops
fi

if [[ "$use_docker" = true ]]; then
    if [[ -f "/.dockerenv" ]]; then
        run_install_and_build
    else
        docker_args=()
        for arg in "${all_args[@]}"; do
            if [[ "$arg" != "--docker" ]]; then
                docker_args+=("$arg")
            fi
        done

        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

        if [[ -z "$(docker ps -a --filter name=$CONTAINER_NAME --format '{{.Names}}')" ]]; then
            docker run -it --name "$CONTAINER_NAME" \
                -v "${SCRIPT_DIR}":"${SCRIPT_DIR}" \
                -v "${SCRIPT_DIR}/${repo_name}":"${SCRIPT_DIR}/${repo_name}" \
                -w "${SCRIPT_DIR}" \
                --privileged \
                ubuntu:22.04 \
                "${SCRIPT_DIR}/$(basename "$0")" --docker "${docker_args[@]}"
        else
            if [[ -z "$(docker ps --filter name=$CONTAINER_NAME --format '{{.Names}}')" ]]; then
                docker start "$CONTAINER_NAME"
            fi
            docker exec -it "$CONTAINER_NAME" /bin/bash -c "cd \"$SCRIPT_DIR\" && ./$(basename "$0") --docker ${docker_args[*]}"
        fi
    fi
else
    run_install_and_build
fi


