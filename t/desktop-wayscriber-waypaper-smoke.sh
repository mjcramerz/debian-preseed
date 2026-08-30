#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-wayscriber-waypaper-smoke.XXXXXX")

cleanup() {
  rm -rf -- "$TMP_DIR"
}

trap cleanup EXIT HUP INT TERM

TEST_COUNT=13
TEST_INDEX=0
FAIL_COUNT=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

printf '1..%s\n' "$TEST_COUNT"

desktop_class="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
desktop_hook="$ROOT_DIR/d-i/forky/hooks/role/desktop/late_command.sh"
desktop_labwc="$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validate="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
wayscriber_toggle="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-wayscriber-toggle"
wayscriber_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/wayscriber.service.d/10-labwc-session.conf"
labwc_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
waypaper_installer="$ROOT_DIR/d-i/forky/scripts/desktop/waypaper.sh"
digital_assets_installer="$ROOT_DIR/d-i/forky/scripts/desktop/digital-assets.sh"
devops_profile="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile.d/71-devops-de.sh"
desktop_pool_tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/75-desktop-pool-storage.conf.tmpl"
shared_runtime_tmpfiles="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/tmpfiles.d/10-runtime-storage-roots.conf"
waypaper_desktop_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/applications/waypaper.desktop.tmpl"
readme="$ROOT_DIR/README.md"
target_readme="$ROOT_DIR/d-i/forky/hooks/role/desktop/README.target.md"

if grep -Fqx 'd-i apt-setup/local21/repository string https://wayscriber.com/apt stable main' "$desktop_class" &&
   grep -Fqx 'd-i apt-setup/local21/comment string Wayscriber Stable' "$desktop_class" &&
   grep -Fqx 'd-i apt-setup/local21/key string https://wayscriber.com/apt/WAYSCRIBER-GPG-KEY.asc' "$desktop_class" &&
   grep -Fqx 'd-i apt-setup/local21/source boolean false' "$desktop_class" &&
   grep -Eq '(^|[[:space:]])wayscriber([[:space:]]|$)' "$desktop_class"; then
  pass "desktop role installs Wayscriber from the vendor stable archive"
else
  fail "desktop role installs Wayscriber from the vendor stable archive"
fi

if /bin/sh -n "$wayscriber_toggle" &&
   grep -Fq '[ "${LABWC_SESSION_OWNER:-}" = desktop ]' "$wayscriber_toggle" &&
   grep -Fq '[ "${XDG_SESSION_TYPE:-}" = wayland ]' "$wayscriber_toggle" &&
   grep -Fq '[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]' "$wayscriber_toggle" &&
   grep -Fq '/usr/bin/systemctl --user start "$service"' "$wayscriber_toggle" &&
   grep -Fq '/usr/bin/systemctl --user reset-failed "$service"' "$wayscriber_toggle" &&
   grep -Fq 'while [ "$attempt" -le 20 ]; do' "$wayscriber_toggle" &&
   grep -Fq '/usr/bin/wayscriber --daemon-toggle' "$wayscriber_toggle" &&
   ! grep -Eq 'pkill|SIGUSR1' "$wayscriber_toggle"; then
  pass "Wayscriber toggle validates the session and recovers the daemon with bounded retries"
else
  fail "Wayscriber toggle validates the session and recovers the daemon with bounded retries"
fi

mock_bin="$TMP_DIR/bin"
mock_runtime="$TMP_DIR/runtime"
mock_state="$TMP_DIR/wayscriber.active"
mock_log="$TMP_DIR/wayscriber-click.log"
mock_toggle_count="$TMP_DIR/wayscriber-toggle-count"
rendered_toggle="$TMP_DIR/labwc-wayscriber-toggle"
install -d -m 0700 "$mock_bin" "$mock_runtime"

cat >"$mock_bin/systemctl" <<'EOF'
#!/bin/sh
set -eu

printf 'systemctl %s\n' "$*" >>"$MOCK_LOG"
case "$*" in
  '--user --quiet is-active wayscriber.service')
    [ -f "$MOCK_STATE" ]
    ;;
  '--user reset-failed wayscriber.service')
    exit 0
    ;;
  '--user start wayscriber.service')
    : >"$MOCK_STATE"
    ;;
  *)
    exit 64
    ;;
esac
EOF

cat >"$mock_bin/wayscriber" <<'EOF'
#!/bin/sh
set -eu

printf 'wayscriber %s\n' "$*" >>"$MOCK_LOG"
[ "$*" = '--daemon-toggle' ] || exit 64
[ -f "$MOCK_STATE" ] || exit 1
toggle_count=0
if [ -r "$MOCK_TOGGLE_COUNT" ]; then
  IFS= read -r toggle_count <"$MOCK_TOGGLE_COUNT"
fi
toggle_count=$((toggle_count + 1))
printf '%s\n' "$toggle_count" >"$MOCK_TOGGLE_COUNT"
[ "$toggle_count" -gt 1 ]
EOF

cat >"$mock_bin/sleep" <<'EOF'
#!/bin/sh
set -eu

printf 'sleep %s\n' "$*" >>"$MOCK_LOG"
EOF

chmod 0700 "$mock_bin/systemctl" "$mock_bin/wayscriber" "$mock_bin/sleep"
sed \
  -e "s#/usr/bin/systemctl#$mock_bin/systemctl#g" \
  -e "s#/usr/bin/wayscriber#$mock_bin/wayscriber#g" \
  -e "s#/usr/bin/sleep#$mock_bin/sleep#g" \
  -e 's/\[ -S /\[ -e /' \
  "$wayscriber_toggle" \
  >"$rendered_toggle"
chmod 0700 "$rendered_toggle"

wayland_display=wayland-wayscriber-test
wayland_socket="$mock_runtime/$wayland_display"
: >"$wayland_socket"

export MOCK_STATE="$mock_state"
export MOCK_LOG="$mock_log"
export MOCK_TOGGLE_COUNT="$mock_toggle_count"

click_path_ok=false
: >"$mock_log"
if [ -e "$wayland_socket" ] &&
   env \
     LABWC_SESSION_OWNER=desktop \
     XDG_SESSION_TYPE=wayland \
     XDG_RUNTIME_DIR="$mock_runtime" \
     WAYLAND_DISPLAY="$wayland_display" \
     "$rendered_toggle" &&
   grep -Fq 'systemctl --user reset-failed wayscriber.service' "$mock_log" &&
   grep -Fq 'systemctl --user start wayscriber.service' "$mock_log" &&
   [ "$(grep -Fc 'wayscriber --daemon-toggle' "$mock_log")" -eq 2 ] &&
   grep -Fq 'sleep 0.1' "$mock_log"; then
  : >"$mock_log"
  if env \
       LABWC_SESSION_OWNER=desktop \
       XDG_SESSION_TYPE=wayland \
       XDG_RUNTIME_DIR="$mock_runtime" \
       WAYLAND_DISPLAY="$wayland_display" \
       "$rendered_toggle" &&
     [ "$(grep -Fc 'wayscriber --daemon-toggle' "$mock_log")" -eq 1 ] &&
     ! grep -Fq 'systemctl --user start wayscriber.service' "$mock_log" &&
     ! grep -Fq 'systemctl --user reset-failed wayscriber.service' "$mock_log" &&
     ! grep -Fq 'sleep 0.1' "$mock_log"; then
    click_path_ok=true
  fi
fi

if [ "$click_path_ok" = true ]; then
  pass "Wayscriber glyph click starts an inactive daemon, retries readiness, and toggles an active daemon"
else
  fail "Wayscriber glyph click starts an inactive daemon, retries readiness, and toggles an active daemon"
fi

if grep -q '^desktop_stage_wayscriber_service() {$' "$desktop_components" &&
   grep -q 'Wayscriber package executable is missing from the target' "$desktop_components" &&
   grep -q 'Wayscriber package user service is missing from the target' "$desktop_components" &&
   grep -q 'desktop_stage_global_user_unit_dropin_asset wayscriber.service 10-labwc-session.conf' "$desktop_components" &&
   grep -q '^ConditionEnvironment=LABWC_SESSION_OWNER=desktop$' "$wayscriber_dropin" &&
   grep -q '^After=labwc-session.target$' "$wayscriber_dropin" &&
   grep -q '^PartOf=labwc-session.target$' "$wayscriber_dropin" &&
   grep -q '^WantedBy=labwc-session.target$' "$wayscriber_dropin" &&
   ! grep -q 'graphical-session.target' "$wayscriber_dropin" &&
   grep -q '^Environment=WAYSCRIBER_NO_TRAY=1$' "$wayscriber_dropin" &&
   grep -q '^Environment=RUST_LOG=wayscriber=info,zbus=error,tracing=error,wayscriber::daemon::core=warn,wayscriber::daemon::global_shortcuts=error$' "$wayscriber_dropin" &&
   grep -q '^Restart=on-failure$' "$wayscriber_dropin" &&
   grep -q '^RestartSec=2s$' "$wayscriber_dropin" &&
   grep -q '^TimeoutStartSec=30s$' "$wayscriber_dropin" &&
   grep -q '^TimeoutStopSec=10s' "$wayscriber_dropin" &&
   grep -q 'usr/local/bin/labwc-wayscriber-toggle /usr/local/bin/labwc-wayscriber-toggle 0755' "$desktop_components" &&
   grep -q '^    wayscriber.service \\$' "$desktop_components"; then
  pass "Wayscriber daemon is session-bound, tray-free, and restart-safe under Labwc"
else
  fail "Wayscriber daemon is session-bound, tray-free, and restart-safe under Labwc"
fi

if grep -q 'for desktop_module in detect components satty xwayland waypaper android-platform-tools samloader digital-assets labwc' "$desktop_hook" &&
   ! grep -q 'desktop_.*wayscriber.*install' "$desktop_labwc" &&
   grep -q 'desktop_stage_target_assets' "$desktop_labwc" &&
   grep -q 'desktop_enable_target_services' "$desktop_labwc"; then
  pass "desktop orchestration relies on the APT package and managed service wiring"
else
  fail "desktop orchestration relies on the APT package and managed service wiring"
fi

rendered_labwc_menu="$TMP_DIR/labwc-menu.xml"
sed 's#__INSTALLER_ACCOUNT_HOME__#/home/testuser#g' \
  "$labwc_menu" \
  >"$rendered_labwc_menu"
if grep -q 'label="Screen Annotation" icon="wayscriber"' "$labwc_menu" &&
   grep -q 'command="labwc-wayscriber-toggle"' "$labwc_menu" &&
   grep -q 'label="Wallpaper" icon="preferences-desktop-wallpaper"' "$labwc_menu" &&
   grep -q 'command="/usr/local/bin/waypaper"' "$labwc_menu" &&
   grep -Fq '"etc/skel/.config/labwc/menu.xml"' "$desktop_components" &&
   grep -Fq 'ACCOUNT_HOME "$ACCOUNT_HOME"' "$desktop_components" &&
   grep -q 'command="/usr/local/bin/waypaper"' "$rendered_labwc_menu" &&
   ! grep -q '__INSTALLER_' "$rendered_labwc_menu" &&
   python3 - "$rendered_labwc_menu" <<'PY'
import sys
import xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY
then
  pass "Labwc exposes valid Wayscriber and Waypaper menu entries"
else
  fail "Labwc exposes valid Wayscriber and Waypaper menu entries"
fi

if /bin/sh -n "$waypaper_installer" &&
   grep -q '^desktop_install_waypaper() {$' "$waypaper_installer" &&
   grep -q 'pipx installation failed or timed out' "$waypaper_installer" &&
   grep -q -- '--kill-after=15s' "$waypaper_installer" &&
   grep -q 'PIPX_HOME="$waypaper_pipx_home"' "$waypaper_installer" &&
   grep -q 'PIPX_BIN_DIR="$waypaper_bin_dir"' "$waypaper_installer" &&
   grep -q 'PIPX_MAN_DIR="$waypaper_pipx_man_dir"' "$waypaper_installer" &&
   grep -q 'PIPX_DEFAULT_PYTHON=/usr/bin/python3' "$waypaper_installer" &&
   grep -q 'PIP_NO_CACHE_DIR=1' "$waypaper_installer" &&
   grep -q '"waypaper==${LABWC_WAYPAPER_VERSION}"' "$waypaper_installer" &&
   grep -q 'desktop_transient_pipx_build_account_prepare' "$waypaper_installer" &&
   grep -q 'desktop_waypaper_seal_runtime' "$waypaper_installer" &&
   grep -Eq -- '(^|[[:space:]])--system-site-packages([[:space:]]|$)' "$waypaper_installer" &&
   grep -Fq -- '-type f -perm /111 -exec /usr/bin/chmod 0755 {} +' "$waypaper_installer" &&
   grep -Fq -- '-type f ! -perm /111 -exec /usr/bin/chmod 0644 {} +' "$waypaper_installer" &&
   grep -Fq -- '-type f ! -perm -004 -print -quit' "$waypaper_installer" &&
   grep -Fq -- '-type f -perm /111 ! -perm -001 -print -quit' "$waypaper_installer" &&
   grep -q 'desktop_render_role_target_template' "$waypaper_installer" &&
   ! grep -Eq -- '(^|[[:space:]])--global([[:space:]]|$)|PIPX_GLOBAL_' "$waypaper_installer" &&
   ! grep -Eq 'desktop_waypaper_verify_prerequisites|desktop_waypaper_runtime_probe|managed Python runtime|importlib|desktop-file-validate|update-desktop-database|capture_in_target|pipx did not expose|launcher escaped|resolved Waypaper binary|runtime probe' "$waypaper_installer"; then
  pass "Waypaper uses a bounded transient pipx build and root-managed readable runtime"
else
  fail "Waypaper uses a bounded transient pipx build and root-managed readable runtime"
fi

waypaper_invocation="$TMP_DIR/waypaper-pipx-invocation"
waypaper_operations="$TMP_DIR/waypaper-pipx-operations"
waypaper_harness="$TMP_DIR/waypaper-pipx-harness.sh"
cat >"$waypaper_harness" <<'EOF'
#!/bin/sh
set -eu

installer_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 99
}

desktop_primary_account_ids() {
  [ "$1" = "$ACCOUNT_USERNAME" ] || return 1
  printf '%s\n' '1100:1100'
}

desktop_require_absolute_account_home() {
  [ "$ACCOUNT_HOME" = /home/testuser ]
}

desktop_transient_pipx_build_account_prepare() {
  printf 'prepare' >>"$WAYPAPER_OPERATIONS"
  for value in "$@"; do
    printf ' <%s>' "$value" >>"$WAYPAPER_OPERATIONS"
  done
  printf '\n' >>"$WAYPAPER_OPERATIONS"
}

desktop_transient_pipx_build_account_destroy() {
  printf 'destroy' >>"$WAYPAPER_OPERATIONS"
  for value in "$@"; do
    printf ' <%s>' "$value" >>"$WAYPAPER_OPERATIONS"
  done
  printf '\n' >>"$WAYPAPER_OPERATIONS"
}

run_in_target() {
  printf 'run-in-target' >>"$WAYPAPER_OPERATIONS"
  for value in "$@"; do
    printf ' <%s>' "$value" >>"$WAYPAPER_OPERATIONS"
  done
  printf '\n' >>"$WAYPAPER_OPERATIONS"
}

install() {
  printf 'install' >>"$WAYPAPER_OPERATIONS"
  for value in "$@"; do
    printf ' <%s>' "$value" >>"$WAYPAPER_OPERATIONS"
  done
  printf '\n' >>"$WAYPAPER_OPERATIONS"
}

chown() {
  printf 'chown' >>"$WAYPAPER_OPERATIONS"
  for value in "$@"; do
    printf ' <%s>' "$value" >>"$WAYPAPER_OPERATIONS"
  done
  printf '\n' >>"$WAYPAPER_OPERATIONS"
}

attempt_in_target() {
  label=$1
  shift
  printf 'label=%s\n' "$label" >"$WAYPAPER_INVOCATION"
  printf '%s\n' "$@" >>"$WAYPAPER_INVOCATION"
}

desktop_render_role_target_template() {
  printf 'render' >>"$WAYPAPER_OPERATIONS"
  for value in "$@"; do
    printf ' <%s>' "$value" >>"$WAYPAPER_OPERATIONS"
  done
  printf '\n' >>"$WAYPAPER_OPERATIONS"
}

desktop_log() {
  :
}

. "$1"
desktop_install_waypaper
EOF
chmod 0700 "$waypaper_harness"

if env \
     ACCOUNT_USERNAME=testuser \
     ACCOUNT_HOME=/home/testuser \
     LABWC_WAYPAPER_VERSION=2.8 \
     LABWC_WAYPAPER_INSTALL_TIMEOUT_SECONDS=600 \
     WAYPAPER_INVOCATION="$waypaper_invocation" \
     WAYPAPER_OPERATIONS="$waypaper_operations" \
     "$waypaper_harness" "$waypaper_installer" &&
   grep -Fqx 'label=install pinned Waypaper with pipx' "$waypaper_invocation" &&
   grep -Fqx 'HOME=/opt/waypaper/.pipx-build-home' "$waypaper_invocation" &&
   grep -Fqx 'USER=installer-pipx-build' "$waypaper_invocation" &&
   grep -Fqx 'PIPX_HOME=/opt/waypaper/pipx' "$waypaper_invocation" &&
   grep -Fqx 'PIPX_BIN_DIR=/opt/waypaper/bin' "$waypaper_invocation" &&
   grep -Fqx 'PIPX_MAN_DIR=/opt/waypaper/man' "$waypaper_invocation" &&
   grep -Fqx 'PIP_NO_CACHE_DIR=1' "$waypaper_invocation" &&
   grep -Fqx -- '--system-site-packages' "$waypaper_invocation" &&
   grep -Fqx -- '-u' "$waypaper_invocation" &&
   grep -Fqx 'installer-pipx-build' "$waypaper_invocation" &&
   grep -Fqx 'waypaper==2.8' "$waypaper_invocation" &&
   grep -Fq '</target/opt/waypaper/pipx>' "$waypaper_operations" &&
   grep -Fq '</target/opt/waypaper/man>' "$waypaper_operations" &&
   grep -Fq 'prepare <installer-pipx-build> </opt/waypaper/.pipx-build-home> </opt/waypaper/pipx> </opt/waypaper/bin> </opt/waypaper/man>' "$waypaper_operations" &&
   grep -Fq 'destroy <installer-pipx-build> </opt/waypaper/.pipx-build-home>' "$waypaper_operations" &&
   grep -Fq 'run-in-target <seal root-owned Waypaper pipx runtime>' "$waypaper_operations" &&
   ! grep -Eq '^(PIPX_GLOBAL_|--global$|HOME=/root$|PIPX_HOME=/root|PIPX_BIN_DIR=/usr/local)' "$waypaper_invocation"; then
  pass "Waypaper builds under a transient account and publishes a root-managed runtime"
else
  fail "Waypaper builds under a transient account and publishes a root-managed runtime"
fi

waypaper_desktop="$TMP_DIR/waypaper.desktop"
sed 's#__INSTALLER_ACCOUNT_HOME__#/home/testuser#g' \
  "$waypaper_desktop_template" \
  >"$waypaper_desktop"
if grep -q '^TryExec=/usr/local/bin/waypaper$' "$waypaper_desktop" &&
   grep -q '^Exec=/usr/local/bin/waypaper$' "$waypaper_desktop" &&
   ! grep -q '__INSTALLER_' "$waypaper_desktop" &&
   grep -q 'desktop_render_role_target_template' "$waypaper_installer" &&
   grep -q '"$account_home/.local/share/applications/waypaper.desktop"' "$desktop_verify"; then
  pass "Waypaper retains its simple primary-user desktop launcher"
else
  fail "Waypaper retains its simple primary-user desktop launcher"
fi

if grep -q 'PIPX_HOME="$waypaper_pipx_home"' "$waypaper_installer" &&
   grep -q 'PIPX_BIN_DIR="$waypaper_bin_dir"' "$waypaper_installer" &&
   grep -q 'desktop_transient_pipx_build_account_prepare' "$waypaper_installer" &&
   grep -q '/usr/sbin/runuser' "$waypaper_installer" &&
   ! grep -Eq -- '(^|[[:space:]])--global([[:space:]]|$)|PIPX_GLOBAL_' "$waypaper_installer" &&
   grep -q 'PIPX_HOME="$digital_assets_pipx_home"' "$digital_assets_installer" &&
   grep -q 'PIPX_BIN_DIR="$digital_assets_pipx_bin_dir"' "$digital_assets_installer" &&
   grep -q 'desktop_transient_pipx_build_account_prepare' "$digital_assets_installer" &&
   grep -q '/usr/sbin/runuser' "$digital_assets_installer" &&
   ! grep -Eq -- '(^|[[:space:]])--global([[:space:]]|$)|PIPX_GLOBAL_' "$digital_assets_installer"; then
  pass "all desktop pipx applications build under transient unprivileged accounts"
else
  fail "all desktop pipx applications build under transient unprivileged accounts"
fi

if /bin/sh -n "$devops_profile" &&
   grep -Fq 'devops_de_mise_node_exec() {' "$devops_profile" &&
   grep -Fq 'devops_de_corepack_exec() {' "$devops_profile" &&
   [ "$(grep -Fc 'command mise exec -- "$@"' "$devops_profile")" -eq 2 ] &&
   grep -Fq 'devops_de_mise_node_exec node "$@"' "$devops_profile" &&
   grep -Fq 'devops_de_mise_node_exec npm "$@"' "$devops_profile" &&
   grep -Fq 'devops_de_mise_node_exec npx "$@"' "$devops_profile" &&
   grep -Fq 'devops_de_corepack_exec pnpm "$@"' "$devops_profile" &&
   grep -Fq 'devops_de_corepack_exec corepack "$@"' "$devops_profile" &&
   grep -Fq 'devops_de_corepack_exec yarn "$@"' "$devops_profile" &&
   grep -Fq 'export MISE_DATA_DIR="${devops_de_db_home}/mise/data"' "$devops_profile" &&
   grep -Fq 'export CARGO_HOME="${devops_de_cache_home}/cargo"' "$devops_profile" &&
   grep -Fq 'export RUSTUP_HOME="${devops_de_db_home}/rustup"' "$devops_profile" &&
   grep -Fq 'export SCCACHE_DIR="${devops_de_cache_home}/sccache"' "$devops_profile" &&
   grep -Fq 'devops_de_prepend_path /usr/lib/llvm-24/bin' "$devops_profile" &&
   grep -Fq 'command /usr/local/lib/bazelisk/bazel' "$devops_profile" &&
   ! grep -Eq 'mise exec.*(clang|llvm|lld|bazel)' "$devops_profile" &&
   ! grep -Fq 'eval "$(mise activate' "$devops_profile"; then
  pass "desktop login routes Node through project-local Mise while LLVM 24 and Bazelisk stay direct with /pool-backed state"
else
  fail "desktop login routes Node through project-local Mise while LLVM 24 and Bazelisk stay direct with /pool-backed state"
fi

desktop_pool_invocation="$TMP_DIR/desktop-pool-invocation"
desktop_pool_harness="$TMP_DIR/desktop-pool-harness.sh"
cat >"$desktop_pool_harness" <<'EOF'
#!/bin/sh
set -eu

. "$1"

desktop_render_role_target_template() {
  printf 'render\n' >>"$DESKTOP_POOL_INVOCATION"
  for desktop_pool_arg in "$@"; do
    printf '%s\n' "$desktop_pool_arg" >>"$DESKTOP_POOL_INVOCATION"
  done
}

normalize_target_tmpfiles_directory_policy() {
  printf 'normalize\n%s\n%s\n' "$1" "$2" >>"$DESKTOP_POOL_INVOCATION"
}

desktop_log() {
  :
}

desktop_stage_primary_account_pool_storage_policy
EOF
chmod 0700 "$desktop_pool_harness"
desktop_pool_expected=$(cat <<'EOF'
render
etc/tmpfiles.d/75-desktop-pool-storage.conf.tmpl
/etc/tmpfiles.d/75-desktop-pool-storage.conf
0644
ACCOUNT_USERNAME
testuser
DIR_POOL_BUILD
/pool/build
DIR_POOL_CACHE
/pool/cache
DIR_POOL_DB
/pool/db
normalize
/etc/tmpfiles.d/75-desktop-pool-storage.conf
desktop primary-account pool storage
EOF
)
if grep -Fqx 'd __INSTALLER_DIR_POOL_BUILD__/__INSTALLER_ACCOUNT_USERNAME__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$desktop_pool_tmpfiles" &&
   grep -Fqx 'd __INSTALLER_DIR_POOL_CACHE__/__INSTALLER_ACCOUNT_USERNAME__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$desktop_pool_tmpfiles" &&
   grep -Fqx 'd __INSTALLER_DIR_POOL_CACHE__/__INSTALLER_ACCOUNT_USERNAME__/whisper 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$desktop_pool_tmpfiles" &&
   grep -Fqx 'd __INSTALLER_DIR_POOL_DB__/__INSTALLER_ACCOUNT_USERNAME__ 2770 __INSTALLER_ACCOUNT_USERNAME__ devops -' "$desktop_pool_tmpfiles" &&
   ! grep -Fq '__INSTALLER_DIR_POOL_BUILD__/__INSTALLER_ACCOUNT_USERNAME__' "$shared_runtime_tmpfiles" &&
   ! grep -Fq '__INSTALLER_DIR_POOL_CACHE__/__INSTALLER_ACCOUNT_USERNAME__' "$shared_runtime_tmpfiles" &&
   ! grep -Fq '__INSTALLER_DIR_POOL_DB__/__INSTALLER_ACCOUNT_USERNAME__' "$shared_runtime_tmpfiles" &&
   grep -Fq 'desktop_stage_primary_account_pool_storage_policy' "$desktop_components" &&
   grep -Fq 'desktop_stage_role_asset etc/skel/.profile.d/71-devops-de.sh /etc/skel/.profile.d/71-devops-de.sh 0644' "$desktop_components" &&
   ! grep -Fq '80-devops-storage.conf' "$desktop_components" &&
   env \
     ACCOUNT_USERNAME=testuser \
     DIR_POOL_BUILD=/pool/build \
     DIR_POOL_CACHE=/pool/cache \
     DIR_POOL_DB=/pool/db \
     DESKTOP_POOL_INVOCATION="$desktop_pool_invocation" \
     "$desktop_pool_harness" "$desktop_components" &&
   [ "$(cat "$desktop_pool_invocation")" = "$desktop_pool_expected" ]; then
  pass "desktop components stage 71-devops-de.sh and apply the complete role-owned devops pool tmpfiles policy"
else
  fail "desktop components stage 71-devops-de.sh and apply the complete role-owned devops pool tmpfiles policy"
fi

if grep -q 'labwc-wayscriber-toggle' "$desktop_verify" &&
   grep -q '/usr/bin/wayscriber' "$desktop_verify" &&
   grep -q '/etc/systemd/user/wayscriber.service.d/10-labwc-session.conf' "$desktop_verify" &&
   grep -q 'primary account package-unit drop-in is still present' "$desktop_verify" &&
   grep -q 'labwc-wayscriber-toggle' "$firstboot_validate" &&
   grep -q '/usr/bin/wayscriber' "$firstboot_validate" &&
   grep -q '/etc/systemd/user/wayscriber.service.d/10-labwc-session.conf' "$firstboot_validate" &&
   grep -q '`Super+W` for Wayscriber' "$readme" &&
   grep -q '`Super+W` for Wayscriber' "$target_readme"; then
  pass "Wayscriber package, daemon helper, and documentation are covered by validation"
else
  fail "Wayscriber package, daemon helper, and documentation are covered by validation"
fi

[ "$FAIL_COUNT" -eq 0 ]
