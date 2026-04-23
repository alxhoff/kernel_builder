# config/

Per-developer defaults for the target device.

- `device_ip.template` — copy to `device_ip` (gitignored) to set the default
  target IP used by most scripts.
- `device_username.template` — copy to `device_username` (gitignored) for the
  default SSH user.

Most `scripts/**/*.sh` helpers check for these files and fall back to
command-line `--ip` / `--user` flags if they're missing.
