#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="/var/log/connectivity-check.log"
LOCK_FILE="/tmp/connectivity-check.lock"
DRY_RUN="false"
CRITICAL_ONLY="false"

TIMEOUT_SECONDS="5"
PING_COUNT="3"
PING_TIMEOUT_SECONDS="5"
NC_TIMEOUT_SECONDS="5"

PASS_COUNT="0"
FAIL_COUNT="0"
SKIP_COUNT="0"
CRITICAL_FAILURES="0"

usage() {
  cat <<'EOF'
Usage: connectivity-check.sh [--once] [--dry-run] [--critical-only] [-h|--help]

Options:
  --once           Run checks once (default behavior)
  --dry-run        Print what checks would run without running them
  --critical-only  Run only critical checks
  -h, --help       Show this help message
EOF
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

log_line() {
  local line="${1}"
  printf '%s\n' "${line}" | sudo tee -a "${LOG_FILE}" >/dev/null
  printf '%s\n' "${line}"
}

init_log_file() {
  if ! sudo mkdir -p "/var/log"; then
    printf '[%s] [FAIL] Unable to create /var/log for log file.\n' "$(timestamp)" >&2
    exit 1
  fi

  if ! sudo touch "${LOG_FILE}"; then
    printf '[%s] [FAIL] Unable to create log file %s.\n' "$(timestamp)" "${LOG_FILE}" >&2
    exit 1
  fi

  if ! sudo chmod 0644 "${LOG_FILE}"; then
    printf '[%s] [FAIL] Unable to set permissions on log file %s.\n' "$(timestamp)" "${LOG_FILE}" >&2
    exit 1
  fi
}

acquire_lock() {
  if [ "${DRY_RUN}" = "true" ]; then
    return 0
  fi

  # Keep fd 9 open for the full process lifetime to hold the lock.
  exec 9>"${LOCK_FILE}"
  if flock -n 9; then
    return 0
  fi

  return 1
}

record_pass() {
  local label="${1}"
  PASS_COUNT="$((PASS_COUNT + 1))"
  log_line "[$(timestamp)] [PASS] ${label}"
}

record_fail() {
  local label="${1}"
  local critical="${2}"
  FAIL_COUNT="$((FAIL_COUNT + 1))"
  if [ "${critical}" = "true" ]; then
    CRITICAL_FAILURES="$((CRITICAL_FAILURES + 1))"
  fi
  log_line "[$(timestamp)] [FAIL] ${label}"
}

record_skip() {
  local label="${1}"
  SKIP_COUNT="$((SKIP_COUNT + 1))"
  log_line "[$(timestamp)] [SKIP] ${label}"
}

run_check() {
  local label="${1}"
  local critical="${2}"
  shift 2

  if [ "${CRITICAL_ONLY}" = "true" ] && [ "${critical}" = "false" ]; then
    record_skip "${label} (skipped by --critical-only)"
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    record_skip "${label} (dry-run: would run: $*)"
    return 0
  fi

  if "$@"; then
    record_pass "${label}"
    return 0
  fi

  record_fail "${label}" "${critical}"
  return 1
}

check_ping() {
  local target="${1}"
  timeout "${TIMEOUT_SECONDS}" ping -c "${PING_COUNT}" -W "${PING_TIMEOUT_SECONDS}" "${target}" >/dev/null 2>&1
}

check_port() {
  local host="${1}"
  local port="${2}"
  timeout "${TIMEOUT_SECONDS}" nc -zv -w "${NC_TIMEOUT_SECONDS}" "${host}" "${port}" >/dev/null 2>&1
}

check_dns() {
  timeout "${TIMEOUT_SECONDS}" nslookup "google.com" >/dev/null 2>&1
}

check_default_route() {
  local route_output=""

  route_output="$(ip route show)"
  if printf '%s\n' "${route_output}" | grep -q "^default"; then
    return 0
  fi

  return 1
}

check_tc_no_latency() {
  local qdisc_output=""

  qdisc_output="$(tc qdisc show dev "eth0" 2>&1)"
  if printf '%s\n' "${qdisc_output}" | grep -q "netem"; then
    if printf '%s\n' "${qdisc_output}" | grep -q "delay"; then
      return 1
    fi
  fi

  return 0
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "${1}" in
      --once)
        # Default behavior is single-run; accept flag for compatibility.
        ;;
      --dry-run)
        DRY_RUN="true"
        ;;
      --critical-only)
        CRITICAL_ONLY="true"
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
}

run_all_checks() {
  log_line "[$(timestamp)] Starting connectivity validation. dry_run=${DRY_RUN} critical_only=${CRITICAL_ONLY}"

  run_check "Ping gateway 10.0.0.1" "true" check_ping "10.0.0.1"
  run_check "Ping self 10.0.0.4" "true" check_ping "10.0.0.4"
  run_check "Ping internet 8.8.8.8" "true" check_ping "8.8.8.8"

  run_check "Ping app server 10.0.1.10" "false" check_ping "10.0.1.10"
  run_check "Ping DB server 10.0.2.10" "false" check_ping "10.0.2.10"

  run_check "TCP check PostgreSQL 10.0.2.10:5432" "false" check_port "10.0.2.10" "5432"
  run_check "TCP check app health 10.0.1.10:8080" "false" check_port "10.0.1.10" "8080"

  run_check "DNS resolution nslookup google.com" "true" check_dns
  run_check "Default route exists" "true" check_default_route
  run_check "tc qdisc has no artificial latency on eth0" "false" check_tc_no_latency
}

print_summary() {
  log_line "[$(timestamp)] Summary: passed=${PASS_COUNT} failed=${FAIL_COUNT} skipped=${SKIP_COUNT}"

  if [ "${CRITICAL_FAILURES}" -gt 0 ]; then
    log_line "[$(timestamp)] Critical check failures detected: ${CRITICAL_FAILURES}. Exiting with code 1."
    return 1
  fi

  log_line "[$(timestamp)] No critical check failures detected. Exiting with code 0."
  return 0
}

main() {
  parse_args "$@"
  init_log_file

  if ! acquire_lock; then
    SKIP_COUNT="$((SKIP_COUNT + 1))"
    log_line "[$(timestamp)] [SKIP] Another connectivity-check instance is already running. Exiting idempotently."
    print_summary
    exit 0
  fi

  run_all_checks
  if print_summary; then
    exit 0
  fi
  exit 1
}

main "$@"
