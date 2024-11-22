
# Jetson Device Tracing Workflow Scripts

This repository contains an improved set of scripts designed to streamline the process of tracing kernel and user-space functionalities on NVIDIA Jetson devices. These scripts help in installing required tools, listing available tracepoints, recording traces, generating reports, and managing the complete tracing workflow.

---

## Overview of Scripts

### 1. `install_trace_cmd.sh`
#### Purpose:
Installs the `trace-cmd` utility, which is essential for capturing and managing kernel trace data.

#### Example Usage:
```bash
./install_trace_cmd.sh
```

### 2. `list_tracepoints.sh`
#### Purpose:
Lists all available tracepoints in the kernel, which can be used for more targeted tracing.

#### Example Usage:
```bash
./list_tracepoints.sh
```

### 3. `record_trace.sh`
#### Purpose:
Records a trace of kernel events for a specified duration. The trace is saved for further analysis.

#### Example Usage:
```bash
./record_trace.sh 10  # Record for 10 seconds
```

### 4. `report_trace.sh`
#### Purpose:
Generates a detailed report from the recorded trace data.

#### Example Usage:
```bash
./report_trace.sh trace.dat
```

### 5. `start_tracing.sh`
#### Purpose:
Starts tracing kernel events for a specified duration.

#### Example Usage:
```bash
./start_tracing.sh 10  # Start tracing for 10 seconds
```

### 6. `start_tracing_system.sh`
#### Purpose:
Starts a system-wide trace of kernel events, useful for monitoring overall system activity.

#### Example Usage:
```bash
./start_tracing_system.sh 10
```

### 7. `stop_tracing.sh`
#### Purpose:
Stops the current tracing session.

#### Example Usage:
```bash
./stop_tracing.sh
```

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

---

## Notes
- Ensure your Jetson device has the necessary kernel configurations enabled for tracing (`CONFIG_FTRACE` and related options).
- Always run these scripts with appropriate privileges (e.g., as root) to interact with kernel tracing interfaces.
- Use the `--help` flag with any script to see usage instructions.

