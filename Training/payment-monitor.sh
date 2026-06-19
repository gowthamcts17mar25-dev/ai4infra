#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/payment-monitor.log"
THREAD_DUMP_FILE="/var/log/payment-monitor-thread-dump.log"
PID_FILE="/var/run/payment-monitor.pid"
STATE_FILE="/var/run/payment-monitor.state"
CHECK_URL="http://localhost:80"
CHECK_INTERVAL_SECONDS="30"
APACHE_SERVICE="apache2"

MODE="daemon"
DRY_RUN="false"
RUNNING="true"
ORIGINAL_APACHE_ACTIVE="unknown"

usage() {
  cat <<'EOF'
Usage: payment-monitor.sh [--daemon | --once | --rollback] [--dry-run]

Options:
  --daemon    Run continuously (default)
  --once      Run a single health check
  --rollback  Stop daemon loop (if running) and restore original apache state
  --dry-run   Print actions without making changes
  -h, --help  Show this help
EOF
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

ensure_log_files() {
  if [ "${DRY_RUN}" = "true" ]; then
    printf '[%s] [DRY-RUN] Would create log files: %s and %s\n' "$(timestamp)" "${LOG_FILE}" "${THREAD_DUMP_FILE}"
    return 0
  fi

  sudo mkdir -p "/var/log"
  sudo touch "${LOG_FILE}"
  sudo touch "${THREAD_DUMP_FILE}"
  sudo chmod 0644 "${LOG_FILE}" "${THREAD_DUMP_FILE}"
}

log() {
  local message="${1}"
  local line

  line="[$(timestamp)] ${message}"
  if [ "${DRY_RUN}" = "true" ]; then
    printf '%s\n' "${line}"
  else
    printf '%s\n' "${line}" | sudo tee -a "${LOG_FILE}" >/dev/null
  fi
}

run_cmd() {
  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would run: $*"
    return 0
  fi

  "$@"
}

load_original_state_from_system() {
  if sudo systemctl is-active --quiet "${APACHE_SERVICE}"; then
    ORIGINAL_APACHE_ACTIVE="active"
  else
    ORIGINAL_APACHE_ACTIVE="inactive"
  fi
}

persist_original_state() {
  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would persist original apache state (${ORIGINAL_APACHE_ACTIVE}) to ${STATE_FILE}"
    return 0
  fi

  printf 'ORIGINAL_APACHE_ACTIVE="%s"\n' "${ORIGINAL_APACHE_ACTIVE}" | sudo tee "${STATE_FILE}" >/dev/null
  sudo chmod 0644 "${STATE_FILE}"
}

load_original_state_from_file() {
  local raw_line
  local parsed_value

  if ! sudo test -f "${STATE_FILE}"; then
    return 1
  fi

  raw_line="$(sudo grep -E '^ORIGINAL_APACHE_ACTIVE=' "${STATE_FILE}" || true)"
  if [ -z "${raw_line}" ]; then
    return 1
  fi

  parsed_value="${raw_line#ORIGINAL_APACHE_ACTIVE=}" 
  parsed_value="${parsed_value#\"}"
  parsed_value="${parsed_value%\"}"

  if [ "${parsed_value}" = "active" ] || [ "${parsed_value}" = "inactive" ]; then
    ORIGINAL_APACHE_ACTIVE="${parsed_value}"
    return 0
  fi

  return 1
}

is_monitor_running() {
  local monitor_pid

  if ! sudo test -f "${PID_FILE}"; then
    return 1
  fi

  monitor_pid="$(sudo cat "${PID_FILE}")"
  if [ -z "${monitor_pid}" ]; then
    return 1
  fi

  if ps -p "${monitor_pid}" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

write_pid_file() {
  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would write daemon pid ($$) to ${PID_FILE}"
    return 0
  fi

  printf '%s\n' "$$" | sudo tee "${PID_FILE}" >/dev/null
  sudo chmod 0644 "${PID_FILE}"
}

remove_pid_file() {
  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would remove pid file ${PID_FILE}"
    return 0
  fi

  run_cmd sudo rm -f "${PID_FILE}"
}

capture_apache_thread_dump() {
  local apache_pids
  local pid
  local header

  apache_pids="$(pgrep -x "apache2" || true)"
  if [ -z "${apache_pids}" ]; then
    log "No apache2 process found for thread dump."
    return 0
  fi

  log "Capturing apache thread dump to ${THREAD_DUMP_FILE}."

  while IFS= read -r pid; do
    [ -z "${pid}" ] && continue
    header="===== $(timestamp) apache2 pid ${pid} ====="

    if [ "${DRY_RUN}" = "true" ]; then
      if command -v gstack >/dev/null 2>&1; then
        log "[DRY-RUN] Would run: sudo gstack ${pid} >> ${THREAD_DUMP_FILE}"
      elif command -v pstack >/dev/null 2>&1; then
        log "[DRY-RUN] Would run: sudo pstack ${pid} >> ${THREAD_DUMP_FILE}"
      elif command -v gdb >/dev/null 2>&1; then
        log "[DRY-RUN] Would run: sudo gdb -batch -ex 'thread apply all bt' -p ${pid} >> ${THREAD_DUMP_FILE}"
      else
        log "[DRY-RUN] Would run fallback: ps -Lp ${pid} -o pid,tid,pcpu,comm >> ${THREAD_DUMP_FILE}"
      fi
      continue
    fi

    printf '%s\n' "${header}" | sudo tee -a "${THREAD_DUMP_FILE}" >/dev/null
    if command -v gstack >/dev/null 2>&1; then
      sudo gstack "${pid}" | sudo tee -a "${THREAD_DUMP_FILE}" >/dev/null || true
    elif command -v pstack >/dev/null 2>&1; then
      sudo pstack "${pid}" | sudo tee -a "${THREAD_DUMP_FILE}" >/dev/null || true
    elif command -v gdb >/dev/null 2>&1; then
      sudo gdb -batch -ex 'thread apply all bt' -p "${pid}" | sudo tee -a "${THREAD_DUMP_FILE}" >/dev/null || true
    else
      ps -Lp "${pid}" -o pid,tid,pcpu,comm | sudo tee -a "${THREAD_DUMP_FILE}" >/dev/null || true
    fi
    printf '\n' | sudo tee -a "${THREAD_DUMP_FILE}" >/dev/null
  done <<< "${apache_pids}"
}

restart_apache() {
  log "Restarting ${APACHE_SERVICE} via systemctl."
  run_cmd sudo systemctl restart "${APACHE_SERVICE}"
}

check_health_once() {
  local http_code

  http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "${CHECK_URL}" || true)"
  if [ "${http_code}" = "200" ]; then
    log "Health check OK at ${CHECK_URL} (HTTP ${http_code})."
    return 0
  fi

  if [ -z "${http_code}" ]; then
    http_code="curl_error"
  fi

  log "Health check FAILED at ${CHECK_URL} (HTTP ${http_code})."
  capture_apache_thread_dump
  restart_apache
}

restore_apache_original_state() {
  local current_state

  if [ "${ORIGINAL_APACHE_ACTIVE}" = "unknown" ]; then
    if ! load_original_state_from_file; then
      log "Original apache state unknown; skipping apache state restore."
      return 0
    fi
  fi

  if sudo systemctl is-active --quiet "${APACHE_SERVICE}"; then
    current_state="active"
  else
    current_state="inactive"
  fi

  if [ "${current_state}" = "${ORIGINAL_APACHE_ACTIVE}" ]; then
    log "Apache state already matches original state (${ORIGINAL_APACHE_ACTIVE})."
    return 0
  fi

  if [ "${ORIGINAL_APACHE_ACTIVE}" = "active" ]; then
    log "Restoring apache to original state: active."
    run_cmd sudo systemctl start "${APACHE_SERVICE}"
  else
    log "Restoring apache to original state: inactive."
    run_cmd sudo systemctl stop "${APACHE_SERVICE}"
  fi
}

rollback() {
  local monitor_pid

  log "Rollback started (mode=${MODE})."
  RUNNING="false"

  if is_monitor_running; then
    monitor_pid="$(sudo cat "${PID_FILE}")"
    if [ "${monitor_pid}" != "$$" ]; then
      log "Stopping running monitor process ${monitor_pid}."
      run_cmd sudo kill "${monitor_pid}"
    fi
    remove_pid_file
  fi

  restore_apache_original_state

  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would remove state file ${STATE_FILE}"
  else
    run_cmd sudo rm -f "${STATE_FILE}"
  fi

  log "Rollback completed."
}

monitor_loop() {
  log "Starting payment monitor daemon loop."
  while [ "${RUNNING}" = "true" ]; do
    check_health_once
    sleep "${CHECK_INTERVAL_SECONDS}"
  done
}

parse_args() {
  local mode_count="0"

  while [ "$#" -gt 0 ]; do
    case "${1}" in
      --daemon)
        MODE="daemon"
        mode_count="$((mode_count + 1))"
        ;;
      --once)
        MODE="once"
        mode_count="$((mode_count + 1))"
        ;;
      --rollback)
        MODE="rollback"
        mode_count="$((mode_count + 1))"
        ;;
      --dry-run)
        DRY_RUN="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown argument: %s\n' "${1}" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done

  if [ "${mode_count}" -gt 1 ]; then
    printf 'Choose only one mode: --daemon, --once, or --rollback\n' >&2
    exit 1
  fi
}

main() {
  parse_args "$@"
  ensure_log_files

  if [ "${MODE}" = "rollback" ]; then
    rollback
    exit 0
  fi

  load_original_state_from_system
  persist_original_state

  if [ "${MODE}" = "once" ]; then
    trap 'rollback' INT TERM ERR
    log "Running single health check mode."
    check_health_once
    log "Single health check completed."
    if [ "${DRY_RUN}" = "false" ]; then
      run_cmd sudo rm -f "${STATE_FILE}"
    fi
    exit 0
  fi

  if is_monitor_running; then
    log "Monitor already running. Exiting without starting another instance."
    exit 0
  fi

  write_pid_file
  trap 'rollback' INT TERM
  monitor_loop
}

main "$@"
