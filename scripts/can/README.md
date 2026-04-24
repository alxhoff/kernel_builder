# can/

CAN bus tooling.

- `tcan/` — TCAN trace capture (`tcan_trace.sh`, `trace_timing.sh`),
  interactive control (`can_tool.py`), and radar-cycle log analysis
  (`analyze_can_log.py`, supports single or dual interfaces via
  `--interfaces`).
- `slcanfd/` — SLCAN-FD helpers (`send_config.py`, `send_data.py`).
- `spammer/` — `can_spammer.sh` for synthetic bus load generation.
