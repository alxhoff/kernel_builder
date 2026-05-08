import sys
from pathlib import Path

try:
    import textual  # noqa: F401
except ImportError:
    _repo = Path(__file__).resolve().parents[2]
    print(
        "kb-menu: the Textual UI needs the 'textual' package.\n"
        f"  python3 -m pip install -r {_repo / 'python' / 'requirements-ui.txt'}\n"
        "After `make install`, run that against the same Python you use for ~/.local/bin/kb-menu,\n"
        "or create a venv in the repo (see scripts/menu/README.md).",
        file=sys.stderr,
    )
    raise SystemExit(1) from None

from kb_menu.app import main

main()
