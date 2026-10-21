#!/usr/bin/env bash
set -euo pipefail
cd /cloudrec
case "${1:-server}" in
  server)
    ./opa run --server --addr=127.0.0.1:8181 --log-level=error &
    opa_pid=$!
    # JAVA_TOOL_OPTIONS is consumed by the JVM without shell evaluation.
    java -jar cloudrec.jar &
    java_pid=$!
    # shellcheck disable=SC2329 # Invoked by the EXIT trap.
    stop() {
      kill -TERM "$java_pid" "$opa_pid" 2>/dev/null || true
      wait "$java_pid" "$opa_pid" 2>/dev/null || true
    }
    trap stop EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    set +e
    wait -n "$opa_pid" "$java_pid"
    status=$?
    set -e
    # Either child exiting is a failure, including an unexpected clean exit.
    if [[ "$status" == 0 ]]; then status=1; fi
    exit "$status"
    ;;
  collector)
    [[ -s config.yaml ]] || { echo 'collector config.yaml is required' >&2; exit 1; }
    # Keep the token in the mounted file: upstream --accessToken logs its value.
    exec ./collectors
    ;;
  *) exec "$@" ;;
esac
