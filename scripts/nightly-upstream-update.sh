#!/bin/zsh
set -u
set -o pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly repo="/Users/l303/repos/docsafterdark-personal"
readonly lock_dir="/tmp/docsafterdark-nightly-update.lock"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

if ! mkdir "$lock_dir" 2>/dev/null; then
    log "SKIP: another update is already running"
    exit 0
fi
trap 'rmdir "$lock_dir"' EXIT

cd "$repo" || {
    log "ERROR: repository is unavailable: $repo"
    exit 1
}

if [[ "$(git branch --show-current)" != "main" ]]; then
    log "SKIP: main is not checked out"
    exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
    log "SKIP: working tree is not clean"
    exit 0
fi

log "Fetching origin/main and upstream/main"
if ! git fetch --prune origin main || ! git fetch --prune upstream main; then
    log "ERROR: fetch failed; current version unchanged"
    exit 1
fi

readonly old_head="$(git rev-parse HEAD)"
readonly old_origin="$(git rev-parse origin/main)"

if git merge-base --is-ancestor upstream/main HEAD; then
    log "OK: already based on current upstream/main"
    exit 0
fi

restore_previous_version() {
    log "Restoring previous version $old_head"
    git rebase --abort >/dev/null 2>&1 || true
    git reset --hard "$old_head"
    npm ci && npm run build
}

log "Rebasing local commits onto upstream/main"
if ! git rebase upstream/main; then
    log "ERROR: rebase conflict; current version unchanged"
    git rebase --abort >/dev/null 2>&1 || true
    exit 1
fi

log "Installing locked dependencies and validating"
if ! npm ci || ! npm run check || ! npm run build; then
    log "ERROR: validation failed"
    restore_previous_version
    exit 1
fi

log "Publishing validated main to origin"
if ! git push --force-with-lease="main:$old_origin" origin HEAD:main; then
    log "ERROR: guarded push failed"
    restore_previous_version
    exit 1
fi

log "OK: updated $(git rev-parse --short HEAD); build and package replaced"
