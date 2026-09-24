#!/usr/bin/env bash
# Builds Menagerie, installs it in ~/Applications and puts a shortcut to it on
# your Desktop. Run it again at any time to update both.
#
#   Scripts/install.sh               # for this Mac's architecture
#   Scripts/install.sh --universal   # Apple silicon + Intel in one binary
#
# Nothing needs administrator rights, and nothing outside ~/Applications and
# ~/Desktop is touched.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="io.github.ligone.Menagerie"
INSTALLED="$HOME/Applications/Menagerie.app"
SHORTCUT="$HOME/Desktop/Menagerie"

step() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }

bundle_id() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true
}

Scripts/build-app.sh "$@"

step "Installing into ~/Applications"
mkdir -p "$(dirname "$INSTALLED")"
if [[ -e "$INSTALLED" ]]; then
    # Only ever replace a previous copy of this app.
    if [[ "$(bundle_id "$INSTALLED")" != "$BUNDLE_ID" ]]; then
        echo "error: $INSTALLED is a different app, so it was left alone." >&2
        exit 1
    fi
    rm -rf "$INSTALLED"
fi
ditto build/Menagerie.app "$INSTALLED"

step "Adding a shortcut to your Desktop"
mkdir -p "$(dirname "$SHORTCUT")"
if [[ -L "$SHORTCUT" || ! -e "$SHORTCUT" ]]; then
    # -n replaces an existing link instead of following it into the bundle.
    ln -sfn "$INSTALLED" "$SHORTCUT"
    step "Done: double-click Menagerie on your Desktop, or search for it in Spotlight."
else
    echo "warning: $SHORTCUT already exists and isn't a shortcut, so it was left alone." >&2
    step "Done: open Menagerie from ~/Applications or Spotlight."
fi
