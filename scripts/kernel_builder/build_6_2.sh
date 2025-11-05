#!/bin/bash

SCRIPT_DIR="$(realpath "$(dirname "$0")/..")"
cd $SCRIPT_DIR/..
$SCRIPT_DIR/kernel_builder/compile_and_package.sh cartken_6_2 --localversion cartken6.2 --dtb-name tegra234-p3737-0000+p3701-0000.dtb "$@"
