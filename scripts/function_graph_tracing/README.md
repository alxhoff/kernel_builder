# Jetson Device Tracing Scripts

This repository contains a set of scripts tailored for tracing kernel and user-space functionalities on NVIDIA Jetson devices. These scripts simplify the setup and management of Linux kernel tracing, aiding in debugging, profiling, and understanding system performance.

---

## Overview of Function Graph Tracing

### What is Function Graph Tracing?
Function graph tracing is a feature of the Linux kernel's `ftrace` framework. It provides detailed insights into kernel function calls by tracing their execution, including:
- **Function Entry Points**: When a function is invoked.
- **Function Exit Points**: When a function returns.
- **Execution Time**: The duration between function entry and exit.

This capability helps developers debug kernel behavior, optimize performance, and understand execution flows.

---

### How It Works
1. **Kernel Support**:
   - Function graph tracing requires the Linux kernel to be compiled with `CONFIG_FTRACE` and `CONFIG_FUNCTION_GRAPH_TRACER` enabled.
   - These options enable the kernel to hook into function entry and exit points.

2. **Tracefs Filesystem**:
   - The `tracefs` filesystem, typically mounted at `/sys/kernel/debug/tracing`, exposes kernel tracing controls and logs.
   - Users can manage tracing filters, settings, and captured logs via this interface.

3. **Dynamic Instrumentation**:
   - The kernel uses hooks to log function entry and exit.
   - Execution time is measured by recording timestamps at entry and exit points.

4. **Tracing Filters**:
   - Filters can limit tracing to specific functions, reducing noise and focusing on areas of interest.

---

### Components of Function Graph Tracing
- **`ftrace` Framework**: The core Linux kernel infrastructure for tracing.
- **Tracefs**: A pseudo-filesystem for managing tracing configurations and logs.
- **User-Defined Filters**: Allow selective tracing of specific functions or modules.
- **Trace Logs**: Detailed output of traced function calls, accessible via `tracefs`.

---

## Scripts Overview

### 1. `setup_function_graph_tracing.sh`
#### Purpose:
Manages function graph tracing on the device.

#### Key Features:
- Start/stop tracing.
- Add/remove functions to/from the trace filter.
- View or clear active filters.
- Enable tracing for a specified duration or during boot.

#### Example Usage:
1. Start tracing:
   ```bash
   ./setup_function_graph_tracing.sh <device-ip> --start-trace
   ```
2. Add a filter for a function `do_work`:
   ```bash
   ./setup_function_graph_tracing.sh <device-ip> --add-filter do_work
   ```
3. Trace for 10 seconds:
   ```bash
   ./setup_function_graph_tracing.sh <device-ip> --duration 10
   ```

---

### 2. `manage_boot_trace.sh`
#### Purpose:
Configures tracing during the boot process by adjusting kernel parameters.

#### Key Features:
- Enable/disable boot-time tracing.
- Automatically persists changes across reboots.

#### Example Usage:
1. Enable boot-time tracing:
   ```bash
   ./manage_boot_trace.sh <device-ip> --enable
   ```
2. Disable boot-time tracing:
   ```bash
   ./manage_boot_trace.sh <device-ip> --disable
   ```

---

### 3. `trace_all_functions.sh`
#### Purpose:
Traces all functions in a specific kernel module.

#### Key Features:
- Automates the addition of module functions to the trace filter.
- Captures comprehensive logs for debugging.

#### Example Usage:
1. Trace all functions in `usb_driver` for 15 seconds:
   ```bash
   ./trace_all_functions.sh <device-ip> usb_driver --duration 15
   ```
2. Start tracing functions in `my_module` until stopped:
   ```bash
   ./trace_all_functions.sh <device-ip> my_module
   ```

---

### 4. `trace_single_function.sh`
#### Purpose:
Traces a single function within a module for targeted debugging.

#### Key Features:
- Precision tracing for isolated function behaviors.
- Supports duration-based tracing.

#### Example Usage:
1. Trace `probe` in `usb_driver` for 10 seconds:
   ```bash
   ./trace_single_function.sh <device-ip> usb_driver probe --duration 10
   ```
2. Trace `my_function` in `my_module`:
   ```bash
   ./trace_single_function.sh <device-ip> my_module my_function
   ```

---

### 5. `trace_gpio.sh`
#### Purpose:
Specialized script for tracing GPIO operations.

#### Key Features:
- Predefined GPIO-related function filters.
- Automates GPIO setup and logging.

#### Example Usage:
1. Trace GPIO operations on the default pin (507):
   ```bash
   ./trace_gpio.sh <device-ip>
   ```
2. Trace GPIO pin 200:
   ```bash
   ./trace_gpio.sh <device-ip> 200
   ```

---

### 6. `real_time_monitor.sh`
#### Purpose:
Provides real-time monitoring of kernel events during trace execution.

#### Key Features:
- Outputs logs directly to the console.
- Ideal for interactive debugging.

#### Example Usage:
```bash
./real_time_monitor.sh <device-ip>
```

---

### 7. `analyze_trace_logs.sh`
#### Purpose:
Post-processing tool for parsing and analyzing trace logs.

#### Key Features:
- Filters logs based on function names or patterns.
- Summarizes execution times and call counts.

#### Example Usage:
1. Parse logs for `do_work`:
   ```bash
   ./analyze_trace_logs.sh <device-ip> --filter do_work
   ```
2. Generate a summary of captured data:
   ```bash
   ./analyze_trace_logs.sh <device-ip> --summary
   ```

---

### 8. `kernel_error_detection.sh`
#### Purpose:
Detects and logs kernel errors and warnings during execution.

#### Key Features:
- Filters logs for error-level messages.
- Provides insight into potential system issues.

#### Example Usage:
```bash
./kernel_error_detection.sh <device-ip>
```

---

## Common Kernel Components for Tracing

When working with function graph tracing, several kernel components exposed through the `tracefs` filesystem are essential. These components allow fine-grained control and configuration of tracing. Below is an overview of the most commonly used components:

### 1. `current_tracer`
- **Path**: `/sys/kernel/debug/tracing/current_tracer`
- **Description**: Specifies the active tracer. For function graph tracing, this value should be set to `function_graph`.
- **Usage**:
  ```bash
  echo function_graph > /sys/kernel/debug/tracing/current_tracer
  ```

---

### 2. `set_ftrace_filter`
- **Path**: `/sys/kernel/debug/tracing/set_ftrace_filter`
- **Description**: Defines the list of functions to be traced. Functions not in this list will be ignored.
- **Usage**:
  - Add a function to the filter:
    ```bash
    echo <function-name> > /sys/kernel/debug/tracing/set_ftrace_filter
    ```
  - Add multiple functions:
    ```bash
    echo <function1> <function2> >> /sys/kernel/debug/tracing/set_ftrace_filter
    ```
  - Clear all filters:
    ```bash
    echo > /sys/kernel/debug/tracing/set_ftrace_filter
    ```

---

### 3. `set_ftrace_notrace`
- **Path**: `/sys/kernel/debug/tracing/set_ftrace_notrace`
- **Description**: Specifies functions to exclude from tracing, even if they match a filter.
- **Usage**:
  - Exclude a function:
    ```bash
    echo <function-name> > /sys/kernel/debug/tracing/set_ftrace_notrace
    ```

---

### 4. `tracing_on`
- **Path**: `/sys/kernel/debug/tracing/tracing_on`
- **Description**: Controls whether tracing is enabled or disabled.
- **Usage**:
  - Start tracing:
    ```bash
    echo 1 > /sys/kernel/debug/tracing/tracing_on
    ```
  - Stop tracing:
    ```bash
    echo 0 > /sys/kernel/debug/tracing/tracing_on
    ```

---

### 5. `trace`
- **Path**: `/sys/kernel/debug/tracing/trace`
- **Description**: Contains the raw trace logs. Reading this file retrieves the recorded trace data.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/trace
  ```

---

### 6. `trace_pipe`
- **Path**: `/sys/kernel/debug/tracing/trace_pipe`
- **Description**: Provides live tracing output. Unlike `trace`, it streams logs as they are generated, which is useful for real-time monitoring.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/trace_pipe
  ```

---

### 7. `available_tracers`
- **Path**: `/sys/kernel/debug/tracing/available_tracers`
- **Description**: Lists all tracers supported by the kernel.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/available_tracers
  ```

---

### 8. `available_filter_functions`
- **Path**: `/sys/kernel/debug/tracing/available_filter_functions`
- **Description**: Lists all functions that can be traced. Useful for identifying functions to include in the `set_ftrace_filter`.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/available_filter_functions
  ```

---

### 9. `per_cpu/cpuX/trace`
- **Path**: `/sys/kernel/debug/tracing/per_cpu/cpuX/trace` (replace `X` with the CPU number)
- **Description**: Captures trace logs specific to a particular CPU. Useful for analyzing behavior on a per-CPU basis.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/per_cpu/cpu0/trace
  ```

---

### 10. `events/`
- **Path**: `/sys/kernel/debug/tracing/events/`
- **Description**: Contains configuration files for specific event-based tracing. For example, it allows enabling/disabling tracepoints in subsystems like `sched`, `irq`, or `block`.
- **Usage**:
  - Enable a tracepoint:
    ```bash
    echo 1 > /sys/kernel/debug/tracing/events/sched/sched_switch/enable
    ```
  - Disable a tracepoint:
    ```bash
    echo 0 > /sys/kernel/debug/tracing/events/sched/sched_switch/enable
    ```

---

