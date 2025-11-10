#!/usr/bin/env bash
# cb-tests.sh — circuit breaker tests (aligned with your baseline style)
# Usage: ./cb-tests.sh start-pf|stop-pf|open|halfopen|timeout|all|status|logs

set -euo pipefail

# Trap EXIT ensures the pause runs even if the script fails early
trap 'echo; read -p "Press Enter to exit..."' EXIT

# ===== Baseline-style vars (match your existing names) =====
NAMESPACE="${NAMESPACE:-lab3}"
CLIENT_SVC="${CLIENT_SVC:-client}"          # baseline used: svc/client
LOCAL_PORT="${LOCAL_PORT:-18080}"
REMOTE_PORT="${REMOTE_PORT:-8080}"

# Your client endpoint that proxies to backend (same as baseline)
# It should accept failPct and delayMs and call the backend accordingly.
BASE_URL="http://localhost:${LOCAL_PORT}"
PATH_OK="${PATH_OK:-/circuitbreaker?failPct=0}"
PATH_FAIL="${PATH_FAIL:-/circuitbreaker?failPct=100}"
PATH_SLOW="${PATH_SLOW:-/circuitbreaker?delayMs=4000}"

# Circuit-breaker timings (match your application.yml or ResilienceConfig)
WAIT_OPEN_SECONDS="${WAIT_OPEN_SECONDS:-12}"      # >= waitDurationInOpenState
HALFOPEN_PROBES="${HALFOPEN_PROBES:-20}"
OPEN_BURST="${OPEN_BURST:-50}"
TIMEOUT_BURST="${TIMEOUT_BURST:-20}"

PF_PIDFILE="/tmp/portfwd_client_${LOCAL_PORT}.pid"
PF_LOG="/tmp/portfwd_client_${LOCAL_PORT}.log"
OUT_LOG="/tmp/cb_test_output.log"

# ===== Helpers =====
ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

start_pf() {
  if [ -f "$PF_PIDFILE" ] && kill -0 "$(cat "$PF_PIDFILE")" 2>/dev/null; then
    echo "[info] port-forward already running (pid $(cat "$PF_PIDFILE"))"
    return 0
  fi
  echo "[info] starting port-forward: svc/${CLIENT_SVC} ${LOCAL_PORT}:${REMOTE_PORT}"
  # Important: run in background AND redirect both stdout/stderr; then record PID.
  # Using nohup so it survives this shell; sleep a moment to let it bind.
  nohup kubectl -n "${NAMESPACE}" port-forward "svc/${CLIENT_SVC}" \
        "${LOCAL_PORT}:${REMOTE_PORT}" >"$PF_LOG" 2>&1 &
  echo $! > "$PF_PIDFILE"
  sleep 1
  echo "[info] pf pid=$(cat "$PF_PIDFILE"), log=$PF_LOG"
}

stop_pf() {
  if [ -f "$PF_PIDFILE" ]; then
    local pid; pid="$(cat "$PF_PIDFILE")"
    echo "[info] stopping port-forward pid ${pid}"
    kill "${pid}" 2>/dev/null || true
    rm -f "$PF_PIDFILE"
    echo "[info] stopped"
  else
    echo "[warn] no pidfile at ${PF_PIDFILE}; nothing to stop"
  fi
}

status_pf() {
  if [ -f "$PF_PIDFILE" ] && kill -0 "$(cat "$PF_PIDFILE")" 2>/dev/null; then
    echo "[ok] port-forward is running (pid $(cat "$PF_PIDFILE"))"
  else
    echo "[down] port-forward not running"
  fi
}

req() {
  local path="$1"
  curl -sS "${BASE_URL}${path}"
}

open_test() {
  echo "[test] OPEN: forcing ${OPEN_BURST} failures to trip breaker"
  echo "[log] $(ts) OPEN begin" | tee -a "$OUT_LOG"
  for i in $(seq 1 "$OPEN_BURST"); do
    out="$(req "${PATH_FAIL}" || true)"
    printf "%4d " "$i"
    echo "$(ts),open,$i,$out" >> "$OUT_LOG"
    sleep 0.1
  done
  echo; echo "[test] OPEN done (tail):"
  tail -n 10 "$OUT_LOG" || true
}

halfopen_test() {
  echo "[test] HALF-OPEN: waiting ${WAIT_OPEN_SECONDS}s, then sending ${HALFOPEN_PROBES} healthy calls"
  sleep "${WAIT_OPEN_SECONDS}"
  echo "[log] $(ts) HALFOPEN begin" | tee -a "$OUT_LOG"
  for i in $(seq 1 "$HALFOPEN_PROBES"); do
    out="$(req "${PATH_OK}" || true)"
    printf "%4d " "$i"
    echo "$(ts),halfopen,$i,$out" >> "$OUT_LOG"
    sleep 0.1
  done
  echo; echo "[test] HALF-OPEN done (tail):"
  tail -n 10 "$OUT_LOG" || true
}

timeout_test() {
  echo "[test] TIMEOUT: sending ${TIMEOUT_BURST} slow calls (client timeout must be < delayMs)"
  echo "[log] $(ts) TIMEOUT begin" | tee -a "$OUT_LOG"
  for i in $(seq 1 "$TIMEOUT_BURST"); do
    out="$(req "${PATH_SLOW}" || true)"
    printf "%4d " "$i"
    echo "$(ts),timeout,$i,$out" >> "$OUT_LOG"
    sleep 0.1
  done
  echo; echo "[test] TIMEOUT done (tail):"
  tail -n 10 "$OUT_LOG" || true
}

logs() {
  echo "[info] showing last 40 lines of ${OUT_LOG} (responses)"
  tail -n 40 "$OUT_LOG" || true
  echo
  echo "[info] port-forward logs (${PF_LOG}) tail:"
  tail -n 20 "$PF_LOG" || true
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  start-pf     Start kubectl port-forward (svc/${CLIENT_SVC} -> localhost:${LOCAL_PORT})
  stop-pf      Stop the background port-forward
  status       Show port-forward status
  open         Force failures to open the circuit (${OPEN_BURST} calls)
  halfopen     Wait ${WAIT_OPEN_SECONDS}s then send ${HALFOPEN_PROBES} healthy calls
  timeout      Send ${TIMEOUT_BURST} slow calls to trigger timeouts
  all          start-pf -> open -> halfopen -> timeout (then keep pf running)
  logs         Tail recent output logs
EOF
}

cmd="${1:-}"
case "${cmd}" in
  start-pf)  start_pf ;;
  stop-pf)   stop_pf ;;
  status)    status_pf ;;
  open)      start_pf; open_test ;;
  halfopen)  start_pf; halfopen_test ;;
  timeout)   start_pf; timeout_test ;;
  all)       start_pf; open_test; halfopen_test; timeout_test; echo "[done] logs in ${OUT_LOG}" ;;
  logs)      logs ;;
  *) usage; exit 1 ;;
esac
