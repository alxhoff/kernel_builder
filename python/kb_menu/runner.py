"""Run subprocess in a modal with live log + tee to .kb-menu.last.log."""

from __future__ import annotations

import asyncio
import os
import signal
from pathlib import Path

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, ScrollableContainer
from textual.screen import ModalScreen
from textual.widgets import Button, RichLog

from kb_menu.config import mask_token


def format_argv_masked(argv: list[str]) -> str:
    parts: list[str] = []
    skip_next = False
    for i, a in enumerate(argv):
        if skip_next:
            parts.append(mask_token(a))
            skip_next = False
            continue
        if a == "--access-token" and i + 1 < len(argv):
            parts.append(a)
            skip_next = True
            continue
        if a == "--password" and i + 1 < len(argv):
            parts.append(a)
            skip_next = True
            continue
        parts.append(a)
    return " ".join(parts)


class RunModal(ModalScreen[int]):
    """Run argv; dismiss returns exit code when user closes."""

    BINDINGS = [
        Binding("ctrl+c", "stop_build", "Stop build", show=True),
    ]

    def __init__(self, argv: list[str], cwd: Path, log_path: Path) -> None:
        super().__init__()
        self.argv = argv
        self.cwd = cwd
        self.log_path = log_path
        self._proc: asyncio.subprocess.Process | None = None
        self._user_stopped = False

    def compose(self) -> ComposeResult:
        with ScrollableContainer():
            yield RichLog(id="log", highlight=False, markup=False)
        with ScrollableContainer():
            with Horizontal(classes="buttons"):
                yield Button("Stop build", variant="warning", id="stop")
                yield Button("Close", variant="primary", id="close", disabled=True)

    def on_mount(self) -> None:
        asyncio.create_task(self._run())

    async def action_stop_build(self) -> None:
        await self._request_stop()

    async def _request_stop(self) -> None:
        proc = self._proc
        if proc is None or proc.returncode is not None or self._user_stopped:
            return
        self._user_stopped = True
        log = self.query_one("#log", RichLog)
        log.write("\n[kb-menu: stopping build - SIGTERM to process group]\n")
        try:
            with self.log_path.open("a", encoding="utf-8", errors="replace") as f:
                f.write("\n[kb-menu: stopping build - SIGTERM to process group]\n")
        except OSError:
            pass
        try:
            if os.name == "nt":
                proc.terminate()
            else:
                os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.query_one("#stop", Button).disabled = True
        except Exception:
            pass

    async def _run(self) -> None:
        log = self.query_one("#log", RichLog)
        log.write(
            'Stop mid-build: use "Stop build" below or Ctrl+C '
            "(SIGTERM to the process group, including make/gcc).\n\n"
        )
        header = f"==> {format_argv_masked(self.argv)}\n(full log: {self.log_path})\n\n"
        log.write(header)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        rc = -1
        try:
            tip = (
                'Stop mid-build: "Stop build" or Ctrl+C '
                "(SIGTERM to the process group).\n\n"
            )
            with self.log_path.open("w", encoding="utf-8", errors="replace") as f:
                f.write(tip)
                f.write(header)
                # New session = new process group so SIGTERM kills make/gcc children too (POSIX).
                proc = await asyncio.create_subprocess_exec(
                    *self.argv,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                    cwd=str(self.cwd),
                    start_new_session=os.name != "nt",
                )
                self._proc = proc
                assert proc.stdout
                while True:
                    chunk = await proc.stdout.read(4096)
                    if not chunk:
                        break
                    text = chunk.decode(errors="replace")
                    log.write(text)
                    f.write(text)
                rc = await proc.wait()
        except OSError as e:
            log.write(f"\n[error] {e}\n")
            rc = 127
        finally:
            self._proc = None
        if self._user_stopped:
            tail = f"\n\n==> exit code: {rc} (stopped by user)\n"
        else:
            tail = f"\n\n==> exit code: {rc}\n"
        log.write(tail)
        try:
            with self.log_path.open("a", encoding="utf-8", errors="replace") as f:
                f.write(tail)
        except OSError:
            pass
        self.query_one("#stop", Button).disabled = True
        self.query_one("#close", Button).disabled = False
        self.query_one("#close", Button).focus()
        self._rc = rc  # type: ignore[attr-defined]

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "close":
            self.dismiss(getattr(self, "_rc", -1))
        elif event.button.id == "stop":
            asyncio.create_task(self._request_stop())
