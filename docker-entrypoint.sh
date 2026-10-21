#!/bin/sh
# Runs the *.sh scripts in /docker-entrypoint.d (in lexical order) and then the container command.
# Same convention as the official postgres image:
#   executable *.sh      run in a child process
#   non-executable *.sh  sourced, so exported variables reach the container command; since it runs
#                        inside this script, `exit` (even `exit 0`) stops the container start
# Any other file is ignored. A failing script aborts the container start.
# Set ENTRYPOINT_QUIET_LOGS to any value to silence the log messages.
set -e

ENTRYPOINT_DIR=/docker-entrypoint.d

log() {
    if [ -z "${ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$0: $*" >&2
    fi
}

if [ -d "$ENTRYPOINT_DIR" ]; then
    for f in "$ENTRYPOINT_DIR"/*; do
        [ -f "$f" ] || continue
        case "$f" in
            *.sh)
                if [ -x "$f" ]; then
                    log "running $f"
                    "$f"
                else
                    log "sourcing $f"
                    # shellcheck disable=SC1090
                    . "$f"
                fi
                ;;
            *)
                log "ignoring $f"
                ;;
        esac
    done
fi

exec "$@"
