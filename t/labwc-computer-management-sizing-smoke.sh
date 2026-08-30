#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
bin_dir="$TMP_DIR/bin"
selections="$TMP_DIR/selections"
launcher_log="$TMP_DIR/launcher.log"
mkdir -p "$bin_dir"

printf '1..2\n'

cat >"$bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF

cat >"$bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
prompt=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompt)
      prompt=$2
      shift 2
      ;;
    --prompt=*)
      prompt=${1#--prompt=}
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf 'prompt=%s width=%s lines=%s font=%s\n' \
  "$prompt" \
  "${LABWC_FUZZEL_MENU_WIDTH_OVERRIDE:-}" \
  "${LABWC_FUZZEL_MENU_LINES_OVERRIDE:-}" \
  "${LABWC_FUZZEL_MENU_FONT_SIZE_OVERRIDE:-}" \
  >>"${LAUNCHER_LOG:?}"
if [ "$prompt" = 'Hardware & Peripherals' ] &&
   [ -n "${LABWC_FUZZEL_MENU_WIDTH_OVERRIDE:-}" ]; then
  exit 2
fi
selection=$(sed -n '1p' "${SELECTIONS:?}")
sed '1d' "$SELECTIONS" >"${SELECTIONS}.next"
mv "${SELECTIONS}.next" "$SELECTIONS"
printf '%s\n' "$selection"
EOF

chmod 0755 "$bin_dir/id" "$bin_dir/labwc-fuzzel"
printf '%s\n' \
  ' Hardware & Peripherals' \
  '← Back' \
  'Exit' >"$selections"

if PATH="$bin_dir:/usr/bin:/bin" \
   LABWC_DESKTOP_DEFAULTS_FILE=/nonexistent \
   LABWC_FUZZEL_HARDWARE_PERIPHERALS_WIDTH=24 \
   LABWC_FUZZEL_HARDWARE_PERIPHERALS_LINES=12 \
   LABWC_FUZZEL_HARDWARE_PERIPHERALS_FONT_SIZE=15 \
   LAUNCHER_LOG="$launcher_log" \
   SELECTIONS="$selections" \
     /bin/sh "$computer_management" \
       >"$TMP_DIR/stdout" \
       2>"$TMP_DIR/stderr" &&
   grep -Fqx 'prompt=Hardware & Peripherals width=24 lines=12 font=15' "$launcher_log" &&
   grep -Fqx 'prompt=Hardware & Peripherals width= lines= font=' "$launcher_log" &&
   grep -Fq 'retrying the Hardware & Peripherals menu without category sizing overrides' \
     "$TMP_DIR/stderr"; then
  printf 'ok 1 - Hardware and Peripherals retries an invalid category sizing override with base Fuzzel settings\n'
else
  printf 'not ok 1 - Hardware and Peripherals retries an invalid category sizing override with base Fuzzel settings\n'
  exit 1
fi

action_log="$TMP_DIR/action.log"
cat >"$bin_dir/labwc-brightness-control" <<'EOF'
#!/bin/sh
printf '%s\n' called >>"${ACTION_LOG:?}"
exit 1
EOF
chmod 0755 "$bin_dir/labwc-brightness-control"

printf '%s\n' \
  ' Hardware & Peripherals' \
  ' Brightness' \
  '← Back' \
  'Exit' >"$selections"
: >"$action_log"

if PATH="$bin_dir:/usr/bin:/bin" \
   LABWC_DESKTOP_DEFAULTS_FILE=/nonexistent \
   LABWC_FUZZEL_HARDWARE_PERIPHERALS_WIDTH=24 \
   LABWC_FUZZEL_HARDWARE_PERIPHERALS_LINES=12 \
   LABWC_FUZZEL_HARDWARE_PERIPHERALS_FONT_SIZE=15 \
   LAUNCHER_LOG="$launcher_log" \
   SELECTIONS="$selections" \
   ACTION_LOG="$action_log" \
     /bin/sh "$computer_management" \
       >"$TMP_DIR/action.stdout" \
       2>"$TMP_DIR/action.stderr" &&
   grep -Fqx called "$action_log" &&
   grep -Fq 'warning: Computer Management action returned status 1: labwc-brightness-control' \
     "$TMP_DIR/action.stderr" &&
   [ ! -s "$selections" ]; then
  printf 'ok 2 - Hardware action failures return to Computer Management instead of terminating the launcher\n'
else
  printf 'not ok 2 - Hardware action failures return to Computer Management instead of terminating the launcher\n'
  exit 1
fi
