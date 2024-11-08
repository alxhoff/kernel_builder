# Kernel Builder, Deployer, and Debugger Scripts Guide

This document provides an overview of all the scripts available in the `scripts` directory. Each script is explained in terms of its purpose, usage, and arguments.

## Available Scripts

### 1. `build_kernel_host_cartken_jetson.sh`

- **Purpose**: Builds the kernel for the Jetson target using fixed parameters for kernel name and toolchain.
- **Usage**:
  ```bash
  ./build_kernel_host_cartken_jetson.sh [<build-target>]
  ```
  - `[<build-target>]` Optional build target such as `clean`.

### 2. `build_kernel_host.sh`

- **Purpose**: General-purpose script for building a kernel on the host machine, allowing dynamic selection of the kernel name, toolchain, and build targets.
- **Usage**:
  ```bash
  ./build_kernel_host.sh <kernel-name> <toolchain-name> [<build-target>]
  ```
  - `<kernel-name>` The name of the kernel directory to compile.
  - `<toolchain-name>` The name of the toolchain to use for cross-compiling.
  - `[<build-target>]` Optional target such as `clean`.

### 3. `clean_jetson_kernel.sh`

- **Purpose**: Cleans the kernel build for the Jetson target.
- **Usage**:
  ```bash
  ./clean_jetson_kernel.sh
  ```

### 4. `compile_and_deploy_jetson.sh`

- **Purpose**: Compiles and deploys the kernel to a Jetson device.
- **Usage**:
  ```bash
  ./compile_and_deploy_jetson.sh [--no-deploy]
  ```
  - `--no-deploy` Skips the deployment step.

### 5. `compile_jetson.sh`

- **Purpose**: Compiles the kernel for the Jetson target.
- **Usage**:
  ```bash
  ./compile_jetson.sh
  ```

### 6. `compile_modules_jetson.sh`

- **Purpose**: Compiles kernel modules for the Jetson target.
- **Usage**:
  ```bash
  ./compile_modules_jetson.sh
  ```

### 7. `deploy_only_jetson.sh`

- **Purpose**: Deploys the compiled kernel to a Jetson device.
- **Usage**:
  ```bash
  ./deploy_only_jetson.sh <device-ip>
  ```
  - `<device-ip>` IP address of the target Jetson device.

### 8. `example_workflow_jetson.sh`

- **Purpose**: Example workflow script to compile and flash a Jetson device with a specific kernel.
- **Usage**:
  ```bash
  ./example_workflow_jetson.sh <git-tag> <device-ip>
  ```
  - `<git-tag>` The Git tag to use for kernel compilation.
  - `<device-ip>` IP address of the target Jetson device.

### 9. `install_trace_cmd.sh`

- **Purpose**: Installs `trace-cmd` on the Jetson device as root.
- **Usage**:
  ```bash
  ./install_trace_cmd.sh
  ```
  - Uses the `device_ip` and `device_username` files if available.

### 10. `list_kernel_modules.sh`

- **Purpose**: Lists the kernel modules loaded on the Jetson device.
- **Usage**:
  ```bash
  ./list_kernel_modules.sh
  ```
  - Uses the `device_ip` and `device_username` files if available.

### 11. `list_tracepoints.sh`

- **Purpose**: Lists available tracepoints on the Jetson device via `trace-cmd`.
- **Usage**:
  ```bash
  ./list_tracepoints.sh
  ```
  - Uses the `device_ip` and `device_username` files if available.

### 12. `menuconfig_jetson.sh`

- **Purpose**: Opens the kernel configuration menu for the Jetson target.
- **Usage**:
  ```bash
  ./menuconfig_jetson.sh
  ```

### 13. `mrproper_jetson.sh`

- **Purpose**: Cleans the kernel source tree for the Jetson target.
- **Usage**:
  ```bash
  ./mrproper_jetson.sh
  ```

### 14. `record_trace.sh`

- **Purpose**: Records kernel events on the Jetson device using `trace-cmd`.
- **Usage**:
  ```bash
  ./record_trace.sh <trace-options> [<duration>]
  ```
  - `<trace-options>` Options for the `trace-cmd` record command.
  - `[<duration>]` Duration in seconds for the trace (optional).

### 15. `report_trace.sh`

- **Purpose**: Generates a trace report from a `trace.dat` file on the host machine.
- **Usage**:
  ```bash
  ./report_trace.sh <trace-file-path> <output-file>
  ```
  - `<trace-file-path>` Path to the `trace.dat` file on the host.
  - `<output-file>` File where the trace report will be saved.

### 16. `retrieve_logs.sh`

- **Purpose**: Retrieves kernel logs from the Jetson device.
- **Usage**:
  ```bash
  ./retrieve_logs.sh <destination-path>
  ```
  - `<destination-path>` Local path to save the kernel logs.

### 17. `retrieve_trace.sh`

- **Purpose**: Retrieves trace data (`trace.dat`) from the Jetson device.
- **Usage**:
  ```bash
  ./retrieve_trace.sh <destination-path>
  ```
  - `<destination-path>` Local path to save the trace data.

### 18. `start_tracing.sh`

- **Purpose**: Starts tracing kernel events on the Jetson device.
- **Usage**:
  ```bash
  ./start_tracing.sh <events>
  ```
  - `<events>` Events to trace, e.g., `sched:sched_switch`.

### 19. `stop_tracing.sh`

- **Purpose**: Stops the ongoing tracing on the Jetson device.
- **Usage**:
  ```bash
  ./stop_tracing.sh
  ```

## Device Configuration Files

- **`device_ip`**: If this file is present in the `scripts` directory, it is used to provide the IP address of the target Jetson device for relevant scripts.
- **`device_username`**: If this file is present, it is used to provide the username to access the Jetson device. If not present, the default username `cartken` is used.

These files simplify the use of the scripts by eliminating the need to provide device details repeatedly.

