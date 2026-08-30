#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-admin-action"
ROOT_HELPER="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-admin-action-root"
WORKER="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-admin-action-worker"
WORKER_UNIT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/etc/systemd/system/labwc-admin-action@.service"
POWER_MENU="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-power-menu"
WAYBAR_CONFIG="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
AUTOSTART="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
HYPR_DROPIN="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/etc/systemd/user/hyprpolkitagent.service.d/10-labwc-session.conf"
POWER_RULE="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/03-labwc-power.rules"
FIRSTBOOT_VALIDATION="${ROOT_DIR}/d-i/forky/scripts/firstboot/04-validation.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-admin-action.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=21
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

make_case() {
  case_name=$1
  case_dir="${TMP_DIR}/${case_name}"
  bin_dir="${case_dir}/bin"
  test_root_helper="${case_dir}/labwc-admin-action-root"

  install -d -m 0700 "$bin_dir" "${case_dir}/runtime"
  : >"${case_dir}/actions.log"
  : >"${case_dir}/notifications.log"
  : >"${case_dir}/stdout.log"
  : >"${case_dir}/stderr.log"

  cat >"${bin_dir}/pkexec" <<'SH'
#!/bin/sh
set -eu
printf 'pkexec %s\n' "$*" >>"${ACTION_LOG:?}"
exit "${PKEXEC_EXIT_STATUS:-0}"
SH
  chmod 0700 "${bin_dir}/pkexec"

  cat >"${bin_dir}/notify-send" <<'SH'
#!/bin/sh
set -eu
{
  printf '%s\n' 'notify-send'
  for argument
  do
    printf '<%s>\n' "$argument"
  done
} >>"${NOTIFY_LOG:?}"
exit "${NOTIFY_EXIT_STATUS:-0}"
SH
  chmod 0700 "${bin_dir}/notify-send"

  printf '#!/bin/sh\nexit 0\n' >"$test_root_helper"
  chmod 0700 "$test_root_helper"
  sed \
    -e "s|/usr/bin/pkexec|${bin_dir}/pkexec|g" \
    -e "s|/usr/local/libexec/labwc-admin-action-root|${test_root_helper}|g" \
    "$SCRIPT" >"${case_dir}/labwc-admin-action"
  chmod 0700 "${case_dir}/labwc-admin-action"

  printf '%s\n' "$case_dir"
}

run_case() {
  case_dir=$1
  shift
  : >"${case_dir}/actions.log"
  : >"${case_dir}/notifications.log"
  : >"${case_dir}/stdout.log"
  : >"${case_dir}/stderr.log"

  if /usr/bin/env -i \
    PATH="${case_dir}/bin:/usr/bin:/bin" \
    ACTION_LOG="${case_dir}/actions.log" \
	    NOTIFY_LOG="${case_dir}/notifications.log" \
	    XDG_RUNTIME_DIR="${case_dir}/runtime" \
    PKEXEC_EXIT_STATUS="${TEST_PKEXEC_EXIT_STATUS:-0}" \
    NOTIFY_EXIT_STATUS="${TEST_NOTIFY_EXIT_STATUS:-0}" \
    /bin/sh "${case_dir}/labwc-admin-action" "$@" \
    >"${case_dir}/stdout.log" \
    2>"${case_dir}/stderr.log"
  then
    CASE_STATUS=0
  else
    CASE_STATUS=$?
  fi
}

expected_request() {
  case_dir=$1
  requested_action=$2
  printf 'pkexec %s %s\n' "${case_dir}/labwc-admin-action-root" "$requested_action"
}

expected_failure_notification() {
  requested_action=$1
  request_status=$2
  cat <<EOF_NOTIFICATION
notify-send
<-a>
<Desktop Power>
<-u>
<critical>
<-i>
<system-shutdown>
<-c>
<x-labwc.power>
<-t>
<0>
<Power request failed>
<The ${requested_action} request was cancelled or failed (status ${request_status}).>
EOF_NOTIFICATION
}

make_root_case() {
  case_name=$1
  case_dir="${TMP_DIR}/${case_name}"
  bin_dir="${case_dir}/bin"

  install -d -m 0700 "$bin_dir"
  : >"${case_dir}/actions.log"
  : >"${case_dir}/stdout.log"
  : >"${case_dir}/stderr.log"

  cat >"${bin_dir}/id" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 1 ] && [ "$1" = -u ] || exit 64
printf '%s\n' "${ROOT_ID_UID:-0}"
SH
  cat >"${bin_dir}/getent" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 2 ] && [ "$1" = passwd ] || exit 64
[ "${ROOT_GETENT_STATUS:-0}" -eq 0 ] || exit "$ROOT_GETENT_STATUS"
printf 'desktop:x:%s:1000:Desktop:/home/desktop:/bin/sh\n' "$2"
SH
  cat >"${bin_dir}/systemctl" <<'SH'
#!/bin/sh
set -eu
printf 'systemctl %s\n' "$*" >>"${ACTION_LOG:?}"
exit "${ROOT_SYSTEMCTL_STATUS:-0}"
SH
  chmod 0700 \
    "${bin_dir}/id" \
    "${bin_dir}/getent" \
    "${bin_dir}/systemctl"

  sed \
    -e "s|/usr/bin/id|${bin_dir}/id|g" \
    -e "s|/usr/bin/getent|${bin_dir}/getent|g" \
    -e "s|/usr/bin/systemctl|${bin_dir}/systemctl|g" \
    "$ROOT_HELPER" >"${case_dir}/labwc-admin-action-root"
  chmod 0700 "${case_dir}/labwc-admin-action-root"
  printf '%s\n' "$case_dir"
}

run_root_case() {
  case_dir=$1
  invoker_uid=$2
  shift 2
  : >"${case_dir}/actions.log"
  : >"${case_dir}/stdout.log"
  : >"${case_dir}/stderr.log"

  if [ "$invoker_uid" = unset ]; then
    if /usr/bin/env -i \
      ACTION_LOG="${case_dir}/actions.log" \
      ROOT_ID_UID="${TEST_ROOT_ID_UID:-0}" \
      ROOT_GETENT_STATUS="${TEST_ROOT_GETENT_STATUS:-0}" \
      ROOT_SYSTEMCTL_STATUS="${TEST_ROOT_SYSTEMCTL_STATUS:-0}" \
      /bin/sh "${case_dir}/labwc-admin-action-root" "$@" \
      >"${case_dir}/stdout.log" 2>"${case_dir}/stderr.log"
    then ROOT_CASE_STATUS=0; else ROOT_CASE_STATUS=$?; fi
  else
    if /usr/bin/env -i \
      PKEXEC_UID="$invoker_uid" \
      ACTION_LOG="${case_dir}/actions.log" \
      ROOT_ID_UID="${TEST_ROOT_ID_UID:-0}" \
      ROOT_GETENT_STATUS="${TEST_ROOT_GETENT_STATUS:-0}" \
      ROOT_SYSTEMCTL_STATUS="${TEST_ROOT_SYSTEMCTL_STATUS:-0}" \
      /bin/sh "${case_dir}/labwc-admin-action-root" "$@" \
      >"${case_dir}/stdout.log" 2>"${case_dir}/stderr.log"
    then ROOT_CASE_STATUS=0; else ROOT_CASE_STATUS=$?; fi
  fi
}

expected_root_action_log() {
  invoker_uid=$1
  requested_action=$2
  printf 'systemctl --no-block start labwc-admin-action@%s-%s.service\n' \
    "$invoker_uid" "$requested_action"
}

make_worker_case() {
  case_name=$1
  case_dir="${TMP_DIR}/${case_name}"
  bin_dir="${case_dir}/bin"

  install -d -m 0700 "$bin_dir"
  : >"${case_dir}/actions.log"
  : >"${case_dir}/stdout.log"
  : >"${case_dir}/stderr.log"

  cat >"${bin_dir}/id" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 1 ] && [ "$1" = -u ] || exit 64
printf '%s\n' "${WORKER_ID_UID:-0}"
SH
  cat >"${bin_dir}/getent" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 2 ] && [ "$1" = passwd ] || exit 64
[ "${WORKER_GETENT_STATUS:-0}" -eq 0 ] || exit "$WORKER_GETENT_STATUS"
printf 'desktop:x:%s:1000:Desktop:/home/desktop:/bin/sh\n' "$2"
SH
  cat >"${bin_dir}/systemctl" <<'SH'
#!/bin/sh
set -eu
printf 'systemctl %s\n' "$*" >>"${ACTION_LOG:?}"
case "${1:-}" in
  --user) exit "${WORKER_SESSION_SYSTEMCTL_STATUS:-0}" ;;
  *) exit "${WORKER_POWER_SYSTEMCTL_STATUS:-0}" ;;
esac
SH
  cat >"${bin_dir}/timeout" <<'SH'
#!/bin/sh
set -eu
printf 'timeout %s\n' "$*" >>"${ACTION_LOG:?}"
[ "$#" -ge 5 ] || exit 64
shift 4
exec "$@"
SH
  chmod 0700 \
    "${bin_dir}/id" \
    "${bin_dir}/getent" \
    "${bin_dir}/systemctl" \
    "${bin_dir}/timeout"

  sed \
    -e "s|/usr/bin/id|${bin_dir}/id|g" \
    -e "s|/usr/bin/getent|${bin_dir}/getent|g" \
    -e "s|/usr/bin/systemctl|${bin_dir}/systemctl|g" \
    -e "s|/usr/bin/timeout|${bin_dir}/timeout|g" \
    "$WORKER" >"${case_dir}/labwc-admin-action-worker"
  chmod 0700 "${case_dir}/labwc-admin-action-worker"
  printf '%s\n' "$case_dir"
}

run_worker_case() {
  case_dir=$1
  shift
  : >"${case_dir}/actions.log"
  : >"${case_dir}/stdout.log"
  : >"${case_dir}/stderr.log"

  if /usr/bin/env -i \
    ACTION_LOG="${case_dir}/actions.log" \
    WORKER_ID_UID="${TEST_WORKER_ID_UID:-0}" \
    WORKER_GETENT_STATUS="${TEST_WORKER_GETENT_STATUS:-0}" \
    WORKER_SESSION_SYSTEMCTL_STATUS="${TEST_WORKER_SESSION_SYSTEMCTL_STATUS:-0}" \
    WORKER_POWER_SYSTEMCTL_STATUS="${TEST_WORKER_POWER_SYSTEMCTL_STATUS:-0}" \
    /bin/sh "${case_dir}/labwc-admin-action-worker" "$@" \
    >"${case_dir}/stdout.log" 2>"${case_dir}/stderr.log"
  then WORKER_CASE_STATUS=0; else WORKER_CASE_STATUS=$?; fi
}

expected_worker_action_log() {
  case_dir=$1
  requested_action=$2

  case "$requested_action" in
    suspend)
      printf 'systemctl --no-block suspend\n'
      ;;
    reboot|poweroff)
      cat <<EOF_ACTIONS
timeout --foreground --signal=TERM --kill-after=5s 45s ${case_dir}/bin/systemctl --user --machine=desktop@.host --no-ask-password --quiet stop labwc-session.target
systemctl --user --machine=desktop@.host --no-ask-password --quiet stop labwc-session.target
systemctl --no-block ${requested_action}
EOF_ACTIONS
      ;;
  esac
}

printf '1..%s\n' "$TEST_COUNT"

# These assertions intentionally match literal shell and Polkit source.
# shellcheck disable=SC2016
if /bin/sh -n "$SCRIPT" &&
   /bin/sh -n "$ROOT_HELPER" &&
   /bin/sh -n "$WORKER" &&
   /bin/sh -n "$POWER_MENU" &&
   [ "$(grep -Fc '"on-click": "labwc-power-menu"' "$WAYBAR_CONFIG")" -eq 2 ] &&
   grep -Fq 'exec labwc-admin-action suspend' "$POWER_MENU" &&
   grep -Fq 'exec labwc-admin-action reboot' "$POWER_MENU" &&
   grep -Fq 'exec labwc-admin-action poweroff' "$POWER_MENU" &&
	   grep -Fqx 'pkexec_cmd=/usr/bin/pkexec' "$SCRIPT" &&
	   grep -Fqx 'root_helper=/usr/local/libexec/labwc-admin-action-root' "$SCRIPT" &&
	   grep -Fq 'power_lock="${runtime_dir%/}/labwc-admin-action.lock"' "$SCRIPT" &&
	   grep -Fq 'if ! /usr/bin/flock --nonblock 9; then' "$SCRIPT" &&
	   grep -Fq 'if "$pkexec_cmd" "$root_helper" "$action"; then' "$SCRIPT" &&
	   ! grep -Eq 'systemctl|LABWC_SESSION_OWNER|XDG_SESSION_TYPE|LABWC_PID|WAYLAND_DISPLAY' "$SCRIPT" &&
	   grep -Fq '[ "$(/usr/bin/id -u)" -eq 0 ]' "$ROOT_HELPER" &&
	   grep -Fq 'invoker_passwd=$(/usr/bin/getent passwd "$PKEXEC_UID" 2>/dev/null)' "$ROOT_HELPER" &&
	   grep -Fq 'worker_unit="labwc-admin-action@${PKEXEC_UID}-${action}.service"' "$ROOT_HELPER" &&
	   grep -Fq 'exec /usr/bin/systemctl --no-block start "$worker_unit"' "$ROOT_HELPER" &&
   ! grep -Eq 'timeout|--machine=|labwc-session[.]target|systemctl "\$action"' "$ROOT_HELPER" &&
   grep -Fq '[ "$(/usr/bin/id -u)" -eq 0 ]' "$WORKER" &&
   grep -Fq 'session_machine="${invoker_name}@.host"' "$WORKER" &&
   grep -Fq '/usr/bin/timeout \' "$WORKER" &&
   grep -Fq -- '--machine="$session_machine" \' "$WORKER" &&
   grep -Fq 'labwc-session.target || session_stop_status=$?' "$WORKER" &&
   grep -Fq 'exec /usr/bin/systemctl --no-block "$action"' "$WORKER" &&
   grep -Fqx 'ExecStart=/usr/local/libexec/labwc-admin-action-worker %i' "$WORKER_UNIT" &&
   grep -Fqx 'AppArmorProfile=managed-labwc-admin-action-worker' "$WORKER_UNIT" &&
   grep -Fqx 'NoNewPrivileges=yes' "$WORKER_UNIT" &&
   grep -Fqx 'ProtectSystem=strict' "$WORKER_UNIT" &&
   grep -Fq '/usr/local/libexec/labwc-admin-action-worker \' "$FIRSTBOOT_VALIDATION" &&
   grep -Fq '/etc/systemd/system/labwc-admin-action@.service \' "$FIRSTBOOT_VALIDATION" &&
   ! grep -Eq 'eval|/bin/(ba)?sh -c|--force' "$ROOT_HELPER" &&
   ! grep -Eq 'eval|/bin/(ba)?sh -c|--force' "$WORKER" &&
   grep -Fq 'var POWER_HELPER = "/usr/local/libexec/labwc-admin-action-root";' "$POWER_RULE" &&
   grep -Fq 'lookupString(action, "program") !== POWER_HELPER' "$POWER_RULE" &&
   grep -Fq 'return polkit.Result.AUTH_ADMIN;' "$POWER_RULE" &&
   ! grep -Eq 'subject\.(active|local|seat)' "$POWER_RULE" &&
   grep -Fq "required_session_units='labwc-kwallet-portal.service hyprpolkitagent.service " "$AUTOSTART" &&
   grep -Fqx 'Restart=on-failure' "$HYPR_DROPIN"; then
	  pass "Waybar keeps its protected entrypoint while PID 1 owns authenticated session pre-drain and power actions"
else
	  fail "Waybar keeps its protected entrypoint while PID 1 owns authenticated session pre-drain and power actions"
fi

for requested_action in reboot poweroff suspend; do
  case_dir=$(make_case "${requested_action}-success")
  run_case "$case_dir" "$requested_action"
  if [ "$CASE_STATUS" -eq 0 ] &&
     [ "$(cat "${case_dir}/actions.log")" = "$(expected_request "$case_dir" "$requested_action")" ] &&
     [ ! -s "${case_dir}/notifications.log" ]; then
    pass "${requested_action} reaches the foreground password path without display-manager session metadata"
  else
    fail "${requested_action} reaches the foreground password path without display-manager session metadata"
  fi
done

case_dir=$(make_case concurrent-request)
exec 8>"${case_dir}/runtime/labwc-admin-action.lock"
/usr/bin/flock --nonblock 8
run_case "$case_dir" poweroff
/usr/bin/flock --unlock 8
exec 8>&-
if [ "$CASE_STATUS" -eq 1 ] &&
   [ ! -s "${case_dir}/actions.log" ] &&
   grep -Fq 'fatal: another desktop power request is already awaiting authorization' "${case_dir}/stderr.log" &&
   grep -Fq '<another desktop power request is already awaiting authorization>' "${case_dir}/notifications.log"; then
  pass "concurrent Waybar clicks cannot start competing Polkit conversations"
else
  fail "concurrent Waybar clicks cannot start competing Polkit conversations"
fi

case_dir=$(make_case authorization-denied)
TEST_PKEXEC_EXIT_STATUS=2 run_case "$case_dir" reboot
unset TEST_PKEXEC_EXIT_STATUS
if [ "$CASE_STATUS" -eq 2 ] &&
   [ "$(cat "${case_dir}/actions.log")" = "$(expected_request "$case_dir" reboot)" ] &&
   [ "$(cat "${case_dir}/notifications.log")" = "$(expected_failure_notification reboot 2)" ]; then
  pass "denied or cancelled authentication is visible and propagates without session manipulation"
else
  fail "denied or cancelled authentication is visible and propagates without session manipulation"
fi

case_dir=$(make_case invalid-action)
run_case "$case_dir" invalid
if [ "$CASE_STATUS" -eq 1 ] &&
   [ ! -s "${case_dir}/actions.log" ] &&
   grep -Fq 'fatal: unsupported privileged desktop action: invalid' "${case_dir}/stderr.log"; then
  pass "unsupported client actions fail before authentication"
else
  fail "unsupported client actions fail before authentication"
fi

case_dir=$(make_case missing-action)
run_case "$case_dir"
if [ "$CASE_STATUS" -eq 1 ] &&
   [ ! -s "${case_dir}/actions.log" ] &&
   grep -Fq 'fatal: usage: labwc-admin-action <suspend|reboot|poweroff>' "${case_dir}/stderr.log"; then
  pass "a missing client action fails with the bounded usage contract"
else
  fail "a missing client action fails with the bounded usage contract"
fi

case_dir=$(make_case extra-argument)
run_case "$case_dir" reboot --force
if [ "$CASE_STATUS" -eq 1 ] &&
   [ ! -s "${case_dir}/actions.log" ] &&
   grep -Fq 'fatal: usage: labwc-admin-action <suspend|reboot|poweroff>' "${case_dir}/stderr.log"; then
  pass "extra client arguments cannot inject power-transition options"
else
  fail "extra client arguments cannot inject power-transition options"
fi

root_case=$(make_root_case supported-root-actions)
root_actions_ok=true
for requested_action in suspend reboot poweroff; do
	  run_root_case "$root_case" 1000 "$requested_action"
	  if [ "$ROOT_CASE_STATUS" -ne 0 ] ||
	     [ "$(cat "${root_case}/actions.log")" != "$(expected_root_action_log 1000 "$requested_action")" ]; then
    root_actions_ok=false
    break
  fi
done
if [ "$root_actions_ok" = true ]; then
	  pass "the authenticated root helper queues only fixed PID-1-owned worker instances"
else
	  fail "the authenticated root helper queues only fixed PID-1-owned worker instances"
fi

root_case=$(make_root_case invalid-root-action)
run_root_case "$root_case" 1000 invalid
if [ "$ROOT_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${root_case}/actions.log" ] &&
   grep -Fq 'fatal: unsupported privileged power action: invalid' "${root_case}/stderr.log"; then
  pass "the root helper rejects unsupported actions before systemctl"
else
  fail "the root helper rejects unsupported actions before systemctl"
fi

root_invoker_rejected=true
for invoker_uid in unset 0 00 invalid; do
  root_case=$(make_root_case "invalid-invoker-${invoker_uid}")
  run_root_case "$root_case" "$invoker_uid" reboot
  if [ "$ROOT_CASE_STATUS" -ne 1 ] ||
     [ -s "${root_case}/actions.log" ] ||
     ! grep -Fq 'fatal: privileged power helper must be invoked by a non-root user through pkexec' "${root_case}/stderr.log"; then
    root_invoker_rejected=false
    break
  fi
done
if [ "$root_invoker_rejected" = true ]; then
  pass "the root helper rejects missing, root, and malformed pkexec identities"
else
  fail "the root helper rejects missing, root, and malformed pkexec identities"
fi

root_case=$(make_root_case unknown-invoker)
TEST_ROOT_GETENT_STATUS=2 run_root_case "$root_case" 9999 poweroff
unset TEST_ROOT_GETENT_STATUS
if [ "$ROOT_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${root_case}/actions.log" ] &&
   grep -Fq 'fatal: pkexec invoking account does not exist: 9999' "${root_case}/stderr.log"; then
  pass "the root helper rejects nonexistent invoking accounts"
else
  fail "the root helper rejects nonexistent invoking accounts"
fi

root_case=$(make_root_case non-root-helper)
TEST_ROOT_ID_UID=1000 run_root_case "$root_case" 1000 suspend
unset TEST_ROOT_ID_UID
if [ "$ROOT_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${root_case}/actions.log" ] &&
   grep -Fq 'fatal: privileged power helper must run as root' "${root_case}/stderr.log"; then
  pass "the privileged helper refuses non-root execution"
else
  fail "the privileged helper refuses non-root execution"
fi

root_case=$(make_root_case extra-root-argument)
run_root_case "$root_case" 1000 reboot --force
if [ "$ROOT_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${root_case}/actions.log" ] &&
   grep -Fq 'fatal: usage: labwc-admin-action-root <suspend|reboot|poweroff>' "${root_case}/stderr.log"; then
  pass "extra root-helper arguments cannot inject systemctl options"
else
  fail "extra root-helper arguments cannot inject systemctl options"
fi

worker_case=$(make_worker_case supported-worker-actions)
worker_actions_ok=true
for requested_action in suspend reboot poweroff; do
  run_worker_case "$worker_case" "1000-${requested_action}"
  if [ "$WORKER_CASE_STATUS" -ne 0 ] ||
     [ "$(cat "${worker_case}/actions.log")" != "$(expected_worker_action_log "$worker_case" "$requested_action")" ]; then
    worker_actions_ok=false
    break
  fi
done
if [ "$worker_actions_ok" = true ]; then
  pass "the PID-1 worker pre-drains only reboot and power-off before queuing the exact system action"
else
  fail "the PID-1 worker pre-drains only reboot and power-off before queuing the exact system action"
fi

worker_case=$(make_worker_case failed-session-predrain)
TEST_WORKER_SESSION_SYSTEMCTL_STATUS=5 run_worker_case "$worker_case" 1000-poweroff
unset TEST_WORKER_SESSION_SYSTEMCTL_STATUS
if [ "$WORKER_CASE_STATUS" -eq 0 ] &&
   [ "$(cat "${worker_case}/actions.log")" = "$(expected_worker_action_log "$worker_case" poweroff)" ] &&
   grep -Fq 'warning: managed desktop session did not stop cleanly before poweroff (status 5)' "${worker_case}/stderr.log"; then
  pass "a bounded worker pre-drain failure cannot strand an already-authorized power-off"
else
  fail "a bounded worker pre-drain failure cannot strand an already-authorized power-off"
fi

worker_instances_rejected=true
for worker_instance in invalid 0-reboot 00-poweroff invalid-suspend 1000-invalid 1000-reboot-poweroff; do
  worker_case=$(make_worker_case "invalid-worker-instance-${worker_instance}")
  run_worker_case "$worker_case" "$worker_instance"
  if [ "$WORKER_CASE_STATUS" -ne 1 ] || [ -s "${worker_case}/actions.log" ]; then
    worker_instances_rejected=false
    break
  fi
done
if [ "$worker_instances_rejected" = true ]; then
  pass "the PID-1 worker rejects malformed UID and action instance tokens before systemctl"
else
  fail "the PID-1 worker rejects malformed UID and action instance tokens before systemctl"
fi

worker_case=$(make_worker_case unknown-worker-account)
TEST_WORKER_GETENT_STATUS=2 run_worker_case "$worker_case" 9999-reboot
unset TEST_WORKER_GETENT_STATUS
if [ "$WORKER_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${worker_case}/actions.log" ] &&
   grep -Fq 'fatal: system power worker account does not exist: 9999' "${worker_case}/stderr.log"; then
  pass "the PID-1 worker rejects nonexistent account identities"
else
  fail "the PID-1 worker rejects nonexistent account identities"
fi

worker_case=$(make_worker_case non-root-worker)
TEST_WORKER_ID_UID=1000 run_worker_case "$worker_case" 1000-suspend
unset TEST_WORKER_ID_UID
if [ "$WORKER_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${worker_case}/actions.log" ] &&
   grep -Fq 'fatal: system power worker must run as root' "${worker_case}/stderr.log"; then
  pass "the PID-1 power worker refuses non-root execution"
else
  fail "the PID-1 power worker refuses non-root execution"
fi

worker_case=$(make_worker_case extra-worker-argument)
run_worker_case "$worker_case" 1000-reboot --force
if [ "$WORKER_CASE_STATUS" -eq 1 ] &&
   [ ! -s "${worker_case}/actions.log" ] &&
   grep -Fq 'fatal: usage: labwc-admin-action-worker <uid>-<suspend|reboot|poweroff>' "${worker_case}/stderr.log"; then
  pass "extra worker arguments cannot inject systemctl options"
else
  fail "extra worker arguments cannot inject systemctl options"
fi
