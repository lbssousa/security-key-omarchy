set shell := ["bash", "-uc"]

plugin_link := env("HOME") / ".config/omarchy/plugins/lbssousa.security-key"

default:
    @just --list

# Every test: the overlay's JS model and catalogs, the helper, QML lint,
# and the shell's own plugin validation.
test: test-js test-py lint validate

test-js:
    node --test tests/js/

# The helper against a fake runner (no key needed).
test-py:
    python3 -I -m unittest discover -s tests/py

# qmllint over the plugin (warnings only: the shell's qs.* modules aren't
# importable outside it) and shellcheck when installed.
lint:
    #!/usr/bin/env bash
    set -uo pipefail
    if command -v shellcheck >/dev/null; then shellcheck bin/*; fi
    /usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml *.qml || true

# What `omarchy plugin add` and the plugin marketplace check: the manifest,
# its entry points, and no symlinks anywhere in the checkout.
validate:
    omarchy-plugin-validate .

# Run the overlay in a separate Quickshell instance, against the real key;
# Escape ends it. `just dev ar` shows it in another language than the shell's.
# The instance's folder is built in a temporary directory: it links the
# shell's Commons and Ui next to the plugin's files, and plugins may not
# carry symlinks.
dev language="":
    #!/usr/bin/env bash
    set -eu
    dir=$(mktemp -d)
    trap 'rm -rf "$dir"' EXIT
    for f in *.qml *.js key-helper i18n; do ln -s "$PWD/$f" "$dir/$f"; done
    ln -s /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$dir/"
    cp dev/shell.qml "$dir/shell.qml"
    if [ -n "{{language}}" ]; then
      export OMARCHY_LANGUAGE_FILE="$dir/language"
      echo "{{language}}" > "$OMARCHY_LANGUAGE_FILE"
    fi
    quickshell -p "$dir"

# Load this checkout's plugin in the real shell, then open it.
link:
    ln -sfn "$PWD" {{plugin_link}}
    omarchy-shell shell rescanPlugins
    omarchy-shell shell enablePlugin lbssousa.security-key '{}'
    omarchy-restart-shell

# Build the Arch package into packaging/.
pkg:
    cd packaging && makepkg -f
