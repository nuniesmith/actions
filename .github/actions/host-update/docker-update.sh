#!/usr/bin/env bash
# Refresh one compose project's images and roll out only what changed.
#
# Piped to the host over SSH by the host-update action and run as the deploy
# user: docker group, no sudo. It never touches the git checkout -- the compose
# file is whatever the last deploy left, and this only refreshes the images
# under it.
#
#   MODE=snapshot  print the services running and healthy right now: the
#                  baseline the rest of the run is judged against
#   MODE=update    wait for that baseline to be back (the apt upgrade may have
#                  restarted dockerd), refresh images, recreate what changed,
#                  verify, roll back failures, check nothing else went down
#   MODE=verify    only the waiting and the checking: for a run that upgraded
#                  apt packages but was told to leave images alone
#
# What happens to each running service:
#   - pulled image         -> pulled; recreated only if the image changed
#   - built here (build:)  -> left alone unless named in REBUILD, which
#                             rebuilds it on a freshly pulled base image
#   - first-party image    -> left alone: ghcr.io/nuniesmith/* and nuniesmith/*
#                             are rolled out by their own CI at an exact revision
#   - pinned by digest, named in SKIP, or not running -> left alone
#
# Every new image is in place BEFORE anything is recreated. A recreated service
# must come back running, unrestarted and healthy (or, with no healthcheck,
# stay up 30s) within HEALTH_TIMEOUT. If it does not, it goes back to the image
# it ran before -- unless it is named in NO_ROLLBACK, for services that migrate
# their data on start. Nextcloud's old image refuses a data directory its new
# one has upgraded, so rolling it back would turn a broken service into a dead
# one. An image that failed is remembered, and not tried again until the tag
# moves on to a different one: otherwise a bad upstream release would take the
# service down for HEALTH_TIMEOUT every morning.
#
# The image a service ran before is kept as rollback/<project>-<service>:previous
# until its next update, so a manual rollback is one `docker tag` and one `up`.
# Rollback works by NAME, never by image id: in the containerd image store an
# image that loses its last tag cannot be tagged again.
#
# Env:    MODE, PROJECT_PATH (directory under $HOME), BASELINE (from snapshot),
#         SKIP, REBUILD, NO_ROLLBACK (space-separated service names),
#         HEALTH_TIMEOUT (seconds, default 600)
# Output: "::report::<line>" lines for the notification, then "::changed::<n>"
#         and "::status::ok|warn|fail". Everything else is log.
set -euo pipefail

MODE=${MODE:-update}
PROJECT_PATH=${PROJECT_PATH:?PROJECT_PATH is required}
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-600}
STATE_DIR="$HOME/.local/state/host-update"
BAD_FILE="$STATE_DIR/failed-images"
cd "$HOME/$PROJECT_PATH"

has() { [[ " $1 " == *" $2 "* ]]; }   # has "<space-separated list>" <word>
status=ok
warn() { [ "$status" = fail ] || status=warn; }
fail() { status=fail; }
report() { echo "::report::$*"; }

# "<running> <health> <restarts> <started-epoch>" for a service's container.
# -a: a stopped container must read as not running, not as absent.
state_of() {
    local cid
    cid=$(docker compose ps -a -q "$1" 2>/dev/null | head -n1)
    if [ -z "$cid" ]; then echo "false missing 0 0"; return; fi
    docker inspect -f '{{.State.Running}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} {{.RestartCount}} {{.State.StartedAt}}' "$cid" \
        | { read -r r h n s; echo "$r $h $n $(date -d "$s" +%s 2>/dev/null || echo 0)"; }
}

# await <timeout> <strict> <service>...
# Waits until each service is running and healthy (or, with no healthcheck, up
# for 30s). strict=1 is for containers this run created: any restart at all
# means it crashed. Leaves a reason per service that never got there in WHY;
# returns non-zero if there are any.
declare -A WHY=()
await() {
    local timeout=$1 strict=$2; shift 2
    local deadline=$((SECONDS + timeout)) svc running health restarts started
    local -a pending=("$@") still=()
    WHY=()
    while [ ${#pending[@]} -gt 0 ]; do
        still=()
        for svc in "${pending[@]}"; do
            read -r running health restarts started <<<"$(state_of "$svc")"
            if [ "$strict" = 1 ] && [ "$restarts" != 0 ]; then
                WHY[$svc]="crashing (restarted $restarts times)"; continue
            fi
            if [ "$running" = true ]; then
                [ "$health" = healthy ] && continue
                [ "$health" = none ] && [ $(( $(date +%s) - started )) -ge 30 ] && continue
            fi
            still+=("$svc")
        done
        pending=("${still[@]}")
        [ ${#pending[@]} -eq 0 ] && break
        if [ $SECONDS -ge $deadline ]; then
            for svc in "${pending[@]}"; do
                read -r running health restarts started <<<"$(state_of "$svc")"
                WHY[$svc]="not healthy after ${timeout}s (running=$running, health=$health)"
            done
            break
        fi
        sleep 5
    done
    [ ${#WHY[@]} -eq 0 ]
}

# A readable version for an image: its OCI version label, else the *_VERSION
# the official images set, else a short id.
ver() {
    local v
    v=$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$1" 2>/dev/null || true)
    if [ -z "$v" ] || [ "$v" = "<no value>" ]; then
        v=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null \
            | sed -n 's/^\(NEXTCLOUD\|PG\|MONGO\|NGINX\|MARIADB\|REDIS\|NODE\)_VERSION=//p' | head -n1 || true)
    fi
    if [ -z "$v" ]; then v=${1#sha256:}; v=${v:0:12}; fi
    printf '%s' "${v:0:40}"
}

# Registries (lscr.io, ghcr.io) time out often enough to be worth one retry.
pull_ref() {
    local out attempt
    for attempt in 1 2; do
        if out=$(timeout 900 docker pull -q "$1" 2>&1); then return 0; fi
        [ "$attempt" = 1 ] && sleep 20
    done
    printf '%s' "$out" | tail -n1 | cut -c1-120
    return 1
}

if [ "$MODE" = snapshot ]; then
    up=()
    for svc in $(docker compose config --services); do
        read -r running health _ _ <<<"$(state_of "$svc")"
        if [ "$running" = true ] && [ "$health" != unhealthy ] && [ "$health" != starting ]; then
            up+=("$svc")
        fi
    done
    echo "::baseline::${up[*]}"
    exit 0
fi

config=$(docker compose config --format json)
project=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' <<<"$config")
mapfile -t rows < <(python3 -c '
import json, sys
for name, s in sorted(json.load(sys.stdin)["services"].items()):
    print(name, "build" if "build" in s else "image", s.get("image") or "-", sep="\t")' <<<"$config")
mkdir -p "$STATE_DIR"; touch "$BAD_FILE"

# Anything up before the run -- and not recreated by it, or already reported
# down -- must still be up.
changed=()
down=""
collateral() {
    local svc others=()
    for svc in "${baseline[@]}"; do
        has "${changed[*]:-} $down" "$svc" || others+=("$svc")
    done
    if [ ${#others[@]} -gt 0 ] && ! await 120 0 "${others[@]}"; then
        for svc in "${!WHY[@]}"; do report "❌ $svc was up before this run and is not now: ${WHY[$svc]}"; done
        fail
    fi
}

# -- 0. the apt upgrade may have restarted dockerd: wait for what was up ------
read -r -a baseline <<<"${BASELINE:-}"
if [ ${#baseline[@]} -gt 0 ] && ! await 300 0 "${baseline[@]}"; then
    for svc in "${!WHY[@]}"; do
        report "❌ $svc was up when this run started and is not now: ${WHY[$svc]}"
        down+=" $svc"
    done
    fail
fi
if [ "$MODE" = verify ]; then   # step 0 was the whole check
    echo "::changed::0"; echo "::status::$status"; exit 0
fi

# -- 1. decide what this run may touch ----------------------------------------
declare -A OLD=() REF=() NEW=() PRE=() PREV=()
pull=() rebuild=()
for row in "${rows[@]}"; do
    IFS=$'\t' read -r svc kind image <<<"$row"
    cid=$(docker compose ps -a -q "$svc" 2>/dev/null | head -n1)
    if [ -z "$cid" ] || [ "$(docker inspect -f '{{.State.Running}}' "$cid")" != true ]; then
        echo "  $svc: not running, left alone"; continue
    fi
    if has "${SKIP:-}" "$svc"; then echo "  $svc: in SKIP"; continue; fi
    if [ "$kind" = build ]; then
        if ! has "${REBUILD:-}" "$svc"; then echo "  $svc: built here, not in REBUILD"; continue; fi
        rebuild+=("$svc")
        REF[$svc]=$(docker inspect -f '{{.Config.Image}}' "$cid")
    else
        case "$image" in
            ghcr.io/nuniesmith/*|nuniesmith/*) echo "  $svc: first-party, rolled out by its own CI"; continue ;;
            *@sha256:*) echo "  $svc: pinned by digest"; continue ;;
        esac
        pull+=("$svc")
        REF[$svc]=$image
    fi
    OLD[$svc]=$(docker inspect -f '{{.Image}}' "$cid")
    # Name the image it runs now, BEFORE a pull or rebuild moves the tag. In
    # Docker's containerd image store (sullivan's) an image that has lost its
    # last name cannot be tagged at all, so a rollback target taken afterwards
    # would not exist.
    PRE[$svc]="rollback/${project}-${svc,,}:pre-update"
    docker tag "${OLD[$svc]}" "${PRE[$svc]}" 2>/dev/null || PRE[$svc]=""
done
echo "pull: ${pull[*]:-none}"
echo "rebuild: ${rebuild[*]:-none}"
# A wrong PROJECT_PATH or project name makes every service look "not running":
# the run would check nothing and still come out green.
if [ -z "$(docker compose ps -q 2>/dev/null)" ]; then
    report "❌ no running containers found for compose project '$project' in ~/$PROJECT_PATH, so nothing was checked"
    echo "::changed::0"; echo "::status::fail"; exit 0
fi
echo "::checked::$(( ${#pull[@]} + ${#rebuild[@]} ))"

# -- 2. fetch every new image before touching anything ------------------------
declare -A PULLED=()
pull_failed=()
for svc in "${pull[@]}"; do
    ref=${REF[$svc]}
    [ -n "${PULLED[$ref]:-}" ] && continue
    if err=$(pull_ref "$ref"); then PULLED[$ref]=ok; else PULLED[$ref]=failed; pull_failed+=("$svc: $err"); fi
done
if [ ${#pull_failed[@]} -gt 0 ]; then
    report "⚠️ pull failed, still running the current image: $(IFS=';'; echo "${pull_failed[*]}")"
    warn
fi
if [ ${#rebuild[@]} -gt 0 ]; then
    echo "rebuilding on a fresh base image: ${rebuild[*]}"
    # Without this, buildx attaches provenance that differs on every build, so
    # an identical rebuild gets a new image id and would be "changed" daily.
    if ! BUILDX_NO_DEFAULT_ATTESTATIONS=1 timeout 1800 docker compose build --pull "${rebuild[@]}"; then
        report "❌ rebuild failed: ${rebuild[*]} (see the run log)"
        fail
    fi
fi

# -- 3. what actually changed -------------------------------------------------
drop_pre() { [ -z "${PRE[$1]}" ] || docker image rm "${PRE[$1]}" >/dev/null 2>&1 || true; }
for svc in "${pull[@]}" "${rebuild[@]}"; do
    if ! new=$(docker image inspect -f '{{.Id}}' "${REF[$svc]}" 2>/dev/null) \
        || [ "$new" = "${OLD[$svc]}" ]; then
        drop_pre "$svc"; continue
    fi
    if grep -qxF "$project/$svc $new" "$BAD_FILE"; then
        # Point the tag back at what runs, so a deploy does not pick it up either.
        if [ -n "${PRE[$svc]}" ]; then docker tag "${PRE[$svc]}" "${REF[$svc]}"; fi
        drop_pre "$svc"
        echo "  $svc: $(ver "$new") failed here before; waiting for a newer image"
        continue
    fi
    NEW[$svc]=$new
    changed+=("$svc")
done

# -- 4. recreate only those, verify, roll back what failed --------------------
if [ ${#changed[@]} -gt 0 ]; then
    for svc in "${changed[@]}"; do
        # The image it ran before becomes the rollback target, replacing the
        # one kept from its last update.
        if [ -n "${PRE[$svc]}" ]; then
            PREV[$svc]="rollback/${project}-${svc,,}:previous"
            docker tag "${PRE[$svc]}" "${PREV[$svc]}"
            drop_pre "$svc"
        fi
    done
    echo "recreating: ${changed[*]}"
    if ! docker compose up -d --no-deps --no-build --pull never "${changed[@]}"; then
        report "❌ docker compose up failed for: ${changed[*]}"
        fail
    fi
    failed=()
    declare -A FAILED_WHY=()
    if ! await "$HEALTH_TIMEOUT" 1 "${changed[@]}"; then
        for svc in "${!WHY[@]}"; do failed+=("$svc"); FAILED_WHY[$svc]=${WHY[$svc]}; done
    fi
    for svc in "${changed[@]}"; do
        has "${failed[*]:-}" "$svc" && continue
        old_v=$(ver "${PREV[$svc]:-${OLD[$svc]}}") new_v=$(ver "${NEW[$svc]}")
        if [ "$old_v" = "$new_v" ]; then report "🐳 $svc $new_v (image refreshed)"
        else report "🐳 $svc $old_v → $new_v"; fi
    done
    for svc in "${failed[@]}"; do
        echo "$project/$svc ${NEW[$svc]}" >>"$BAD_FILE"
        old_v=$(ver "${PREV[$svc]:-${OLD[$svc]}}") new_v=$(ver "${NEW[$svc]}")
        if has "${NO_ROLLBACK:-}" "$svc"; then
            report "❌ $svc $old_v → $new_v is ${FAILED_WHY[$svc]}. NOT rolled back: it migrates its data on start. Previous image: ${PREV[$svc]:-none kept}"
            fail
            continue
        fi
        if [ -z "${PREV[$svc]:-}" ]; then
            report "❌ $svc $new_v is ${FAILED_WHY[$svc]}, and there is no previous image to roll back to"
            fail
            continue
        fi
        docker tag "${PREV[$svc]}" "${REF[$svc]}"
        if docker compose up -d --no-deps --no-build --pull never "$svc" && await 300 1 "$svc"; then
            report "↩️ $svc rolled back to $old_v: $new_v was ${FAILED_WHY[$svc]}"
            warn
        else
            report "❌ $svc $new_v was ${FAILED_WHY[$svc]}, and rolling back to $old_v did not recover it: ${WHY[$svc]:-compose up failed}"
            fail
        fi
    done
fi

# -- 5. collateral damage: anything that was up before and is not now ---------
collateral

# -- 6. tidy: dangling images only; rollback tags and in-use images stay ------
reclaimed=$(docker image prune -f 2>/dev/null | awk '/Total reclaimed space/ {print $4}' || true)
docker builder prune -f --filter until=168h >/dev/null 2>&1 || true
case "$reclaimed" in
    *GB) report "🧹 pruned dangling images: $reclaimed freed" ;;
    *) echo "pruned dangling images: ${reclaimed:-0B}" ;;
esac

echo "::changed::${#changed[@]}"
echo "::status::$status"
