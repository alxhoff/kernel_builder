# Tracing Scripts

## Overview
This set of scripts enables streamlined kernel tracing on a target device using `ftrace` and `trace-cmd`. Each script handles a specific step of the tracing workflow, making it modular and customizable.

## Scripts

1. **prepare_tracing.sh**: Clears logs and resets tracing configurations.
2. **set_filter.sh**: Sets filters for modules or functions.
3. **manage_tracers.sh**: Lists or enables tracers (e.g., `function_graph`).
4. **tracepoints.sh**: Manages tracepoints (enable, disable, list).
5. **control_tracing.sh**: Controls tracing (start, stop, duration-based).
6. **retrieve_logs.sh**: Fetches and processes logs from the target.
7. **trace_workflow.sh**: Combines all scripts into a complete tracing workflow.

## Usage
Run the `trace_workflow.sh` script for an end-to-end tracing workflow:

```bash
./trace_workflow.sh 15 stack_tracer_dump 
```

