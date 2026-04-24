# camera/

Camera and V4L2 helpers.

- `v4l2/` — V4L2 probing and control over SSH: `list_cameras.sh`,
  `list_camera_formats.sh`, `list_camera_i2c_info.sh`, `camera_info*.sh`,
  `set_camera_exposure.sh`, `probe_camera_controls.sh`,
  `writable_control_interactive.sh`, and `v4l_trace.sh`.
- `realsense/` — Intel RealSense helpers including `build_librealsense.sh`,
  firmware listing/update (`list_rs_firmware_versions.sh`,
  `update_rs_firmware.sh`), debug toggling (`toggle_d4xx_debug.sh`), and a
  bundled `librealsense_cartken/` vendor checkout plus `firmware/` blobs.
- `streaming/` — quick `stream_cameras*.sh` launchers for RGB / generic
  streams.
