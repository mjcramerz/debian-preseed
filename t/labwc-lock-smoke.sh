#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-lock"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-lock.XXXXXX")
BIN_DIR="${TMP_DIR}/bin"
CONFIG_DIR="${TMP_DIR}/config/swaylock"
RUNTIME_DIR="${TMP_DIR}/runtime"
BACKGROUND_PATH="${TMP_DIR}/lock.png"
SWAYLOCK_LOG="${TMP_DIR}/swaylock.log"

TEST_COUNT=4
TEST_INDEX=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

install -d -m 0700 "$BIN_DIR" "$CONFIG_DIR" "$RUNTIME_DIR"
: >"$BACKGROUND_PATH"
: >"${CONFIG_DIR}/config"

cat >"${BIN_DIR}/swaylock" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$SWAYLOCK_LOG"
EOF
chmod 0700 "${BIN_DIR}/swaylock"

run_lock() {
  : >"$SWAYLOCK_LOG"
  PATH="${BIN_DIR}:/usr/bin:/bin" \
  HOME="$TMP_DIR" \
  XDG_CONFIG_HOME="${TMP_DIR}/config" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  LABWC_LOCK_BACKGROUND_PATH="$BACKGROUND_PATH" \
  SWAYLOCK_LOG="$SWAYLOCK_LOG" \
    /bin/sh "$SCRIPT" "$@"
}

printf '1..%s\n' "$TEST_COUNT"

run_lock --debug
if [ "$(cat "$SWAYLOCK_LOG")" = "-f -c ${CONFIG_DIR}/config --image ${BACKGROUND_PATH} --scaling fill --debug" ]; then
  pass "configured lock uses the managed wallpaper and waits for swaylock readiness"
else
  fail "configured lock uses the managed wallpaper and waits for swaylock readiness"
fi

(
  exec 9>"${RUNTIME_DIR}/labwc-swaylock.lock"
  /usr/bin/flock -n 9
  sleep 2
) &
lock_holder=$!
sleep 0.1
run_lock
kill "$lock_holder" >/dev/null 2>&1 || true
wait "$lock_holder" 2>/dev/null || true
if [ ! -s "$SWAYLOCK_LOG" ]; then
  pass "a held swaylock runtime lock suppresses duplicate lockers"
else
  fail "a held swaylock runtime lock suppresses duplicate lockers"
fi

rm -f "${CONFIG_DIR}/config"
run_lock
if [ "$(cat "$SWAYLOCK_LOG")" = "-f --image ${BACKGROUND_PATH} --scaling fill" ]; then
  pass "missing user config still preserves the managed lock wallpaper"
else
  fail "missing user config still preserves the managed lock wallpaper"
fi

rm -f "$BACKGROUND_PATH"
run_lock
if [ "$(cat "$SWAYLOCK_LOG")" = "-f" ]; then
  pass "missing optional assets still produce a functional swaylock command"
else
  fail "missing optional assets still produce a functional swaylock command"
fi
