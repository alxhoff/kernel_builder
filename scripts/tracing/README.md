# tracing/

Ftrace / trace-cmd / function-graph helpers that run against a remote device.

- `prepare_tracing.sh`, `control_tracing.sh`, `manage_tracers.sh`,
  `set_filter.sh`, `tracepoints.sh`, `retrieve_trace_logs.sh` — generic
  tracing primitives.
- `function_graph/` — function-graph tracing workflows plus pre-built
  `targets/` (per-module/per-subsystem trace setups).
- `rtcpu/` — NVIDIA RTCPU tracing helpers.
- `targets/` — top-level trace recipes (e.g. `stack_tracer_dump.sh`).

Device IP / user default to `scripts/config/device_ip` and
`scripts/config/device_username`.
