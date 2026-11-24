#!/bin/bash

# Shared helpers for the cmux sessionizer scripts (cmux-s, cmux-mk).
# Source this file; do not execute it directly.

# Silence the "'<cmd>' is now an alias for ..." deprecation notices on stderr.
export CMUX_QUIET=1

# `cmux list-workspaces` prints one line per workspace:
#   [* ]workspace:<n>  <title>[  [selected]]
# Emit "<ref>\t<title>" pairs.
cmux_workspaces() {
    cmux list-workspaces 2>/dev/null | awk '
        {
            sub(/^\*?[[:space:]]*/, "")
            ref = $1
            $1 = ""
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+\[selected\][[:space:]]*$/, "")
            printf "%s\t%s\n", ref, $0
        }
    '
}

workspace_ref() {
    local name="$1"
    cmux_workspaces | awk -F'\t' -v name="$name" '$2 == name { print $1; exit }'
}

# Open (or focus) a cmux workspace for a directory, with the standard tab layout.
#   Args:   <path> [name]   (name defaults to basename of path)
#   Prints: the workspace ref
#   Effect: selects the workspace
#
# Reuses an existing workspace of the same name; otherwise creates a new one with
# a Code (nvim) tab plus Server / Claude / Whatever terminal tabs.
cmux_open_workspace() {
    local path="$1" name="${2:-$(basename "$1")}"

    # Reuse a workspace with this name if it already exists.
    local existing_ref
    existing_ref=$(workspace_ref "$name")
    if [[ -n "$existing_ref" ]]; then
        cmux select-workspace --workspace "$existing_ref" >/dev/null
        echo "$existing_ref"
        return 0
    fi

    # Not workspace_ref: a just-created workspace isn't listed yet, and an empty ref targets the caller's workspace.
    local new_ref
    new_ref=$(cmux new-workspace --name "$name" --cwd "$path" --command "nvim" | awk '$1 == "OK" { print $2 }')
    if [[ -z "$new_ref" ]]; then
        echo "cmux_open_workspace: failed to create workspace '$name'" >&2
        return 1
    fi

    # The initial tab (running nvim) is the currently focused one.
    cmux rename-tab --workspace "$new_ref" "Code" >/dev/null

    # Extra terminal tabs to create after Code, in the intended left-to-right order.
    local tabs=("Server" "Claude" "Whatever")

    # new-surface does NOT focus the new tab — it inserts right after the focused
    # (first) tab. Iterating in reverse means each fresh tab gets pushed rightward
    # by the next one, landing in the intended left-to-right order.
    # Capture the new surface's ref from the `OK surface:<n> ...` output.
    local index surface_ref
    for (( index=${#tabs[@]}-1; index>=0; index-- )); do
        surface_ref=$(cmux new-surface --workspace "$new_ref" | awk '{ print $2 }')
        if [[ -n "$surface_ref" ]]; then
            cmux rename-tab --workspace "$new_ref" --tab "$surface_ref" "${tabs[$index]}" >/dev/null
        fi
    done

    cmux select-workspace --workspace "$new_ref" >/dev/null
    echo "$new_ref"
}
