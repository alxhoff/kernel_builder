# device/

On-target inspection and stressing helpers, grouped by concern.

- `logs/` — pull and clear kernel / boot / pstore logs
  (`retrieve_logs.sh`, `retrieve_boot_logs.sh`, `retrieve_pstore_logs.sh`,
  `clear_*_logs_on_device.sh`, `setup_dumping.sh`).
- `serial/` — serial console helpers.
- `load/` — synthetic load for stability testing
  (`generate_load_stressng.sh`, `generate_load_const.sh`,
  `docker_stability_test.sh`).
- `storage/` — Jetson SSD / LVM migration helpers
  (`migrate_ssd_to_lvm.sh`, `reset_ssd_for_migration_test.sh`).
- `system_info/` — kernel module inventory and default-kernel selection
  (`list_kernel_modules.sh`, `set_default_kernel_jetson.sh`).
- `dynamic_debug/` — dynamic debug / trace control
  (`manage_dynamic_debug.sh`, `retrieve_trace.sh`).
