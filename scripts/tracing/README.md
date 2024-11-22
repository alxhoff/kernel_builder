# Jetson Device Tracing Workflow Scripts - Complete Updated Version

This repository contains an improved set of scripts designed to streamline the process of tracing kernel and user-space functionalities on NVIDIA Jetson devices. These scripts help in installing required tools, listing available tracepoints, recording traces, generating reports, and managing the complete tracing workflow. The updated version includes consolidated scripts, better tracepoint management utilities, and a comprehensive workflow automation.

---

## Overview of Scripts

### 1. `install_trace_cmd.sh`
#### Purpose:
Installs the `trace-cmd` utility, which is essential for capturing and managing kernel trace data.

#### Example Usage:
```bash
./install_trace_cmd.sh
```

---

### 2. `list_tracepoints.sh`
#### Purpose:
Lists all available tracepoints in the kernel, which can be used for more targeted tracing.

#### Example Usage:
```bash
./list_tracepoints.sh
```

---

### 3. `trace.sh`
#### Purpose:
Consolidates the functionality of recording traces and starting real-time tracing. This script can either record trace data to a file or start a tracing session for real-time observation without saving the trace.

#### Usage:
```bash
./trace.sh [--record <duration_in_seconds> | --start <duration_in_seconds>]
```

#### Options:
- **`--record <duration>`**: Records a trace of kernel events for the specified duration and saves it to a file named `trace.dat`.
  - Example:
    ```bash
    ./trace.sh --record 10  # Record trace data for 10 seconds and save to trace.dat
    ```

- **`--start <duration>`**: Starts tracing kernel events for the specified duration without saving the trace data. This is useful for real-time monitoring.
  - Example:
    ```bash
    ./trace.sh --start 10  # Start tracing for 10 seconds without saving
    ```

#### Key Differences:
- **`--record`** captures trace data into a file for further analysis.
- **`--start`** initiates tracing without saving data, suitable for quick diagnostics.

---

### 4. `report_trace.sh`
#### Purpose:
Generates a detailed report from the recorded trace data.

#### Example Usage:
```bash
./report_trace.sh trace.dat
```

---

### 5. `select_tracepoints.sh`
#### Purpose:
Facilitates the selection of specific tracepoints for targeted tracing.

#### Usage:
```bash
./select_tracepoints.sh [--list | --enable <tracepoint> | --disable <tracepoint>]
```

#### Options:
- **`--list`**: Lists all available tracepoints in the kernel.
  - Example:
    ```bash
    ./select_tracepoints.sh --list
    ```

- **`--enable <tracepoint>`**: Enables tracing for the specified tracepoint.
  - Example:
    ```bash
    ./select_tracepoints.sh --enable sched:sched_switch
    ```

- **`--disable <tracepoint>`**: Disables tracing for the specified tracepoint.
  - Example:
    ```bash
    ./select_tracepoints.sh --disable sched:sched_switch
    ```

---

### 6. `trace_entire_system.sh`
#### Purpose:
Starts a system-wide trace of kernel events, useful for monitoring overall system activity.

#### Example Usage:
```bash
./trace_entire_system.sh 10
```

---

### 7. `stop_tracing.sh`
#### Purpose:
Stops the current tracing session.

#### Example Usage:
```bash
./stop_tracing.sh
```

---

### 8. `trace_workflow.sh`
#### Purpose:
Automates the full tracing workflow, which includes starting the trace, recording data, stopping, and generating a report.

#### Example Usage:
```bash
./trace_workflow.sh 20  # Automate the tracing workflow for 20 seconds
```

---

## Common Kernel Components for Tracing

When interacting with the kernel for tracing purposes, several key components exposed through the `tracefs` filesystem are utilized:

### 1. `tracefs`
- **Path**: `/sys/kernel/debug/tracing`
- **Description**: This pseudo-filesystem provides an interface to configure tracing settings and read trace logs.

### 2. `current_tracer`
- **Path**: `/sys/kernel/debug/tracing/current_tracer`
- **Purpose**: Sets the active tracer type, such as `function`, `function_graph`, or `nop`.

### 3. `set_ftrace_filter`
- **Path**: `/sys/kernel/debug/tracing/set_ftrace_filter`
- **Purpose**: Allows specifying which functions to trace, enabling more focused data collection.

### 4. `tracing_on`
- **Path**: `/sys/kernel/debug/tracing/tracing_on`
- **Purpose**: Controls whether tracing is currently active or not.

### 5. `trace`
- **Path**: `/sys/kernel/debug/tracing/trace`
- **Description**: Contains the raw trace logs. Reading this file retrieves the recorded trace data.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/trace
  ```

### 6. `trace_pipe`
- **Path**: `/sys/kernel/debug/tracing/trace_pipe`
- **Description**: Provides live tracing output. Unlike `trace`, it streams logs as they are generated, which is useful for real-time monitoring.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/trace_pipe
  ```

### 7. `available_tracers`
- **Path**: `/sys/kernel/debug/tracing/available_tracers`
- **Description**: Lists all tracers supported by the kernel.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/available_tracers
  ```

### 8. `available_filter_functions`
- **Path**: `/sys/kernel/debug/tracing/available_filter_functions`
- **Description**: Lists all functions that can be traced. Useful for identifying functions to include in the `set_ftrace_filter`.
- **Usage**:
  ```bash
  cat /sys/kernel/debug/tracing/available_filter_functions
  ```

---

## Notes
- Ensure your Jetson device has the necessary kernel configurations enabled for tracing (`CONFIG_FTRACE` and related options).
- Always run these scripts with appropriate privileges (e.g., as root) to interact with kernel tracing interfaces.
- Use the `--help` flag with any script to see detailed usage instructions.



