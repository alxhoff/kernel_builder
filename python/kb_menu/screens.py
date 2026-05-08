"""menuconfig-style hub: option list + help panel."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Awaitable, Callable

from textual.app import ComposeResult, ScreenStackError
from textual.binding import Binding
from textual.containers import Horizontal, ScrollableContainer
from textual.screen import Screen
from textual.widgets import Footer, Header, OptionList, Static
from textual.widgets.option_list import Option


@dataclass
class MenuEntry:
    key: str
    label: str
    help: str
    action: Callable[[Any], Awaitable[None]]


class MenuHubScreen(Screen[None]):
    """Left: options. Right: help for highlighted row."""

    BINDINGS = [
        Binding("escape", "pop", "Back", show=True),
    ]

    def __init__(self, title: str, subtitle: str, entries: list[MenuEntry]) -> None:
        super().__init__()
        self.menu_title = title
        self.subtitle = subtitle
        self.entries = entries
        self._help_map = {e.key: e.help for e in entries}

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield Static(
            "↑↓ move · Enter open · Esc back · q quit — help for the highlighted row is on the right "
            "(scroll the help panel when text is long).",
            id="nav-hint",
            markup=False,
        )
        with Horizontal(id="menu-row"):
            ol = OptionList(id="menu-list")
            for e in self.entries:
                ol.add_option(Option(e.label, id=e.key))
            yield ol
            help_text = self.entries[0].help if self.entries else ""
            with ScrollableContainer(id="help-scroll"):
                yield Static(
                    help_text,
                    id="help-panel",
                    expand=False,
                    shrink=True,
                    markup=False,
                )
        yield Footer()

    def on_mount(self) -> None:
        self.title = self.menu_title
        self.sub_title = self.subtitle

    def on_option_list_option_highlighted(
        self, event: OptionList.OptionHighlighted
    ) -> None:
        opt = event.option
        if opt and opt.id:
            h = self._help_map.get(str(opt.id), "")
            self.query_one("#help-panel", Static).update(h)

    def on_option_list_option_selected(
        self, event: OptionList.OptionSelected
    ) -> None:
        opt = event.option
        if not opt or not opt.id:
            return
        key = str(opt.id)
        for e in self.entries:
            if e.key == key:
                # push_screen_wait() must run inside a Textual worker (Textual >= 0.80).
                self.app.run_worker(
                    e.action(self.app),
                    name=f"kb-menu:{e.key}",
                    exclusive=True,
                    exit_on_error=False,
                )
                break

    async def action_pop(self) -> None:
        try:
            await self.app.pop_screen()
        except ScreenStackError:
            self.app.exit()
