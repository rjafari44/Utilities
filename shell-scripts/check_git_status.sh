#!/usr/bin/env bash
#
# check_git_status.sh
# Scans one or more directories for git repos and reports which ones have:
#   - uncommitted changes (modified/staged/untracked files)
#   - committed changes that haven't been pushed to their remote
#
# Usage:
#   ./check_git_status.sh                 # scans $HOME by default
#   ./check_git_status.sh ~/projects ~/dev
#   ./check_git_status.sh -d 3 ~/projects # limit search depth (default: unlimited)

set -euo pipefail

MAX_DEPTH=""
SEARCH_DIRS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--depth)
            MAX_DEPTH="-maxdepth $2"
            shift 2
            ;;
        *)
            SEARCH_DIRS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#SEARCH_DIRS[@]} -eq 0 ]]; then
    # Default to the directory this script lives in, not $HOME —
    # lets you drop it in your projects root and just run it with no args.
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    SEARCH_DIRS=("$SCRIPT_DIR")
fi

DIRTY_REPOS=()
UNPUSHED_REPOS=()
NO_REMOTE_REPOS=()

# Find all .git directories, dedupe, skip common noise like node_modules
mapfile -t GIT_DIRS < <(
    find "${SEARCH_DIRS[@]}" $MAX_DEPTH -type d -name ".git" \
        -not -path "*/node_modules/*" \
        -not -path "*/.cache/*" \
        2>/dev/null
)

if [[ ${#GIT_DIRS[@]} -eq 0 ]]; then
    echo "No git repositories found under: ${SEARCH_DIRS[*]}"
    exit 0
fi

echo "Scanning ${#GIT_DIRS[@]} repositories..."
echo

for git_dir in "${GIT_DIRS[@]}"; do
    repo="$(dirname "$git_dir")"

    # Uncommitted changes (working tree + staged + untracked)
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        DIRTY_REPOS+=("$repo")
    fi

    # Does it even have a remote?
    if [[ -z "$(git -C "$repo" remote 2>/dev/null)" ]]; then
        NO_REMOTE_REPOS+=("$repo")
        continue
    fi

    # Unpushed commits: compare each local branch to its upstream, if it has one
    while read -r branch; do
        upstream=$(git -C "$repo" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null) || continue
        ahead=$(git -C "$repo" rev-list --count "${upstream}..${branch}" 2>/dev/null) || continue
        if [[ "$ahead" -gt 0 ]]; then
            UNPUSHED_REPOS+=("$repo (branch '$branch': $ahead commit(s) ahead of $upstream)")
            break
        fi
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/)
done

print_section() {
    local title="$1"; shift
    local arr=("$@")
    echo "── $title (${#arr[@]}) ──"
    if [[ ${#arr[@]} -eq 0 ]]; then
        echo "  none"
    else
        printf '  %s\n' "${arr[@]}"
    fi
    echo
}

print_section "Repos with uncommitted changes" ${DIRTY_REPOS[@]+"${DIRTY_REPOS[@]}"}
print_section "Repos with unpushed commits"    ${UNPUSHED_REPOS[@]+"${UNPUSHED_REPOS[@]}"}
print_section "Repos with no remote configured" ${NO_REMOTE_REPOS[@]+"${NO_REMOTE_REPOS[@]}"}