# kernel_builder — installer for the bin/ aliases and shell completions
#
# Usage:
#   make install              # install copies into $(PREFIX) (default ~/.local)
#   make install PREFIX=/usr  # system-wide install (requires sudo)
#   make uninstall            # remove what was installed
#   make help                 # this message
#
# `make install` writes standalone copies of the bin/ wrapper scripts with
# REPO_ROOT baked in — that way they keep working even when launched from
# $PREFIX/bin and the repo never has to be on the user's PATH.

PREFIX  ?= $(HOME)/.local
DESTDIR ?=

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BINDIR  := $(DESTDIR)$(PREFIX)/bin
FISHDIR := $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d

BIN_SOURCES := $(filter-out bin/README.md,$(wildcard bin/*))
BIN_NAMES   := $(notdir $(BIN_SOURCES))

.PHONY: install uninstall help list

help:
	@echo "kernel_builder install targets:"
	@echo "  install    Install bin/* + completions into PREFIX (default $(HOME)/.local)"
	@echo "  uninstall  Remove anything install would have placed under PREFIX"
	@echo "  list       Show the files install will write"
	@echo "  help       This message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX     Install root           (current: $(PREFIX))"
	@echo "  DESTDIR    Staging dir for pkgs   (current: $(DESTDIR))"
	@echo "  REPO_ROOT  Baked into bin scripts (current: $(REPO_ROOT))"

list:
	@echo "Will install (PREFIX=$(PREFIX)):"
	@for n in $(BIN_NAMES); do echo "  $(BINDIR)/$$n"; done
	@echo "  $(FISHDIR)/kb.fish"

install:
	@mkdir -p "$(BINDIR)" "$(FISHDIR)"
	@for f in $(BIN_SOURCES); do \
	    name=$$(basename $$f); \
	    sed 's|^REPO_ROOT=.*|REPO_ROOT="$(REPO_ROOT)"|' "$$f" > "$(BINDIR)/$$name"; \
	    chmod 0755 "$(BINDIR)/$$name"; \
	    echo "  install $(BINDIR)/$$name"; \
	done
	@cp completions/kb.fish "$(FISHDIR)/kb.fish"
	@chmod 0644 "$(FISHDIR)/kb.fish"
	@echo "  install $(FISHDIR)/kb.fish"
	@echo ""
	@echo "Done. Make sure $(PREFIX)/bin is on your PATH."

uninstall:
	@for n in $(BIN_NAMES); do \
	    if [ -e "$(BINDIR)/$$n" ]; then \
	        rm -f "$(BINDIR)/$$n" && echo "  remove  $(BINDIR)/$$n"; \
	    fi; \
	done
	@if [ -e "$(FISHDIR)/kb.fish" ]; then \
	    rm -f "$(FISHDIR)/kb.fish" && echo "  remove  $(FISHDIR)/kb.fish"; \
	fi
	@rmdir "$(FISHDIR)" 2>/dev/null || true
