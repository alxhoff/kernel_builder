# ota/

Over-the-air update tooling for fleets of robots.

Includes scripts to build OTA payloads (`create_ota_payload_docker.sh`,
`create_full_ota_update.sh`), set up a rootfs as an OTA-capable robot
(`setup_rootfs_as_robot_for_ota.sh`), and query which robots need an update
(`query_updatable_robots.py`). The `ota_update/` subdirectory holds the
payload assembly helpers.
