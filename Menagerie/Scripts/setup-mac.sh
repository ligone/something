#!/usr/bin/env bash
# One command to take Menagerie from the cloud to your Mac:
#
#   1. checks for macOS 14+ and Xcode's command-line tools,
#   2. clones this repository (or updates your clone) on the project branch,
#   3. builds and installs the app with a shortcut on your Desktop,
#   4. opens Claude Code in the project so the work can carry on locally.
#
# Run it straight from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/ligone/something/refs/heads/claude/hopeful-babbage-djjew8/Menagerie/Scripts/setup-mac.sh | bash
#
# or from a clone, with Menagerie/Scripts/setup-mac.sh. It is safe to re-run.
#
# Settings, all optional:
#   MENAGERIE_DIR=path     where to clone (default: ~/Developer/something)
#   MENAGERIE_BRANCH=name  branch to use (default: claude/hopeful-babbage-djjew8)
#   MENAGERIE_CLAUDE=mode  how to open Claude Code afterwards: continue (the
#                          default), fresh, remote or none
set -euo pipefail

REPO_URL="https://github.com/ligone/something.git"
REPO_SLUG="ligone/something"
BRANCH="${MENAGERIE_BRANCH:-claude/hopeful-babbage-djjew8}"
CLAUDE_MODE="${MENAGERIE_CLAUDE:-continue}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
step() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }
note() { printf '  %s\n' "$1"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# When piped from curl, stdin is the script itself, so questions and
# interactive programs have to talk to the terminal directly.
has_terminal() { [[ -r /dev/tty && -w /dev/tty ]] && { : </dev/tty; } 2>/dev/null; }

ask() { # ask "Question?" default(y/n) -> returns 0 for yes
    local answer
    has_terminal || return 1
    printf '%s [%s] ' "$1" "$([[ "$2" == y ]] && echo Y/n || echo y/N)" >/dev/tty
    read -r answer </dev/tty || answer=""
    answer="$(printf '%s' "${answer:-$2}" | tr '[:upper:]' '[:lower:]')"
    [[ "$answer" == y || "$answer" == yes ]]
}

main() {
    bold "Menagerie: setting up on this Mac"

    case "$CLAUDE_MODE" in
        continue|fresh|remote|none) ;;
        *) fail "MENAGERIE_CLAUDE must be continue, fresh, remote or none, not '$CLAUDE_MODE'." ;;
    esac

    step "Checking your Mac"
    [[ "$(uname -s)" == Darwin ]] || fail "This script is for macOS."
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    (( macos_major >= 14 )) || fail "Menagerie needs macOS 14 Sonoma or later; this Mac has $(sw_vers -productVersion)."
    if ! xcode-select -p >/dev/null 2>&1; then
        note "Xcode's command-line tools are needed to build the app."
        xcode-select --install >/dev/null 2>&1 || true
        fail "Finish the installer that just opened, then run this command again."
    fi
    swift_version="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
    swift_major="${swift_version%%.*}"
    swift_minor="${swift_version#*.}"
    if [[ -z "$swift_version" ]] || (( swift_major < 5 || (swift_major == 5 && swift_minor < 9) )); then
        fail "Menagerie needs Swift 5.9 or later (Xcode 15+); found '${swift_version:-none}'. Update Xcode or its command-line tools."
    fi
    note "macOS $(sw_vers -productVersion), Swift $swift_version"

    # ---------------------------------------------------------------------------
    # Find or create the working copy. Local changes are never overwritten.

    is_our_repo() { # is_our_repo dir
        local origin
        origin="$(git -C "$1" config --get remote.origin.url 2>/dev/null || true)"
        [[ "$origin" == *"$REPO_SLUG"* ]]
    }

    script_dir=""
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    if [[ -n "$script_dir" ]] && is_our_repo "$script_dir/../.."; then
        REPO_DIR="$(cd "$script_dir/../.." && pwd)"
        step "Using this clone: $REPO_DIR"
    else
        REPO_DIR="${MENAGERIE_DIR:-$HOME/Developer/something}"
        if [[ -e "$REPO_DIR" ]]; then
            is_our_repo "$REPO_DIR" || fail "$REPO_DIR exists but isn't a clone of $REPO_SLUG. Set MENAGERIE_DIR to another folder."
            step "Updating $REPO_DIR"
        else
            step "Cloning into $REPO_DIR"
            mkdir -p "$(dirname "$REPO_DIR")"
            git clone --quiet --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
        fi
    fi

    git -C "$REPO_DIR" fetch --quiet origin "$BRANCH"
    current_branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
    if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
        note "Your clone has uncommitted changes, so it stays on '$current_branch' as it is."
    else
        if [[ "$current_branch" != "$BRANCH" ]]; then
            if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
                git -C "$REPO_DIR" checkout --quiet "$BRANCH"
            else
                git -C "$REPO_DIR" checkout --quiet --track -b "$BRANCH" "origin/$BRANCH"
            fi
        fi
        git -C "$REPO_DIR" merge --quiet --ff-only "origin/$BRANCH" 2>/dev/null \
            || note "Your '$BRANCH' has commits that aren't on GitHub, so it wasn't fast-forwarded."
    fi
    note "On $(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD) at $(git -C "$REPO_DIR" rev-parse --short HEAD)"
    [[ -x "$REPO_DIR/Menagerie/Scripts/install.sh" ]] \
        || fail "This checkout has no Menagerie app. Commit or stash your changes so the script can switch to '$BRANCH', then run it again."

    # ---------------------------------------------------------------------------
    step "Building and installing the app (the first build takes a few minutes)"
    "$REPO_DIR/Menagerie/Scripts/install.sh"

    # ---------------------------------------------------------------------------
    # Open Claude Code in the project.
    #
    #   continue  teleport the cloud session this project was built in, with its
    #             whole conversation (needs the same claude.ai account)
    #   fresh     a new session that starts from a handoff note
    #   remote    a new session you can also steer from the Claude app or
    #             claude.ai (Remote Control)
    #   none      stop here

    SESSION="${MENAGERIE_SESSION:-session_01WLYZPcgn612wvpUjRiqFi6}"
    HANDOFF="You're picking up Menagerie, a native macOS app built in a Claude Code on the web session. CLAUDE.md and Menagerie/README.md describe it. setup-mac.sh has already built it and installed it in ~/Applications with a shortcut on the Desktop. Please (1) run swift test in Menagerie/ to confirm the engines pass on this Mac, (2) open the app with: open ~/Applications/Menagerie.app, (3) run the screenshot tour with: ~/Applications/Menagerie.app/Contents/MacOS/Menagerie --capture /tmp/menagerie-shots, then look at the images, and (4) help me try every exhibit by hand (gestures, keyboard shortcuts, audio, Dark Mode, bigger windows). Fix whatever misbehaves and commit to this branch."

    finish() {
        printf '\n'
        bold "All set."
        note "App:      ~/Applications/Menagerie.app (with a shortcut on your Desktop)"
        note "Project:  $REPO_DIR"
        [[ -z "${1:-}" ]] || note "$1"
        exit 0
    }

    [[ "$CLAUDE_MODE" != none ]] || finish "Start Claude Code there any time with: cd \"$REPO_DIR\" && claude"

    has_terminal || finish "To continue with Claude, run: cd \"$REPO_DIR\" && claude --teleport $SESSION"

    CLAUDE_BIN="$(command -v claude || true)"
    if [[ -z "$CLAUDE_BIN" && -x "$HOME/.local/bin/claude" ]]; then
        CLAUDE_BIN="$HOME/.local/bin/claude"
    fi
    if [[ -z "$CLAUDE_BIN" ]]; then
        step "Claude Code isn't installed yet"
        if ask "Install it now with Anthropic's official installer?" y; then
            curl -fsSL https://claude.ai/install.sh | bash
            # The installer updates PATH for new shells only, so use its launcher directly.
            if [[ -x "$HOME/.local/bin/claude" ]]; then
                CLAUDE_BIN="$HOME/.local/bin/claude"
            else
                CLAUDE_BIN="$(command -v claude || true)"
            fi
        fi
        [[ -n "$CLAUDE_BIN" ]] || finish "Install Claude Code (https://code.claude.com/docs/en/setup), then run: cd \"$REPO_DIR\" && claude --teleport $SESSION"
    fi

    cd "$REPO_DIR"
    printf '\n'
    case "$CLAUDE_MODE" in
        continue)
            step "Opening Claude Code with the cloud session's conversation"
            note "Sign in with your claude.ai account if asked. Type /remote-control inside"
            note "to keep steering this session from the Claude app on your phone."
            if ! "$CLAUDE_BIN" --teleport "$SESSION" </dev/tty; then
                note "If the conversation couldn't be brought over, run /login in Claude Code and try"
                note "again, or start a fresh session from a handoff note with:"
                note "  MENAGERIE_CLAUDE=fresh \"$REPO_DIR/Menagerie/Scripts/setup-mac.sh\""
            fi
            ;;
        fresh)
            step "Opening a new Claude Code session with a handoff note"
            "$CLAUDE_BIN" --name Menagerie "$HANDOFF" </dev/tty
            ;;
        remote)
            step "Opening Claude Code with Remote Control"
            note "It appears in the Claude app and at claude.ai/code as \"Menagerie\"."
            "$CLAUDE_BIN" --remote-control Menagerie </dev/tty
            ;;
    esac
}

# Nothing above runs until bash has read the whole file, so a download that
# is cut off halfway through `curl | bash` can't run half a script.
main "$@"
