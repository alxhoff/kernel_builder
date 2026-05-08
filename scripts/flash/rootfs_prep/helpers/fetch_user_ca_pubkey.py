#!/usr/bin/env python3
"""Fetch the Cartken user-CA public key(s) for a backend environment.

The output is suitable to drop in as `/etc/ssh/cartken_sshd/ssh_user_ca.pub`
on a robot rootfs (one key per line, no markers). The robot's
`cartken-jetson-sshd-v2` reads this file to decide which user certificates
to trust.

This helper piggy-backs on `cartken-dev`'s logged-in user session via
`AuthTokenManager`, so the invoking user must already have run
`cartken account login <env>` for the chosen environment.

Sibling, in spirit, to `roles/common/robot-sshd-config-update/files/
fetch_robot_sshd_ca.py` in the it-management repo, which does the
same fetch from AWX using a Keycloak service-client secret instead.
"""

import argparse
import sys
from pathlib import Path

try:
    from cartken_dev.account.auth import AuthTokenManager, DeviceFlowError
    from cartken_dev.connectivity.robot_ssh_ca_client import (
        CartkenRobotSshCaClient,
        SshCaClientError,
    )
    from cartken_dev.constants import BackendEnvironment
except ImportError as exc:
    print(
        f"Failed to import cartken-dev modules: {exc}\n"
        "Install cartken-dev and run `cartken account login <env>` for the "
        "target environment before running this helper.",
        file=sys.stderr,
    )
    sys.exit(2)


_ENV_BY_NAME = {
    "production": BackendEnvironment.PROD,
    "prod": BackendEnvironment.PROD,
    "staging": BackendEnvironment.STAGING,
    "sandbox": BackendEnvironment.SANDBOX,
    "localhost": BackendEnvironment.LOCALHOST,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--env",
        required=True,
        choices=sorted(_ENV_BY_NAME),
        help="Target backend environment.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Destination file for the user CA public keys (one per line).",
    )
    args = parser.parse_args()
    env = _ENV_BY_NAME[args.env]

    try:
        client = CartkenRobotSshCaClient(env.backend_url, AuthTokenManager(env))
        keys = client.get_public_keys()
    except (DeviceFlowError, SshCaClientError, OSError) as exc:
        print(f"Failed to fetch user CA public keys: {exc}", file=sys.stderr)
        return 1

    user_ca_keys = [k.strip() for k in keys.user_ca_public_keys if k.strip()]
    if not user_ca_keys:
        print(
            f"Backend returned no user CA public keys for env '{args.env}'.",
            file=sys.stderr,
        )
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(user_ca_keys) + "\n")
    print(
        f"Wrote {len(user_ca_keys)} user CA public key(s) to {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
