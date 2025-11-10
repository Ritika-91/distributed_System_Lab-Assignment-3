#!/usr/bin/env bash
set -euo pipefail

# Trap EXIT ensures the pause runs even if the script fails early
trap 'echo; read -p "Press Enter to exit..."' EXIT

# ---------- Config ----------
N=${N:-30}                                   # requests per phase (seq)
C=${C:-10}                                   # concurrency for parallel phase
URL=${URL:-http://localhost:18080/ping}      # client endpoint
OUTDIR=${OUTDIR:-tests/results}
CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT:-1}
CURL_MAX_TIME=${CURL_MAX_TIME:-5}
# If you can slow the backend with an env var, set it here (ms). Leave empty to skip.
SLOW_DELAY_MS=${SLOW_DELAY_MS:-1000}
BACKEND_DEPLOY=${BACKEND_DEPLOY:-backend}
CLIENT_DEPLOY=${CLIENT_DEPLOY:-client}

mkdir -p "$OUTDIR"

# ---------- Helpers ----------
now_ms() { date +%s%3N; }

curl_line() {
  # Prints: i,status,time_total_s,ts_ms
  local i="$1"
  # On failure, emit "000 9999" to mark timeout/conn error
  read -r status total <<<"$(
    curl -sS -o /dev/null \
      --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
      --max-time "${CURL_MAX_TIME}" \
      -w "%{http_code} %{time_total}" \
      "${URL}" || echo "000 9999"
  )"
  echo "${i},${status},${total},$(now_ms)"
}

summarize_csv() {
  awk -F, '
    NR>1 { c++; s+=$3; errs += ($2 !~ /^2/); t[c]=$3 }
    END {
      if (c==0) { print "no results"; exit }
      # sort times (simple O(n^2) — fine for small N)
      for (i=1;i<=c;i++) for (j=i+1;j<=c;j++) if (t[i]>t[j]) { tmp=t[i]; t[i]=t[j]; t[j]=tmp }

      # indices for quantiles
      i50 = int(0.50*(c+1)); if(i50<1)i50=1; if(i50>c)i50=c
      i95 = int(0.95*(c+1)); if(i95<1)i95=1; if(i95>c)i95=c
      i99 = int(0.99*(c+1)); if(i99<1)i99=1; if(i99>c)i99=c

      printf "count=%d, errors=%d (%.1f%%), avg=%.3f, p50=%.3f, p95=%.3f, p99=%.3f, max=%.3f\n",
             c, errs, (100.0*errs/c), (s/c), t[i50], t[i95], t[i99], t[c]
    }' "$1"
}

write_header() {
  local path="$1"
  echo "#i,status,time_total_s,ts_ms" > "$path"
}

phase_seq() {
  local name="$1"
  local out="${OUTDIR}/baseline_${name}_seq.csv"
  write_header "$out"
  echo "== ${name} (sequential, N=${N}) =="
  for i in $(seq 1 "$N"); do
    curl_line "$i" | tee -a "$out" >/dev/null
  done
  echo "Summary: $(summarize_csv "$out")"
  echo "Saved:   $out"
}

phase_parallel() {
  local name="$1"
  local out="${OUTDIR}/baseline_${name}_c${C}.csv"
  write_header "$out"
  echo "== ${name} (parallel, C=${C}, N=${N}) =="

  # launch up to C jobs at a time
  for i in $(seq 1 "$N"); do
    # wait until we have a free slot
    while [ "$(jobs -rp | wc -l)" -ge "$C" ]; do
      # wait for any job to finish (bash 4.3+ supports -n; if not, use plain wait)
      if wait -n 2>/dev/null; then :; else wait; fi
    done
    ( curl_line "$i" >> "$out" ) &
  done
  wait

  echo "Summary: $(summarize_csv "$out")"
  echo "Saved:   $out"
}

# ---------- Phases ----------
normal() {
  echo "--- NORMAL ---"
  phase_seq normal
  phase_parallel normal
}

backend_down() {
  echo "--- BACKEND DOWN ---"
  echo "Scaling ${BACKEND_DEPLOY} to 0…"
  kubectl scale deploy/"${BACKEND_DEPLOY}" --replicas=0 >/dev/null
  kubectl rollout status deploy/"${BACKEND_DEPLOY}" --timeout=60s || true

  phase_seq down
  phase_parallel down

  echo "Restoring ${BACKEND_DEPLOY}…"
  kubectl scale deploy/"${BACKEND_DEPLOY}" --replicas=1 >/dev/null
  kubectl rollout status deploy/"${BACKEND_DEPLOY}" --timeout=120s
  kubectl port-forward svc/client 18080:8080 >/dev/null 2>&1 &
  PF_PID_2=$!
  echo "Port-forward started (pid=$PF_PID)"
}

backend_slow() {
  echo "--- BACKEND SLOW ---"
  if [[ -z "${SLOW_DELAY_MS}" ]]; then
    echo "SLOW_DELAY_MS not set; skipping slow phase."
    return
  fi
  echo "Setting backend delay to ${SLOW_DELAY_MS} ms…"
  kubectl set env deploy/"${BACKEND_DEPLOY}" DELAY_MS="${SLOW_DELAY_MS}" >/dev/null
  kubectl rollout status deploy/"${BACKEND_DEPLOY}" --timeout=120s

  phase_seq slow
  phase_parallel slow

  echo "Removing backend delay…"
  kubectl set env deploy/"${BACKEND_DEPLOY}" DELAY_MS- >/dev/null
  kubectl rollout status deploy/"${BACKEND_DEPLOY}" --timeout=120s
}

# ---------- Run ----------
echo "URL=${URL}"
echo "OUTDIR=${OUTDIR}"
echo "Client: ${CLIENT_DEPLOY} | Backend: ${BACKEND_DEPLOY}"
echo

kubectl config set-context --current --namespace=lab3
kubectl port-forward svc/client 18080:8080 >/dev/null 2>&1 &
PF_PID=$!
echo "Port-forward started (pid=$PF_PID)"

normal
backend_down
backend_slow

echo "Done."
read -p "Press Enter to exit..."

