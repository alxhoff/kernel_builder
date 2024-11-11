# README for Kernel Debugging and Tracing Scripts

## Overview
This collection of scripts is aimed at managing and debugging kernels, especially on Jetson devices, using tools like `trace-cmd`. The scripts automate the installation, tracing, log collection, and analysis procedures for kernel modules. This README provides details on each script and usage examples.

### Introduction to `trace-cmd`
`trace-cmd` is a command-line utility used to interact with Linux's ftrace framework, which enables users to trace kernel events. It helps gather information on how kernel functions are being executed, aiding developers in debugging driver code, monitoring kernel performance, and identifying system bottlenecks.

Ftrace supports various types of tracers like function tracers, scheduling events, and more. With `trace-cmd`, users can easily capture and report on these events.

## Script Descriptions

### 1. `install_trace_cmd.sh`
- **Function**: Installs `trace-cmd` on a target Jetson device.
- **Execution**: This script will SSH into the target device as root and install `trace-cmd` using the package manager (`apt-get`). It’s useful for ensuring that the tracing utility is available.
- **Command**: `./install_trace_cmd.sh <device-ip>`
- **Details**: The script uses SSH to run `apt-get install trace-cmd` on the remote Jetson device. This allows the ftrace tracing tool to be available for subsequent kernel debugging activities.

### 2. `list_kernel_modules.sh`
- **Function**: Lists all loaded kernel modules on the target device.
- **Execution**: It connects to the device via SSH and runs `lsmod`, which prints out a list of currently loaded kernel modules.
- **Command**: `./list_kernel_modules.sh [<device-ip>]`
- **Details**: This script will be used to verify which kernel modules are currently loaded. It can be particularly useful before tracing to ensure that the targeted driver is loaded properly.

### 3. `list_tracepoints.sh`
- **Function**: Lists available tracepoints on the target device.
- **Execution**: Runs `trace-cmd list` on the target device, showing all available tracepoints that can be traced using ftrace.
- **Command**: `./list_tracepoints.sh [<device-ip>]`
- **Details**: Tracepoints are static points within the Linux kernel where event information can be collected. This script helps identify what tracepoints are available on the system, such as function entries, exit points, or critical events.

### 4. `record_trace.sh`
- **Function**: Records a set of tracepoints on the target device.
- **Execution**: The script will start tracing specified events using `trace-cmd record`. The trace data will be saved on the remote Jetson device.
- **Command**: `./record_trace.sh --trace-options "<trace-options>" --duration <duration>`
- **Details**: This script is used to record trace data for specific events. The command `trace-cmd record` collects trace data for the provided trace events or system subsystems. Options passed to the script allow specific events, such as `sched:*` for all scheduler events, to be targeted. Example: `./record_trace.sh --trace-options "-e net:*" --duration 10` will record all network events for 10 seconds.

### 5. `retrieve_trace.sh`
- **Function**: Retrieves the recorded trace data (`trace.dat`) from the target device.
- **Execution**: The script uses `scp` to copy the `trace.dat` file from the target device to the host.
- **Command**: `./retrieve_trace.sh [<device-ip>] [<destination-path>]`
- **Details**: The `trace.dat` file is the output of the `trace-cmd record` command and contains all the tracing information. This script helps in getting the data from the remote Jetson device for further analysis.

### 6. `report_trace.sh`
- **Function**: Generates a readable report from the collected trace data on the host.
- **Execution**: It runs `trace-cmd report` on the `trace.dat` file to generate a human-readable text report.
- **Command**: `./report_trace.sh [<trace-file-path>] [<output-file>]`
- **Details**: `trace-cmd report` processes the binary trace file (`trace.dat`) and outputs the details of the trace in a readable format. This report can include details about function calls, timestamps, and event-specific information, which is crucial for diagnosing kernel behavior.

### 7. `start_tracing.sh`
- **Function**: Starts kernel tracing by enabling specific events in ftrace.
- **Execution**: Uses `echo` to add events to `/sys/kernel/debug/tracing/set_event` and start tracing with `/sys/kernel/debug/tracing/tracing_on`.
- **Command**: `./start_tracing.sh --events "<trace-events>"`
- **Details**: This script sets up the tracing infrastructure by enabling the specified tracepoints. The `echo` command is used to add the desired events to the tracing file, allowing the kernel to trace those events specifically.

### 8. `start_tracing_system.sh`
- **Function**: Starts tracing all events for a particular subsystem.
- **Execution**: This script sets up ftrace to start tracing all events of a given system, like `net`, `sched`, etc.
- **Command**: `./start_tracing_system.sh --system net`
- **Details**: Tracing a complete subsystem is very helpful when trying to understand system-wide behaviors, interactions between different components, or when diagnosing issues like latencies.

### 9. `stop_tracing.sh`
- **Function**: Stops kernel tracing on the target device.
- **Execution**: Uses `/sys/kernel/debug/tracing/tracing_on` to disable tracing.
- **Command**: `./stop_tracing.sh`
- **Details**: Disabling tracing ensures no additional system resources are used and also stops logging. This script simply turns tracing off by writing `0` to `/sys/kernel/debug/tracing/tracing_on`.

### 10. `retrieve_logs.sh`
- **Function**: Retrieves kernel logs (`dmesg`) from the target device.
- **Execution**: Uses `scp` to copy `dmesg` logs from the Jetson to the local machine for debugging.
- **Command**: `./retrieve_logs.sh [<device-ip>] [<destination-path>]`
- **Details**: Kernel logs (`dmesg`) contain a history of kernel messages and are useful in understanding what might be happening at a lower level, especially when combined with trace logs.


## Example Workflow: Using `trace-cmd` to Debug a Kernel Driver
1. **Install `trace-cmd`**: First, make sure `trace-cmd` is installed on the target device.
   ```sh
   ./install_trace_cmd.sh <device-ip>
   ```
2. **List Available Tracepoints**: Check the available tracepoints to decide which ones are most relevant for tracing your driver.
   ```sh
   ./list_tracepoints.sh <device-ip>
   ```
3. **Start Tracing Events**: Start recording the trace data by specifying tracepoints or a system.
   ```sh
   ./record_trace.sh --trace-options "-e driver:* -e irq:*" --duration 10
   ```
   In this example, it records all events in the `driver` and `irq` categories for 10 seconds.
4. **Retrieve Trace Data**: Copy the collected `trace.dat` file to the host for analysis.
   ```sh
   ./retrieve_trace.sh <device-ip> /path/to/destination
   ```
5. **Generate a Report**: Convert the binary trace file into a human-readable format to analyze the collected information.
   ```sh
   ./report_trace.sh /path/to/trace.dat /path/to/output.txt
   ```
6. **Analyze and Debug**: Open the generated report to analyze the traced kernel behavior and look for any unexpected calls or anomalies in your driver’s execution.

## Trace Events Explained
- **Tracepoints**: These are specific hooks within the kernel code where data can be logged for debugging. You can think of them as checkpoints to get information when the system passes through certain critical paths.
- **Example Tracepoints**:
  - `net:*`: Traces all network subsystem events, such as packet transmission or reception.
  - `sched:*`: Tracks scheduling events, useful for analyzing context switches or latency.
  - `irq:*`: Traces interrupt handling, helpful for debugging performance issues related to interrupts.

## Notes on Usage
- **Permissions**: Most `trace-cmd` operations require root permissions as they interact with the kernel.
- **Impact on Performance**: Tracing can significantly impact system performance, especially if a lot of events are traced. It is suggested to minimize the number of events traced in a live production system.

Feel free to tweak the scripts or `trace-cmd` options to suit your debugging needs.


