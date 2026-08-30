#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/shutdown"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-shutdown.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

BIN_DIR="${TMP_DIR}/bin"
ACTION_LOG="${TMP_DIR}/actions.log"
STDOUT_LOG="${TMP_DIR}/stdout.log"
STDERR_LOG="${TMP_DIR}/stderr.log"
RUNTIME_DIR="${TMP_DIR}/runtime"
TEST_COUNT=3
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

install -d -m 0700 "$BIN_DIR" "$RUNTIME_DIR"

for command_name in systemctl pkill gio wl-copy sync fusermount fusermount3 umount kill; do
  cat >"${BIN_DIR}/${command_name}" <<'EOF'
#!/bin/sh
set -eu
printf '%s %s\n' "${0##*/}" "$*" >>"$ACTION_LOG"
EOF
  chmod 0700 "${BIN_DIR}/${command_name}"
done

run_case() {
  shutdown_mode=$1
  : >"$ACTION_LOG"
  : >"$STDOUT_LOG"
  : >"$STDERR_LOG"
  PATH="${BIN_DIR}:/usr/bin:/bin" \
  ACTION_LOG="$ACTION_LOG" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    /bin/sh "$SCRIPT" "$shutdown_mode" >"$STDOUT_LOG" 2>"$STDERR_LOG"
}

assert_no_manual_teardown() {
  [ ! -s "$ACTION_LOG" ] &&
    [ ! -s "$STDOUT_LOG" ] &&
    [ ! -s "$STDERR_LOG" ]
}

printf '1..%s\n' "$TEST_COUNT"

run_case logout
if assert_no_manual_teardown; then
  pass "logout leaves session teardown entirely to systemd"
else
  fail "logout leaves session teardown entirely to systemd"
fi

run_case power-transition
if assert_no_manual_teardown; then
  pass "power transitions do not race systemd with manual teardown"
else
  fail "power transitions do not race systemd with manual teardown"
fi

: >"$ACTION_LOG"
: >"$STDOUT_LOG"
: >"$STDERR_LOG"
if PATH="${BIN_DIR}:/usr/bin:/bin" \
   ACTION_LOG="$ACTION_LOG" \
   XDG_RUNTIME_DIR="$RUNTIME_DIR" \
     /bin/sh "$SCRIPT" invalid-mode >"$STDOUT_LOG" 2>"$STDERR_LOG"; then
  fail "unsupported shutdown modes are rejected before any action"
elif [ ! -s "$ACTION_LOG" ] &&
     [ ! -s "$STDOUT_LOG" ] &&
     grep -Fq 'fatal: unsupported Labwc shutdown mode: invalid-mode' "$STDERR_LOG"; then
  pass "unsupported shutdown modes are rejected before any action"
else
  fail "unsupported shutdown modes are rejected before any action"
fi
