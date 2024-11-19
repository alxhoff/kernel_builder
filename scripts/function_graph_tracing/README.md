
# Function Graph Tracing Scripts for Jetson Devices

This directory contains a collection of scripts designed to simplify function graph tracing for debugging and profiling device drivers on NVIDIA Jetson devices. Function graph tracing is a powerful Linux kernel feature that enables detailed tracking of function calls and their execution flow, helping developers understand and debug kernel behavior.

---

## Overview of Function Graph Tracing

### What is Function Graph Tracing?
Function graph tracing is a feature of the Linux kernel’s `ftrace` framework. It records:
- **Function Entry Points**: When a function is called.
- **Function Exit Points**: When a function returns.
- **Execution Times**: How long the function took to execute.

### How Does It Work?
1. The kernel must be compiled with **`CONFIG_FTRACE`** and **`CONFIG_FUNCTION_GRAPH_TRACER`** enabled.
2. The `tracefs` filesystem exposes tracing configuration and logs under `/sys/kernel/debug/tracing`.
3. Function graph tracing relies on dynamically instrumenting the kernel to log function call paths, leveraging hooks to capture function entry/exit.

### Components It Relies Upon:
- **`ftrace`**: The main framework for function tracing.
- **`tracefs`**: A pseudo-filesystem for managing and accessing trace configurations/logs.
- **Kernel Config Options**: Ensure the kernel supports the required tracing features.

---

## Available Scripts

### 1. `setup_function_graph_tracing.sh`
#### Description:
A multi-purpose script for setting up and managing function graph tracing. It supports actions like starting/stopping tracing, managing filters, and listing/filtering specific functions.

#### Features:
- Start/stop tracing.
- Add/remove/list/clear function filters.
- Enable tracing for a specific duration.
- Enable/disable tracing during boot.

#### Usage:
```bash
./setup_function_graph_tracing.sh <device-ip> [options]
```

#### Options:
- `--start-trace`: Start function graph tracing.
- `--stop-trace`: Stop tracing and fetch logs.
- `--add-filter <function>`: Add a function to the trace filter.
- `--remove-filter <function>`: Remove a function from the trace filter.
- `--list-filters`: List active filters.
- `--clear-filters`: Clear all filters.
- `--duration <seconds>`: Trace for a specific duration.
- `--enable-boot-trace`: Enable tracing during boot.
- `--disable-boot-trace`: Disable tracing during boot.

---

### 2. `manage_boot_trace.sh`
#### Description:
Manages boot-time tracing by modifying kernel boot parameters.

#### Features:
- Enable or disable function graph tracing during boot.

#### Usage:
```bash
./manage_boot_trace.sh <device-ip> --enable | --disable
```

#### Examples:
1. Enable tracing during boot:
   ```bash
   ./manage_boot_trace.sh 192.168.1.100 --enable
   ```
2. Disable tracing during boot:
   ```bash
   ./manage_boot_trace.sh 192.168.1.100 --disable
   ```

---

### 3. `trace_all_functions.sh`
#### Description:
Traces **all functions** in a specified kernel module.

#### Features:
- Adds all functions from a module to the trace filter.
- Allows tracing for a specific duration or until manually stopped.

#### Usage:
```bash
./trace_all_functions.sh [<device-ip>] <module-name> [--duration <seconds>]
```

#### Examples:
1. Trace all functions in `my_module` for 15 seconds:
   ```bash
   ./trace_all_functions.sh 192.168.1.100 my_module --duration 15
   ```
2. Trace all functions in `usb_driver` until manually stopped:
   ```bash
   ./trace_all_functions.sh usb_driver
   ```

---

### 4. `trace_single_function.sh`
#### Description:
Traces a **specific function** within a kernel module.

#### Features:
- Adds a specific function to the trace filter.
- Allows tracing for a specific duration or until manually stopped.

#### Usage:
```bash
./trace_single_function.sh [<device-ip>] <module-name> <function-name> [--duration <seconds>]
```

#### Examples:
1. Trace `my_function` in `my_module` for 10 seconds:
   ```bash
   ./trace_single_function.sh 192.168.1.100 my_module my_function --duration 10
   ```
2. Trace `probe` in `usb_driver` until manually stopped:
   ```bash
   ./trace_single_function.sh usb_driver probe
   ```

---

### 5. `trace_gpio.sh`
#### Description:
Interactive workflow script for tracing GPIO operations.

#### Features:
- Adds GPIO-related functions to the trace filter.
- Automates GPIO pin export, direction setting, and value toggling.
- Saves detailed trace logs.

#### Usage:
```bash
./trace_gpio.sh [<device-ip>] [<gpio-pin>]
```

#### Examples:
1. Trace GPIO operations on GPIO pin 507 (default):
   ```bash
   ./trace_gpio.sh
   ```
2. Trace GPIO operations on GPIO pin 200:
   ```bash
   ./trace_gpio.sh 192.168.1.100 200
   ```

---

