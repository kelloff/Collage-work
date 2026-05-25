#!/bin/bash
# Убивает зависшие процессы «ollama runner» (долгий inference / зомби CPU).
# Не трогает ollama serve и инстанс check на :11435.
#
# Env:
#   OLLAMA_RUNNER_MAX_AGE_SEC  — убить, если работает дольше (default 660 ≈ 11 min)
#   OLLAMA_RUNNER_MIN_AGE_SEC  — не трогать совсем свежие (default 120)
#   OLLAMA_RUNNER_MAX_COUNT    — если runner'ов больше N, убить самые старые (default 1)
#   OLLAMA_RUNNER_DRY_RUN=1    — только лог, без kill

set -euo pipefail

MAX_AGE="${OLLAMA_RUNNER_MAX_AGE_SEC:-660}"
MIN_AGE="${OLLAMA_RUNNER_MIN_AGE_SEC:-120}"
MAX_COUNT="${OLLAMA_RUNNER_MAX_COUNT:-1}"
DRY_RUN="${OLLAMA_RUNNER_DRY_RUN:-0}"
LOG_TAG="ollama-runner-killer"

log() {
  local msg="$1"
  logger -t "$LOG_TAG" "$msg" 2>/dev/null || true
  printf '%s %s\n' "$(date -Is)" "$msg"
}

is_check_runner_parent() {
  local pid="$1"
  local ppid
  ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" || return 1
  [[ -n "$ppid" ]] || return 1
  if [[ -r "/proc/${ppid}/environ" ]] \
    && tr '\0' '\n' <"/proc/${ppid}/environ" | grep -q '^OLLAMA_HOST=127.0.0.1:11435'; then
    return 0
  fi
  return 1
}

kill_pid() {
  local pid="$1" reason="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: would kill pid=$pid ($reason)"
    return 0
  fi
  if kill -9 "$pid" 2>/dev/null; then
    log "killed pid=$pid ($reason)"
    return 0
  fi
  log "kill failed pid=$pid ($reason)"
  return 1
}

declare -A KILLED=()

mark_killed() { KILLED[$1]=1; }
already_killed() { [[ -n "${KILLED[$1]+x}" ]]; }

# etimes по возрастанию: в конце самые долгие
mapfile -t RUNNERS < <(
  ps -C ollama -o pid=,etimes=,args= 2>/dev/null \
    | awk '/ollama runner/ {print $1":"$2}' \
    | sort -t: -k2 -n
)

if [[ ${#RUNNERS[@]} -eq 0 ]]; then
  exit 0
fi

declare -a MAIN_PIDS=()
declare -a MAIN_AGES=()

for entry in "${RUNNERS[@]}"; do
  pid="${entry%%:*}"
  age="${entry##*:}"
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  [[ "$age" =~ ^[0-9]+$ ]] || continue
  if is_check_runner_parent "$pid"; then
    continue
  fi
  MAIN_PIDS+=("$pid")
  MAIN_AGES+=("$age")
done

if [[ ${#MAIN_PIDS[@]} -eq 0 ]]; then
  exit 0
fi

killed_n=0

# 1) Дольше MAX_AGE (клиент бэка обычно рвёт на 600s)
for i in "${!MAIN_PIDS[@]}"; do
  pid="${MAIN_PIDS[$i]}"
  age="${MAIN_AGES[$i]}"
  if (( age >= MAX_AGE )) && ! already_killed "$pid"; then
    kill_pid "$pid" "age=${age}s >= max=${MAX_AGE}s" && mark_killed "$pid" && killed_n=$((killed_n + 1)) || true
  fi
done

# 2) Больше MAX_COUNT — убить самые старые (наибольший etimes)
if (( MAX_COUNT > 0 && ${#MAIN_PIDS[@]} > MAX_COUNT )); then
  excess=$((${#MAIN_PIDS[@]} - MAX_COUNT))
  for ((j = 0; j < excess; j++)); do
    idx=$((${#MAIN_PIDS[@]} - 1 - j))
    pid="${MAIN_PIDS[$idx]}"
    age="${MAIN_AGES[$idx]}"
    if (( age >= MIN_AGE )) && ! already_killed "$pid"; then
      kill_pid "$pid" "extra runner age=${age}s (max_count=${MAX_COUNT})" \
        && mark_killed "$pid" && killed_n=$((killed_n + 1)) || true
    fi
  done
fi

# 3) CPU-spin: огромный CPU при умеренном wall-time
clk="$(getconf CLK_TCK 2>/dev/null || echo 100)"
for i in "${!MAIN_PIDS[@]}"; do
  pid="${MAIN_PIDS[$i]}"
  age="${MAIN_AGES[$i]}"
  if already_killed "$pid"; then
    continue
  fi
  if (( age < MIN_AGE || age >= MAX_AGE )); then
    continue
  fi
  if [[ ! -r "/proc/${pid}/stat" ]]; then
    continue
  fi
  cpu_ticks="$(awk '{print $14+$15}' "/proc/${pid}/stat" 2>/dev/null || echo 0)"
  cpu_sec=$((cpu_ticks / clk))
  if (( age >= 300 && cpu_sec > age * 8 )); then
    kill_pid "$pid" "cpu_spin age=${age}s cpu=${cpu_sec}s" \
      && mark_killed "$pid" && killed_n=$((killed_n + 1)) || true
  fi
done

if (( killed_n > 0 )); then
  log "done: killed ${killed_n} runner(s)"
fi

exit 0
