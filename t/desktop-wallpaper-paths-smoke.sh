#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-wallpaper-paths-smoke.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

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

desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
desktop_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validate="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
swaybg_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-swaybg"
wallpaper_save="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-wallpaper-save"
lock_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-lock"
swaylock_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/swaylock/config"
waypaper_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waypaper/config.ini"
waypaper_keybindings="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waypaper/keybindings.ini"
waypaper_style="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waypaper/style.css"
gtkgreet_css="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/greetd/gtkgreet.css"
desktop_wallpaper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds/desktop/wallpaper-1920x1080.png"
wallpaper_archive="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds/desktop/wallpapers.tar.gz"
login_welcome="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds/login/welcome-1920x1080.png"
login_lock="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds/login/lock-1920x1080.png"
other_greeter="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds/other/regreet-000-greeter-purple.svg"
other_alt="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds/other/wp2653774-black-and-blue-wallpaper-hd.png"

if [ -f "$desktop_wallpaper" ] &&
   [ -f "$wallpaper_archive" ] &&
   [ -f "$login_welcome" ] &&
   [ -f "$login_lock" ] &&
   [ -f "$other_greeter" ] &&
   [ -f "$other_alt" ]; then
  pass "wallpaper assets live under the new desktop, login, and other background trees"
else
  fail "wallpaper assets live under the new desktop, login, and other background trees"
fi

if grep -q '^LABWC_WALLPAPER_PATH="/usr/share/backgrounds/desktop/wallpaper-1920x1080.png"$' "$desktop_env" &&
   grep -q '^LABWC_LOCK_BACKGROUND_PATH="/usr/share/backgrounds/login/lock-1920x1080.png"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_BACKGROUND_PATH="/usr/share/backgrounds/login/welcome-1920x1080.png"$' "$desktop_env"; then
  pass "desktop host policy points Labwc, lock, and gtkgreet to the renamed wallpapers"
else
  fail "desktop host policy points Labwc, lock, and gtkgreet to the renamed wallpapers"
fi

if grep -q '/usr/share/backgrounds/desktop/wallpaper-1920x1080.png' "$desktop_detect" &&
   grep -q '/usr/share/backgrounds/login/lock-1920x1080.png' "$desktop_detect" &&
   grep -q '/usr/share/backgrounds/login/welcome-1920x1080.png' "$desktop_detect"; then
  pass "desktop detection validates and writes the renamed wallpaper defaults"
else
  fail "desktop detection validates and writes the renamed wallpaper defaults"
fi

if grep -q 'usr/share/backgrounds/desktop/wallpaper-1920x1080.png /usr/share/backgrounds/desktop/wallpaper-1920x1080.png 0644' "$desktop_components" &&
   grep -q '^desktop_extract_role_wallpaper_archive() {$' "$desktop_components" &&
   grep -q 'desktop_extract_role_wallpaper_archive' "$desktop_components" &&
   grep -q 'run_in_target "extract managed desktop wallpaper archive"' "$desktop_components" &&
   grep -q -- '--no-same-owner' "$desktop_components" &&
   grep -q -- '--no-same-permissions' "$desktop_components" &&
   grep -q '/usr/bin/install -m 0644 "$extracted_path"' "$desktop_components" &&
   ! grep -q 'wallpapers.tar.gz /usr/share/backgrounds/desktop/wallpapers.tar.gz' "$desktop_components" &&
   grep -q 'usr/share/backgrounds/login/lock-1920x1080.png /usr/share/backgrounds/login/lock-1920x1080.png 0644' "$desktop_components" &&
   grep -q 'usr/share/backgrounds/login/welcome-1920x1080.png /usr/share/backgrounds/login/welcome-1920x1080.png 0644' "$desktop_components" &&
   grep -q '^desktop_stage_role_asset_tree() {$' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset_tree usr/share/backgrounds/other /usr/share/backgrounds/other' "$desktop_components" &&
   ! grep -q 'usr/share/backgrounds/other/regreet-000-greeter-purple.svg /usr/share/backgrounds/other/regreet-000-greeter-purple.svg 0644' "$desktop_components" &&
   ! grep -q 'usr/share/backgrounds/other/wp2653774-black-and-blue-wallpaper-hd.png /usr/share/backgrounds/other/wp2653774-black-and-blue-wallpaper-hd.png 0644' "$desktop_components"; then
  pass "desktop target staging validates and extracts the wallpaper archive without installing it"
else
  fail "desktop target staging validates and extracts the wallpaper archive without installing it"
fi

archive_extract="$TMP_DIR/archive"
mkdir -p "$archive_extract"
archive_members_valid=true
if ! tar -tzf "$wallpaper_archive" |
  awk '
    BEGIN { count = 0 }
    {
      count += 1
      if ($0 == "" || $0 ~ /^\// || $0 ~ /\// || $0 ~ /^\./ ||
          $0 !~ /\.(png|jpg|jpeg)$/) {
        exit 1
      }
    }
    END {
      if (count != 15) {
        exit 1
      }
    }
  '
then
  archive_members_valid=false
fi
if ! tar --numeric-owner -tvzf "$wallpaper_archive" |
  awk '$1 !~ /^-/ || $1 ~ /x/ { exit 1 }'
then
  archive_members_valid=false
fi
if ! tar -xzf "$wallpaper_archive" -C "$archive_extract"; then
  archive_members_valid=false
fi
for archive_image in "$archive_extract"/*; do
  [ -f "$archive_image" ] || {
    archive_members_valid=false
    continue
  }
  archive_mime=$(file --brief --mime-type -- "$archive_image" 2>/dev/null || true)
  case "${archive_image}:${archive_mime}" in
    *.png:image/png|*.jpg:image/jpeg|*.jpeg:image/jpeg) ;;
    *) archive_members_valid=false ;;
  esac
done
if [ "$archive_members_valid" = true ]; then
  pass "wallpaper archive contains only bounded regular PNG and JPEG image members"
else
  fail "wallpaper archive contains only bounded regular PNG and JPEG image members"
fi

extract_target="$TMP_DIR/extract-target"
extract_env="$TMP_DIR/extract-env"
mkdir -p "$extract_target/tmp" "$extract_env"
if (
     TEST_TARGET=$extract_target
     TMP_ENV_DIR=$extract_env
     export TEST_TARGET TMP_ENV_DIR
     installer_repo_join_var() {
       printf '%s/d-i/forky/hooks/role/desktop/%s\n' "$ROOT_DIR" "$2"
     }
     target_asset_host_path() {
       printf '%s%s\n' "$TEST_TARGET" "$1"
     }
     fetch_hook() {
       cp "$1" "$2"
     }
     installer_fatal() {
       printf 'fatal: %s\n' "$*" >&2
       exit 1
     }
     desktop_log() {
       :
     }
     run_in_target() {
       target_label=$1
       shift
       [ "$1" = /bin/sh ] &&
         [ "$2" = -eu ] &&
         [ "$3" = -c ] ||
         installer_fatal "$target_label used an unexpected shell invocation"
       target_script=$4
       target_argv0=$5
       target_archive=$6
       target_destination=$7
       target_member_limit=$8
       target_byte_limit=$9
       /bin/sh -eu -c "$target_script" "$target_argv0" \
         "${TEST_TARGET}${target_archive}" \
         "${TEST_TARGET}${target_destination}" \
         "$target_member_limit" \
         "$target_byte_limit"
     }
     # shellcheck disable=SC1090
     . "$desktop_components"
     desktop_extract_role_wallpaper_archive
   ) &&
   [ "$(find "$extract_target/usr/share/backgrounds/desktop" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 15 ] &&
   [ ! -e "$extract_target/tmp/installer-desktop-wallpapers.tar.gz" ] &&
   ! find "$extract_target/usr/share/backgrounds/desktop" -maxdepth 1 -type f ! -perm 0644 -print |
     grep -q .; then
  pass "installer extraction publishes only normalized wallpaper files into the target"
else
  fail "installer extraction publishes only normalized wallpaper files into the target"
fi

expected_waypaper_config="$TMP_DIR/waypaper-config.ini"
cat >"$expected_waypaper_config" <<'EOF'
[Settings]
language = en
folder = /usr/share/backgrounds/desktop
wallpaper = /usr/share/backgrounds/desktop/wallpaper-1920x1080.png
backend = none
monitors = All
fill = fill
sort = name
color = #000000
subfolders = False
all_subfolders = False
show_hidden = False
show_gifs_only = False
show_path_in_tooltip = True
number_of_columns = 3
use_xdg_state = False
zen_mode = False
swww_transition_type = any
swww_transition_step = 63
swww_transition_angle = 0
swww_transition_duration = 2
swww_transition_fps = 60
mpvpaper_sound = False
mpvpaper_options =
post_command = /usr/local/bin/labwc-wallpaper-save --apply "$wallpaper"
stylesheet = ~/.config/waypaper/style.css
keybindings = ~/.config/waypaper/keybindings.ini
wallpaperengine_folder = ~/.steam/root/steamapps/workshop/content/431960
linux_wallpaperengine_clamp = none
linux_wallpaperengine_volume = 15
linux_wallpaperengine_silent = False
linux_wallpaperengine_noautomute = False
linux_wallpaperengine_no_audio_processing = False
linux_wallpaperengine_fps = 30
linux_wallpaperengine_disable_particles = True
linux_wallpaperengine_disable_mouse = False
linux_wallpaperengine_disable_parallax = False
linux_wallpaperengine_no_fullscreen_pause = False
linux_wallpaperengine_fullscreen_pause_only_active = False
EOF
expected_waypaper_keybindings="$TMP_DIR/waypaper-keybindings.ini"
cat >"$expected_waypaper_keybindings" <<'EOF'
[Keybindings]
clear_input_fields = Escape, Return, KP_Enter
quit = q
clear_cache = r
random_wallpaper = R
hidden_files = period
search = slash
include_subfolders = s
navigation_left = h, Left
navigation_down = j, Down
navigation_up = k, Up
navigation_right = l, Right
choose_folder = f
scroll_to_top = g
zen_mode = z
scroll_to_bottom = G
help_page = question
select_wallpaper = Return, KP_Enter
EOF
if /bin/sh -n "$wallpaper_save" &&
   cmp -s "$expected_waypaper_config" "$waypaper_config" &&
   cmp -s "$expected_waypaper_keybindings" "$waypaper_keybindings" &&
   grep -Fqx '/* Inherit the managed GTK theme while keeping a valid customization target. */' "$waypaper_style" &&
   grep -q 'usr/local/bin/labwc-wallpaper-save /usr/local/bin/labwc-wallpaper-save 0755' "$desktop_components" &&
   grep -q 'etc/skel/.config/waypaper/config.ini /etc/skel/.config/waypaper/config.ini 0644' "$desktop_components" &&
   grep -q 'etc/skel/.config/waypaper/keybindings.ini /etc/skel/.config/waypaper/keybindings.ini 0644' "$desktop_components" &&
   grep -q 'etc/skel/.config/waypaper/style.css /etc/skel/.config/waypaper/style.css 0644' "$desktop_components" &&
   grep -q '^    \.config/waypaper \\$' "$desktop_components"; then
  pass "Waypaper delegates the systemd-owned swaybg lifecycle to the state helper"
else
  fail "Waypaper delegates the systemd-owned swaybg lifecycle to the state helper"
fi

helper_root="$TMP_DIR/usr/share/backgrounds/desktop"
helper_home="$TMP_DIR/home"
helper_copy="$TMP_DIR/labwc-wallpaper-save"
systemctl_stub="$TMP_DIR/systemctl"
systemctl_log="$TMP_DIR/systemctl.log"
expected_systemctl_log="$TMP_DIR/systemctl.expected"
mkdir -p "$helper_root" "$helper_home"
cp "$desktop_wallpaper" "$helper_root/valid.png"
cp "$desktop_wallpaper" "$helper_root/executable.png"
chmod 0755 "$helper_root/executable.png"
printf 'not an image\n' >"$helper_root/fake.png"
cp "$desktop_wallpaper" "$TMP_DIR/outside.png"
cat >"$systemctl_stub" <<'EOF'
#!/bin/sh
set -eu

: "${SYSTEMCTL_LOG:?SYSTEMCTL_LOG must be set}"
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"

case "$*" in
  '--user --quiet is-active labwc-session.target')
    [ "${SYSTEMCTL_TARGET_ACTIVE:-true}" = true ]
    ;;
  '--user restart swaybg.service')
    [ "${SYSTEMCTL_RESTART_OK:-true}" = true ]
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod 0755 "$systemctl_stub"
cat >"$expected_systemctl_log" <<'EOF'
--user --quiet is-active labwc-session.target
--user restart swaybg.service
EOF
sed \
  -e "s#wallpaper_root=/usr/share/backgrounds/desktop#wallpaper_root=${helper_root}#" \
  -e "s#/usr/bin/systemctl#${systemctl_stub}#g" \
  "$wallpaper_save" \
  >"$helper_copy"
chmod 0755 "$helper_copy"
resolved_helper_wallpaper=$(readlink -f "$helper_root/valid.png")
quiet_helper_stderr="$TMP_DIR/quiet-helper.stderr"
if HOME="$helper_home" "$helper_copy" "$helper_root/valid.png" &&
   [ "$(cat "$helper_home/.local/state/labwc/wallpaper")" = "$resolved_helper_wallpaper" ] &&
   [ "$(stat -c %a "$helper_home/.local/state/labwc/wallpaper")" = 600 ] &&
   [ "$(HOME="$helper_home" "$helper_copy" --current)" = "$resolved_helper_wallpaper" ] &&
   ! HOME="$helper_home" "$helper_copy" "$TMP_DIR/outside.png" >/dev/null 2>&1 &&
   ! HOME="$helper_home" "$helper_copy" "$helper_root/executable.png" >/dev/null 2>&1 &&
   ! HOME="$helper_home" "$helper_copy" "$helper_root/fake.png" >/dev/null 2>&1 &&
   ! HOME="$helper_home" "$helper_copy" --quiet "$TMP_DIR/outside.png" >/dev/null 2>"$quiet_helper_stderr" &&
   [ ! -s "$quiet_helper_stderr" ] &&
   SYSTEMCTL_LOG="$systemctl_log" HOME="$helper_home" "$helper_copy" --apply "$helper_root/valid.png" &&
   cmp -s "$expected_systemctl_log" "$systemctl_log" &&
   : >"$systemctl_log" &&
   SYSTEMCTL_LOG="$systemctl_log" SYSTEMCTL_TARGET_ACTIVE=false \
     HOME="$helper_home" "$helper_copy" --apply "$helper_root/valid.png" &&
   grep -Fqx -- '--user --quiet is-active labwc-session.target' "$systemctl_log" &&
   [ "$(wc -l <"$systemctl_log" | tr -d ' ')" = 1 ] &&
   : >"$systemctl_log" &&
   ! SYSTEMCTL_LOG="$systemctl_log" SYSTEMCTL_RESTART_OK=false \
     HOME="$helper_home" "$helper_copy" --apply "$helper_root/valid.png" >/dev/null 2>&1 &&
   cmp -s "$expected_systemctl_log" "$systemctl_log" &&
   ! SYSTEMCTL_LOG="$systemctl_log" HOME="$helper_home" \
     "$helper_copy" --apply --current >/dev/null 2>&1 &&
   [ "$(cat "$helper_home/.local/state/labwc/wallpaper")" = "$resolved_helper_wallpaper" ] &&
   ! find "$helper_home/.local/state/labwc" -name '.wallpaper.*' -print | grep -q .; then
  pass "wallpaper helper stores valid images and applies active-session changes through systemd"
else
  fail "wallpaper helper stores valid images and applies active-session changes through systemd"
fi

if grep -q 'greeter_background_url="file://${LABWC_GREETER_BACKGROUND_PATH:-/usr/share/backgrounds/login/welcome-1920x1080.png}"' "$desktop_components" &&
   grep -q '^  background-image: url("__INSTALLER_LABWC_GREETER_BACKGROUND_URL__");$' "$gtkgreet_css"; then
  pass "gtkgreet keeps using the managed greeter background placeholder with the new welcome wallpaper path"
else
  fail "gtkgreet keeps using the managed greeter background placeholder with the new welcome wallpaper path"
fi

if grep -q 'wallpaper_path=${LABWC_WALLPAPER_PATH:-/usr/share/backgrounds/desktop/wallpaper-1920x1080.png}' "$swaybg_wrapper" &&
   grep -q '/usr/local/bin/labwc-wallpaper-save --current' "$swaybg_wrapper" &&
   grep -q 'if \[ -n "$saved_wallpaper_path" \]; then' "$swaybg_wrapper" &&
   grep -q 'exec "$swaybg_cmd" -m fill -i "$wallpaper_path"' "$swaybg_wrapper"; then
  pass "the swaybg service wrapper restores a validated saved wallpaper or uses the managed fallback"
else
  fail "the swaybg service wrapper restores a validated saved wallpaper or uses the managed fallback"
fi

if grep -q '^image=/usr/share/backgrounds/login/lock-1920x1080.png$' "$swaylock_config" &&
   ! grep -q '^indicator$' "$swaylock_config" &&
   grep -q 'lock_background_path=${LABWC_LOCK_BACKGROUND_PATH:-/usr/share/backgrounds/login/lock-1920x1080.png}' "$lock_wrapper" &&
   grep -q '^run_swaylock() {$' "$lock_wrapper" &&
   grep -q 'flock -n 9 || exit 0' "$lock_wrapper" &&
   grep -q 'swaylock -f -c "$config_path" --image "$lock_background_path" --scaling fill "$@" 9>&-' "$lock_wrapper"; then
  pass "lock handling uses a valid swaylock config, the managed wallpaper, and a single locker instance"
else
  fail "lock handling uses a valid swaylock config, the managed wallpaper, and a single locker instance"
fi

if grep -q '/usr/share/backgrounds/desktop/wallpaper-1920x1080.png' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-wallpaper-save' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-swaybg' "$desktop_verify" &&
   grep -q '/etc/skel/.config/waypaper/config.ini' "$desktop_verify" &&
   grep -q '/etc/skel/.config/waypaper/keybindings.ini' "$desktop_verify" &&
   grep -q '/etc/skel/.config/waypaper/style.css' "$desktop_verify" &&
   grep -q 'require_absent /usr/share/backgrounds/desktop/wallpapers.tar.gz' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-wallpaper-save' "$firstboot_validate" &&
   grep -q '/etc/skel/.config/waypaper/config.ini' "$firstboot_validate" &&
   grep -q '/etc/skel/.config/waypaper/keybindings.ini' "$firstboot_validate" &&
   grep -q '/etc/skel/.config/waypaper/style.css' "$firstboot_validate" &&
   grep -q '/usr/share/backgrounds/desktop/labwall0-1920x1080.png' "$firstboot_validate" &&
   grep -q 'desktop-wallpaper-archive-not-installed' "$firstboot_validate" &&
   grep -q '/usr/share/backgrounds/login/lock-1920x1080.png' "$desktop_verify" &&
   grep -q '/usr/share/backgrounds/login/welcome-1920x1080.png' "$desktop_verify" &&
   grep -q '/usr/share/backgrounds/other/regreet-000-greeter-purple.svg' "$desktop_verify" &&
   grep -q '/usr/share/backgrounds/other/wp2653774-black-and-blue-wallpaper-hd.png' "$desktop_verify"; then
  pass "desktop verification checks the staged wallpaper files in the new folder layout"
else
  fail "desktop verification checks the staged wallpaper files in the new folder layout"
fi

if ! find "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/backgrounds" -path '*/labwc/wallpapers/*' | grep -q .; then
  pass "the old labwc wallpaper subtree is no longer populated"
else
  fail "the old labwc wallpaper subtree is no longer populated"
fi

[ "$FAIL_COUNT" -eq 0 ]
