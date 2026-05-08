"""Modal dialogs — confirm, input, select, radiolist, checklist, info."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, ScrollableContainer, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Checkbox, Input, Label, OptionList, Static
from textual.widgets.option_list import Option


class InfoModal(ModalScreen[None]):
    BINDINGS = [Binding("escape", "close", "Close", show=True)]

    def __init__(self, text: str) -> None:
        super().__init__()
        self.text = text

    def compose(self) -> ComposeResult:
        with Vertical(classes="kb-dialog"):
            yield Label(f"[b]Notice[/b]")
            yield Static(
                "Enter or Esc closes.",
                classes="dialog-hint",
                markup=False,
            )
            with ScrollableContainer(classes="info-scroll"):
                yield Static(self.text, shrink=True, expand=False, markup=False)
            yield Button("OK", variant="primary", id="ok")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "ok":
            self.dismiss()

    def action_close(self) -> None:
        self.dismiss()


class ConfirmModal(ModalScreen[bool]):
    BINDINGS = [Binding("escape", "back", "Back", show=True)]

    def __init__(self, title: str, body: str) -> None:
        super().__init__()
        self.title = title
        self.body = body

    def compose(self) -> ComposeResult:
        with Vertical(classes="kb-dialog"):
            yield Label(f"[b]{self.title}[/b]")
            yield Static(
                "Tab moves between Run / Back. Enter activates the focused button.",
                classes="dialog-hint",
                markup=False,
            )
            with ScrollableContainer(classes="confirm-body"):
                yield Static(self.body, shrink=True, expand=False, markup=True)
            with Horizontal(classes="buttons"):
                yield Button("Run", variant="success", id="yes")
                yield Button("Back", variant="default", id="no")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "yes":
            self.dismiss(True)
        else:
            self.dismiss(False)

    def action_back(self) -> None:
        self.dismiss(False)


class InputModal(ModalScreen[str | None]):
    BINDINGS = [Binding("escape", "cancel", "Cancel", show=True)]

    def __init__(self, label: str, default: str = "", password: bool = False) -> None:
        super().__init__()
        self.label = label
        self.default = default
        self.password = password

    def compose(self) -> ComposeResult:
        with Vertical(classes="kb-dialog"):
            yield Label(self.label)
            yield Static(
                "Enter submits · Tab reaches OK / Cancel · Esc cancels.",
                classes="dialog-hint",
                markup=False,
            )
            inp = Input(value=self.default, password=self.password)
            inp.id = "field"
            yield inp
            with Horizontal(classes="buttons"):
                yield Button("OK", variant="primary", id="ok")
                yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self.query_one("#field", Input).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "ok":
            self.dismiss(self.query_one("#field", Input).value)
        else:
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)

    def action_cancel(self) -> None:
        self.dismiss(None)


class SelectModal(ModalScreen[str | None]):
    """Single choice; options are (key, description). Enter on a row confirms."""

    BINDINGS = [Binding("escape", "cancel", "Cancel", show=True)]

    def __init__(self, title: str, choices: list[tuple[str, str]], default_key: str | None) -> None:
        super().__init__()
        self.title = title
        self.choices = choices
        self._default_key: str | None = default_key
        dv = default_key
        if dv is None or not any(k == dv for k, _ in self.choices):
            dv = self.choices[0][0] if self.choices else None
        self._resolved_default = dv

    def compose(self) -> ComposeResult:
        with Vertical(classes="kb-dialog"):
            yield Label(f"[b]{self.title}[/b]")
            yield Static(
                "↑↓ choose · Enter confirms this row (more steps may follow) · Esc cancels.",
                classes="dialog-hint",
                markup=False,
            )
            ol = OptionList(id="choices")
            for key, desc in self.choices:
                ol.add_option(Option(f"{desc}  [{key}]", id=key))
            yield ol
            with Horizontal(classes="buttons"):
                yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        ol = self.query_one("#choices", OptionList)
        if self._resolved_default is not None and self.choices:
            try:
                idx = next(i for i, (k, _) in enumerate(self.choices) if k == self._resolved_default)
                ol.highlighted = idx
            except StopIteration:
                ol.highlighted = 0
        elif self.choices:
            ol.highlighted = 0
        ol.focus()

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        opt = event.option
        if opt and opt.id is not None:
            self.dismiss(str(opt.id))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class RadiolistModal(ModalScreen[str | None]):
    """Plain list of keys; Enter on a row confirms (same interaction as the main menu)."""

    BINDINGS = [Binding("escape", "cancel", "Cancel", show=True)]

    def __init__(self, title: str, keys: list[str], default_key: str) -> None:
        super().__init__()
        self.title = title
        self.keys = keys
        self.default_key = default_key if default_key in keys else (keys[0] if keys else "")

    def compose(self) -> ComposeResult:
        with Vertical(classes="kb-dialog"):
            yield Label(f"[b]{self.title}[/b]")
            yield Static(
                "↑↓ choose · Enter confirms (wizard continues with more questions) · Esc cancels.",
                classes="dialog-hint",
                markup=False,
            )
            ol = OptionList(id="choices")
            for k in self.keys:
                ol.add_option(Option(k, id=k))
            yield ol
            with Horizontal(classes="buttons"):
                yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        ol = self.query_one("#choices", OptionList)
        if self.keys:
            try:
                ol.highlighted = self.keys.index(self.default_key)
            except ValueError:
                ol.highlighted = 0
        ol.focus()

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        opt = event.option
        if opt and opt.id is not None:
            self.dismiss(str(opt.id))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class ChecklistModal(ModalScreen[list[str] | None]):
    """Returns list of keys where checkbox is on."""

    BINDINGS = [Binding("escape", "cancel", "Cancel", show=True)]

    def __init__(self, title: str, items: list[tuple[str, str, bool]]) -> None:
        super().__init__()
        self.title = title
        self.items = items

    def compose(self) -> ComposeResult:
        with Vertical(classes="kb-dialog"):
            yield Label(f"[b]{self.title}[/b]")
            yield Static(
                "Space toggles the focused row · Tab to OK / Cancel · Esc cancels.",
                classes="dialog-hint",
                markup=False,
            )
            with Vertical(id="checks"):
                for i, (_key, desc, on) in enumerate(self.items):
                    yield Checkbox(desc, value=on, id=f"cb_{i}")
            with Horizontal(classes="buttons"):
                yield Button("OK", variant="primary", id="ok")
                yield Button("Cancel", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
            return
        out: list[str] = []
        for i in range(len(self.items)):
            cb = self.query_one(f"#cb_{i}", Checkbox)
            if cb.value:
                out.append(self.items[i][0])
        self.dismiss(out)

    def action_cancel(self) -> None:
        self.dismiss(None)
