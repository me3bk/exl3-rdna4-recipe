#!/bin/bash
# One-line install: puts this recipe in ~/.local/share/exl3-rdna4-recipe (EXL3_RECIPE_DIR to change it) and starts
# container/run.sh, which downloads the models once (~14 GB) and serves http://127.0.0.1:8096/v1.
#
#   curl -fsSL https://raw.githubusercontent.com/parth-thakre/exl3-rdna4-recipe/main/install.sh | bash
#   curl -fsSL .../install.sh | CTX=128k bash        environment and arguments go to container/run.sh
#
# Rerun it to update the recipe and start the server again. Needs Docker or Podman, curl, and git or tar.
set -euo pipefail

# Everything runs from main, called on the last line, so a download cut short runs nothing
main() {
    local dir=${EXL3_RECIPE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/exl3-rdna4-recipe}
    local url=https://github.com/parth-thakre/exl3-rdna4-recipe
    if [ -d "$dir/.git" ]; then
        git -C "$dir" pull -q --ff-only || echo "install.sh: couldn't update $dir (local changes?); using it as it is" >&2
    elif command -v git >/dev/null; then
        [ -e "$dir" ] && [ ! -f "$dir/container/run.sh" ] && { echo "install.sh: $dir exists and isn't this recipe" >&2; exit 1; }
        rm -rf "$dir" && git clone -q --depth 1 "$url" "$dir"
    else
        # No git: the main branch as a tarball (also how such an install updates)
        [ -e "$dir" ] && [ ! -f "$dir/container/run.sh" ] && { echo "install.sh: $dir exists and isn't this recipe" >&2; exit 1; }
        mkdir -p "$dir" && curl -fsSL "$url/archive/refs/heads/main.tar.gz" | tar -xz -C "$dir" --strip-components 1
    fi
    echo "recipe in $dir"
    # Under curl | bash, stdin is the script; give run.sh the terminal so it can ask before opening ./triage.sh
    if { : </dev/tty; } 2>/dev/null; then
        exec "$dir/container/run.sh" "$@" </dev/tty
    fi
    exec "$dir/container/run.sh" "$@"
}

main "$@"
