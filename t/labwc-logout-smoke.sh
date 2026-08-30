#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-logout"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-logout.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=2
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

case_dir="${TMP_DIR}/logout"
bin_dir="${case_dir}/bin"
home_dir="${case_dir}/home"
log_file="${case_dir}/actions.log"

mkdir -p "$bin_dir" "$home_dir/.config/labwc"
: >"$log_file"

cat >"${bin_dir}/labwc" <<'EOF'
#!/bin/sh
set -eu
[ "${LABWC_SESSION_OWNER:-}" = desktop ]
[ "${LABWC_PID:-}" = 4242 ]
printf 'labwc %s\n' "$*" >>"$ACTION_LOG"
exit 0
EOF
chmod 0755 "${bin_dir}/labwc"

cat >"${home_dir}/.config/labwc/shutdown" <<'EOF'
#!/bin/sh
set -eu
printf 'shutdown-hook %s\n' "${1:-}" >>"$ACTION_LOG"
EOF
chmod 0755 "${home_dir}/.config/labwc/shutdown"

printf '1..%s\n' "$TEST_COUNT"

if PATH="${case_dir}/bin:/usr/bin:/bin" \
   HOME="${case_dir}/home" \
   XDG_CONFIG_HOME="${case_dir}/home/.config" \
   LABWC_SESSION_OWNER=desktop \
   LABWC_PID=4242 \
   ACTION_LOG="${case_dir}/actions.log" \
   /bin/sh "$SCRIPT" &&
   [ "$(cat "${case_dir}/actions.log")" = "labwc --exit" ]; then
  pass "logout asks Labwc to exit without invoking manual session teardown"
else
  fail "logout asks Labwc to exit without invoking manual session teardown"
fi

: >"$log_file"
if ! PATH="${case_dir}/bin:/usr/bin:/bin" \
     HOME="${case_dir}/home" \
     XDG_CONFIG_HOME="${case_dir}/home/.config" \
     LABWC_SESSION_OWNER=desktop \
     ACTION_LOG="${case_dir}/actions.log" \
     /bin/sh "$SCRIPT" >/dev/null 2>&1 &&
   [ ! -s "$log_file" ]; then
  pass "logout preserves the running session when the compositor pid is unavailable"
else
  fail "logout preserves the running session when the compositor pid is unavailable"
fi
