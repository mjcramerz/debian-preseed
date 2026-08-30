#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-verify-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=87
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

make_stub() {
  stub_name=$1
  stub_path="$2/$stub_name"
  mkdir -p "$(dirname "$stub_path")"
  cat >"$stub_path" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod 0755 "$stub_path"
}

run_verify_required() {
  mock_path=$1
  (
    set -eu
    run_in_target() {
      label=$1
      shift
      PATH="$mock_path" "$@"
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
    desktop_verify_required_commands
  )
}

run_verify_inline_syntax() {
  (
    set -eu
    run_in_target() {
      label=$1
      shift
      [ "$#" -ge 3 ] || {
        printf 'fatal: %s did not pass a /bin/sh -c payload\n' "$label" >&2
        exit 1
      }
      [ "$1" = /bin/sh ] && [ "$2" = -c ] || {
        printf 'fatal: %s used unexpected target shell invocation: %s %s\n' "$label" "$1" "$2" >&2
        exit 1
      }
      if ! /bin/sh -n -c "$3"; then
        printf 'fatal: %s generated invalid /bin/sh -c payload\n' "$label" >&2
        exit 1
      fi
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
    desktop_verify_required_commands
    ACCOUNT_USERNAME=user desktop_verify_staged_files
    desktop_verify_optional_staged_files
    ACCOUNT_USERNAME=user ACCOUNT_HOME=/home/user desktop_verify_primary_user_files
    LABWC_GREETER_USER=greeter desktop_verify_greeter_access
    desktop_verify_user_resource_policy
  )
}

run_calendar_token_preflight() {
  test_cmdline=$1
  fatal_message_path=$2
  expected_username=$3
  expected_password=$4
  expected_telegram_api_key=$5
  expected_telegram_chat_id=$6
  (
    set -eu
    INSTALLER_CMDLINE=$test_cmdline
    installer_cmdline() {
      printf '%s\n' "$INSTALLER_CMDLINE"
    }
    installer_cmdline_value() {
      wanted_key=$1
      for cmdline_arg in $(installer_cmdline); do
        case "$cmdline_arg" in
          "$wanted_key"=*)
            printf '%s\n' "${cmdline_arg#*=}"
            return 0
            ;;
        esac
      done
      return 1
    }
    installer_fatal() {
      printf '%s\n' "$*" >"$fatal_message_path"
      exit 1
    }
    desktop_log() {
      :
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/hosts/shared/account.env"
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
    desktop_preflight_required_cmdline_tokens
    [ "$DESKTOP_FRUUX_USERNAME" = "$expected_username" ]
    [ "$DESKTOP_FRUUX_PASSWORD" = "$expected_password" ]
    [ "$DESKTOP_TELEGRAM_API_KEY" = "$expected_telegram_api_key" ]
    [ "$DESKTOP_TELEGRAM_CHAT_ID" = "$expected_telegram_chat_id" ]
  )
}

run_gpg_passphrase_helper() {
  expected_passphrase=$1
  account_gpg_passphrase=$2
  account_gpg_passphrase_is_plain=$3
  (
    set -eu
    ACCOUNT_GPG_PASSPHRASE=$account_gpg_passphrase
    ACCOUNT_GPG_PASSPHRASE_IS_PLAIN=$account_gpg_passphrase_is_plain
    installer_fatal() {
      printf 'fatal: %s\n' "$*" >&2
      exit 1
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
    actual_passphrase=$(desktop_primary_account_gpg_passphrase)
    [ "$actual_passphrase" = "$expected_passphrase" ]
  )
}

run_xwayland_find_portability() (
  set -eu
  xwayland_installer_path=$1
  xwayland_find_test_root="$TMP_DIR/xwayland-find-portability"
  xwayland_find_test_bin="$xwayland_find_test_root/bin"
  xwayland_find_test_payload="$xwayland_find_test_root/payload"
  xwayland_find_test_output="$xwayland_find_test_root/find-output"

  mkdir -p \
    "$xwayland_find_test_bin" \
    "$xwayland_find_test_payload/usr" \
    "$xwayland_find_test_payload/var"
  cat >"$xwayland_find_test_bin/find" <<'EOF'
#!/bin/sh
set -eu
for argument in "$@"; do
  [ "$argument" != -quit ] || {
    printf 'unrecognized: %s\n' "$argument" >&2
    exit 64
  }
done
exec /usr/bin/find "$@"
EOF
  chmod 0755 "$xwayland_find_test_bin/find"

  installer_fatal() {
    printf 'fatal: %s\n' "$*" >&2
    exit 1
  }
  PATH="$xwayland_find_test_bin:$PATH"
  export PATH
  # shellcheck disable=SC1090
  . "$xwayland_installer_path"

  mkfifo "$xwayland_find_test_payload/special-node"
  xwayland_first_path=$(
    desktop_xwayland_find_first_path \
      "unsupported special files" \
      "$xwayland_find_test_output" \
      "$xwayland_find_test_payload" -xdev \
      \( -type b -o -type c -o -type p -o -type s \)
  )
  [ "$xwayland_first_path" = "$xwayland_find_test_payload/special-node" ]
  rm -f "$xwayland_find_test_payload/special-node"

  : >"$xwayland_find_test_payload/setid-file"
  chmod 4755 "$xwayland_find_test_payload/setid-file"
  xwayland_first_path=$(
    desktop_xwayland_find_first_path \
      "set-ID files" \
      "$xwayland_find_test_output" \
      "$xwayland_find_test_payload" -xdev -type f -perm /6000
  )
  [ "$xwayland_first_path" = "$xwayland_find_test_payload/setid-file" ]
  rm -f "$xwayland_find_test_payload/setid-file"

  xwayland_first_path=$(
    desktop_xwayland_find_first_path \
      "top-level entries" \
      "$xwayland_find_test_output" \
      "$xwayland_find_test_payload" -mindepth 1 -maxdepth 1 \
      ! -name usr \
      ! -name var
  )
  [ -z "$xwayland_first_path" ]

  mkdir "$xwayland_find_test_payload/unexpected"
  xwayland_first_path=$(
    desktop_xwayland_find_first_path \
      "top-level entries" \
      "$xwayland_find_test_output" \
      "$xwayland_find_test_payload" -mindepth 1 -maxdepth 1 \
      ! -name usr \
      ! -name var
  )
  [ "$xwayland_first_path" = "$xwayland_find_test_payload/unexpected" ]
)

run_calendar_sync_wrapper() {
  wrapper_path=$1
  log_path=$2
  home_path=$3
  runtime_path=$4
  bin_path="$TMP_DIR/calendar-wrapper-bin"

  mkdir -p "$bin_path" \
    "$home_path/.config/vdirsyncer" \
    "$home_path/.local/share" \
    "$home_path/.local/state" \
    "$runtime_path"

  cat >"$bin_path/vdirsyncer" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${CALENDAR_WRAPPER_LOG:?}"
exit 0
EOF
  chmod 0755 "$bin_path/vdirsyncer"

  cat >"$home_path/.config/vdirsyncer/config" <<'EOF'
[general]
status_path = "~/.local/state/vdirsyncer/status/"

[pair fruux_calendar]
a = "fruux_calendar_local"
b = "fruux_calendar_remote"
collections = null
EOF

  (
    set -eu
    PATH="$bin_path:$PATH" \
    HOME="$home_path" \
    XDG_CONFIG_HOME="$home_path/.config" \
    XDG_DATA_HOME="$home_path/.local/share" \
    XDG_STATE_HOME="$home_path/.local/state" \
    XDG_RUNTIME_DIR="$runtime_path" \
    CALENDAR_WRAPPER_LOG="$log_path" \
      /bin/sh "$wrapper_path" sync --quiet
  )
}

run_calendar_menu_wrapper() {
  wrapper_path=$1
  log_path=$2
  home_path=$3
  runtime_path=$4
  bin_path="$TMP_DIR/calendar-menu-bin"

  mkdir -p "$bin_path" "$home_path/.config" "$runtime_path"

  cat >"$bin_path/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >"${CALENDAR_MENU_LOG:?}"
exit 0
EOF
  chmod 0755 "$bin_path/labwc-fuzzel"

  (
    set -eu
    PATH="$bin_path:$PATH" \
    HOME="$home_path" \
    XDG_CONFIG_HOME="$home_path/.config" \
    XDG_DATA_HOME="$home_path/.local/share" \
    XDG_STATE_HOME="$home_path/.local/state" \
    XDG_RUNTIME_DIR="$runtime_path" \
    CALENDAR_MENU_LOG="$log_path" \
      /bin/sh "$wrapper_path" menu
  )
}

printf '1..%s\n' "$TEST_COUNT"

required_desktop_commands='
labwc
cage
slirp4netns
gtkgreet
greetd-power-action
labwc-greeter-output
labwc-greeter-power
labwc-greeter-session
labwc-session
labwc-autostart
labwc-admin-action
labwc-calendar
labwc-ocr
labwc-logout
labwc-fuzzel
labwc-computer-management
labwc-ai-copilots
labwc-ai-copilots-action
labwc-digital-assets
labwc-digital-assets-action
labwc-users-groups-menu
labwc-adb-menu
labwc-adb-action
labwc-maintenance-menu
labwc-podman-menu
labwc-external-drives
labwc-security-action
labwc-system-action
labwc-recovery-action
labwc-network-control-menu
labwc-network-control-action
labwc-firewall-menu
labwc-firewall-action
labwc-network-scan-menu
labwc-network-scan-action
labwc-remote-desktop
labwc-freerdp-askpass
labwc-run
labwc-terminal
labwc-bluetooth
labwc-brightness-control
labwc-power-settings
labwc-power-menu
labwc-output-refresh
wayland-info
labwc-output-watch
labwc-kanshi
labwc-swaybg
labwc-swayidle
labwc-managed-app
labwc-qbittorrent
labwc-sync-application-launchers
labwc-keyboard-layout
labwc-capture
labwc-wayscriber-toggle
satty
wayscriber
systemctl
systemd-run
dbus-update-activation-environment
desktop-file-validate
grim
slurp
wf-recorder
wl-copy
khal
keepassxc
recoll
recollindex
fido2-token
mail
pkexec
eject
lsblk
sync
udisksctl
lynis
rkhunter
chkrootkit
systemd-analyze
fwupdmgr
spectre-meltdown-checker
debsecan
debsums
ss
nmap
lua5.5
luac5.5
dumpcap
tshark
tcpdump
wireshark
clamscan
freshclam
fangfrisch
visudo
aa-easyprof
aa-enabled
aa-features-abi
aa-audit
aa-autodep
aa-genprof
aa-logprof
aa-remove-unknown
aa-unconfined
logrotate
rsyslogd
ip
ifup
ifdown
ifquery
nmcli
perl
python3
flock
notify-send
sendmail
tesseract
todoman
task
taskwarrior-tui
vdirsyncer
'

core_path="$TMP_DIR/core-bin"
for cmd in $required_desktop_commands; do
  make_stub "$cmd" "$core_path"
done

if run_verify_required "$core_path"; then
  pass "optional desktop commands do not fail target verification"
else
  fail "optional desktop commands do not fail target verification"
fi

missing_required_path="$TMP_DIR/missing-required-bin"
for cmd in $required_desktop_commands; do
  [ "$cmd" != labwc ] || continue
  make_stub "$cmd" "$missing_required_path"
done

if run_verify_required "$missing_required_path"; then
  fail "required desktop commands still fail target verification when absent"
else
  pass "required desktop commands still fail target verification when absent"
fi

if run_verify_inline_syntax; then
  pass "desktop in-target verification snippets are POSIX sh syntax-valid"
else
  fail "desktop in-target verification snippets are POSIX sh syntax-valid"
fi

desktop_role_hook="$ROOT_DIR/d-i/forky/hooks/role/desktop/late_command.sh"
if grep -q '^desktop_late_stage_stamp=' "$desktop_role_hook" &&
   grep -q 'managed Labwc desktop role already completed earlier in this install; skipping duplicate late_command run' "$desktop_role_hook" &&
   grep -q '^: >"\$desktop_late_stage_stamp"$' "$desktop_role_hook" &&
   grep -q 'completion stamp recorded' "$desktop_role_hook"; then
  pass "desktop late-command persists a completion stamp so finish-install retries skip duplicate target staging"
else
  fail "desktop late-command persists a completion stamp so finish-install retries skip duplicate target staging"
fi

desktop_packages_file="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
if grep -Eq '(^|[[:space:]])gvfs-backends([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])wsdd(/forky)?([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])file([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libgtk-4-1([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libadwaita-1-0([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])wayland-utils([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])wf-recorder([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])grim([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])slurp([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])brightness-udev([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])bluez([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])rfkill([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libinput-tools([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])keepassxc([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])fido2-tools([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libfido2-1([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])recoll([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])recollgui([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])libccid([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])cage([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])slirp4netns([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])xwayland([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])tesseract-ocr([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])tesseract-ocr-eng([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])tesseract-ocr-swe([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])poppler-utils([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])(jsonlint|php([[:alnum:].-]*)?)([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set installs nested Cage, private-network support, Wayland readiness, diagnostics, Recoll, and FIDO2 support without system Xwayland, CCID, or PHP tooling"
else
  fail "desktop package set installs nested Cage, private-network support, Wayland readiness, diagnostics, Recoll, and FIDO2 support without system Xwayland, CCID, or PHP tooling"
fi

shared_skel_config="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/skel/.config"
desktop_skel_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config"
desktop_account_script="$ROOT_DIR/d-i/forky/scripts/late/account.sh"
desktop_components_script="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify_script="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
desktop_labwc_script="$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"
focuswriter_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/GottCode/FocusWriter.conf"
focuswriter_theme="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/GottCode/FocusWriter/Themes/managed-word.theme"
recoll_gui_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/Recoll.org/recoll.ini"
recoll_index_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.recoll/recoll.conf"
recoll_ini_valid=false
if python3 - "$recoll_gui_config" <<'PY'
import configparser
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
parser = configparser.RawConfigParser()
parser.optionxform = str
with path.open(encoding="utf-8") as handle:
    parser.read_file(handle)

section = parser["Recoll"]
expected = {
    r"prefs\ssearch\idxfiltertreedepth": "3",
    r"prefs\simpleSearchTyp": "3",
    r"prefs\previewHtml": "true",
    r"prefs\previewActiveLinks": "false",
    r"prefs\reslist\pagelen": "20",
    r"prefs\historysize": "100",
    r"prefs\reslist\collapseDuplicates": "true",
    r"prefs\preview\maxhltextkbs": "8192",
    r"prefs\query\stemLang": "ALL",
    r"prefs\useDesktopOpen": "true",
    r"prefs\query\buildAbstract": "true",
    r"prefs\query\syntAbsLen": "320",
    r"prefs\query\syntAbsCtx": "6",
    r"prefs\reslist\alwaysSnippets": "true",
    r"prefs\query\noBeeps": "true",
    r"ui\showcompleterhitcounts": "true",
    r"ui\colorscheme": "2",
    r"ui\singleapp": "true",
    r"preview\previewdarkbg": "false",
    r"prefs\rclVersion": "1009",
}
for key, value in expected.items():
    if section.get(key) != value:
        raise SystemExit(f"{key} mismatch")
PY
then
  recoll_ini_valid=true
fi

if [ "$recoll_ini_valid" = true ] &&
   awk '
     /^[[:space:]]*($|#|\[)/ { next }
     /^[[:space:]]+/ { next }
     /^[[:space:]]*[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-]*[[:space:]]*=/ { next }
     { exit 1 }
   ' "$recoll_index_config" &&
   ! grep -q '__INSTALLER_' "$recoll_gui_config" &&
   ! grep -q '__INSTALLER_' "$recoll_index_config" &&
   grep -Fq 'topdirs = ~' "$recoll_index_config" &&
   grep -Fq 'skippedNames+ = .git .svn .hg .bzr .jj .pijul _darcs \' "$recoll_index_config" &&
   grep -Fq '    .fossil-settings CVS node_modules .venv venv .mypy_cache .ruff_cache \' "$recoll_index_config" &&
   grep -Fq 'skippedPaths = /media /mnt /run/user/*/gvfs \' "$recoll_index_config" &&
   grep -Fq '    ~/.aws ~/.azure ~/.docker ~/.gnupg ~/.kube ~/.ssh \' "$recoll_index_config" &&
   grep -Fq '    ~/.config/containers ~/.config/gcloud ~/.config/gh \' "$recoll_index_config" &&
   grep -Fq '    ~/Syncthing/keepassxc' "$recoll_index_config" &&
   ! grep -Eq '^[[:space:]]*~/Syncthing([[:space:]\\]|$)' "$recoll_index_config" &&
   grep -Fq 'nowalkfn = .recoll-noindex' "$recoll_index_config" &&
   grep -Fq 'pdfocr = 1' "$recoll_index_config" &&
   grep -Fq 'pdfforceocr = 0' "$recoll_index_config" &&
   grep -Fq 'ocrprogs = tesseract' "$recoll_index_config" &&
   grep -Fq 'tesseractlang = eng+swe' "$recoll_index_config" &&
   grep -Fq 'ocrcachedir = ~/.cache/recoll/ocrcache' "$recoll_index_config" &&
   grep -Fq 'indexstemminglanguages = english swedish' "$recoll_index_config" &&
   grep -Fq 'cachedir = ~/.cache/recoll' "$recoll_index_config" &&
   grep -Fq 'maxfsoccuppc = 90' "$recoll_index_config" &&
   grep -Fq 'filtermaxseconds = 300' "$recoll_index_config" &&
   grep -Fq 'suspendonbattery = 1' "$recoll_index_config" &&
   grep -Fq 'desktop_stage_role_asset etc/skel/.config/Recoll.org/recoll.ini /etc/skel/.config/Recoll.org/recoll.ini 0600' "$desktop_components_script" &&
   grep -Fq 'desktop_stage_role_asset etc/skel/.recoll/recoll.conf /etc/skel/.recoll/recoll.conf 0644' "$desktop_components_script" &&
   grep -Fq 'chmod 0700 /target/etc/skel/.config/Recoll.org' "$desktop_components_script" &&
   grep -Fq 'chmod 0700 /target/etc/skel/.recoll' "$desktop_components_script" &&
   grep -Fq 'install -d -m 0700 /target/etc/skel/.cache /target/etc/skel/.cache/recoll' "$desktop_components_script" &&
   grep -Fq 'install -d -m 0700 "$account_home/.cache"' "$desktop_components_script" &&
   grep -Fq '.cache/recoll \' "$desktop_components_script" &&
   grep -Fq '.config/Recoll.org \' "$desktop_components_script" &&
   grep -Fq '.recoll \' "$desktop_components_script" &&
   grep -Fq '/etc/skel/.config/Recoll.org/recoll.ini \' "$desktop_verify_script" &&
   grep -Fq '/etc/skel/.recoll/recoll.conf \' "$desktop_verify_script"; then
  pass "Recoll packages, GUI preferences, private index configuration, staging, and account-copy contracts are complete"
else
  fail "Recoll packages, GUI preferences, private index configuration, staging, and account-copy contracts are complete"
fi

desktop_editor_configs_ok=true
for config_path in \
  featherpad/fp.conf \
  GottCode/FocusWriter.conf \
  kdiff3rc \
  micro/settings.json \
  nano/nanorc \
  nvim/init.lua \
  qalculate/qalc.cfg \
  qalculate/qalculate-qt.cfg \
  vim/vimrc
do
  [ -f "$desktop_skel_config/$config_path" ] || desktop_editor_configs_ok=false
  [ ! -e "$shared_skel_config/$config_path" ] || desktop_editor_configs_ok=false
  grep -Fq \
    "desktop_stage_role_asset etc/skel/.config/$config_path /etc/skel/.config/$config_path 0644" \
    "$desktop_components_script" || desktop_editor_configs_ok=false
  [ "$(grep -Fc ".config/$config_path" "$desktop_verify_script")" -eq 2 ] ||
    desktop_editor_configs_ok=false
  case "$config_path" in
    kdiff3rc)
      grep -Fq '.config/kdiff3rc' "$desktop_components_script" ||
        desktop_editor_configs_ok=false
      ;;
    *)
      config_dir=${config_path%%/*}
      grep -Eq "^[[:space:]]+\\.config/${config_dir}[[:space:]]+\\\\$" \
        "$desktop_components_script" || desktop_editor_configs_ok=false
      ;;
  esac
done
desktop_stage_line=$(grep -n '^  desktop_stage_target_assets$' "$desktop_labwc_script" | cut -d: -f1)
desktop_user_copy_line=$(grep -n '^  desktop_install_user_config$' "$desktop_labwc_script" | cut -d: -f1)
if [ "$desktop_editor_configs_ok" = true ] &&
   grep -Eq '(^|[[:space:]])nano([[:space:]]|$)' "$desktop_packages_file" &&
   grep -q '^set autoindent$' "$desktop_skel_config/nano/nanorc" &&
   grep -q '^set linenumbers$' "$desktop_skel_config/nano/nanorc" &&
   grep -q '^set tabstospaces$' "$desktop_skel_config/nano/nanorc" &&
   grep -q '^include "/usr/share/nano/\*\.nanorc"$' "$desktop_skel_config/nano/nanorc" &&
   grep -q '^include "/usr/share/nano/debian/\*\.nanorc"$' "$desktop_skel_config/nano/nanorc" &&
   grep -q '^include "/usr/share/nano/extra/\*\.nanorc"$' "$desktop_skel_config/nano/nanorc" &&
   grep -q '^DefaultFormat=docx$' "$focuswriter_config" &&
   grep -q '^Theme=managed-word$' "$focuswriter_config" &&
   grep -q '^ThemeDefault=false$' "$focuswriter_config" &&
   grep -q '^RestoreSession=true$' "$focuswriter_config" &&
   grep -q '^Color=#34383f$' "$focuswriter_theme" &&
   grep -q '^Color=#ffffff$' "$focuswriter_theme" &&
   grep -q '^Position=1$' "$focuswriter_theme" &&
   grep -q '^Width=900$' "$focuswriter_theme" &&
   grep -Fq '.local/share/GottCode/FocusWriter' "$desktop_components_script" &&
   ! grep -Eq 'DIR_HOOKS_SHARED_TARGET etc/skel/\.config/(featherpad|GottCode|kdiff3rc|micro|nvim|qalculate|vim)' "$desktop_account_script" &&
   grep -Fq 'source_path=$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP "target/$role_relpath")' "$desktop_components_script" &&
   [ -n "$desktop_stage_line" ] &&
   [ -n "$desktop_user_copy_line" ] &&
   [ "$desktop_stage_line" -lt "$desktop_user_copy_line" ]; then
  pass "desktop editor and utility defaults are owned and staged exclusively by the desktop role"
else
  fail "desktop editor and utility defaults are owned and staged exclusively by the desktop role"
fi

satty_installer="$ROOT_DIR/d-i/forky/scripts/desktop/satty.sh"
xwayland_installer="$ROOT_DIR/d-i/forky/scripts/desktop/xwayland.sh"
samloader_installer="$ROOT_DIR/d-i/forky/scripts/desktop/samloader.sh"
digital_assets_installer="$ROOT_DIR/d-i/forky/scripts/desktop/digital-assets.sh"
samsung_extractor="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-samsung-firmware-extract"
satty_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/satty/config.toml"
satty_overrides="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/satty/overrides.css"
capture_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-capture"
satty_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/satty"
desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
desktop_labwc="$ROOT_DIR/d-i/forky/scripts/desktop/labwc.sh"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
common_cfg="$ROOT_DIR/d-i/forky/common.cfg"
apt_cfg="$ROOT_DIR/d-i/forky/fragments/apt.cfg"
repo_env="$ROOT_DIR/d-i/forky/repo.env"
experimental_desktop_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/experimental.pref"
experimental_server_pref="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/server/experimental.pref"
if /bin/sh -n "$satty_installer" &&
   /bin/sh -n "$samloader_installer" &&
   /bin/sh -n "$digital_assets_installer" &&
   /bin/sh -n "$capture_helper" &&
   python3 -m py_compile "$samsung_extractor" &&
   /bin/sh -n "$satty_wrapper" &&
   grep -q '^d-i apt-setup/local20/repository string https://deb.debian.org/debian experimental main$' "$apt_cfg" &&
   grep -q '^d-i apt-setup/local20/key string https://ftp-master.debian.org/keys/archive-key-13.asc$' "$apt_cfg" &&
   grep -q '^d-i apt-setup/local20/source boolean false$' "$apt_cfg" &&
   grep -q '^DEBIAN_APT_PREFERENCES="forky,trixie,sid,experimental,cramerz,dbus,x11,vulkan"$' "$repo_env" &&
   grep -q '^Pin: release a=experimental,n=rc-buggy$' "$experimental_desktop_pref" &&
   grep -q '^Pin-Priority: 1$' "$experimental_desktop_pref" &&
   cmp -s "$experimental_desktop_pref" "$experimental_server_pref" &&
   grep -q '^LABWC_SATTY_VERSION="0.21.1"$' "$desktop_env" &&
   grep -q '^LABWC_SATTY_ARCHITECTURE="amd64"$' "$desktop_env" &&
   grep -q '^LABWC_SATTY_SHA256="63816f3f797950751881147eeb0eb999f14efc8c613adb9937672e6a2df18120"$' "$desktop_env" &&
   grep -q '^LABWC_SATTY_GLIBC_VERSION="2.44-1"$' "$desktop_env" &&
   grep -q '^LABWC_SATTY_GLIBC_LIBC6_SHA256="17d9a246ae46a457227c19a3d821c49d68b9c6f9531bfa6f52d9c064307de585"$' "$desktop_env" &&
   grep -q '^LABWC_SATTY_GLIBC_GCONV_SHA256="00408257a5287df51898bb5f71beca80a37f1b569c2ae6b977cb6b27de2929b2"$' "$desktop_env" &&
   grep -q '^LABWC_SATTY_GLIBC_RUNTIME_ROOT="/opt/glibc/2.44-1/satty"$' "$desktop_env" &&
   grep -q '^SAMLOADER_VERSION="2.0.0"$' "$desktop_env" &&
   grep -q '^SAMLOADER_SHA256="7c6514028f20d5ea0eb57d6f872eee41b3a52336eabac6379b15a01a06ed7a79"$' "$desktop_env" &&
   grep -q '^DIGITAL_ASSETS_PDFCPU_URL="https://github.com/pdfcpu/pdfcpu/releases/download/v0.13.0/pdfcpu_0.13.0_Linux_x86_64.tar.xz"$' "$desktop_env" &&
   grep -q '^DIGITAL_ASSETS_PDFCPU_SHA256="0f03f691c6275fa826e5d99e7aefbc8050180e4bc4a3b919b582137cd7da9bd7"$' "$desktop_env" &&
   grep -q '^DIGITAL_ASSETS_TYPST_URL="https://github.com/typst/typst/releases/download/v0.15.1/typst-x86_64-unknown-linux-musl.tar.xz"$' "$desktop_env" &&
   grep -q '^DIGITAL_ASSETS_TYPST_SHA256="a6d077d0a95eed5a2eba715b2dae06be954f624ccbf85758a03f389ded33118c"$' "$desktop_env" &&
   grep -Eq '(^|[[:space:]])pandoc([[:space:]]|$)' "$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg" &&
   grep -Eq '(^|[[:space:]])qpdf([[:space:]]|$)' "$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg" &&
   grep -Eq '(^|[[:space:]])libarchive-zip-perl([[:space:]]|$)' "$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg" &&
   grep -Eq '(^|[[:space:]])graphicsmagick([[:space:]]|$)' "$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg" &&
   grep -q -- "--proto '=https'" "$satty_installer" &&
   grep -q -- '--max-filesize "$LABWC_SATTY_MAXIMUM_BYTES"' "$satty_installer" &&
   ! grep -Fq "tr -d '[:space:]'" "$satty_installer" &&
   ! grep -q -- '-quit' "$samloader_installer" &&
   ! grep -Fq "tr -d '[:space:]'" "$samloader_installer" &&
   ! grep -q -- '--target-release experimental' "$satty_installer" &&
   grep -Fq 'satty_glibc_snapshot_base=https://snapshot.debian.org/archive/debian/20260810T202458Z/pool/main/g/glibc' "$satty_installer" &&
   grep -q 'libc6_${LABWC_SATTY_GLIBC_VERSION}_${LABWC_SATTY_GLIBC_ARCHITECTURE}.deb' "$satty_installer" &&
   grep -q 'libc-gconv-modules-extra_${LABWC_SATTY_GLIBC_VERSION}_${LABWC_SATTY_GLIBC_ARCHITECTURE}.deb' "$satty_installer" &&
   grep -q -- '--max-filesize "$satty_private_download_maximum_bytes"' "$satty_installer" &&
   grep -q -- '--url "$satty_private_download_url"' "$satty_installer" &&
   grep -q 'download private Satty ${satty_private_download_name} package from Debian Snapshot' "$satty_installer" &&
   ! grep -q -- '/usr/bin/apt-get' "$satty_installer" &&
   ! grep -q -- '-y install' "$satty_installer" &&
   ! grep -q -- 'dpkg -i' "$satty_installer" &&
   grep -q 'libc-gconv-modules-extra (= ${LABWC_SATTY_GLIBC_VERSION})' "$satty_installer" &&
   grep -q 'target libgcc-s1 runtime is not installed' "$satty_installer" &&
   grep -Fq '[ "$LABWC_SATTY_GLIBC_RUNTIME_ROOT" = /opt/glibc/2.44-1/satty ]' "$satty_installer" &&
   grep -Fq 'install -d -m 0755 /target/opt/glibc/2.44-1' "$satty_installer" &&
   grep -q '\[ "\$satty_private_version" = "\$satty_private_expected_version" \]' "$satty_installer" &&
   grep -q 'dpkg-deb -x "\$satty_glibc_deb" "\$satty_glibc_extract_dir"' "$satty_installer" &&
   grep -q 'dpkg-deb -x "\$satty_glibc_gconv_deb" "\$satty_glibc_extract_dir"' "$satty_installer" &&
   grep -q 'usr/local/libexec/satty/satty' "$satty_installer" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/satty /usr/local/bin/satty 0755' "$satty_installer" &&
   grep -q 'attempt_in_target "extract pinned Satty archive"' "$satty_installer" &&
   grep -q -- '--no-same-owner' "$satty_installer" &&
   grep -q -- '--no-same-permissions' "$satty_installer" &&
   grep -q 'for desktop_module in detect components satty xwayland waypaper android-platform-tools samloader digital-assets labwc' "$desktop_role_hook" &&
   grep -Fqx ". \"\${desktop_module_dir}/digital-assets.sh\"" "$desktop_role_hook" &&
   grep -q '^  desktop_satty_preflight_target_architecture$' "$desktop_labwc" &&
   grep -q '^  desktop_log "validated Satty target architecture=${SATTY_TARGET_ARCHITECTURE}"$' "$desktop_labwc" &&
   grep -q '^  desktop_install_satty$' "$desktop_labwc" &&
   grep -q '^  desktop_samloader_preflight_target_architecture$' "$desktop_labwc" &&
   grep -q '^  desktop_install_samloader$' "$desktop_labwc" &&
   grep -q '^  desktop_digital_assets_preflight_target_architecture$' "$desktop_labwc" &&
   grep -q '^  desktop_install_digital_assets$' "$desktop_labwc" &&
   grep -q 'ln -sfn ../lib/samloader/samloader /target/usr/local/bin/samloader' "$samloader_installer" &&
   grep -q -- "--proto '=https'" "$digital_assets_installer" &&
   grep -q 'downloaded ${tool_name} archive SHA-256 does not match the pinned digest' "$digital_assets_installer" &&
   grep -q '^  tool_member_list_maximum_blocks=' "$digital_assets_installer" &&
   grep -Fq 'ulimit -f "$maximum_blocks"' "$digital_assets_installer" &&
   grep -q 'downloaded ${tool_name} archive contains unsafe or excessive member paths' "$digital_assets_installer" &&
   grep -q 'pdf2docx==0.5.13' "$digital_assets_installer" &&
   grep -q 'pymupdf4llm==1.28.0' "$digital_assets_installer" &&
   grep -q 'PIPX_HOME="$digital_assets_pipx_home"' "$digital_assets_installer" &&
   grep -q 'ln -sfn "../lib/${tool_name}/${tool_name}" "/target/usr/local/bin/${tool_name}"' "$digital_assets_installer" &&
   grep -q 'labwc-samsung-firmware-extract' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-capture /usr/local/bin/labwc-capture 0755' "$desktop_components" &&
   grep -q 'usr/local/bin/satty /usr/local/bin/satty 0755' "$desktop_components" &&
   grep -q 'etc/skel/.config/satty/config.toml /etc/skel/.config/satty/config.toml 0644' "$desktop_components" &&
   grep -q 'etc/skel/.config/satty/overrides.css /etc/skel/.config/satty/overrides.css 0644' "$desktop_components" &&
   grep -q '^GTK_THEME=Adwaita:light$' "$satty_wrapper" &&
   grep -q '^export PATH LC_ALL GTK_THEME$' "$satty_wrapper" &&
   grep -q '^runtime_root=/opt/glibc/2.44-1/satty$' "$satty_wrapper" &&
   grep -q '^satty_binary=/usr/local/libexec/satty/satty$' "$satty_wrapper" &&
   grep -q -- '--library-path "\$satty_library_path"' "$satty_wrapper" &&
   grep -q '^resize = { mode = "smart" }$' "$satty_config" &&
   grep -q '^input-scale = 1.0$' "$satty_config" &&
   grep -q '^output-filename = "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png"$' "$satty_config" &&
   grep -q '^save-after-copy = true$' "$satty_config" &&
   grep -Fqx '.outer_box,' "$satty_overrides" &&
   grep -Fqx '.toolbar {' "$satty_overrides" &&
   grep -q '^  background-color: rgba(248, 250, 252, 0.98);$' "$satty_overrides" &&
   grep -q '^  color: #111827;$' "$satty_overrides" &&
   grep -Fq 'SCREENSHOT_DIR="${HOME}/Pictures/Screenshots"' "$capture_helper" &&
   grep -Fq 'RECORDING_DIR="${HOME}/Videos/Recordings"' "$capture_helper" &&
   grep -q 'labwc-capture must run in the managed desktop session' "$capture_helper" &&
   grep -q 'labwc-capture requires a non-root desktop runtime directory' "$capture_helper" &&
   grep -q '^if \[ "\${1:-status}" = status \]; then$' "$capture_helper" &&
   ! grep -Fq 'id -u' "$capture_helper" &&
   grep -q "'Open annotation tool'" "$capture_helper" &&
   grep -q "'Take Screenshot (Full)'" "$capture_helper" &&
   grep -q "'Take Screenshot (Box)'" "$capture_helper" &&
   grep -q "'Record Screen (Full)'" "$capture_helper" &&
   grep -q "'Record Screen (Box)'" "$capture_helper" &&
   grep -q "'Local - mkv'" "$capture_helper" &&
   grep -q "'Share - mp4'" "$capture_helper" &&
   grep -q "'Website - webm'" "$capture_helper" &&
   grep -q '^    --audio \\$' "$capture_helper" &&
   grep -q '^    --audio-backend=pipewire \\$' "$capture_helper" &&
   grep -q '^    --audio-codec "\$recording_audio_codec" \\$' "$capture_helper" &&
   grep -q '^      recording_audio_codec=libopus$' "$capture_helper" &&
   grep -q '^      recording_audio_codec=aac$' "$capture_helper" &&
   grep -Fq 'RECORDING_LOG="${RECORDING_LOG_DIR}/recording.log"' "$capture_helper" &&
   grep -Fq '"on-click-middle": "__INSTALLER_LABWC_CAPTURE_COMMAND__ stop"' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl" &&
   grep -A2 '^  primary)$' "$capture_helper" | grep -q 'annotate_capture box' &&
   ! grep -A4 '^  primary)$' "$capture_helper" | grep -q 'stop_recording' &&
   grep -q '^    --property=UMask=0077 \\$' "$capture_helper"; then
  pass "desktop role pins, validates, installs, configures, and drives Satty screenshots plus audio recordings"
else
  fail "desktop role pins, validates, installs, configures, and drives Satty screenshots plus audio recordings"
fi

if run_xwayland_find_portability "$xwayland_installer" &&
   python3 - "$ROOT_DIR" "$xwayland_installer" <<'PY'
from pathlib import Path
import re
import sys

root_dir = Path(sys.argv[1])
installer_path = Path(sys.argv[2])
installer = installer_path.read_text(encoding="utf-8")

expected_profile_policy = (
    'LABWC_XWAYLAND_VERSION="2:24.1.13-1"',
    'LABWC_XWAYLAND_ARCHITECTURE="amd64"',
    'LABWC_XWAYLAND_URL="https://snapshot.debian.org/archive/debian/20260805T142647Z/pool/main/x/xwayland/xwayland_24.1.13-1_amd64.deb"',
    'LABWC_XWAYLAND_SHA256="a0633569cf2b65d5d4902a2b6213d59c7db7973faef0233df9ace48f334ba6c2"',
    'LABWC_XWAYLAND_BYTES="992244"',
    'LABWC_XWAYLAND_COMMON_VERSION="2:21.1.24-1"',
    'LABWC_XWAYLAND_COMMON_ARCHITECTURE="all"',
    'LABWC_XWAYLAND_COMMON_URL="https://snapshot.debian.org/archive/debian/20260805T142647Z/pool/main/x/xorg-server/xserver-common_21.1.24-1_all.deb"',
    'LABWC_XWAYLAND_COMMON_SHA256="807f2faaccada8ceac329a2c4d5b264fb794baf44bd6a2a787f9a0a75a67446b"',
    'LABWC_XWAYLAND_COMMON_BYTES="2455368"',
    'LABWC_XWAYLAND_XCB_CURSOR_VERSION="0.1.6-1"',
    'LABWC_XWAYLAND_XCB_CURSOR_URL="https://snapshot.debian.org/archive/debian/20260206T022815Z/pool/main/x/xcb-util-cursor/libxcb-cursor0_0.1.6-1_amd64.deb"',
    'LABWC_XWAYLAND_XCB_CURSOR_SHA256="f2f7730d4559769ec45aa610967d27f410b642af0c993813f50092972f8da0d4"',
    'LABWC_XWAYLAND_XCB_CURSOR_BYTES="17772"',
    'LABWC_XWAYLAND_XKBCOMP_VERSION="7.7+9"',
    'LABWC_XWAYLAND_XKBCOMP_ARCHITECTURE="amd64"',
    'LABWC_XWAYLAND_XKBCOMP_URL="https://snapshot.debian.org/archive/debian/20260805T142647Z/pool/main/x/x11-xkb-utils/x11-xkb-utils_7.7+9_amd64.deb"',
    'LABWC_XWAYLAND_XKBCOMP_SHA256="745e29c79bb435d057cdbf8bb59a35fa33e818e566cb754674f44d381ccd4317"',
    'LABWC_XWAYLAND_XKBCOMP_BYTES="158552"',
    'LABWC_XWAYLAND_RUNTIME_ROOT="/opt/xwayland"',
)
profile_paths = sorted(
    (
        root_dir / "d-i/forky/hosts/profiles/btrfs/desktop.env",
        root_dir / "d-i/forky/hosts/profiles/f2fs/desktop.env",
        root_dir / "d-i/forky/hosts/profiles/vm/desktop.env",
        *(root_dir / "d-i/forky/hosts/profiles/override").glob("*-de*.env"),
    ),
    key=lambda path: str(path),
)
assert len(profile_paths) == 13
for profile_path in profile_paths:
    profile_policy = tuple(
        line
        for line in profile_path.read_text(encoding="utf-8").splitlines()
        if line.startswith("LABWC_XWAYLAND_")
    )
    assert profile_policy == expected_profile_policy, profile_path

required_installer_pins = (
    '[ "$LABWC_XWAYLAND_VERSION" = "2:24.1.13-1" ]',
    '[ "$LABWC_XWAYLAND_ARCHITECTURE" = amd64 ]',
    '[ "$LABWC_XWAYLAND_URL" = "https://snapshot.debian.org/archive/debian/20260805T142647Z/pool/main/x/xwayland/xwayland_24.1.13-1_amd64.deb" ]',
    '[ "$LABWC_XWAYLAND_SHA256" = a0633569cf2b65d5d4902a2b6213d59c7db7973faef0233df9ace48f334ba6c2 ]',
    '[ "$LABWC_XWAYLAND_BYTES" -eq 992244 ]',
    '[ "$LABWC_XWAYLAND_COMMON_VERSION" = "2:21.1.24-1" ]',
    '[ "$LABWC_XWAYLAND_COMMON_ARCHITECTURE" = all ]',
    '[ "$LABWC_XWAYLAND_COMMON_URL" = "https://snapshot.debian.org/archive/debian/20260805T142647Z/pool/main/x/xorg-server/xserver-common_21.1.24-1_all.deb" ]',
    '[ "$LABWC_XWAYLAND_COMMON_SHA256" = 807f2faaccada8ceac329a2c4d5b264fb794baf44bd6a2a787f9a0a75a67446b ]',
    '[ "$LABWC_XWAYLAND_COMMON_BYTES" -eq 2455368 ]',
    '[ "$LABWC_XWAYLAND_XCB_CURSOR_VERSION" = 0.1.6-1 ]',
    '[ "$LABWC_XWAYLAND_XCB_CURSOR_URL" = "https://snapshot.debian.org/archive/debian/20260206T022815Z/pool/main/x/xcb-util-cursor/libxcb-cursor0_0.1.6-1_amd64.deb" ]',
    '[ "$LABWC_XWAYLAND_XCB_CURSOR_SHA256" = f2f7730d4559769ec45aa610967d27f410b642af0c993813f50092972f8da0d4 ]',
    '[ "$LABWC_XWAYLAND_XCB_CURSOR_BYTES" -eq 17772 ]',
    '[ "$LABWC_XWAYLAND_XKBCOMP_VERSION" = "7.7+9" ]',
    '[ "$LABWC_XWAYLAND_XKBCOMP_ARCHITECTURE" = amd64 ]',
    '[ "$LABWC_XWAYLAND_XKBCOMP_ARCHITECTURE" = "$LABWC_XWAYLAND_ARCHITECTURE" ]',
    '[ "$LABWC_XWAYLAND_XKBCOMP_URL" = "https://snapshot.debian.org/archive/debian/20260805T142647Z/pool/main/x/x11-xkb-utils/x11-xkb-utils_7.7+9_amd64.deb" ]',
    '[ "$LABWC_XWAYLAND_XKBCOMP_SHA256" = 745e29c79bb435d057cdbf8bb59a35fa33e818e566cb754674f44d381ccd4317 ]',
    '[ "$LABWC_XWAYLAND_XKBCOMP_BYTES" -eq 158552 ]',
    '[ "$LABWC_XWAYLAND_RUNTIME_ROOT" = /opt/xwayland ]',
    "XWAYLAND_PRIVATE_DEPENDENCY_RELEASE=forky",
    "XWAYLAND_PRIVATE_DEPENDENCY_MAX_BYTES=16777216",
    '[ "$XWAYLAND_PRIVATE_DEPENDENCY_RELEASE" = forky ]',
    '[ "$XWAYLAND_PRIVATE_DEPENDENCY_MAX_BYTES" -eq 16777216 ]',
)
assert all(pin in installer for pin in required_installer_pins)

installer_lines = installer.splitlines()
private_dependency_specs = (
    "libfontenc1:libfontenc.so.1",
    "libxau6:libXau.so.6",
    "libxcb-image0:libxcb-image.so.0",
    "libxcb-render-util0:libxcb-render-util.so.0",
    "libxcb-render0:libxcb-render.so.0",
    "libxcb-shm0:libxcb-shm.so.0",
    "libxcb-util1:libxcb-util.so.1",
    "libxcb1:libxcb.so.1",
    "libxcvt0:libxcvt.so.0",
    "libxdmcp6:libXdmcp.so.6",
    "libxfont2:libXfont2.so.2",
    "libxshmfence1:libxshmfence.so.1",
)
dependency_specs_start = installer.index(
    "XWAYLAND_PRIVATE_DEPENDENCY_SPECS='\n"
) + len("XWAYLAND_PRIVATE_DEPENDENCY_SPECS='\n")
dependency_specs_end = installer.index("\n'\n", dependency_specs_start)
assert tuple(
    installer[dependency_specs_start:dependency_specs_end].splitlines()
) == private_dependency_specs
private_dependency_packages = {
    spec.partition(":")[0] for spec in private_dependency_specs
}
private_library_names = {
    "libxcb-cursor.so.0",
    *(spec.partition(":")[2] for spec in private_dependency_specs),
}

for class_path in (root_dir / "d-i/forky/classes").rglob("*.cfg"):
    for line in class_path.read_text(encoding="utf-8").splitlines():
        prefix = "d-i pkgsel/include string "
        if line.startswith(prefix):
            assert private_dependency_packages.isdisjoint(
                line.removeprefix(prefix).split()
            ), class_path

required_packages_start = installer_lines.index(
    "  for xwayland_required_package in \\"
)
required_packages_end = installer_lines.index("  do", required_packages_start + 1)
required_target_packages = {
    line.strip().removesuffix("\\").strip()
    for line in installer_lines[required_packages_start + 1 : required_packages_end]
}
assert private_dependency_packages.isdisjoint(required_target_packages)
required_xkbcomp_target_packages = {
    "libc6",
    "libdecor-0-plugin-1-gtk",
    "libx11-6",
    "libxaw7",
    "libxkbfile1",
    "libxrandr2",
    "libxt6t64",
}
assert required_xkbcomp_target_packages <= required_target_packages

desktop_package_line = next(
    line
    for line in (
        root_dir / "d-i/forky/classes/class-select/role/desktop.cfg"
    ).read_text(encoding="utf-8").splitlines()
    if line.startswith("d-i pkgsel/include string ")
)
desktop_packages = set(
    desktop_package_line.removeprefix("d-i pkgsel/include string ").split()
)
assert required_xkbcomp_target_packages.difference({"libc6"}) <= desktop_packages
assert "x11-xkb-utils" not in desktop_packages

validation_calls = []
for index, line in enumerate(installer_lines):
    if line.strip() != "desktop_xwayland_validate_private_deb \\":
        continue
    arguments = []
    for argument_line in installer_lines[index + 1 :]:
        argument = argument_line.strip()
        continued = argument.endswith("\\")
        if continued:
            argument = argument[:-1].rstrip()
        arguments.append(argument)
        if not continued:
            break
    validation_calls.append(tuple(arguments))
assert validation_calls == [
    (
        '"$xwayland_deb"',
        '"$xwayland_deb_host"',
        "xwayland",
        '"$LABWC_XWAYLAND_VERSION"',
        '"$LABWC_XWAYLAND_ARCHITECTURE"',
        '"$LABWC_XWAYLAND_BYTES"',
        '"$LABWC_XWAYLAND_SHA256"',
    ),
    (
        '"$xwayland_common_deb"',
        '"$xwayland_common_deb_host"',
        "xserver-common",
        '"$LABWC_XWAYLAND_COMMON_VERSION"',
        '"$LABWC_XWAYLAND_COMMON_ARCHITECTURE"',
        '"$LABWC_XWAYLAND_COMMON_BYTES"',
        '"$LABWC_XWAYLAND_COMMON_SHA256"',
    ),
    (
        '"$xwayland_xcb_cursor_deb"',
        '"$xwayland_xcb_cursor_deb_host"',
        "libxcb-cursor0",
        '"$LABWC_XWAYLAND_XCB_CURSOR_VERSION"',
        '"$LABWC_XWAYLAND_ARCHITECTURE"',
        '"$LABWC_XWAYLAND_XCB_CURSOR_BYTES"',
        '"$LABWC_XWAYLAND_XCB_CURSOR_SHA256"',
    ),
    (
        '"$xwayland_xkbcomp_deb"',
        '"$xwayland_xkbcomp_deb_host"',
        "x11-xkb-utils",
        '"$LABWC_XWAYLAND_XKBCOMP_VERSION"',
        '"$LABWC_XWAYLAND_XKBCOMP_ARCHITECTURE"',
        '"$LABWC_XWAYLAND_XKBCOMP_BYTES"',
        '"$LABWC_XWAYLAND_XKBCOMP_SHA256"',
    ),
]

extract_start = installer_lines.index("  for xwayland_extract_spec in \\")
extract_end = installer_lines.index("  do", extract_start + 1)
extract_specs = []
for line in installer_lines[extract_start + 1 : extract_end]:
    value = line.strip()
    if value.endswith("\\"):
        value = value[:-1].rstrip()
    extract_specs.append(value.removeprefix('"').removesuffix('"'))
assert extract_specs == [
    "xwayland:${xwayland_deb}",
    "xserver-common:${xwayland_common_deb}",
    "libxcb-cursor0:${xwayland_xcb_cursor_deb}",
    "x11-xkb-utils:${xwayland_xkbcomp_deb}",
]
assert installer.count(
    "desktop_xwayland_extract_private_deb \\"
) == 2
assert "desktop_xwayland_validate_repository_deb \\" in installer
assert "desktop_xwayland_validate_extracted_library() {" in installer
assert installer.count("desktop_xwayland_validate_extracted_library \\") == 2
for library_name in private_library_names:
    assert library_name in installer

apt_download_start = installer.index(
    "desktop_xwayland_download_repository_deb() {"
)
apt_download_end = installer.index("\n}\n", apt_download_start) + 3
apt_download_policy = installer[apt_download_start:apt_download_end]
assert installer.count("/usr/bin/apt-get") == 2
assert "\n          download \\\n" in apt_download_policy
assert re.search(r"\binstall\b", apt_download_policy) is None
assert "-o APT::Get::AllowUnauthenticated=false" in apt_download_policy
assert "-o Acquire::AllowInsecureRepositories=false" in apt_download_policy
assert "-o Acquire::AllowDowngradeToInsecureRepositories=false" in apt_download_policy
assert "-o APT::Install-Recommends=false" in apt_download_policy
assert "-o APT::Install-Suggests=false" in apt_download_policy
assert "dpkg -i" not in installer
assert "-quit" not in installer
public_runtime_assert_start = installer.index(
    "desktop_xwayland_assert_public_runtime_absent() {"
)
public_runtime_assert_end = installer.index(
    "\n}\n", public_runtime_assert_start
) + 3
public_runtime_assert_policy = installer[
    public_runtime_assert_start:public_runtime_assert_end
]
assert 'dpkg-query -W -f="\\${Status}" xwayland' in public_runtime_assert_policy
assert '"public xwayland package must not remain installed"' in public_runtime_assert_policy
assert "[ -e /target/usr/bin/Xwayland ]" in public_runtime_assert_policy
assert "[ -L /target/usr/bin/Xwayland ]" in public_runtime_assert_policy
assert '"public /usr/bin/Xwayland must not exist"' in public_runtime_assert_policy

public_runtime_remove_start = installer.index(
    "desktop_xwayland_remove_public_runtime() {"
)
public_runtime_remove_end = installer.index(
    "\n}\n", public_runtime_remove_start
) + 3
public_runtime_remove_policy = installer[
    public_runtime_remove_start:public_runtime_remove_end
]
assert public_runtime_remove_policy.count("/usr/bin/apt-get") == 1
assert "purge xwayland" in public_runtime_remove_policy
assert "autoremove" not in public_runtime_remove_policy
assert public_runtime_remove_policy.count(
    "desktop_xwayland_assert_public_runtime_absent"
) == 1
assert installer.count("desktop_xwayland_remove_public_runtime") == 2
assert installer.count("desktop_xwayland_assert_public_runtime_absent") == 3
assert "desktop_xwayland_find_first_path() {" in installer
assert 'if ! find "$@" -print >"$xwayland_find_output"; then' in installer
assert "sed -n '1p'" in installer
assert 'xwayland_find_output="${xwayland_work_host}/find-output"' in installer
assert installer.count("    desktop_xwayland_find_first_path \\") == 4
assert "desktop_xwayland_prepare_xkbcomp_mountpoint" not in installer
assert "desktop_xwayland_prepare_xkbcomp_overlay() {" in installer
for overlay_contract in (
    "xwayland_system_xkbcomp_host=/target/usr/bin/xkbcomp",
    'xwayland_xkbcomp_source="${xwayland_extract_host}/usr/bin/xkbcomp"',
    'xwayland_xkbcomp_overlay_directory="${xwayland_extract_host}/usr/lib/xkbcomp-overlay"',
    'xwayland_xkbcomp_overlay_entry="${xwayland_xkbcomp_overlay_directory}/xkbcomp"',
    '[ -d /target/usr/bin ] && [ ! -L /target/usr/bin ]',
    '[ -e "$xwayland_system_xkbcomp_host" ] ||',
    "target /usr/bin/xkbcomp must remain absent; x11-xkb-utils must not be installed system-wide",
    'install -d -m 0700 "$xwayland_xkbcomp_overlay_directory"',
    'ln "$xwayland_xkbcomp_source" "$xwayland_xkbcomp_overlay_entry"',
    'chown root:root "$xwayland_xkbcomp_overlay_directory"',
    'chmod 0555 "$xwayland_xkbcomp_overlay_directory"',
    '[ "$xwayland_xkbcomp_source" -ef "$xwayland_xkbcomp_overlay_entry" ]',
):
    assert overlay_contract in installer
overlay_start = installer.index("desktop_xwayland_prepare_xkbcomp_overlay() {")
overlay_end = installer.index("\n}\n", overlay_start) + 3
overlay_policy = installer[overlay_start:overlay_end]
overlay_population_steps = (
    'install -d -m 0700 "$xwayland_xkbcomp_overlay_directory"',
    'ln "$xwayland_xkbcomp_source" "$xwayland_xkbcomp_overlay_entry"',
    'chown root:root "$xwayland_xkbcomp_overlay_directory"',
    'chmod 0555 "$xwayland_xkbcomp_overlay_directory"',
)
assert tuple(overlay_policy.index(step) for step in overlay_population_steps) == tuple(
    sorted(overlay_policy.index(step) for step in overlay_population_steps)
)
assert "stat -c" not in overlay_policy
assert "xwayland_xkbcomp_overlay_metadata" not in overlay_policy
assert (
    "private xkbcomp overlay directory must remain root-owned mode 0555"
    not in installer
)
for forbidden_mountpoint_contract in (
    'install -m 0444 \\',
    "xkbcomp.mountpoint",
    "private xkbcomp mountpoint",
):
    assert forbidden_mountpoint_contract not in installer

top_level_start = installer.index("  xwayland_unexpected_top_level=$(")
top_level_end = installer.index("\n  )", top_level_start)
top_level_policy = installer[top_level_start:top_level_end]
assert "-mindepth 1 -maxdepth 1" in top_level_policy
assert top_level_policy.count("! -name") == 2
assert "! -name usr" in top_level_policy
assert "! -name var" in top_level_policy

prepare_start = installer.index('  chown -R root:root "$xwayland_extract_host"\n')
publish_start = installer.index("  install -d -m 0755 /target/opt\n")
prepare_policy = installer[prepare_start:publish_start]
assert prepare_policy == (
    '  chown -R root:root "$xwayland_extract_host"\n'
    '  chmod -R go-w "$xwayland_extract_host"\n'
    "  xwayland_unsafe_xkbcomp=$(\n"
    "    desktop_xwayland_find_first_path \\\n"
    '      "prepared xkbcomp ownership and mode" \\\n'
    '      "$xwayland_find_output" \\\n'
    '      "$xwayland_extract_host/usr/bin/xkbcomp" \\\n'
    r"      \( ! -type f -o ! -user 0 -o ! -group 0 -o -perm /022 \)"
    "\n"
    "  )\n"
    '  [ -z "$xwayland_unsafe_xkbcomp" ] ||\n'
    '    desktop_xwayland_fail "prepared private xkbcomp is not a root-owned regular file with a safe mode"\n'
    "\n"
    "  desktop_xwayland_prepare_xkbcomp_overlay\n"
    "\n"
)
publish_end = installer.index(
    '  rm -rf -- "$xwayland_work_host"\n',
    publish_start,
)
publish_policy = installer[publish_start:publish_end]
assert publish_policy == (
    "  install -d -m 0755 /target/opt\n"
    '  rm -rf -- "$xwayland_runtime_host"\n'
    '  mv "$xwayland_extract_host" "$xwayland_runtime_host"\n'
    "\n"
)
assert (
    '[ -f "$xwayland_extract_host/usr/bin/xkbcomp" ] &&\n'
    '    [ ! -L "$xwayland_extract_host/usr/bin/xkbcomp" ] &&\n'
    '    [ -x "$xwayland_extract_host/usr/bin/xkbcomp" ] ||\n'
    '    desktop_xwayland_fail "extracted private Xwayland runtime is missing executable usr/bin/xkbcomp"'
) in installer
for forbidden_runtime_content in (
    "/opt/xwayland/libexec",
    "run-private-x11",
    "/usr/bin/bwrap",
    "metadata.json",
    "release.txt",
):
    assert forbidden_runtime_content not in installer

x11_preferences = (
    root_dir
    / "d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/x11.pref"
).read_text(encoding="utf-8")
package_line = next(
    line for line in x11_preferences.splitlines() if line.startswith("Package: ")
)
pinned_system_packages = set(package_line.removeprefix("Package: ").split())
assert {"x11-xkb-utils", "xwayland", "xserver-common"} <= pinned_system_packages
assert "libxcb-cursor0" not in pinned_system_packages

native_labwc_installer = root_dir / "d-i/forky/scripts/desktop/native-labwc.sh"
assert not native_labwc_installer.exists()
assert "native-labwc" not in installer
PY
then
  pass "private Xwayland keeps four pinned payloads, blocks system xkbcomp, builds a private read-only overlay, and keeps all 13 desktop profiles synchronized"
else
  fail "private Xwayland keeps four pinned payloads, blocks system xkbcomp, builds a private read-only overlay, and keeps all 13 desktop profiles synchronized"
fi

if grep -Eq '(^|[[:space:]])qt6ct([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])labwc-tweaks([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set installs the managed qt6ct and labwc-tweaks stack"
else
  fail "desktop package set installs the managed qt6ct and labwc-tweaks stack"
fi

mailname_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/mailname.tmpl"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
if grep -q '^desktop_unit_mask_link_path() {$' "$desktop_components" &&
   grep -q '^desktop_unit_is_masked() {$' "$desktop_components" &&
   grep -q 'already_masked=true' "$desktop_components" &&
   grep -q 'readlink "\$mask_path"' "$desktop_components"; then
  pass "desktop target masking treats pre-existing /dev/null systemd masks as idempotent state"
else
  fail "desktop target masking treats pre-existing /dev/null systemd masks as idempotent state"
fi

if grep -Eq '(^|[[:space:]])mailutils([[:space:]]|$)' "$desktop_packages_file" &&
   grep -q '__INSTALLER_MAILNAME__' "$mailname_template" &&
   grep -q '^desktop_target_hostname() {$' "$desktop_components" &&
   grep -q '^desktop_mailname_value() {$' "$desktop_components" &&
   grep -q '/target/etc/hostname' "$desktop_components" &&
   grep -q 'desktop_render_shared_target_template "etc/mailname.tmpl" "/etc/mailname" 0644' "$desktop_components" &&
   grep -q 'desktop_render_role_target_template "etc/aliases.tmpl" "/etc/aliases" 0644' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset etc/apt/apt.conf.d/60desktop-local-mail.conf /etc/apt/apt.conf.d/60desktop-local-mail.conf 0644' "$desktop_components" &&
   ! grep -q 'refresh desktop local mail aliases' "$desktop_components" &&
   ! grep -q 'SYSTEM_HOSTNAME must be set for desktop local mail delivery' "$desktop_components" &&
   ! grep -q 'SYSTEM_DOMAIN must be set for desktop local mail delivery' "$desktop_components" &&
   ! grep -q 'update-exim4.conf' "$desktop_components" &&
   ! grep -q 'newaliases' "$desktop_components"; then
  pass "desktop mail delivery installs mailutils and stages mail assets without in-target alias refresh"
else
  fail "desktop mail delivery installs mailutils and stages mail assets without in-target alias refresh"
fi

health_notifier="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-health-notify"
health_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-health-notify.service"
health_path="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-health-notify.path"
mako_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mako/config"
mako_override="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/mako.service.d/10-labwc-session.conf"
autostart_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
output_refresh_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-output-refresh"
mail_test_dir="$TMP_DIR/mail-notification"
mailbox_path="$mail_test_dir/mailbox"
notify_log="$mail_test_dir/notify.log"
notify_mock="$mail_test_dir/notify-send"
timeshift_event_dir="$mail_test_dir/timeshift"
timeshift_seen_dir="$mail_test_dir/timeshift-seen"
unattended_event_dir="$mail_test_dir/unattended-upgrades"
unattended_seen_dir="$mail_test_dir/unattended-seen"
security_signal_dir="$mail_test_dir/security"
security_signal_state_dir="$mail_test_dir/security-state"
meminfo_file="$mail_test_dir/meminfo"
power_supply_dir="$mail_test_dir/power-supply"
reboot_required_file="$mail_test_dir/reboot-required"
health_runtime_dir="$mail_test_dir/runtime"
health_wayland_display=wayland-0
health_wayland_socket="$health_runtime_dir/$health_wayland_display"
mkdir -p \
  "$mail_test_dir/home" \
  "$mail_test_dir/state" \
  "$health_runtime_dir" \
  "$timeshift_event_dir" \
  "$unattended_event_dir" \
  "$security_signal_dir" \
  "$power_supply_dir/BAT0"
chmod 0700 "$health_runtime_dir"
chmod 0755 "$timeshift_event_dir" "$unattended_event_dir" "$security_signal_dir"
python3 - "$health_wayland_socket" <<'PY'
import socket
import sys

wayland_socket = socket.socket(socket.AF_UNIX)
wayland_socket.bind(sys.argv[1])
wayland_socket.close()
PY
cat >"$notify_mock" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod 0755 "$notify_mock"
cat >"$mailbox_path" <<'EOF'
From root Tue Jul 14 18:00:00 2026
Subject: managed local mail test

test
EOF
cat >"$timeshift_event_dir/1773849597-0000001000-0001.event" <<'EOF'
started|daily|-
EOF
cat >"$timeshift_event_dir/1773849598-0000001000-0001.event" <<'EOF'
completed|daily|-
EOF
cat >"$timeshift_event_dir/1773849599-0000001000-0001.event" <<'EOF'
failed|weekly|7
EOF
cat >"$unattended_event_dir/1773849600-0000001000-0001.event" <<'EOF'
started|none|none|none
EOF
cat >"$unattended_event_dir/1773849601-0000001000-0001.event" <<'EOF'
completed|success|exited|0
EOF
cat >"$unattended_event_dir/1773849602-0000001000-0001.event" <<'EOF'
failed|exit-code|exited|100
EOF
printf 'auth\nauth\n' >"$security_signal_dir/auth.signal"
printf 'usb\n' >"$security_signal_dir/usb.signal"
printf 'storage\n' >"$security_signal_dir/storage.signal"
printf 'apparmor\n' >"$security_signal_dir/apparmor.signal"
printf 'firewall\n' >"$security_signal_dir/firewall.signal"
cat >"$meminfo_file" <<'EOF'
MemTotal:       1048576 kB
MemAvailable:     52428 kB
EOF
printf 'Battery\n' >"$power_supply_dir/BAT0/type"
printf '9\n' >"$power_supply_dir/BAT0/capacity"
printf 'Discharging\n' >"$power_supply_dir/BAT0/status"
: >"$reboot_required_file"
chmod 0644 "$timeshift_event_dir"/*.event "$unattended_event_dir"/*.event
chmod 0640 "$security_signal_dir"/*.signal
current_test_user=$(id -un)
current_test_uid=$(id -u)
for mail_test_run in 1 2; do
  NOTIFY_LOG="$notify_log" \
  NOTIFY_SEND="$notify_mock" \
  MAIL="$mailbox_path" \
  HOME="$mail_test_dir/home" \
  XDG_STATE_HOME="$mail_test_dir/state" \
  TIMESHIFT_EVENT_DIR="$timeshift_event_dir" \
  TIMESHIFT_SEEN_DIR="$timeshift_seen_dir" \
  TIMESHIFT_EVENT_OWNER_UID="$current_test_uid" \
  UNATTENDED_EVENT_DIR="$unattended_event_dir" \
  UNATTENDED_SEEN_DIR="$unattended_seen_dir" \
  SECURITY_SIGNAL_DIR="$security_signal_dir" \
  SECURITY_SIGNAL_STATE_DIR="$security_signal_state_dir" \
  ROOT_EVENT_OWNER_UID="$current_test_uid" \
  MEMINFO_FILE="$meminfo_file" \
  POWER_SUPPLY_DIR="$power_supply_dir" \
  REBOOT_REQUIRED_FILE="$reboot_required_file" \
  LABWC_SESSION_OWNER=desktop \
  XDG_SESSION_TYPE=wayland \
  XDG_RUNTIME_DIR="$health_runtime_dir" \
  WAYLAND_DISPLAY="$health_wayland_display" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$mail_test_dir/fake-bus" \
    /bin/sh "$health_notifier"
done
email_notification_count=$(grep -c 'email.arrived' "$notify_log" || true)
timeshift_started_count=$(grep -c 'Timeshift daily snapshot started' "$notify_log" || true)
timeshift_completed_count=$(grep -c 'Timeshift daily snapshot completed' "$notify_log" || true)
timeshift_failed_count=$(grep -c 'Timeshift weekly snapshot failed' "$notify_log" || true)
unattended_started_count=$(grep -c 'Automatic package maintenance started' "$notify_log" || true)
unattended_notification_count=$(grep -c 'Automatic package maintenance completed' "$notify_log" || true)
unattended_failed_count=$(grep -c 'Automatic package maintenance failed' "$notify_log" || true)
auth_notification_count=$(grep -c 'Authentication activity detected' "$notify_log" || true)
usb_notification_count=$(grep -c 'USB or hardware hotplug activity detected' "$notify_log" || true)
storage_notification_count=$(grep -c 'Storage error detected' "$notify_log" || true)
apparmor_notification_count=$(grep -c 'AppArmor policy denial detected' "$notify_log" || true)
firewall_notification_count=$(grep -c 'Firewall blocked network traffic' "$notify_log" || true)
memory_notification_count=$(grep -c 'Critical memory pressure' "$notify_log" || true)
battery_notification_count=$(grep -c 'Critical battery level' "$notify_log" || true)
reboot_notification_count=$(grep -c 'System restart required' "$notify_log" || true)
labwc_package_dropin_block=$(awk '
  /^desktop_stage_labwc_package_user_unit_dropins\(\) \{$/ { show = 1 }
  show { print }
  show && /^}$/ { exit }
' "$desktop_components")
if grep -q '^CURRENT_USER=$(id -un 2>/dev/null || true)$' "$health_notifier" &&
   grep -q '^MAILBOX="${MAIL:-/var/mail/${CURRENT_USER}}"$' "$health_notifier" &&
   grep -q '^Wants=mako.service$' "$health_service" &&
   grep -q '^After=labwc-session.target mako.service$' "$health_service" &&
   ! grep -q '^ExecCondition=' "$health_service" &&
   grep -Fqx 'trap cancel_coalescing HUP INT TERM' "$health_notifier" &&
   grep -Fqx '[ -S "$wayland_socket" ] || exit 0' "$health_notifier" &&
   grep -q '^ReadOnlyPaths=/var/mail$' "$health_service" &&
   grep -q '^ReadOnlyPaths=-/var/lib/labwc-notifications$' "$health_service" &&
   ! grep -q '^IPAddressDeny=' "$health_service" &&
   grep -q '^PathModified=/var/mail/%u$' "$health_path" &&
   grep -q '^PathChanged=/var/lib/labwc-notifications/timeshift$' "$health_path" &&
   grep -q '^PathChanged=/var/lib/labwc-notifications/unattended-upgrades$' "$health_path" &&
   grep -q '^PathModified=/var/lib/labwc-notifications/security/auth.signal$' "$health_path" &&
   grep -q '^PathModified=/var/lib/labwc-notifications/security/usb.signal$' "$health_path" &&
   grep -q '^PathModified=/var/lib/labwc-notifications/security/storage.signal$' "$health_path" &&
   grep -q '^PathModified=/var/lib/labwc-notifications/security/apparmor.signal$' "$health_path" &&
   grep -q '^PathModified=/var/lib/labwc-notifications/security/firewall.signal$' "$health_path" &&
   grep -q '^ConditionEnvironment=LABWC_SESSION_OWNER=desktop$' "$mako_override" &&
   grep -q '^After=labwc-session.target$' "$mako_override" &&
   grep -q '^PartOf=labwc-session.target$' "$mako_override" &&
   grep -q '^WantedBy=labwc-session.target$' "$mako_override" &&
   ! grep -q 'graphical-session.target' "$mako_override" &&
   ! grep -q '^ExecStartPre=' "$mako_override" &&
   grep -q '^desktop_stage_global_user_unit_dropin_asset() {$' "$desktop_components" &&
   grep -Fq '    mako.service \' "$desktop_components" &&
   grep -q '^start_health_notifier_if_enabled() {$' "$autostart_wrapper" &&
   grep -q -- '--no-block start labwc-health-notify.path' "$autostart_wrapper" &&
   grep -Fq '    mako.service \' "$desktop_components" &&
   printf '%s\n' "$labwc_package_dropin_block" |
     grep -Fq '    hyprpolkitagent.service \' &&
   printf '%s\n' "$labwc_package_dropin_block" |
     grep -Fq '    desktop_stage_global_user_unit_dropin_asset "$unit" 10-labwc-session.conf' &&
   ! grep -Fq 'etc/skel/.config/systemd/user/hyprpolkitagent.service.d/10-labwc-session.conf' "$desktop_components" &&
   grep -q '^default-timeout=5000$' "$mako_config" &&
   awk '$0 == "[urgency=low]" { in_low = 1; next } /^\[/ { in_low = 0 } in_low && $0 == "invisible=1" { hidden = 1 } END { exit hidden }' "$mako_config" &&
   grep -q '^\[app-name="Desktop Health" category=email.arrived\]$' "$mako_config" &&
   grep -q '^\[app-name="Timeshift" category=system.backup\]$' "$mako_config" &&
   grep -q '^\[app-name="Software Updater" category=system.software-update\]$' "$mako_config" &&
   grep -q '^\[app-name="Unattended Upgrades" category=system.software-update\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=system.security.auth\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=device.added\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=device.error\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=system.security\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Security" category=system.security.network\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Health" category=system.memory\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Health" category=system.battery\]$' "$mako_config" &&
   grep -q '^\[app-name="Desktop Health" category=system.reboot\]$' "$mako_config" &&
   grep -q '^\[app-name="System Maintenance" category=x-labwc.maintenance\]$' "$mako_config" &&
   grep -q '^\[app-name="Security Maintenance" category=x-labwc.maintenance\]$' "$mako_config" &&
   grep -q '^\[app-name="Recovery" category=x-labwc.maintenance\]$' "$mako_config" &&
   grep -q '^\[app-name="Network Scanning" category=x-labwc.maintenance\]$' "$mako_config" &&
   grep -q '^\[app-name="Android Device" category=x-labwc.maintenance\]$' "$mako_config" &&
   grep -q '^\[app-name="OCR" category=x-labwc.maintenance\]$' "$mako_config" &&
   grep -q '^\[app-name="Calendar" category=x-labwc.calendar\]$' "$mako_config" &&
   grep -q '^\[app-name="Bluetooth"\]$' "$mako_config" &&
   grep -q '^\[app-name="Screen Capture" category=x-labwc.screen-capture\]$' "$mako_config" &&
   grep -q '^\[app-name="Screen Capture" category=x-labwc.screen-recording\]$' "$mako_config" &&
   grep -q '^check_timeshift_events() {$' "$health_notifier" &&
   grep -q '^check_unattended_upgrade_events() {$' "$health_notifier" &&
   grep -q '^check_security_signals() {$' "$health_notifier" &&
   grep -q '^check_memory_pressure() {$' "$health_notifier" &&
   grep -q '^check_battery() {$' "$health_notifier" &&
   grep -q '^check_reboot_required() {$' "$health_notifier" &&
   grep -q '^TIMESHIFT_EVENT_DIR=${TIMESHIFT_EVENT_DIR:-/var/lib/labwc-notifications/timeshift}$' "$health_notifier" &&
   grep -q '^TIMESHIFT_EVENT_OWNER_UID=${TIMESHIFT_EVENT_OWNER_UID:-0}$' "$health_notifier" &&
   grep -q '^UNATTENDED_EVENT_DIR=${UNATTENDED_EVENT_DIR:-/var/lib/labwc-notifications/unattended-upgrades}$' "$health_notifier" &&
   grep -q '^SECURITY_SIGNAL_DIR=${SECURITY_SIGNAL_DIR:-/var/lib/labwc-notifications/security}$' "$health_notifier" &&
   [ "$email_notification_count" -eq 1 ] &&
   [ "$timeshift_started_count" -eq 1 ] &&
   [ "$timeshift_completed_count" -eq 1 ] &&
   [ "$timeshift_failed_count" -eq 1 ] &&
   [ "$unattended_started_count" -eq 1 ] &&
   [ "$unattended_notification_count" -eq 1 ] &&
   [ "$unattended_failed_count" -eq 1 ] &&
   [ "$auth_notification_count" -eq 1 ] &&
   [ "$usb_notification_count" -eq 1 ] &&
   [ "$storage_notification_count" -eq 1 ] &&
   [ "$apparmor_notification_count" -eq 1 ] &&
   [ "$firewall_notification_count" -eq 1 ] &&
   [ "$memory_notification_count" -eq 1 ] &&
   [ "$battery_notification_count" -eq 1 ] &&
   [ "$reboot_notification_count" -eq 1 ] &&
   grep -q "New local mail for ${current_test_user}" "$notify_log" &&
   grep -q 'contains 1 message(s)' "$notify_log" &&
   grep -q '2 new events were recorded. Review /var/log/managed/auth/auth.log.' "$notify_log" &&
   grep -q 'Sensitive boot, kernel, GPU, firmware, and audio packages remained excluded.' "$notify_log" &&
   grep -q 'Review the system journal and /var/log/unattended-upgrades/.' "$notify_log"; then
  pass "Labwc starts Mako synchronously and preserves local mail, health, security, Timeshift, and unattended-upgrade notifications"
else
  fail "Labwc starts Mako synchronously and preserves local mail, health, security, Timeshift, and unattended-upgrade notifications"
fi

intel_cpu_class="$ROOT_DIR/d-i/forky/classes/class-auto/cpu/intel.cfg"
intel_regdom_rule="$ROOT_DIR/d-i/forky/hooks/hardware/cpu/intel/target/etc/udev/rules.d/85-wifi-regdom.rules"
if grep -Eq '(^|[[:space:]])iw([[:space:]]|$)' "$intel_cpu_class" &&
   grep -q '/usr/sbin/iw reg set SE' "$intel_regdom_rule"; then
  pass "Intel hardware policy installs iw and pins the managed Swedish regdom through the canonical usr-sbin callout path"
else
  fail "Intel hardware policy installs iw and pins the managed Swedish regdom through the canonical usr-sbin callout path"
fi

if grep -Eq '(^|[[:space:]])libspa-0\.2-libcamera([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libcamera-ipa([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])vdirsyncer([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])khal([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])todoman(/trixie)?([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])gsimplecal([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set installs the calendar sync stack, libcamera IPA modules, and no legacy gsimplecal dependency"
else
  fail "desktop package set installs the calendar sync stack, libcamera IPA modules, and no legacy gsimplecal dependency"
fi

base_packages_file="$ROOT_DIR/d-i/forky/fragments/apt.cfg"
if grep -Eq '(^|[[:space:]])dosfstools([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '(^|[[:space:]])tpm2-tools([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '(^|[[:space:]])tpm-udev([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '(^|[[:space:]])usrmerge([[:space:]]|$)' "$base_packages_file"; then
  pass "base package set installs VFAT fsck, TPM support, and merged-usr conversion"
else
  fail "base package set installs VFAT fsck, TPM support, and merged-usr conversion"
fi

if grep -Eq '(^|[[:space:]])libpam-wtmpdb([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])wtmpdb([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])xwayland([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])x11-xkb-utils([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '^d-i base-installer/excludes string .*([[:space:]])xwayland([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '^d-i base-installer/excludes string .*([[:space:]])x11-xkb-utils([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '^Package: .*([[:space:]])x11-xkb-utils([[:space:]]|$)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/x11.pref" &&
   grep -Eq '^Package: .*([[:space:]])xwayland([[:space:]]|$)' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apt/preferences.d/desktop/x11.pref" &&
   ! grep -Eq '(^|[[:space:]])libpam-kwallet5([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])power-profiles-daemon([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])hyprpolkitagent([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libmtp-runtime([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])xdg-terminal-exec([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])gir1\.2-gtklayershell-0\.1([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])python3-gi([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])polkit-kde-agent-1([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])xfce4-power-manager([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set stays native-Wayland, keeps PAM generic, leaves GPG-backed KWallet off kwallet-pam, and still installs the desktop runtime helpers"
else
  fail "desktop package set stays native-Wayland, keeps PAM generic, leaves GPG-backed KWallet off kwallet-pam, and still installs the desktop runtime helpers"
fi

if grep -q '^LABWC_GREETER_COMMAND="/usr/local/bin/labwc-greeter-session"$' "$desktop_env" &&
   ! grep -q '^LABWC_GREETER_START_DELAY_SECONDS=' "$desktop_env" &&
   grep -q '^LABWC_WLR_RENDERER="gles2"$' "$desktop_env" &&
   grep -q '^LABWC_GSK_RENDERER="opengl"$' "$desktop_env" &&
   grep -q '^LABWC_GDK_DISABLE="vulkan"$' "$desktop_env" &&
   grep -q '^LABWC_WLR_NO_HARDWARE_CURSORS="1"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_WLR_RENDERER="gles2"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_GSK_RENDERER="opengl"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_GDK_DISABLE="vulkan"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_WLR_NO_HARDWARE_CURSORS="1"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_INTERNAL_SCALE="1"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_EXTERNAL_SCALE="1"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_HOTPLUG_DEBOUNCE_SECONDS="0"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_POLICY="auto"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_INTERNAL_PREFERRED_WIDTH="1920"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_INTERNAL_PREFERRED_HEIGHT="1080"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_INTERNAL_PREFERRED_REFRESH_HZ="60"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH="1920"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT="1080"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="120"$' "$desktop_env" &&
   grep -q '^LABWC_CALENDAR_COMMAND="labwc-calendar"$' "$desktop_env" &&
   grep -q '^LABWC_KEYBOARD_LAYOUTS="us se"$' "$desktop_env" &&
   grep -q '^LABWC_KEYBOARD_DEFAULT_LAYOUT="us"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_INTERNAL_SCALE="1"$' "$desktop_env" &&
   grep -q '^LABWC_OUTPUT_EXTERNAL_SCALE="1"$' "$desktop_env" &&
   grep -q '^LABWC_WAYBAR_TASKBAR_ICON_SIZE="18"$' "$desktop_env" &&
   grep -q '^LABWC_WAYBAR_MENU_BUTTON_MIN_WIDTH="52"$' "$desktop_env" &&
   grep -q '^LABWC_WAYBAR_MENU_BUTTON_PADDING_X="11"$' "$desktop_env" &&
   grep -q '^LABWC_WAYBAR_WORKSPACE_BUTTON_MIN_WIDTH="26"$' "$desktop_env" &&
   grep -q '^LABWC_WAYBAR_TASKBAR_BUTTON_MIN_WIDTH="0"$' "$desktop_env" &&
   grep -q '^LABWC_WAYBAR_TASKBAR_BUTTON_PADDING_X="4"$' "$desktop_env" &&
   ! grep -q '^LABWC_WAYBAR_START_DELAY_SECONDS=' "$desktop_env"; then
  pass "desktop defaults keep profile-owned rendering, sizing, and connector-specific output policy"
else
  fail "desktop defaults keep profile-owned rendering, sizing, and connector-specific output policy"
fi

crystal_dock_panel="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/crystal-dock/labwc/panel_1.conf"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
if grep -q '^\[General\]$' "$crystal_dock_panel" &&
   grep -q '^autoHide=false$' "$crystal_dock_panel" &&
   grep -q '^launchers="show-desktop;vivaldi;foot;thunar;code;bitwarden;keepassxc;timeshift;spotify;mpv;qalculate;focuswriter;gnumeric"$' "$crystal_dock_panel" &&
   grep -q '^showBatteryIndicator=false$' "$crystal_dock_panel" &&
   grep -q '^showTaskManager=true$' "$crystal_dock_panel" &&
   grep -q '^visibility=3$' "$crystal_dock_panel" &&
   ! grep -q '^desktop_render_crystal_dock_panel() {$' "$desktop_components" &&
   ! grep -q '^desktop_crystal_dock_launchers() {$' "$desktop_components" &&
   ! grep -q 'desktop_stage_role_asset .*crystal-dock.* /usr/local/share/applications' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset etc/skel/.config/crystal-dock/labwc/panel_1.conf /etc/skel/.config/crystal-dock/labwc/panel_1.conf 0644$' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset etc/skel/.config/crystal-dock/labwc/panel_1.conf /etc/xdg/crystal-dock/labwc/panel_1.conf 0644$' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-show-desktop /usr/local/bin/labwc-show-desktop 0755$' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset usr/share/applications/show-desktop.desktop /usr/share/applications/show-desktop.desktop 0644$' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset usr/local/share/icons/hicolor/64x64/apps/show-desktop.png /usr/local/share/icons/hicolor/64x64/apps/show-desktop.png 0644$' "$desktop_components" &&
   [ "$(od -An -tx1 -N8 "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/icons/hicolor/64x64/apps/show-desktop.png" | tr -d ' \n')" = '89504e470d0a1a0a' ]; then
  pass "desktop role ships the managed Crystal Dock panel preset to skel and xdg targets"
else
  fail "desktop role ships the managed Crystal Dock panel preset to skel and xdg targets"
fi

fruux_fatal_message="$TMP_DIR/fruux-fatal.txt"
synthetic_telegram_api_key='123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi_123456789'
synthetic_telegram_chat_id='123456789'
if run_calendar_token_preflight \
     "classes=lab,desktop,standard,dhcp fruux_username=alice fruux_password=secret-token telegram_api_key=$synthetic_telegram_api_key telegram_chat_id=$synthetic_telegram_chat_id" \
     "$fruux_fatal_message" \
     'alice' \
     'secret-token' \
     "$synthetic_telegram_api_key" \
     "$synthetic_telegram_chat_id"; then
  pass "desktop role preflights Fruux and Telegram cmdline tokens in one cached pass"
else
  fail "desktop role preflights Fruux and Telegram cmdline tokens in one cached pass"
fi

if run_calendar_token_preflight \
     "classes=lab,desktop,standard,dhcp fruux_password=secret-token telegram_api_key=$synthetic_telegram_api_key telegram_chat_id=$synthetic_telegram_chat_id" \
     "$fruux_fatal_message" \
     'b3297374650' \
     'secret-token' \
     "$synthetic_telegram_api_key" \
     "$synthetic_telegram_chat_id"; then
  pass "desktop role falls back to shared Fruux username when cmdline username is missing"
else
  fail "desktop role falls back to shared Fruux username when cmdline username is missing"
fi

if run_calendar_token_preflight \
     "classes=lab,desktop,standard,dhcp telegram_api_key=$synthetic_telegram_api_key telegram_chat_id=$synthetic_telegram_chat_id" \
     "$fruux_fatal_message" \
     'b3297374650' \
     'testing123' \
     "$synthetic_telegram_api_key" \
     "$synthetic_telegram_chat_id"; then
  pass "desktop role falls back to shared Fruux credentials when cmdline tokens are omitted"
else
  fail "desktop role falls back to shared Fruux credentials when cmdline tokens are omitted"
fi

if run_gpg_passphrase_helper 'gpgSecret' 'gpgSecret' true; then
  pass "desktop GPG bootstrap uses the runtime-selected primary GPG passphrase"
else
  fail "desktop GPG bootstrap uses the runtime-selected primary GPG passphrase"
fi

gpg_passphrase_error="$TMP_DIR/gpg-passphrase.err"
if ! run_gpg_passphrase_helper ignored '' false 2>"$gpg_passphrase_error" &&
   grep -Fq 'desktop GPG bootstrap requires primary_gpg_passphrase= or primary_password=' "$gpg_passphrase_error"; then
  pass "desktop GPG bootstrap refuses unrelated fallback passphrases"
else
  fail "desktop GPG bootstrap refuses unrelated fallback passphrases"
fi

desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
if grep -Fq -- '--quick-generate-key "$gpg_user_id" future-default default never' "$desktop_components" &&
   grep -Fq 'printf "%s:6:\n" "$gpg_fingerprint"' "$desktop_components" &&
   grep -Fq 'account_gpg --batch --no-options --import-ownertrust' "$desktop_components" &&
   grep -Fq 'substr(\$9, 1, 1) == \"u\" && \$12 ~ /E/' "$desktop_components"; then
  pass "desktop GPG bootstrap creates a modern encryption key and verifies KWallet ultimate-trust eligibility"
else
  fail "desktop GPG bootstrap creates a modern encryption key and verifies KWallet ultimate-trust eligibility"
fi

fuzzel_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-fuzzel"
fuzzel_base_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/fuzzel/base.ini.tmpl"
fuzzel_launcher_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/fuzzel/fuzzel.ini.tmpl"
fuzzel_menu_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/fuzzel/menu.ini.tmpl"
computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
maintenance_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-maintenance-menu"
podman_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-podman-menu"
labwc_rc_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
power_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-power-menu"
power_settings="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-power-settings"
brightness_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-brightness-control"
run_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-run"
admin_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-admin-action"
admin_root_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-admin-action-root"
admin_worker="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-admin-action-worker"
admin_worker_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/labwc-admin-action@.service"
logout_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-logout"
labwc_power_rule="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/03-labwc-power.rules"
if grep -q '^LABWC_LAUNCHER_COMMAND="labwc-fuzzel launcher"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_MENU_COMMAND="labwc-fuzzel launcher"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q 'launcher_command=${LABWC_LAUNCHER_COMMAND:-labwc-fuzzel launcher}' "$run_wrapper" &&
   grep -q 'labwc-fuzzel menu --dmenu --prompt power' "$power_menu" &&
   grep -q 'exec labwc-logout' "$power_menu" &&
   grep -q 'exec labwc-admin-action suspend' "$power_menu" &&
   grep -q 'exec labwc-admin-action reboot' "$power_menu" &&
   grep -q 'exec labwc-admin-action poweroff' "$power_menu" &&
   grep -q 'CPU power profile' "$power_settings" &&
   grep -q 'exec powerprofilesctl set' "$power_settings" &&
   grep -q 'labwc-fuzzel menu --dmenu --prompt "Brightness' "$brightness_menu" &&
   grep -q 'brightnessctl --class=backlight' "$brightness_menu" &&
   grep -q 'labwc-brightness-control must run in the managed desktop session' "$brightness_menu" &&
   grep -q 'labwc-brightness-control requires a non-root desktop runtime directory' "$brightness_menu" &&
   ! grep -Fq 'id -u' "$brightness_menu" &&
   grep -q 'include=~/.config/fuzzel/base.ini' "$fuzzel_launcher_template" &&
   grep -q 'icon-theme=__INSTALLER_LABWC_ICON_THEME__' "$fuzzel_base_template" &&
   grep -q '^match-mode=fzf$' "$fuzzel_base_template" &&
   grep -q '^filter-desktop=yes$' "$fuzzel_base_template" &&
   ! grep -q '^fuzzy=' "$fuzzel_base_template" &&
   grep -q 'terminal=__INSTALLER_LABWC_TERMINAL_PRIMARY__' "$fuzzel_base_template" &&
   grep -q '^width=__INSTALLER_LABWC_FUZZEL_WIDTH__$' "$fuzzel_launcher_template" &&
   grep -q '^lines=__INSTALLER_LABWC_FUZZEL_LINES__$' "$fuzzel_launcher_template" &&
   grep -q 'config_name=fuzzel.ini' "$fuzzel_wrapper" &&
   grep -q 'mode=menu' "$fuzzel_wrapper" &&
   grep -q '^runtime_root=\${XDG_RUNTIME_DIR:-}$' "$fuzzel_wrapper" &&
   grep -Fq 'if ! /usr/bin/flock -w 5 8; then' "$fuzzel_wrapper" &&
   grep -Fq "fatal 'unable to acquire the Fuzzel launcher lock within five seconds'" "$fuzzel_wrapper" &&
   grep -Fq 'pid_path="${runtime_root%/}/labwc-fuzzel.pid"' "$fuzzel_wrapper" &&
   grep -q '^run_fuzzel() {$' "$fuzzel_wrapper" &&
   grep -q 'fuzzel "\$@" <&7 >&1 2>&2 8>&- &' "$fuzzel_wrapper" &&
   ! grep -Fq 'id -u' "$fuzzel_wrapper" &&
   ! grep -Eq '(^|[^[:alnum:]_])(pgrep|pkill|pidof)([^[:alnum:]_]|$)' "$fuzzel_wrapper" &&
   grep -q '"Container Management"' "$podman_menu" &&
   grep -q -- '--create-user' "$podman_menu" &&
   grep -q -- '--create-container' "$podman_menu" &&
   grep -q -- '--service-podman' "$podman_menu" &&
   grep -q -- '--wipe-all' "$podman_menu" &&
   grep -q 'sudo "\$PODBIN_BINARY" "\$@"' "$podman_menu" &&
   grep -q 'exec labwc-terminal -e "\$script_path" _run "\$@"' "$podman_menu" &&
   grep -A2 '<keybind key="W-m">' "$labwc_rc_template" |
     grep -q 'command="labwc-computer-management"' &&
   grep -A2 '<keybind key="C-A-m">' "$labwc_rc_template" |
     grep -q 'command="labwc-computer-management"' &&
   ! grep -q '<keybind key="C-W-m">' "$labwc_rc_template" &&
   ! grep -q '<keybind key="C-W-p">' "$labwc_rc_template" &&
   grep -q '^LABWC_FUZZEL_MANAGED_ICONS=1$' "$computer_management" &&
   grep -q '^choose_root_lines() {$' "$computer_management" &&
   grep -q 'managed_icons=${LABWC_FUZZEL_MANAGED_ICONS:-0}' "$fuzzel_wrapper" &&
   grep -q 'print "← Back"' "$fuzzel_wrapper" &&
   grep -q '"⮞ Container Management"' "$computer_management" &&
   grep -q '"⮞ Users & Groups"' "$computer_management" &&
   grep -q '"⮞ Network Management"' "$computer_management" &&
   ! grep -q '"⮞ Firewall Security"' "$computer_management" &&
   grep -q "'⮞ Firewall Security'" "$maintenance_menu" &&
   grep -q '"⮞ Network Scanning"' "$computer_management" &&
   grep -q '"⮞ Connection Profiles"' "$computer_management" &&
   grep -q '"⮞ VPN Connections"' "$computer_management" &&
   grep -q '"⮞ WireGuard Connections"' "$computer_management" &&
   grep -q '"⮞ DNS Configuration"' "$computer_management" &&
   grep -q '"⮞ System Maintenance & Diagnostics"' "$computer_management" &&
   grep -q '"⮞ Troubleshooting"' "$computer_management" &&
   grep -q '"⮞ Backup Drives"' "$computer_management" &&
   grep -q 'run_command labwc-podman-menu' "$computer_management" &&
   grep -q 'usr/local/bin/labwc-computer-management /usr/local/bin/labwc-computer-management 0755' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-users-groups-menu /usr/local/bin/labwc-users-groups-menu 0755' "$desktop_components" &&
	   grep -q 'usr/local/bin/labwc-firewall-menu /usr/local/bin/labwc-firewall-menu 0755' "$desktop_components" &&
	   grep -q 'usr/local/bin/labwc-podman-menu /usr/local/bin/labwc-podman-menu 0755' "$desktop_components" &&
	   grep -q 'usr/local/libexec/labwc-admin-action-root /usr/local/libexec/labwc-admin-action-root 0755' "$desktop_components" &&
	   grep -q 'usr/local/libexec/labwc-admin-action-worker /usr/local/libexec/labwc-admin-action-worker 0755' "$desktop_components" &&
	   grep -q 'etc/systemd/system/labwc-admin-action@.service /etc/systemd/system/labwc-admin-action@.service 0644' "$desktop_components" &&
	   grep -q 'notify_send_cmd=$(command -v notify-send' "$admin_wrapper" &&
	   grep -Fq '[ "$#" -eq 1 ]' "$admin_wrapper" &&
	   grep -Fqx 'pkexec_cmd=/usr/bin/pkexec' "$admin_wrapper" &&
	   grep -Fqx 'root_helper=/usr/local/libexec/labwc-admin-action-root' "$admin_wrapper" &&
	   grep -Fq 'runtime_dir=${XDG_RUNTIME_DIR:-}' "$admin_wrapper" &&
	   grep -Fq 'power_lock="${runtime_dir%/}/labwc-admin-action.lock"' "$admin_wrapper" &&
	   grep -Fq 'exec 9>"$power_lock"' "$admin_wrapper" &&
	   grep -Fq '/usr/bin/flock --nonblock 9' "$admin_wrapper" &&
	   grep -Fq 'if "$pkexec_cmd" "$root_helper" "$action"; then' "$admin_wrapper" &&
	   grep -Fq 'notify_failure "The ${action} request was cancelled or failed (status ${action_status})."' "$admin_wrapper" &&
	   grep -Fq -- '-u critical' "$admin_wrapper" &&
	   grep -Fq -- '-t 0' "$admin_wrapper" &&
	   ! grep -Eq 'systemctl|busctl|LABWC_SESSION_OWNER|XDG_SESSION_TYPE|LABWC_PID|WAYLAND_DISPLAY' "$admin_wrapper" &&
	   ! grep -Eq 'systemd-inhibit|labwc/shutdown|run_session_shutdown_hook|restore_session_after_failed_power_request|release_power_authorization_agent' "$admin_wrapper" &&
	   grep -Fq '[ "$(/usr/bin/id -u)" -eq 0 ]' "$admin_root_helper" &&
	   grep -Fq '/usr/bin/getent passwd "$PKEXEC_UID"' "$admin_root_helper" &&
	   grep -Fq 'worker_unit="labwc-admin-action@${PKEXEC_UID}-${action}.service"' "$admin_root_helper" &&
	   grep -Fq 'exec /usr/bin/systemctl --no-block start "$worker_unit"' "$admin_root_helper" &&
	   ! grep -Eq 'timeout|--machine=|labwc-session[.]target|systemctl "\$action"' "$admin_root_helper" &&
	   grep -Fq 'session_machine="${invoker_name}@.host"' "$admin_worker" &&
	   grep -Fq -- '--machine="$session_machine"' "$admin_worker" &&
	   grep -Fq 'labwc-session.target || session_stop_status=$?' "$admin_worker" &&
	   grep -Fq 'exec /usr/bin/systemctl --no-block "$action"' "$admin_worker" &&
	   grep -Fqx 'ExecStart=/usr/local/libexec/labwc-admin-action-worker %i' "$admin_worker_unit" &&
	   grep -Fqx 'AppArmorProfile=managed-labwc-admin-action-worker' "$admin_worker_unit" &&
	   grep -Fqx 'NoNewPrivileges=yes' "$admin_worker_unit" &&
	   grep -Fqx 'ProtectSystem=strict' "$admin_worker_unit" &&
	   grep -Fq 'var POWER_HELPER = "/usr/local/libexec/labwc-admin-action-root";' "$labwc_power_rule" &&
	   grep -Fq 'return polkit.Result.AUTH_ADMIN;' "$labwc_power_rule" &&
	   ! grep -Eq 'subject\.(active|local|seat)' "$labwc_power_rule" &&
	   ! grep -q '/bin/sh -lc' "$admin_wrapper" &&
   ! grep -q '"$shutdown_hook" logout' "$logout_wrapper" &&
   grep -q 'LABWC_SESSION_OWNER' "$logout_wrapper" &&
   grep -q 'LABWC_PID' "$logout_wrapper" &&
   grep -q 'labwc --exit' "$logout_wrapper" &&
   ! grep -q 'loginctl terminate-session' "$logout_wrapper"; then
  pass "Fuzzel helpers keep launcher modes coherent and issue authenticated display-manager-independent power requests"
else
  fail "Fuzzel helpers keep launcher modes coherent and issue authenticated display-manager-independent power requests"
fi

if grep -q '^wifi\.scan-rand-mac-address=yes$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/80-managed-link-privacy.conf" &&
   grep -q '^match-device=type:wifi-p2p$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/80-managed-link-privacy.conf" &&
   grep -q '^managed=0$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/80-managed-link-privacy.conf" &&
   grep -q '^ethernet\.cloned-mac-address=random$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/80-managed-link-privacy.conf" &&
   grep -q '^wifi\.cloned-mac-address=random$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/NetworkManager/conf.d/80-managed-link-privacy.conf"; then
  pass "NetworkManager keeps link privacy while leaving the unused Wi-Fi P2P pseudo-device unmanaged"
else
  fail "NetworkManager keeps link privacy while leaving the unused Wi-Fi P2P pseudo-device unmanaged"
fi

network_late_helper="$ROOT_DIR/d-i/forky/scripts/late/network.sh"
networkmanager_dispatcher_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/NetworkManager.service.d/20-managed-dispatcher.conf"
dispatcher_persistent_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/NetworkManager-dispatcher.service.d/20-managed-persistent.conf"
if grep -q '^stage_target_networkmanager_dispatcher_activation_if_available() {$' "$network_late_helper" &&
   grep -q 'dispatcher_dbus_service=/usr/share/dbus-1/system-services/org.freedesktop.nm_dispatcher.service' "$network_late_helper" &&
   grep -q "Name=org.freedesktop.nm_dispatcher" "$network_late_helper" &&
   grep -q "SystemdService=dbus-org.freedesktop.nm-dispatcher.service" "$network_late_helper" &&
   grep -q "BusName=org.freedesktop.nm_dispatcher" "$network_late_helper" &&
   grep -q 'stage_target_systemd_unit_alias_to_path' "$network_late_helper" &&
   grep -q 'dbus-org.freedesktop.nm-dispatcher.service' "$network_late_helper" &&
   grep -Fqx 'After=NetworkManager-dispatcher.service networking.service wpa_supplicant.service' "$networkmanager_dispatcher_dropin" &&
   ! grep -q '^Before=' "$networkmanager_dispatcher_dropin" &&
   grep -q 'write_target_file /etc/systemd/system/NetworkManager.service 0644' "$network_late_helper" &&
   grep -Fqx 'PartOf=NetworkManager.service' "$dispatcher_persistent_dropin" &&
   grep -Fqx 'ExecStart=/usr/libexec/nm-dispatcher --persist' "$dispatcher_persistent_dropin" &&
   grep -q 'desktop_enable_unit_if_available NetworkManager-dispatcher.service system' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   ! grep -q '^desktop_stage_networkmanager_dispatcher_dbus_alias_if_available() {$' "$ROOT_DIR/d-i/forky/scripts/desktop/components.sh" &&
   grep -q '/usr/share/dbus-1/system-services/org.freedesktop.nm_dispatcher.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   ! grep -q 'require_readable /etc/systemd/system/NetworkManager.service$' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/systemd/system/NetworkManager.service.d/20-managed-dispatcher.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/systemd/system/NetworkManager-dispatcher.service.d/20-managed-persistent.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"; then
  pass "network staging validates the dispatcher, keeps it persistent, and preserves D-Bus activation"
else
  fail "network staging validates the dispatcher, keeps it persistent, and preserves D-Bus activation"
fi

greetd_greeter_pam="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pam.d/greetd-greeter"
if grep -Eq '^auth[[:space:]]+required[[:space:]]+pam_permit\.so$' "$greetd_greeter_pam" &&
   grep -Eq '^account[[:space:]]+required[[:space:]]+pam_permit\.so$' "$greetd_greeter_pam" &&
   grep -q 'pam_systemd\.so class=greeter type=wayland desktop=labwc' "$greetd_greeter_pam" &&
   ! grep -q 'pam_systemd\.so class=user-light' "$greetd_greeter_pam" &&
   ! grep -Eq '^@include common-(auth|account)$|pam_nologin\.so' "$greetd_greeter_pam"; then
  pass "greeter PAM permits the system account and registers a Labwc display-manager session"
else
  fail "greeter PAM permits the system account and registers a Labwc display-manager session"
fi

if grep -q 'pam_systemd\.so class=user type=wayland desktop=labwc' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pam.d/greetd" &&
   ! grep -q 'pam_kwallet5\.so' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pam.d/greetd"; then
  pass "desktop PAM keeps the real session as a normal Labwc user session and leaves the GPG-backed wallet off kwallet-pam"
else
  fail "desktop PAM keeps the real session as a normal Labwc user session and leaves the GPG-backed wallet off kwallet-pam"
fi

greetd_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/greetd.service.d/20-labwc-vt.conf"
if grep -q '^Wants=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket$' "$greetd_dropin" &&
   grep -q '^After=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket$' "$greetd_dropin" &&
   ! grep -q 'systemd-udev-settle.service' "$greetd_dropin"; then
  pass "greetd waits for login services without blocking boot on the global udev queue"
else
  fail "greetd waits for login services without blocking boot on the global udev queue"
fi

if grep -q '^d __INSTALLER_DIR_POLKIT_RUNTIME_RULES_D__ 0755 root root -$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/70-polkit-runtime.conf" &&
   grep -q '^d __INSTALLER_DIR_POLKIT_LOCAL_RULES_D__ 0755 root root -$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/70-polkit-runtime.conf"; then
  pass "polkit tmpfiles create optional rules directories"
else
  fail "polkit tmpfiles create optional rules directories"
fi

greeter_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-session.tmpl"
greeter_client="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-greeter-client"
greeter_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-greeter/rc.xml"
greeter_autostart="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-greeter/autostart"
greeter_output="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-output"
greeter_power="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-greeter-power"
greeter_power_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/sbin/greetd-power-action"
greeter_power_rule="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/10-greetd-power.rules.tmpl"
greeter_power_css="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/greetd/gtkgreet-power.css"
labwc_x11_environment_names='DISPLAY XAUTHORITY WLR_XWAYLAND XWAYLAND XWAYLAND_PATH XWAYLAND_NO_GLAMOR XWAYLAND_FORCE_SCALE XWAYLAND_RESTART_DELAY _XWAYLAND_GLOBAL_OUTPUT_SCALE WINDOWID SESSION_MANAGER DESKTOP_STARTUP_ID'
greeter_client_scrub_line=$(grep -n -F 'unset $labwc_x11_environment_names' "$greeter_client" | cut -d: -f1)
greeter_client_launch_line=$(grep -n -F '/usr/bin/gtkgreet -l -s /etc/greetd/gtkgreet.css -c "$LABWC_GREETER_SESSION_COMMAND"' "$greeter_client" | cut -d: -f1)
if grep -q 'mktemp -d "\${greeter_runtime_parent}/labwc-greeter\.\${greeter_uid}\.XXXXXX"' "$greeter_wrapper" &&
   grep -q 'export XDG_CACHE_HOME=' "$greeter_wrapper" &&
   grep -q 'export XDG_STATE_HOME=' "$greeter_wrapper" &&
   grep -q 'export XDG_CONFIG_HOME=' "$greeter_wrapper" &&
   grep -q 'export GNUPGHOME=' "$greeter_wrapper" &&
   grep -q '^export GIO_USE_VFS=local$' "$greeter_wrapper" &&
   grep -q '^export GVFS_DISABLE_FUSE=1$' "$greeter_wrapper"; then
  pass "greeter wrapper uses temporary private runtime state without GVFS"
else
  fail "greeter wrapper uses temporary private runtime state without GVFS"
fi

if ! grep -q 'dbus-run-session' "$greeter_wrapper" &&
   ! grep -q 'systemctl --user' "$greeter_wrapper" &&
   grep -q 'export LIBSEAT_BACKEND=seatd' "$greeter_wrapper" &&
   grep -q '^export LABWC_SESSION_OWNER=greeter$' "$greeter_wrapper" &&
   grep -q '^export LABWC_UPDATE_ACTIVATION_ENV=0$' "$greeter_wrapper" &&
   grep -q '^unset WAYLAND_DISPLAY SWAYSOCK LABWC_PID$' "$greeter_wrapper" &&
   grep -Fqx "labwc_x11_environment_names='$labwc_x11_environment_names'" "$greeter_wrapper" &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$greeter_wrapper")" -eq 2 ] &&
   ! grep -Eq '/opt/xwayland|libxcb-cursor|/tmp/.X11-unix' "$greeter_wrapper" &&
   grep -q '^greeter_wlr_no_hardware_cursors=\${LABWC_GREETER_WLR_NO_HARDWARE_CURSORS:-__INSTALLER_LABWC_GREETER_WLR_NO_HARDWARE_CURSORS__}$' "$greeter_wrapper" &&
   grep -q '^unset WLR_RENDERER$' "$greeter_wrapper" &&
   grep -q '^unset GSK_RENDERER$' "$greeter_wrapper" &&
   grep -q '^unset WLR_NO_HARDWARE_CURSORS$' "$greeter_wrapper" &&
   grep -q 'export WLR_RENDERER="${LABWC_GREETER_WLR_RENDERER}"' "$greeter_wrapper" &&
   grep -q '^  export WLR_RENDERER="__INSTALLER_LABWC_GREETER_WLR_RENDERER__"$' "$greeter_wrapper" &&
   grep -q 'if \[ "${LABWC_GREETER_GSK_RENDERER+x}" = x \]; then' "$greeter_wrapper" &&
   grep -q '\[ -z "${LABWC_GREETER_GSK_RENDERER}" \] || export GSK_RENDERER="${LABWC_GREETER_GSK_RENDERER}"' "$greeter_wrapper" &&
   grep -q '^greeter_gsk_renderer_default="__INSTALLER_LABWC_GREETER_GSK_RENDERER__"$' "$greeter_wrapper" &&
   grep -q '^  \[ -z "\$greeter_gsk_renderer_default" \] || export GSK_RENDERER="\$greeter_gsk_renderer_default"$' "$greeter_wrapper" &&
   grep -q '^\[ -z "\$greeter_wlr_no_hardware_cursors" \] || export WLR_NO_HARDWARE_CURSORS="\$greeter_wlr_no_hardware_cursors"$' "$greeter_wrapper" &&
   grep -q '^export GDK_DISABLE="\${LABWC_GREETER_GDK_DISABLE:-__INSTALLER_LABWC_GREETER_GDK_DISABLE__}"$' "$greeter_wrapper" &&
   ! grep -q 'udevadm settle' "$greeter_wrapper" &&
   ! grep -q 'greeter_start_delay' "$greeter_wrapper" &&
   grep -q '^session_command=\${LABWC_DESKTOP_SESSION_COMMAND:-__INSTALLER_LABWC_DESKTOP_SESSION_COMMAND__}$' "$greeter_wrapper" &&
   grep -q '^greeter_config_dir="\${greeter_session_root}/config/labwc"$' "$greeter_wrapper" &&
   grep -q '^greeter_asset_dir=/usr/local/share/labwc-greeter$' "$greeter_wrapper" &&
   grep -q '^greeter_client=/usr/local/libexec/labwc-greeter-client$' "$greeter_wrapper" &&
   grep -q '^greeter_autostart="\${greeter_config_dir}/autostart"$' "$greeter_wrapper" &&
   grep -q '^exit 0$' "$greeter_autostart" &&
   ! grep -q 'labwc-output-refresh' "$greeter_wrapper" &&
   grep -q '<autoEnableOutputs>no</autoEnableOutputs>' "$greeter_rc" &&
   ! grep -q 'xwaylandPersistence' "$greeter_rc" &&
   grep -q '^if ! /usr/local/bin/labwc-greeter-output --configure >/dev/null 2>&1; then$' "$greeter_client" &&
   grep -q 'fatal: managed greeter output selection failed' "$greeter_client" &&
   ! grep -q 'continuing with Labwc auto-enabled outputs' "$greeter_client" &&
   grep -Fqx "labwc_x11_environment_names='$labwc_x11_environment_names'" "$greeter_client" &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$greeter_client")" -eq 1 ] &&
   [ -n "$greeter_client_scrub_line" ] &&
   [ -n "$greeter_client_launch_line" ] &&
   [ "$greeter_client_scrub_line" -lt "$greeter_client_launch_line" ] &&
   ! grep -Eq '/opt/xwayland|libxcb-cursor|/tmp/.X11-unix' "$greeter_client" &&
   grep -q 'labwc-greeter-output --watch' "$greeter_client" &&
   grep -q '^trap cleanup_greeter_children EXIT$' "$greeter_client" &&
   grep -q "^trap 'exit 0' HUP INT TERM$" "$greeter_client" &&
   grep -q 'labwc-greeter-power' "$greeter_client" &&
   grep -q 'greetd-power-action reboot' "$greeter_rc" &&
   grep -q 'greetd-power-action poweroff' "$greeter_rc" &&
   grep -q '^/usr/bin/gtkgreet -l -s /etc/greetd/gtkgreet.css -c "$LABWC_GREETER_SESSION_COMMAND"$' "$greeter_client" &&
   grep -q '^/usr/bin/labwc -C "$greeter_config_dir" -S "$greeter_client"$' "$greeter_wrapper" &&
   grep -q 'desktop_render_role_target_template \\' "$desktop_components" &&
   grep -q '"usr/local/bin/labwc-greeter-session.tmpl"' "$desktop_components" &&
   grep -q 'usr/local/libexec/labwc-greeter-client /usr/local/libexec/labwc-greeter-client 0755' "$desktop_components" &&
   grep -q 'usr/local/share/labwc-greeter/rc.xml /usr/local/share/labwc-greeter/rc.xml 0644' "$desktop_components" &&
   grep -q 'usr/local/share/labwc-greeter/autostart /usr/local/share/labwc-greeter/autostart 0644' "$desktop_components"; then
  pass "greeter wrapper applies the managed output policy and runs gtkgreet fullscreen in a private Labwc session"
else
  fail "greeter wrapper applies the managed output policy and runs gtkgreet fullscreen in a private Labwc session"
fi

if head -n 1 "$greeter_output" | grep -q '^#!/usr/bin/env perl$' &&
   grep -q '^sub configure_outputs {$' "$greeter_output" &&
   grep -q '^sub watch_outputs {$' "$greeter_output" &&
   grep -q '^sub external_mode_for_output {$' "$greeter_output" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH' "$greeter_output" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT' "$greeter_output" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ' "$greeter_output" &&
   grep -q "'--mode', \$mode" "$greeter_output" &&
   grep -q 'LABWC_GREETER_EXTERNAL_SCALE' "$greeter_output" &&
   grep -Fq "\$defaults{LABWC_GREETER_EXTERNAL_SCALE} // '1'" "$greeter_output" &&
   grep -q 'LABWC_GREETER_INTERNAL_SCALE' "$greeter_output" &&
   grep -q '^sub is_hdmi_output {$' "$greeter_output" &&
   grep -q "'--output', \$selected," "$greeter_output" &&
   grep -q "'--output', \$output_name, '--off'" "$greeter_output" &&
   python3 -m py_compile "$greeter_power" &&
   grep -q 'GtkLayerShell.set_anchor' "$greeter_power" &&
   grep -q '"reboot" if action == "reboot" else "shutdown"' "$greeter_power" &&
   grep -q 'Confirm shutdown' "$greeter_power" &&
   grep -q 'Confirm reboot' "$greeter_power" &&
   grep -q 'button.greeter-power-button.reboot {' "$greeter_power_css" &&
   grep -q 'background-color: #eab308;' "$greeter_power_css" &&
   grep -q 'button.greeter-power-button.shutdown {' "$greeter_power_css" &&
   grep -q 'background-color: #dc2626;' "$greeter_power_css" &&
   grep -q 'org.freedesktop.login1.Manager' "$greeter_power_action" &&
   grep -q 'var GREETER_USER = "__INSTALLER_LABWC_GREETER_USER__";' "$greeter_power_rule" &&
   grep -q 'org.freedesktop.login1.power-off' "$greeter_power_rule" &&
   grep -q 'org.freedesktop.login1.reboot' "$greeter_power_rule"; then
  pass "greeter output selection, adaptive scale, power controls, and narrow logind authorization are staged"
else
  fail "greeter output selection, adaptive scale, power controls, and narrow logind authorization are staged"
fi

session_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-session.tmpl"
labwc_compositor_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-compositor.service"
retired_session_environment="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/environment.d/90-labwc-session.conf.tmpl"
labwc_environment="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/environment.tmpl"
labwc_wayland_environment="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/environment.d/10-wayland.env.tmpl"
greetd_pam="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pam.d/greetd"
if [ ! -e "$retired_session_environment" ] &&
   ! grep -q 'dbus-run-session' "$session_wrapper" &&
   grep -Fq 'session    required   pam_systemd.so class=user type=wayland desktop=labwc' "$greetd_pam" &&
   grep -q '^export ELECTRON_OZONE_PLATFORM_HINT="\${ELECTRON_OZONE_PLATFORM_HINT:-wayland}"$' "$session_wrapper" &&
   grep -q '^export QT_QPA_PLATFORM="\${LABWC_QT_QPA_PLATFORM:-__INSTALLER_LABWC_QT_QPA_PLATFORM__}"$' "$session_wrapper" &&
   grep -q '^export QT_QPA_PLATFORMTHEME="\${QT_QPA_PLATFORMTHEME:-\${LABWC_QT_PLATFORMTHEME:-__INSTALLER_LABWC_QT_PLATFORMTHEME__}}"$' "$session_wrapper" &&
   grep -q '^export QT_WAYLAND_DISABLE_WINDOWDECORATION=1$' "$session_wrapper" &&
   grep -q '^export QT_OPENGL="\${QT_OPENGL:-desktop}"$' "$session_wrapper" &&
   grep -q '^export QSG_RHI_BACKEND="\${QSG_RHI_BACKEND:-opengl}"$' "$session_wrapper" &&
   ! grep -q '^export QT_STYLE_OVERRIDE=' "$session_wrapper" &&
   grep -q '^export GDK_BACKEND="\${LABWC_GDK_BACKEND:-__INSTALLER_LABWC_GDK_BACKEND__}"$' "$session_wrapper" &&
   grep -q '^export GDK_DISABLE="\${LABWC_GDK_DISABLE:-__INSTALLER_LABWC_GDK_DISABLE__}"$' "$session_wrapper" &&
   grep -q '^export SDL_VIDEODRIVER="\${LABWC_SDL_VIDEODRIVER:-__INSTALLER_LABWC_SDL_VIDEODRIVER__}"$' "$session_wrapper" &&
   grep -q '^export CLUTTER_BACKEND="\${LABWC_CLUTTER_BACKEND:-__INSTALLER_LABWC_CLUTTER_BACKEND__}"$' "$session_wrapper" &&
   grep -q '^export XCURSOR_THEME="\${XCURSOR_THEME:-\${LABWC_CURSOR_THEME:-__INSTALLER_LABWC_CURSOR_THEME__}}"$' "$session_wrapper" &&
   grep -q '^export XCURSOR_SIZE="\${XCURSOR_SIZE:-\${LABWC_CURSOR_SIZE:-__INSTALLER_LABWC_CURSOR_SIZE__}}"$' "$session_wrapper" &&
   grep -q '^export GTK_THEME="\${GTK_THEME:-\${LABWC_GTK_THEME:-__INSTALLER_LABWC_GTK_THEME__}}"$' "$session_wrapper" &&
   grep -q '^session_wlr_renderer=\${LABWC_WLR_RENDERER:-__INSTALLER_LABWC_WLR_RENDERER__}$' "$session_wrapper" &&
   grep -q '^session_gsk_renderer=\${LABWC_GSK_RENDERER:-__INSTALLER_LABWC_GSK_RENDERER__}$' "$session_wrapper" &&
   grep -q '^session_wlr_no_hardware_cursors=\${LABWC_WLR_NO_HARDWARE_CURSORS:-__INSTALLER_LABWC_WLR_NO_HARDWARE_CURSORS__}$' "$session_wrapper" &&
   grep -q '^unset WLR_RENDERER$' "$session_wrapper" &&
   grep -q '^unset GSK_RENDERER$' "$session_wrapper" &&
   grep -q '^unset WLR_NO_HARDWARE_CURSORS$' "$session_wrapper" &&
   grep -Fqx "labwc_x11_environment_names='$labwc_x11_environment_names'" "$session_wrapper" &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$session_wrapper")" -eq 2 ] &&
   grep -Fq -- '--user unset-environment $cleanup_environment_names' "$session_wrapper" &&
   ! grep -Eq '/opt/xwayland|libxcb-cursor|/tmp/.X11-unix' "$session_wrapper" &&
   grep -q '^WLR_RENDERER=__INSTALLER_LABWC_WLR_RENDERER__$' "$labwc_environment" &&
   grep -q '^__INSTALLER_LABWC_GSK_RENDERER_LINE__$' "$labwc_environment" &&
   grep -q '^GDK_DISABLE=__INSTALLER_LABWC_GDK_DISABLE__$' "$labwc_environment" &&
   grep -q '^WLR_NO_HARDWARE_CURSORS=__INSTALLER_LABWC_WLR_NO_HARDWARE_CURSORS__$' "$labwc_environment" &&
   grep -q '^XCURSOR_THEME=__INSTALLER_LABWC_CURSOR_THEME__$' "$labwc_environment" &&
   grep -q '^XCURSOR_SIZE=__INSTALLER_LABWC_CURSOR_SIZE__$' "$labwc_environment" &&
   grep -q '^ELECTRON_OZONE_PLATFORM_HINT=wayland$' "$labwc_environment" &&
   grep -q '^QT_WAYLAND_DISABLE_WINDOWDECORATION=1$' "$labwc_environment" &&
   grep -q '^QT_OPENGL=desktop$' "$labwc_environment" &&
   grep -q '^QSG_RHI_BACKEND=opengl$' "$labwc_environment" &&
   grep -q '^WLR_RENDERER=__INSTALLER_LABWC_WLR_RENDERER__$' "$labwc_wayland_environment" &&
   grep -q '^__INSTALLER_LABWC_GSK_RENDERER_LINE__$' "$labwc_wayland_environment" &&
   grep -q '^GDK_DISABLE=__INSTALLER_LABWC_GDK_DISABLE__$' "$labwc_wayland_environment" &&
   grep -q '^WLR_NO_HARDWARE_CURSORS=__INSTALLER_LABWC_WLR_NO_HARDWARE_CURSORS__$' "$labwc_wayland_environment" &&
   grep -q '^QT_QPA_PLATFORM=__INSTALLER_LABWC_QT_QPA_PLATFORM__$' "$labwc_wayland_environment" &&
   grep -q '^QT_QPA_PLATFORMTHEME=__INSTALLER_LABWC_QT_PLATFORMTHEME__$' "$labwc_wayland_environment" &&
   grep -q '^QT_WAYLAND_DISABLE_WINDOWDECORATION=1$' "$labwc_wayland_environment" &&
   grep -q '^QT_OPENGL=desktop$' "$labwc_wayland_environment" &&
   grep -q '^QSG_RHI_BACKEND=opengl$' "$labwc_wayland_environment" &&
   grep -q '^ELECTRON_OZONE_PLATFORM_HINT=wayland$' "$labwc_wayland_environment" &&
   ! grep -q '^QT_STYLE_OVERRIDE=' "$labwc_wayland_environment" &&
   grep -q '^GDK_BACKEND=__INSTALLER_LABWC_GDK_BACKEND__$' "$labwc_wayland_environment" &&
   grep -q '^SDL_VIDEODRIVER=__INSTALLER_LABWC_SDL_VIDEODRIVER__$' "$labwc_wayland_environment" &&
   grep -q '^CLUTTER_BACKEND=__INSTALLER_LABWC_CLUTTER_BACKEND__$' "$labwc_wayland_environment" &&
   grep -q '^GTK_THEME=__INSTALLER_LABWC_GTK_THEME__$' "$labwc_wayland_environment" &&
   ! grep -q '_JAVA_AWT_WM_NONREPARENTING' "$labwc_wayland_environment" &&
   ! grep -q '^LABWC_QT_STYLE_OVERRIDE=' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -Fq 'current_uid=$(/usr/bin/id -u)' "$session_wrapper" &&
   grep -Fq 'expected_runtime_dir="/run/user/${current_uid}"' "$session_wrapper" &&
   grep -q '^lock_path="\${XDG_RUNTIME_DIR}/labwc-session.lock"$' "$session_wrapper" &&
   grep -q '^exec 9>"\$lock_path"$' "$session_wrapper" &&
   grep -q '^/usr/bin/flock --nonblock 9 || exit 0$' "$session_wrapper" &&
   grep -Fq 'greeter_uid=$(/usr/bin/id -u -- "$greeter_user" 2>/dev/null)' "$session_wrapper" &&
   grep -Fq 'DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket \' "$session_wrapper" &&
   grep -Fq '            --json=short \' "$session_wrapper" &&
   grep -Fq '            list-sessions \' "$session_wrapper" &&
   grep -Fq '  handoff_deadline=$((handoff_started + 20))' "$session_wrapper" &&
   grep -Fq 'fatal: the managed greeter did not release all logind sessions within 20 seconds:' "$session_wrapper" &&
   grep -q '^cleanup_environment_names=' "$session_wrapper" &&
   grep -q '^compositor_environment_names=' "$session_wrapper" &&
   grep -Fq '"$systemctl_cmd" --user import-environment $compositor_environment_names' "$session_wrapper" &&
   ! sed -n "s/^compositor_environment_names='\([^']*\)'$/\1/p" "$session_wrapper" |
     grep -Eq '(^| )(DISPLAY|LABWC_PID|SWAYSOCK|WAYLAND_DISPLAY)( |$)' &&
   ! grep -q 'stop labwc-session.target' "$session_wrapper" &&
   ! grep -q '^trap cleanup_labwc_session EXIT$' "$session_wrapper" &&
	   grep -Fq '"$systemctl_cmd" --user --wait start labwc-compositor.service 9>&- || labwc_status=$?' "$session_wrapper" &&
	   [ "$(grep -n -F 'wait_for_greeter_seat_release' "$session_wrapper" | tail -n 1 | cut -d: -f1)" -lt "$(grep -n -F '"$systemctl_cmd" --user --wait start labwc-compositor.service 9>&- || labwc_status=$?' "$session_wrapper" | cut -d: -f1)" ] &&
	   ! grep -q '^/usr/bin/labwc 9>&- || labwc_status=\$?$' "$session_wrapper" &&
	   ! sed -n '/^cleanup_labwc_session() {$/,/^}$/p' "$session_wrapper" |
	     grep -Fq 'dbus-update-activation-environment' &&
	   grep -q '^DefaultDependencies=no$' "$labwc_compositor_unit" &&
	   grep -q '^Conflicts=shutdown.target$' "$labwc_compositor_unit" &&
	   grep -q '^Before=shutdown.target$' "$labwc_compositor_unit" &&
	   grep -q '^Requires=dbus.service dbus.socket$' "$labwc_compositor_unit" &&
	   grep -q '^After=dbus.service dbus.socket$' "$labwc_compositor_unit" &&
	   grep -q '^PartOf=labwc-session.target$' "$labwc_compositor_unit" &&
	   grep -q '^Before=labwc-session.target$' "$labwc_compositor_unit" &&
	   grep -q '^Environment=LIBSEAT_BACKEND=seatd$' "$labwc_compositor_unit" &&
	   grep -q '^UnsetEnvironment=DISPLAY XAUTHORITY WLR_XWAYLAND XWAYLAND XWAYLAND_PATH XWAYLAND_NO_GLAMOR XWAYLAND_FORCE_SCALE XWAYLAND_RESTART_DELAY _XWAYLAND_GLOBAL_OUTPUT_SCALE WINDOWID SESSION_MANAGER DESKTOP_STARTUP_ID$' "$labwc_compositor_unit" &&
	   ! grep -q '^Environment=WLR_XWAYLAND=' "$labwc_compositor_unit" &&
	   grep -q '^ExecStart=/usr/bin/labwc$' "$labwc_compositor_unit" &&
   ! grep -Eq '^(After|BindsTo|Requires|Wants)=.*(greetd|seatd|systemd-user-sessions)[.]service' "$labwc_compositor_unit" &&
   ! grep -Fq '/usr/bin/true' "$session_wrapper" &&
   ! grep -q 'etc/environment.d/90-labwc-session.conf.tmpl' "$desktop_components" &&
   grep -q '"etc/skel/.config/labwc/environment.tmpl"' "$desktop_components" &&
   grep -q '"etc/skel/.config/labwc/environment.d/10-wayland.env.tmpl"' "$desktop_components" &&
   grep -q '"usr/local/bin/labwc-session.tmpl"' "$desktop_components" &&
   grep -q "activation_environment_names=.*QT_OPENGL QSG_RHI_BACKEND" "$autostart_wrapper" &&
   grep -Fq 'session_bus_path="${XDG_RUNTIME_DIR}/bus"' "$session_wrapper" &&
   grep -Fq 'session_bus_address="unix:path=${session_bus_path}"' "$session_wrapper" &&
   grep -Fq '[ ! -S "$session_bus_path" ]' "$session_wrapper" &&
   grep -Fq 'DBUS_SESSION_BUS_ADDRESS=$session_bus_address' "$session_wrapper" &&
   ! grep -Fq 'DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-' "$session_wrapper"; then
  pass "Labwc session assets are rendered from desktop policy placeholders and keep the renderer contract aligned"
else
  fail "Labwc session assets are rendered from desktop policy placeholders and keep the renderer contract aligned"
fi

qt6ct_config_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/qt6ct/qt6ct.conf.tmpl"
crystal_dock_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/crystal-dock.service"
if grep -q '^color_scheme_path=/usr/share/qt6ct/colors/darker.conf$' "$qt6ct_config_template" &&
   grep -q '^custom_palette=true$' "$qt6ct_config_template" &&
   grep -q '^icon_theme=__INSTALLER_LABWC_ICON_THEME__$' "$qt6ct_config_template" &&
   grep -q '^fixed="Noto Sans Mono,__INSTALLER_LABWC_QT_FIXED_FONT_SIZE__,-1,5,50,0,0,0,0,0"$' "$qt6ct_config_template" &&
   grep -q '^general="Noto Sans,__INSTALLER_LABWC_QT_FONT_SIZE__,-1,5,50,0,0,0,0,0"$' "$qt6ct_config_template" &&
   grep -q '^style=Adwaita-Dark$' "$qt6ct_config_template" &&
   grep -q '^standard_dialogs=default$' "$qt6ct_config_template" &&
   grep -q '^desktop_render_qt6ct_config() {$' "$desktop_components" &&
   grep -q '/etc/skel/.config/qt6ct/qt6ct.conf' "$desktop_components" &&
   grep -q '/etc/xdg/qt6ct/qt6ct.conf' "$desktop_components" &&
   grep -Fq 'LABWC_ICON_THEME "${LABWC_ICON_THEME:-Papirus-Dark}"' "$desktop_components" &&
   grep -Fq 'LABWC_QT_FONT_SIZE "${LABWC_QT_FONT_SIZE:-11}"' "$desktop_components" &&
   grep -Fq 'LABWC_QT_FIXED_FONT_SIZE "${LABWC_QT_FIXED_FONT_SIZE:-12}"' "$desktop_components" &&
   grep -q '^    \.config/foot \\$' "$desktop_components" &&
   grep -q '^    \.config/qt6ct \\$' "$desktop_components" &&
   grep -q '^ExecStartPre=/usr/local/bin/labwc-sync-application-launchers %u %h$' "$crystal_dock_service" &&
   grep -q '^ExecStart=/usr/bin/crystal-dock$' "$crystal_dock_service" &&
   grep -q '^Environment=QT_QPA_PLATFORM=wayland$' "$crystal_dock_service" &&
   grep -q '^Environment=GDK_DISABLE=vulkan$' "$crystal_dock_service" &&
   grep -q '^StandardOutput=null$' "$crystal_dock_service" &&
   grep -q '^StandardError=null$' "$crystal_dock_service" &&
   ! grep -Eq 'XDG_(CONFIG|CACHE|DATA|STATE)_HOME=' "$crystal_dock_service"; then
  pass "Crystal Dock runs directly in the user manager without rewriting user XDG or Qt configuration"
else
  fail "Crystal Dock runs directly in the user manager without rewriting user XDG or Qt configuration"
fi

role_desktop_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target"
system_desktop_dir="$role_desktop_root/usr/share/applications"
local_desktop_dir="$role_desktop_root/usr/local/share/applications"
show_desktop_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-show-desktop"
if [ ! -e "$local_desktop_dir/featherpad.desktop" ] &&
   [ ! -e "$local_desktop_dir/labwc-tweaks.desktop" ] &&
   [ ! -e "$local_desktop_dir/qt6ct.desktop" ] &&
   [ ! -e "$local_desktop_dir/retroarch.desktop" ] &&
   [ ! -e "$local_desktop_dir/com.github.xournalpp.xournalpp.desktop" ] &&
   [ ! -e "$local_desktop_dir/org.gnome.Gnote.desktop" ] &&
   [ ! -e "$local_desktop_dir/show-desktop.desktop" ] &&
   grep -q '^TryExec=/usr/local/bin/labwc-show-desktop$' "$system_desktop_dir/show-desktop.desktop" &&
   grep -q '^Icon=show-desktop$' "$system_desktop_dir/show-desktop.desktop" &&
   grep -q '^Exec=/usr/local/bin/labwc-show-desktop$' "$system_desktop_dir/show-desktop.desktop" &&
   grep -q '^wlrctl toplevel minimize state:inactive >/dev/null 2>&1 || true$' "$show_desktop_wrapper" &&
   grep -q '^wlrctl toplevel minimize state:active >/dev/null 2>&1 || true$' "$show_desktop_wrapper"; then
  pass "desktop role relies on package launchers and installs show-desktop in the system applications directory"
else
  fail "desktop role relies on package launchers and installs show-desktop in the system applications directory"
fi

autostart_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
output_watch_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-output-watch.service"
plans_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-plans.service"
if grep -q 'import-environment' "$autostart_wrapper" &&
   grep -q 'dbus-update-activation-environment' "$autostart_wrapper" &&
   grep -q 'activation_environment_names=' "$autostart_wrapper" &&
   grep -q 'LABWC_SESSION_OWNER' "$autostart_wrapper" &&
   grep -q 'LABWC_PID' "$autostart_wrapper" &&
   grep -q 'LABWC_SESSION_UID' "$autostart_wrapper" &&
   grep -Fq 'if [ "${LABWC_SESSION_OWNER:-}" != desktop ]; then' "$autostart_wrapper" &&
   grep -q 'fatal: Labwc did not provide WAYLAND_DISPLAY' "$autostart_wrapper" &&
   grep -Fqx "labwc_x11_environment_names='$labwc_x11_environment_names'" "$autostart_wrapper" &&
   [ "$(grep -Fc 'unset $labwc_x11_environment_names' "$autostart_wrapper")" -eq 1 ] &&
   grep -Fq -- '--user unset-environment $labwc_x11_environment_names' "$autostart_wrapper" &&
   ! grep -Eq '/opt/xwayland|libxcb-cursor|/tmp/.X11-unix' "$autostart_wrapper" &&
   ! grep -q '_JAVA_AWT_WM_NONREPARENTING' "$autostart_wrapper" &&
   grep -q 'fatal: XDG_RUNTIME_DIR is unsafe or does not belong to the active Labwc session user' "$autostart_wrapper" &&
   grep -Fq 'session_bus_path="${XDG_RUNTIME_DIR}/bus"' "$autostart_wrapper" &&
   grep -Fq 'if [ ! -S "$session_bus_path" ]; then' "$autostart_wrapper" &&
   grep -Fqx 'DBUS_SESSION_BUS_ADDRESS="unix:path=${session_bus_path}"' "$autostart_wrapper" &&
   grep -q '^start_session_target() {$' "$autostart_wrapper" &&
   grep -q -- '--user --no-block start labwc-session.target' "$autostart_wrapper" &&
   grep -q '^wait_for_required_session_units() {$' "$autostart_wrapper" &&
   grep -Fq "required_session_units='labwc-kwallet-portal.service hyprpolkitagent.service " "$autostart_wrapper" &&
   grep -q 'required Labwc authentication, secret, or portal services did not become active' "$autostart_wrapper" &&
   grep -q -- '--user --quiet is-active "$session_unit"' "$autostart_wrapper" &&
   grep -q '^start_waybar_if_enabled() {$' "$autostart_wrapper" &&
   grep -q 'labwc-health-notify.path' "$autostart_wrapper" &&
   grep -q '^start_plans_notifier() {$' "$autostart_wrapper" &&
   grep -q -- '--user --no-block start labwc-plans.service' "$autostart_wrapper" &&
   ! grep -Eq '(flock|start_background|--delayed-waybar|LABWC_WAYBAR_START_DELAY_SECONDS|swaybg|kanshi|swayidle)' "$autostart_wrapper" &&
   grep -q '^After=labwc-session.target labwc-output-watch.service$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/waybar.service" &&
   grep -q '^ExecStartPre=/usr/local/libexec/labwc-output-watch --wait-for-output$' "$output_watch_unit" &&
   [ "$(grep -c '^ExecStartPre=' "$output_watch_unit")" -eq 1 ] &&
   grep -q '^Restart=always$' "$output_watch_unit"; then
  pass "Labwc autostart imports the session environment and delegates persistent components to systemd"
else
  fail "Labwc autostart imports the session environment and delegates persistent components to systemd"
fi

session_units='labwc-output-watch.service swaybg.service kanshi.service swayidle.service crystal-dock.service'
all_session_units_bound=true
for session_unit in $session_units; do
  unit_path="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/$session_unit"
  global_unit_path="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/$session_unit"
  if ! grep -qx 'Requisite=labwc-session.target' "$unit_path" ||
     ! grep -qx 'PartOf=labwc-session.target' "$unit_path" ||
     ! grep -qx 'WantedBy=labwc-session.target' "$unit_path" ||
     ! grep -Fqx "    $session_unit \\" "$desktop_components" ||
     [ -e "$global_unit_path" ] ||
     [ -L "$global_unit_path" ]; then
    all_session_units_bound=false
    break
  fi
done
if [ "$all_session_units_bound" = true ] &&
   [ -d "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user" ] &&
   [ -r "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/mako.service.d/10-labwc-session.conf" ] &&
   grep -q '^ExecStart=/usr/local/libexec/labwc-swaybg$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/swaybg.service" &&
   grep -q '^ExecStart=/usr/local/libexec/labwc-kanshi$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/kanshi.service" &&
   grep -q '^ExecStart=/usr/local/libexec/labwc-swayidle$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/swayidle.service" &&
   grep -q '^ExecStart=/usr/bin/crystal-dock$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/crystal-dock.service" &&
   grep -qx 'Requisite=labwc-session.target' "$plans_unit" &&
   grep -qx 'PartOf=labwc-session.target' "$plans_unit" &&
   grep -qx 'WantedBy=labwc-session.target' "$plans_unit" &&
   grep -qx 'ExecStart=/usr/local/libexec/labwc-plans.pl' "$plans_unit" &&
   grep -Fq 'etc/skel/.config/systemd/user/labwc-plans.service \' "$desktop_components" &&
   grep -Fq 'usr/local/libexec/labwc-plans.pl /usr/local/libexec/labwc-plans.pl 0755' "$desktop_components" &&
   grep -Eq '(^|[[:space:]])libhttp-tiny-perl([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libio-socket-ssl-perl([[:space:]]|$)' "$desktop_packages_file"; then
  pass "Labwc component user services are target-bound and staged by the installer"
else
  fail "Labwc component user services are target-bound and staged by the installer"
fi

desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
if grep -q 'refresh_output_chrome_after_dpms();' "$output_refresh_wrapper" &&
   grep -q '^sub refresh_output_chrome {$' "$output_refresh_wrapper" &&
   grep -q '^sub refresh_output_chrome_after_dpms {$' "$output_refresh_wrapper" &&
   grep -q '^sub refresh_waybar {$' "$output_refresh_wrapper" &&
   grep -q '^sub refresh_dock {$' "$output_refresh_wrapper" &&
   grep -q '^sub session_is_active {$' "$output_refresh_wrapper" &&
   grep -Fq "'--user', '--quiet', 'is-active', 'labwc-session.target'," "$output_refresh_wrapper" &&
   ! grep -Eq '(^|[^[:alnum:]_])(stop_fuzzel|fuzzel|kill|pgrep|pkill|pidof|loginctl|reboot|shutdown|poweroff|halt)([^[:alnum:]_]|$)' "$output_refresh_wrapper" &&
   ! grep -Fq "'stop', 'labwc-session.target'" "$output_refresh_wrapper" &&
   ! grep -Fq "'restart', 'labwc-session.target'" "$output_refresh_wrapper"; then
  pass "Labwc output refresh uses the session target only as a lifecycle gate and never terminates sessions or user applications"
else
  fail "Labwc output refresh uses the session target only as a lifecycle gate and never terminates sessions or user applications"
fi

if python3 - "$desktop_verify" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
metadata_body = text[text.index("desktop_verify_staged_files() {") :]
forbidden = re.compile(
    r"(?m)^[ \t]*(?:![ \t]+)?"
    r"(?:grep|sed|awk|python3|perl|jq|cmp|diff|head|tail|cat|file|ldd|"
    r"luac(?:[0-9.]+)?|desktop-file-validate)(?:[ \t]|$)"
)
assert forbidden.search(metadata_body) is None
assert "json.tool" not in metadata_body
assert "<<'PY'" not in metadata_body
assert 'read_text(' not in metadata_body
PY
then
  pass "desktop target verification is metadata-only and does not inspect file contents"
else
  fail "desktop target verification is metadata-only and does not inspect file contents"
fi

desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
if grep -q 'requested_groups="seat render video"' "$desktop_components" &&
   grep -q 'missing_groups=' "$desktop_components" &&
   grep -q 'usermod -a -G "\$missing_groups" "\$greeter_user"' "$desktop_components"; then
  pass "desktop role grants the greeter seat and DRM access groups without repeating usermod when already aligned"
else
  fail "desktop role grants the greeter seat and DRM access groups without repeating usermod when already aligned"
fi

slice_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/user-1000.slice.d/50-resource-accounting.conf"
user_manager_dropin="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/system/user@.service.d/50-oom-score.conf"
user_manager_config="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/user.conf.d/50-resource-defaults.conf"
if grep -q '^CPUAccounting=yes$' "$slice_template" &&
   grep -q '^MemoryAccounting=yes$' "$slice_template" &&
   grep -q '^TasksAccounting=yes$' "$slice_template" &&
   grep -q '^IOAccounting=yes$' "$slice_template" &&
   ! grep -Eq '^(CPUQuota|MemoryHigh|MemoryMax|TasksMax|IOWeight)=' "$slice_template" &&
   grep -q '^OOMScoreAdjust=0$' "$user_manager_dropin" &&
   grep -q '^UMask=0077$' "$user_manager_dropin" &&
   grep -q '^DefaultOOMScoreAdjust=0$' "$user_manager_config" &&
   grep -q '^DefaultTasksMax=infinity$' "$user_manager_config"; then
  pass "desktop user policy keeps accounting, removes caps and OOM bias, and inherits a private umask"
else
  fail "desktop user policy keeps accounting, removes caps and OOM bias, and inherits a private umask"
fi

waybar_generator="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
waybar_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
labwc_rc_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
calendar_vdir_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/vdirsyncer/config.tmpl"
calendar_khal_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/khal/config"
calendar_todoman_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/todoman/config.py"
calendar_personal_displayname="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/calendars/personal/displayname"
calendar_tasks_displayname="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/calendars/tasks/displayname"
calendar_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-calendar"
calendar_sync_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-calendar-sync.service"
ocr_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-ocr"
ocr_defaults="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/tesseract/ocr-defaults.conf"
if grep -Fq '<command>labwc-capture screenshot-full</command>' "$labwc_rc_template" &&
   grep -Fq '<command>labwc-capture screenshot-box</command>' "$labwc_rc_template" &&
   ! grep -q 'allWorkspaces' "$labwc_rc_template" &&
   grep -q '<windowSwitcher preview="yes" outlines="yes" order="focus">' "$labwc_rc_template" &&
   grep -q '<osd show="yes" style="classic" output="all" />' "$labwc_rc_template" &&
   grep -q '<action name="NextWindow" workspace="all" />' "$labwc_rc_template" &&
   grep -q '<action name="PreviousWindow" workspace="all" />' "$labwc_rc_template" &&
   grep -q '^username = "__INSTALLER_FRUUX_USERNAME__"$' "$calendar_vdir_template" &&
   grep -q '^password = "__INSTALLER_FRUUX_PASSWORD__"$' "$calendar_vdir_template" &&
   grep -q '^collections = \[\["personal", "personal", "__INSTALLER_FRUUX_CALENDAR_COLLECTION__"\]\]$' "$calendar_vdir_template" &&
   grep -q '^collections = \[\["tasks", "tasks", "__INSTALLER_FRUUX_TASKS_COLLECTION__"\]\]$' "$calendar_vdir_template" &&
   grep -q '^metadata = \["displayname", "color"\]$' "$calendar_vdir_template" &&
   grep -q '^path = "~/.local/share/calendars"$' "$calendar_vdir_template" &&
   grep -q '^url = "__INSTALLER_FRUUX_ROOT_URL__"$' "$calendar_vdir_template" &&
   grep -q '^default_calendar = personal$' "$calendar_khal_config" &&
   grep -q '^longdateformat = "%A, %Y-%m-%d"$' "$calendar_khal_config" &&
   grep -q '^longdatetimeformat = "%A, %Y-%m-%d %H:%M"$' "$calendar_khal_config" &&
   grep -q '^show_all_days = True$' "$calendar_khal_config" &&
   grep -q '^highlight_event_days = True$' "$calendar_khal_config" &&
   grep -q '^default_list = "Tasks"$' "$calendar_todoman_config" &&
   grep -q '^ConditionPathExists=%h/.config/vdirsyncer/config$' "$calendar_sync_service" &&
   grep -q '^ConditionPathExists=%h/.config/khal/config$' "$calendar_sync_service" &&
   grep -q '^ConditionPathExists=%h/.config/todoman/config.py$' "$calendar_sync_service" &&
   grep -q '^Environment=HOME=%h$' "$calendar_sync_service" &&
   grep -q '^Environment=XDG_CONFIG_HOME=%h/.config$' "$calendar_sync_service" &&
   grep -q '^Environment=XDG_DATA_HOME=%h/.local/share$' "$calendar_sync_service" &&
   grep -q '^Environment=XDG_STATE_HOME=%h/.local/state$' "$calendar_sync_service" &&
   grep -q '^Environment=XDG_RUNTIME_DIR=%t$' "$calendar_sync_service" &&
   grep -q '^Calendar$' "$calendar_personal_displayname" &&
   grep -q '^Tasks$' "$calendar_tasks_displayname" &&
   grep -q 'fruux_root_url=' "$desktop_components" &&
   grep -q 'fruux_calendar_collection=' "$desktop_components" &&
   grep -q 'fruux_tasks_collection=' "$desktop_components" &&
   grep -q 'vdirsyncer_state_root="${state_root}/vdirsyncer"' "$desktop_components" &&
   grep -q '"/target${vdirsyncer_state_root}"' "$desktop_components" &&
   ! grep -Fq 'cat >"$vdirsyncer_config"' "$desktop_components" &&
   ! grep -Fq 'cat >"$khal_config"' "$desktop_components" &&
   ! grep -Fq 'cat >"$todoman_config"' "$desktop_components"; then
  pass "Desktop target config bodies live in staged templates and files rather than inline calendar heredocs"
else
  fail "Desktop target config bodies live in staged templates and files rather than inline calendar heredocs"
fi

if grep -q '^OCR_LANGUAGES=eng+swe$' "$ocr_defaults" &&
   grep -q '^OCR_ENGINE_MODE=1$' "$ocr_defaults" &&
   grep -q '^OCR_PAGE_SEGMENTATION_MODE=3$' "$ocr_defaults" &&
   grep -q '^OCR_OUTPUT_FORMAT=txt$' "$ocr_defaults" &&
   grep -q '^OCR_OUTPUT_DIRECTORY=~/Documents/OCR$' "$ocr_defaults" &&
   grep -q 'require_command tesseract' "$ocr_wrapper" &&
   grep -q 'resolve_optional_lang_file' "$ocr_wrapper" &&
   grep -q -- '--user-words' "$ocr_wrapper" &&
   grep -q -- '--user-patterns' "$ocr_wrapper" &&
   grep -q 'tesseract "\$@"' "$ocr_wrapper" &&
   grep -q '^notify_ocr() {$' "$ocr_wrapper" &&
   grep -q -- '-a OCR' "$ocr_wrapper" &&
   grep -q -- '-c x-labwc.maintenance' "$ocr_wrapper" &&
   grep -q '"OCR completed"' "$ocr_wrapper" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-ocr /usr/local/bin/labwc-ocr 0755' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset etc/skel/.config/tesseract/ocr-defaults.conf /etc/skel/.config/tesseract/ocr-defaults.conf 0644' "$desktop_components" &&
   grep -q '\.config/tesseract \\' "$desktop_components"; then
  pass "desktop OCR defaults stage a managed bilingual helper with Mako completion and failure results"
else
  fail "desktop OCR defaults stage a managed bilingual helper with Mako completion and failure results"
fi

if grep -q '<keybind key="XF86MonBrightnessUp">' "$labwc_rc_template" &&
   grep -q '<keybind key="XF86MonBrightnessDown">' "$labwc_rc_template" &&
   grep -q '<keybind key="XF86MonBrightnessCycle">' "$labwc_rc_template" &&
   grep -q '<keybind key="W-F6">' "$labwc_rc_template" &&
   grep -q '<keybind key="W-F5">' "$labwc_rc_template" &&
   grep -q '<action name="Execute" command="labwc-brightness-control up" />' "$labwc_rc_template" &&
   grep -q '<action name="Execute" command="labwc-brightness-control down" />' "$labwc_rc_template" &&
   grep -q '<action name="Execute" command="labwc-brightness-control menu" />' "$labwc_rc_template"; then
  pass "Labwc brightness keys route through the managed helper for XF86 and Super-F5/F6 bindings"
else
  fail "Labwc brightness keys route through the managed helper for XF86 and Super-F5/F6 bindings"
fi

if ! grep -q 'allWorkspaces' "$labwc_rc_template" &&
   ! grep -q '<windowSwitcher allWorkspaces' "$labwc_rc_template" &&
   grep -q '<windowSwitcher preview="yes" outlines="yes" order="focus">' "$labwc_rc_template" &&
   grep -q '<osd show="yes" style="classic" output="all" />' "$labwc_rc_template" &&
   grep -q '<field content="trimmed_identifier" width="32%" />' "$labwc_rc_template" &&
   grep -q '<field content="title" width="58%" />' "$labwc_rc_template" &&
   grep -q '<action name="NextWindow" workspace="all" />' "$labwc_rc_template" &&
   grep -q '<action name="PreviousWindow" workspace="all" />' "$labwc_rc_template"; then
  pass "Labwc Alt-Tab uses focus history for tap-back and key-repeat window selection"
else
  fail "Labwc Alt-Tab uses focus history for tap-back and key-repeat window selection"
fi

greeter_css="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/greetd/gtkgreet.css"
greeter_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
labwc_defaults_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/labwc-desktop.tmpl"
if grep -Fq '  greeter_font_size=${LABWC_GREETER_FONT_SIZE:-17}' "$desktop_components" &&
   grep -Fq '  greeter_clock_font_size=${LABWC_GREETER_CLOCK_FONT_SIZE:-104}' "$desktop_components" &&
   grep -Fq 'desktop_validate_decimal_range LABWC_GREETER_EXTERNAL_SCALE "${LABWC_GREETER_EXTERNAL_SCALE:-1}" 0.5 3' "$greeter_detect" &&
   grep -Fq 'desktop_validate_uint_range LABWC_GREETER_CLOCK_FONT_SIZE "${LABWC_GREETER_CLOCK_FONT_SIZE:-104}" 24 128' "$greeter_detect" &&
   grep -Fqx 'LABWC_GREETER_EXTERNAL_SCALE=__INSTALLER_LABWC_GREETER_EXTERNAL_SCALE__' "$labwc_defaults_template" &&
   grep -Fqx 'LABWC_GREETER_CLOCK_FONT_SIZE=__INSTALLER_LABWC_GREETER_CLOCK_FONT_SIZE__' "$labwc_defaults_template" &&
   grep -Fq '  greeter_panel_min_width=${LABWC_GREETER_PANEL_MIN_WIDTH:-$((greeter_font_size * 44))}' "$desktop_components" &&
   grep -Fq '  greeter_entry_min_width=${LABWC_GREETER_ENTRY_MIN_WIDTH:-$((greeter_font_size * 34))}' "$desktop_components" &&
   grep -Fq '  greeter_shell_min_width=${LABWC_GREETER_SHELL_MIN_WIDTH:-$greeter_entry_min_width}' "$desktop_components" &&
   grep -Fq '  greeter_button_min_width=${LABWC_GREETER_BUTTON_MIN_WIDTH:-$((greeter_font_size * 13))}' "$desktop_components" &&
   grep -Fq 'LABWC_GREETER_CLOCK_FONT_SIZE "$greeter_clock_font_size"' "$desktop_components" &&
   grep -Fq 'LABWC_GREETER_SHELL_MIN_WIDTH "$greeter_shell_min_width"' "$desktop_components" &&
   grep -q 'font-size: __INSTALLER_LABWC_GREETER_CLOCK_FONT_SIZE__px;' "$greeter_css" &&
   grep -q '^box#body entry#input-field {$' "$greeter_css" &&
   grep -q 'min-width: __INSTALLER_LABWC_GREETER_ENTRY_MIN_WIDTH__px;' "$greeter_css" &&
   grep -q '^box#body combobox#command-selector {$' "$greeter_css" &&
   grep -q 'min-width: __INSTALLER_LABWC_GREETER_SHELL_MIN_WIDTH__px;' "$greeter_css" &&
   grep -q '^box#body button {$' "$greeter_css" &&
   grep -q '^  background-color: #374151;$' "$greeter_css" &&
   grep -q '^box#body button.suggested-action {$' "$greeter_css" &&
   grep -q '^  background-color: #1d4ed8;$' "$greeter_css" &&
   grep -q 'label#clock' "$greeter_css" &&
   grep -q 'background-color: rgba(15, 23, 42, 0.96);' "$greeter_css" &&
   grep -q 'border: 1px solid rgba(148, 163, 184, 0.34);' "$greeter_css"; then
  pass "gtkgreet uses independent larger typography with graphite cancel and dark-blue login actions"
else
  fail "gtkgreet uses independent larger typography with graphite cancel and dark-blue login actions"
fi

if grep -q 'require_command todoman' "$calendar_wrapper" &&
   grep -q 'for pair in fruux_calendar fruux_tasks; do' "$calendar_wrapper" &&
   grep -q 'vdirsyncer discover "\$pair"' "$calendar_wrapper" &&
   grep -q 'vdirsyncer sync fruux_calendar fruux_tasks' "$calendar_wrapper" &&
   grep -q '^notify_calendar() {$' "$calendar_wrapper" &&
   grep -q -- '-a Calendar' "$calendar_wrapper" &&
   grep -q -- '-c x-labwc.calendar' "$calendar_wrapper" &&
   grep -q '"Calendar synchronization completed"' "$calendar_wrapper" &&
   grep -q '"Calendar synchronization failed"' "$calendar_wrapper" &&
   grep -q 'Fruux calendar and task .ics files are synchronized below' "$calendar_wrapper" &&
   grep -q 'todoman list' "$calendar_wrapper" &&
   grep -q 'exec labwc-terminal -e todoman new -i' "$calendar_wrapper" &&
   grep -q 'exec todoman edit -i "\$task_id"' "$calendar_wrapper" &&
   ! grep -q 'calendar_discovery_stamp' "$calendar_wrapper" &&
   ! grep -q '/bin/sh -lc' "$calendar_wrapper"; then
  pass "calendar wrapper discovers and syncs the exact Fruux collections into local ICS storage"
else
  fail "calendar wrapper discovers and syncs the exact Fruux collections into local ICS storage"
fi

calendar_wrapper_log="$TMP_DIR/calendar-wrapper.log"
calendar_wrapper_home="$TMP_DIR/calendar-wrapper-home"
calendar_wrapper_runtime="$TMP_DIR/calendar-wrapper-runtime"
if run_calendar_sync_wrapper "$calendar_wrapper" "$calendar_wrapper_log" "$calendar_wrapper_home" "$calendar_wrapper_runtime" &&
   [ "$(wc -l < "$calendar_wrapper_log")" -eq 3 ] &&
   [ "$(sed -n '1p' "$calendar_wrapper_log")" = 'discover fruux_calendar' ] &&
   [ "$(sed -n '2p' "$calendar_wrapper_log")" = 'discover fruux_tasks' ] &&
   [ "$(sed -n '3p' "$calendar_wrapper_log")" = 'sync fruux_calendar fruux_tasks' ]; then
  pass "calendar wrapper quiet sync discovers both Fruux collections before synchronization"
else
  fail "calendar wrapper quiet sync discovers both Fruux collections before synchronization"
fi

calendar_menu_log="$TMP_DIR/calendar-menu.log"
calendar_menu_home="$TMP_DIR/calendar-menu-home"
calendar_menu_runtime="$TMP_DIR/calendar-menu-runtime"
if run_calendar_menu_wrapper "$calendar_wrapper" "$calendar_menu_log" "$calendar_menu_home" "$calendar_menu_runtime" &&
   [ "$(wc -l < "$calendar_menu_log")" -eq 8 ] &&
   grep -qx 'Open Calendar' "$calendar_menu_log" &&
   grep -qx 'Upcoming Agenda' "$calendar_menu_log" &&
   grep -qx 'Open Tasks' "$calendar_menu_log" &&
   grep -qx 'Create new Event' "$calendar_menu_log" &&
   grep -qx 'Edit Event' "$calendar_menu_log" &&
   grep -qx 'Create new Task' "$calendar_menu_log" &&
   grep -qx 'Edit Task' "$calendar_menu_log" &&
   grep -qx 'Sync Calendar' "$calendar_menu_log"; then
  pass "calendar wrapper menu exposes all 8 right-click Waybar entries to Fuzzel"
else
  fail "calendar wrapper menu exposes all 8 right-click Waybar entries to Fuzzel"
fi

wsdd_schema_override="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/glib-2.0/schemas/90-desktop-wsdd.gschema.override"
legacy_wsdd_function='desktop_wsdd_''params'
legacy_wsdd_defaults='/etc/wsdd-server/''defaults'
legacy_wsdd_placeholder='WSDD_''PARAMS'
if grep -q '^\[org.gnome.system.wsdd\]$' "$wsdd_schema_override" &&
   grep -q "^display-mode='disabled'$" "$wsdd_schema_override" &&
   grep -q 'usr/share/glib-2.0/schemas/90-desktop-wsdd.gschema.override' "$desktop_components" &&
   grep -q '/usr/share/glib-2.0/schemas/90-desktop-wsdd.gschema.override' "$desktop_verify" &&
   ! grep -q "$legacy_wsdd_function" "$desktop_components" &&
   ! grep -q "$legacy_wsdd_defaults" "$desktop_components" &&
   ! grep -q "$legacy_wsdd_placeholder" "$desktop_components"; then
  pass "desktop role disables unsolicited GVFS WSDD discovery through the packaged GLib schema"
else
  fail "desktop role disables unsolicited GVFS WSDD discovery through the packaged GLib schema"
fi

keyboard_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-keyboard-layout"
bluetooth_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-bluetooth"
network_control_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-menu"
network_control_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-action"
network_control_root_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-control-action-root"
network_control_root_module="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-network-control-action/LabwcNetworkControlAction/Root.pm"
bluetooth_init="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/bluetooth-controller-init"
bluetooth_init_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/bluetooth-controller-init.service"
bluetooth_main="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/bluetooth/main.conf"
waybar_style_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/waybar/style.css.tmpl"
if grep -q '^\[$' "$waybar_template" &&
   grep -q '"name": "internal"' "$waybar_template" &&
   grep -q '"name": "external"' "$waybar_template" &&
   grep -q '"output": \[__INSTALLER_LABWC_WAYBAR_INTERNAL_OUTPUTS__\]' "$waybar_template" &&
   grep -q '"output": \[__INSTALLER_LABWC_WAYBAR_EXTERNAL_OUTPUTS__\]' "$waybar_template" &&
   grep -q '"modules-center": \["clock"\]' "$waybar_template" &&
   grep -q '"modules-left": \[__INSTALLER_LABWC_WAYBAR_MODULES_LEFT__\]' "$waybar_template" &&
   grep -q '"modules-right": \[__INSTALLER_LABWC_WAYBAR_MODULES_RIGHT_INTERNAL__\]' "$waybar_template" &&
   grep -q '"modules-right": \[__INSTALLER_LABWC_WAYBAR_MODULES_RIGHT_EXTERNAL__\]' "$waybar_template" &&
   ! grep -q '"format-alt":' "$waybar_template" &&
   ! grep -q 'SANDBOX' "$waybar_template" &&
   grep -q '^desktop_waybar_modules_left_json() {$' "$desktop_components" &&
   grep -q '^desktop_waybar_modules_right_json() {$' "$desktop_components" &&
   grep -q '^desktop_waybar_modules_right_internal_json() {$' "$desktop_components" &&
   grep -q '^desktop_waybar_output_selectors_json() {$' "$desktop_components" &&
   grep -q '^desktop_waybar_internal_outputs_json() {$' "$desktop_components" &&
   grep -q '^desktop_waybar_external_outputs_json() {$' "$desktop_components" &&
   grep -q '^  selector_prefixes=${LABWC_OUTPUT_INTERNAL_PREFIXES:-eDP LVDS DSI}$' "$desktop_components" &&
   grep -q '^  selector_index_max=32$' "$desktop_components" &&
   ! grep -q 'desktop_waybar_sandbox' "$desktop_components" &&
   grep -q '"exec": "labwc-keyboard-layout status"' "$waybar_template" &&
   [ "$(grep -Fc '"exec-on-event": true' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"on-click": "labwc-keyboard-layout waybar-toggle"' "$waybar_template")" -eq 2 ] &&
   ! grep -q 'labwc-keyboard-layout toggle && pkill' "$waybar_template" &&
   grep -q '^waybar_toggle() {$' "$keyboard_helper" &&
   grep -q '^  if ! flock -n 9; then$' "$keyboard_helper" &&
   grep -q '^  sleep 0.15 9>&-$' "$keyboard_helper" &&
   grep -q '^  labwc --reconfigure 9>&- >/dev/null 2>&1 || true$' "$keyboard_helper" &&
   grep -q '"exec": "__INSTALLER_LABWC_CAPTURE_COMMAND__ status"' "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_CAPTURE_COMMAND__ primary"' "$waybar_template" &&
   grep -q '"on-click-right": "__INSTALLER_LABWC_CAPTURE_COMMAND__ menu"' "$waybar_template" &&
   grep -q '"sort-by-app-id": true' "$waybar_template" &&
   grep -q '"group/apps": {' "$waybar_template" &&
   grep -q '"click-to-reveal": true' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"custom/app-terminal"' "$waybar_template" &&
   grep -q '"custom/app-files"' "$waybar_template" &&
   grep -q '"custom/app-tuta"' "$waybar_template" &&
   grep -q '"custom/app-notes"' "$waybar_template" &&
   grep -q '"custom/app-sleek"' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   ! grep -q '"image#app-' "$waybar_template" &&
   grep -q '"on-click": "featherpad"' "$waybar_template" &&
   [ "$(grep -Fc '"on-click": "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ tutanota"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"on-click": "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ sleek"' "$waybar_template")" -eq 2 ] &&
   ! grep -q '"custom/tasks"' "$waybar_template" &&
   grep -Fq '"custom/launcher", "ext/workspaces", "custom/wayscriber", "group/apps", "wlr/taskbar"' "$desktop_components" &&
   ! grep -q 'labwc-waybar-app-icon' "$desktop_components" &&
   ! grep -q 'labwc-waybar-app-icon' "$desktop_verify" &&
   ! grep -q '"custom/files"' "$waybar_template" &&
   ! grep -q '"custom/terminal"' "$waybar_template" &&
   grep -q '"group/quick-controls": {' "$waybar_template" &&
   grep -q '"group/quick-controls-internal": {' "$waybar_template" &&
   grep -q '"orientation": "inherit"' "$waybar_template" &&
   grep -q '"transition-duration": 300' "$waybar_template" &&
   grep -q '"transition-left-to-right": false' "$waybar_template" &&
   grep -q '"custom/system"' "$waybar_template" &&
   grep -q '"format": ""' "$waybar_template" &&
   [ "$(grep -Fc '"group/quick-controls-internal": {' "$waybar_template")" -eq 1 ] &&
   [ "$(grep -Fc '"custom/system": {' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"format": ""' "$waybar_template")" -eq 2 ] &&
   grep -Fq '"group/quick-controls", "custom/lock", "custom/power"' "$desktop_components" &&
   grep -Fq '"group/quick-controls-internal", "custom/lock", "custom/power"' "$desktop_components" &&
   ! grep -q 'custom/dnd' "$waybar_template" &&
   ! grep -q 'custom/dnd' "$waybar_style_template" &&
   ! grep -q 'custom/dnd' "$desktop_components" &&
   grep -q 'XKB_DEFAULT_LAYOUT=%s' "$keyboard_helper" &&
   grep -q '🇸🇪' "$keyboard_helper" &&
   grep -q '🇺🇸' "$keyboard_helper" &&
   grep -q '"sort-by-name": true' "$waybar_template" &&
   [ "$(grep -Fc '"on-click": "activate"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"on-click": "minimize-raise"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"on-click-right": "minimize-raise"' "$waybar_template")" -eq 2 ]; then
  pass "Waybar template keeps the clock centered and omits the retired sandbox modules"
else
  fail "Waybar template keeps the clock centered and omits the retired sandbox modules"
fi

keyboard_test_home="$TMP_DIR/keyboard-home"
keyboard_test_state="$keyboard_test_home/.local/state"
keyboard_test_config="$keyboard_test_home/.config"
mkdir -p "$keyboard_test_home"
HOME="$keyboard_test_home" \
XDG_STATE_HOME="$keyboard_test_state" \
XDG_CONFIG_HOME="$keyboard_test_config" \
LABWC_KEYBOARD_LAYOUTS="us se" \
LABWC_KEYBOARD_DEFAULT_LAYOUT=us \
WAYLAND_DISPLAY= \
  /bin/sh "$keyboard_helper" set us >/dev/null
HOME="$keyboard_test_home" \
XDG_STATE_HOME="$keyboard_test_state" \
XDG_CONFIG_HOME="$keyboard_test_config" \
LABWC_KEYBOARD_LAYOUTS="us se" \
LABWC_KEYBOARD_DEFAULT_LAYOUT=us \
WAYLAND_DISPLAY= \
  /bin/sh "$keyboard_helper" waybar-toggle >"$TMP_DIR/keyboard-toggle-1.json" &
keyboard_toggle_pid_1=$!
HOME="$keyboard_test_home" \
XDG_STATE_HOME="$keyboard_test_state" \
XDG_CONFIG_HOME="$keyboard_test_config" \
LABWC_KEYBOARD_LAYOUTS="us se" \
LABWC_KEYBOARD_DEFAULT_LAYOUT=us \
WAYLAND_DISPLAY= \
  /bin/sh "$keyboard_helper" waybar-toggle >"$TMP_DIR/keyboard-toggle-2.json" &
keyboard_toggle_pid_2=$!
if wait "$keyboard_toggle_pid_1" &&
   wait "$keyboard_toggle_pid_2" &&
   [ "$(
     HOME="$keyboard_test_home" \
     XDG_STATE_HOME="$keyboard_test_state" \
     XDG_CONFIG_HOME="$keyboard_test_config" \
     LABWC_KEYBOARD_LAYOUTS="us se" \
     LABWC_KEYBOARD_DEFAULT_LAYOUT=us \
     WAYLAND_DISPLAY= \
       /bin/sh "$keyboard_helper" current
   )" = se ] &&
   [ -f "$keyboard_test_state/labwc/keyboard-layout-waybar.lock" ]; then
  pass "Waybar keyboard clicks are delayed and coalesced into one layout change"
else
  fail "Waybar keyboard click handling can leak or apply repeated layout changes"
fi

if grep -q '"format-wifi": "📶"' "$waybar_template" &&
   grep -q '"format-ethernet": "🖧"' "$waybar_template" &&
   grep -q '"format-linked": "🔌"' "$waybar_template" &&
   grep -q '"format-disconnected": "✖"' "$waybar_template" &&
   grep -q '"format-disabled": "✖"' "$waybar_template" &&
   grep -q '"on-click-right": "labwc-network-control-menu"' "$waybar_template" &&
   grep -q '"exec": "labwc-bluetooth status"' "$waybar_template" &&
   grep -q '"on-click": "labwc-bluetooth open"' "$waybar_template" &&
   grep -q '"on-click-right": "labwc-bluetooth menu"' "$waybar_template" &&
   grep -q '"exec": "__INSTALLER_LABWC_BRIGHTNESS_CONTROL_COMMAND__ status"' "$waybar_template" &&
   grep -q '"on-scroll-up": "__INSTALLER_LABWC_BRIGHTNESS_CONTROL_COMMAND__ up"' "$waybar_template" &&
   grep -q '"on-scroll-down": "__INSTALLER_LABWC_BRIGHTNESS_CONTROL_COMMAND__ down"' "$waybar_template" &&
   [ "$(grep -Fc '"format-not-charging": "🔌 {capacity}%"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"interval": 5' "$waybar_template")" -ge 2 ] &&
   [ "$(grep -Fc '"format-warning": "⚠️ {capacity}%"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"format-critical": "🪫 {capacity}%"' "$waybar_template")" -eq 2 ] &&
   /bin/sh -n "$bluetooth_helper" &&
   /bin/sh -n "$network_control_menu" &&
   head -n 1 "$network_control_action" | grep -q '^#!/usr/bin/perl$' &&
   head -n 1 "$network_control_root_action" | grep -q '^#!/usr/bin/perl$' &&
   /bin/sh -n "$bluetooth_init" &&
   grep -q 'notify-send \\' "$bluetooth_helper" &&
   grep -q -- '-a Bluetooth' "$bluetooth_helper" &&
   grep -q -- '--agent KeyboardDisplay' "$bluetooth_helper" &&
   grep -Fq '{"text":"",' "$bluetooth_helper" &&
   ! grep -Fq '"text":" BLE"' "$bluetooth_helper" &&
   grep -Fq "'Scan for Devices'" "$bluetooth_helper" &&
   grep -Fq "'Pair Device'" "$bluetooth_helper" &&
   grep -Fq "'Unpair Device'" "$bluetooth_helper" &&
   grep -q '^validate_device_address() {$' "$bluetooth_helper" &&
   grep -Fq "'Enable Bluetooth'" "$bluetooth_helper" &&
   grep -Fq "'Disable Bluetooth'" "$bluetooth_helper" &&
   grep -Fq "'Manage Device'" "$bluetooth_helper" &&
   grep -Fq "'Adapter Settings'" "$bluetooth_helper" &&
   grep -Fq "'Generate Random MAC Addresses'" "$network_control_menu" &&
   grep -q "'802-3-ethernet.cloned-mac-address'" "$network_control_root_module" &&
   grep -q "'802-11-wireless.cloned-mac-address'" "$network_control_root_module" &&
   grep -q '^sub _ifupdown_configured {$' "$network_control_root_module" &&
   grep -q 'btmgmt setting' "$bluetooth_init" &&
   grep -q '^TIMEOUT=/usr/bin/timeout$' "$bluetooth_init" &&
   grep -q '^BTMGMT_TIMEOUT_SECONDS=2$' "$bluetooth_init" &&
   grep -q '^COMMAND_TIMEOUT_SECONDS=5$' "$bluetooth_init" &&
   grep -q '^controller_is_powered() {$' "$bluetooth_init" &&
   grep -q 'BlueZ already enabled the controller' "$bluetooth_init" &&
   grep -q -- '--kill-after="${COMMAND_KILL_GRACE_SECONDS}s"' "$bluetooth_init" &&
   grep -q '"\$@" </dev/null 2>&1' "$bluetooth_init" &&
   grep -q '^Wants=bluetooth.service$' "$bluetooth_init_service" &&
   grep -q '^After=bluetooth.service$' "$bluetooth_init_service" &&
   grep -q '^ConditionFileIsExecutable=/usr/bin/btmgmt$' "$bluetooth_init_service" &&
   grep -q '^ConditionFileIsExecutable=/usr/bin/timeout$' "$bluetooth_init_service" &&
   grep -q '^TimeoutStartSec=35s$' "$bluetooth_init_service" &&
   grep -q '^CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW$' "$bluetooth_init_service" &&
   grep -q '^AutoEnable=true$' "$bluetooth_main" &&
   grep -q '^SecureConnections = on$' "$bluetooth_main" &&
   ! grep -q '^KernelExperimental' "$bluetooth_main" &&
   grep -q 'usr/local/bin/labwc-bluetooth /usr/local/bin/labwc-bluetooth 0755' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-network-control-menu /usr/local/bin/labwc-network-control-menu 0755' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-network-control-action /usr/local/bin/labwc-network-control-action 0755' "$desktop_components" &&
   grep -q 'usr/local/libexec/labwc-network-control-action-root /usr/local/libexec/labwc-network-control-action-root 0755' "$desktop_components" &&
   grep -q 'bluetooth-controller-init.service system' "$desktop_components" &&
   [ "$(grep -Fc '"format": "🔊 {volume}% {format_source}"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"format-muted": "🔇 {volume}% {format_source}"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"format-source": "<span color='\''#6dc4ed'\''></span> {volume}%"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"format-source-muted": "<span color='\''#ffb4a2'\''></span> {volume}%"' "$waybar_template")" -eq 2 ] &&
   [ "$(grep -Fc '"on-scroll-up": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit 1.2"' "$waybar_template")" -eq 2 ] &&
   ! grep -Fq '<span foreground=' "$waybar_template" &&
   ! grep -Fq '⏺' "$waybar_template" &&
   grep -q '"format": "🖴 {percentage_used}%"' "$waybar_template" &&
   grep -q '"height": __INSTALLER_LABWC_WAYBAR_INTERNAL_HEIGHT__' "$waybar_template" &&
   grep -q '"height": __INSTALLER_LABWC_WAYBAR_HEIGHT__' "$waybar_template" &&
   grep -q '"expand-left": true' "$waybar_template" &&
   grep -q '"expand": true' "$waybar_template" &&
   ! grep -q '"homogeneous":' "$waybar_template" &&
   ! grep -q '"truncate":' "$waybar_template" &&
   grep -q '"tooltip-format": "{title}"' "$waybar_template" &&
   grep -q '"icon-size": __INSTALLER_LABWC_WAYBAR_INTERNAL_TASKBAR_ICON_SIZE__' "$waybar_template" &&
   grep -q '"icon-size": __INSTALLER_LABWC_WAYBAR_INTERNAL_TRAY_ICON_SIZE__' "$waybar_template" &&
   grep -q '"icon-size": __INSTALLER_LABWC_WAYBAR_TASKBAR_ICON_SIZE__' "$waybar_template" &&
   grep -q '"icon-size": __INSTALLER_LABWC_WAYBAR_TRAY_ICON_SIZE__' "$waybar_template" &&
   grep -q '"spacing": 4' "$waybar_template" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_HEIGHT "${LABWC_WAYBAR_INTERNAL_HEIGHT:-${LABWC_WAYBAR_HEIGHT:-46}}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_TASKBAR_ICON_SIZE "${LABWC_WAYBAR_INTERNAL_TASKBAR_ICON_SIZE:-${LABWC_WAYBAR_TASKBAR_ICON_SIZE:-18}}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_TRAY_ICON_SIZE "${LABWC_WAYBAR_INTERNAL_TRAY_ICON_SIZE:-${LABWC_WAYBAR_TRAY_ICON_SIZE:-18}}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_HEIGHT "${LABWC_WAYBAR_HEIGHT:-46}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TASKBAR_ICON_SIZE "${LABWC_WAYBAR_TASKBAR_ICON_SIZE:-18}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TRAY_ICON_SIZE "${LABWC_WAYBAR_TRAY_ICON_SIZE:-18}"' "$waybar_generator" &&
   ! grep -q 'labwc-sandbox' "$desktop_components" &&
   grep -q '"on-click": "labwc-terminal -e btop"' "$waybar_template" &&
   grep -q '"on-click": "labwc-terminal -e ncdu /"' "$waybar_template" &&
   grep -q '"on-click": "labwc-terminal -e nmtui"' "$waybar_template" &&
   grep -q '"on-click-right": "labwc-calendar menu"' "$waybar_template" &&
   grep -q "\"tooltip-format\": \"<span size='large'><tt>{calendar}</tt></span>\"" "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_BRIGHTNESS_CONTROL_COMMAND__ menu"' "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_POWER_SETTINGS_COMMAND__"' "$waybar_template" &&
   grep -q 'desktop_validate_command_string LABWC_CAPTURE_COMMAND' "$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh" &&
   grep -q '#custom-launcher {' "$waybar_style_template" &&
   grep -q 'min-width: __INSTALLER_LABWC_WAYBAR_MENU_BUTTON_MIN_WIDTH__px;' "$waybar_style_template" &&
   grep -q 'padding: 0 __INSTALLER_LABWC_WAYBAR_MENU_BUTTON_PADDING_X__px;' "$waybar_style_template" &&
   ! grep -q 'text-align:' "$waybar_style_template"; then
  pass "Waybar template wires the requested desktop actions without Incus app-container controls"
else
  fail "Waybar template wires the requested desktop actions without Incus app-container controls"
fi

if grep -q '#custom-keyboard' "$waybar_style_template" &&
   grep -q '#custom-screenshot' "$waybar_style_template" &&
   grep -q '#custom-bluetooth' "$waybar_style_template" &&
   grep -q '^#quick-controls,$' "$waybar_style_template" &&
   grep -q '^#quick-controls-internal {$' "$waybar_style_template" &&
   grep -A8 '^#quick-controls,$' "$waybar_style_template" | grep -q '^  background: @panel_alt;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style_template" | grep -q '^  border: 1px solid @border;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style_template" | grep -q '^  border-radius: 999px;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style_template" | grep -q '^  margin: 5px 1px;$' &&
   grep -A8 '^#quick-controls,$' "$waybar_style_template" | grep -q '^  padding: 0;$' &&
   ! grep -q '^#quick-controls:hover,$' "$waybar_style_template" &&
   ! grep -q '^#quick-controls-internal:hover {$' "$waybar_style_template" &&
   grep -q '^#quick-controls > \*,$' "$waybar_style_template" &&
   grep -q '^#quick-controls-internal > \* {$' "$waybar_style_template" &&
   grep -A4 '^#quick-controls > \*,$' "$waybar_style_template" | grep -q '^  margin: 0;$' &&
   grep -A4 '^#quick-controls > \*,$' "$waybar_style_template" | grep -q '^  padding: 0;$' &&
   grep -q '^#quick-controls #custom-system,$' "$waybar_style_template" &&
   grep -q '^#quick-controls #network,$' "$waybar_style_template" &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style_template" | grep -q '^  margin: 0;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style_template" | grep -q '^  border: 1px solid transparent;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style_template" | grep -q '^  border-radius: 999px;$' &&
   grep -A19 '^#quick-controls #custom-system,$' "$waybar_style_template" | grep -q '^  background: transparent;$' &&
   grep -q '^#quick-controls #custom-system:hover,$' "$waybar_style_template" &&
   grep -q '^#quick-controls #network:hover,$' "$waybar_style_template" &&
   grep -q '^#quick-controls #custom-bluetooth:hover,$' "$waybar_style_template" &&
   grep -q '^#quick-controls-internal #custom-screenshot:hover {$' "$waybar_style_template" &&
   grep -A13 '^#quick-controls #custom-system:hover,$' "$waybar_style_template" | grep -q '^  background: @panel_hover;$' &&
   grep -A13 '^#quick-controls #custom-system:hover,$' "$waybar_style_template" | grep -q '^  border-color: @border;$' &&
   grep -q '^window#waybar.internal #pulseaudio,$' "$waybar_style_template" &&
   grep -A12 '^window#waybar.internal #pulseaudio,$' "$waybar_style_template" | grep -q '^  padding-left: __INSTALLER_LABWC_WAYBAR_INTERNAL_STATUS_MODULE_PADDING_X__px;$' &&
   grep -A7 '^window#waybar.internal #pulseaudio,$' "$waybar_style_template" | grep -q '^  min-width: __INSTALLER_LABWC_WAYBAR_INTERNAL_STATUS_MODULE_MIN_WIDTH__px;$' &&
   grep -A4 '^window#waybar.internal #quick-controls-internal {$' "$waybar_style_template" | grep -q '^  padding-left: __INSTALLER_LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_GROUP_PADDING_X__px;$' &&
   grep -A4 '^window#waybar.internal #quick-controls-internal {$' "$waybar_style_template" | grep -q '^  padding-right: __INSTALLER_LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_GROUP_PADDING_X__px;$' &&
   grep -A10 '^window#waybar.internal #quick-controls-internal #custom-system,$' "$waybar_style_template" | grep -q '^  min-width: __INSTALLER_LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_BUTTON_MIN_WIDTH__px;$' &&
   grep -A6 '^window#waybar.internal #custom-lock,$' "$waybar_style_template" | grep -q '^  min-width: __INSTALLER_LABWC_WAYBAR_INTERNAL_SESSION_BUTTON_MIN_WIDTH__px;$' &&
   ! grep -q '^window#waybar.internal #custom-lock {$' "$waybar_style_template" &&
   ! grep -q '^window#waybar.internal #quick-controls-internal #custom-system {$' "$waybar_style_template" &&
   grep -q '^window#waybar.internal #custom-launcher {$' "$waybar_style_template" &&
   grep -q '^window#waybar.internal #workspaces button {$' "$waybar_style_template" &&
   grep -q '^window#waybar.internal #taskbar button {$' "$waybar_style_template" &&
   grep -q '^window#waybar.internal #custom-apps,$' "$waybar_style_template" &&
   grep -q '^#custom-system {$' "$waybar_style_template" &&
   grep -A5 '^#custom-system {$' "$waybar_style_template" | grep -q '^  color: @amber;$' &&
   grep -A5 '^#custom-system {$' "$waybar_style_template" | grep -Fq '  font-family: "Font Awesome 6 Free", "Font Awesome 5 Free", "Noto Sans Symbols 2", "Symbola";' &&
   grep -q '#custom-backlight' "$waybar_style_template" &&
   grep -q '^#apps {$' "$waybar_style_template" &&
   grep -q '^#custom-apps {$' "$waybar_style_template" &&
   grep -A5 '^#custom-apps {$' "$waybar_style_template" | grep -q '^  min-width: 28px;$' &&
   grep -A5 '^#custom-apps {$' "$waybar_style_template" | grep -q '^  padding: 0 7px;$' &&
   grep -q '^#custom-app-terminal,$' "$waybar_style_template" &&
   grep -q '^#custom-app-files,$' "$waybar_style_template" &&
   grep -q '^#custom-app-tuta,$' "$waybar_style_template" &&
   grep -q '^#custom-app-notes,$' "$waybar_style_template" &&
   grep -q '^#custom-app-sleek {$' "$waybar_style_template" &&
   ! grep -q '^#custom-tasks' "$waybar_style_template" &&
   ! grep -q '^#image' "$waybar_style_template" &&
   ! grep -q '#custom-sandbox' "$waybar_style_template" &&
   grep -q 'font-size: __INSTALLER_LABWC_WAYBAR_FONT_SIZE__px;' "$waybar_style_template" &&
   grep -q '^tooltip {' "$waybar_style_template" &&
   grep -q 'padding: __INSTALLER_LABWC_WAYBAR_TOOLTIP_PADDING_Y__px __INSTALLER_LABWC_WAYBAR_TOOLTIP_PADDING_X__px;' "$waybar_style_template" &&
   grep -q '^tooltip label {' "$waybar_style_template" &&
   grep -q 'font-size: __INSTALLER_LABWC_WAYBAR_TOOLTIP_FONT_SIZE__px;' "$waybar_style_template" &&
   grep -q '#taskbar button {' "$waybar_style_template" &&
   grep -q '^#taskbar {$' "$waybar_style_template" &&
   grep -q '^  min-width: 0;$' "$waybar_style_template" &&
   grep -q 'min-width: __INSTALLER_LABWC_WAYBAR_TASKBAR_BUTTON_MIN_WIDTH__px;' "$waybar_style_template" &&
   grep -q 'padding: 0 __INSTALLER_LABWC_WAYBAR_TASKBAR_BUTTON_PADDING_X__px;' "$waybar_style_template" &&
   grep -q '#workspaces button {' "$waybar_style_template" &&
   grep -q 'min-width: __INSTALLER_LABWC_WAYBAR_WORKSPACE_BUTTON_MIN_WIDTH__px;' "$waybar_style_template" &&
   grep -q 'padding: 0 __INSTALLER_LABWC_WAYBAR_WORKSPACE_BUTTON_PADDING_X__px;' "$waybar_style_template" &&
   grep -q 'LABWC_WAYBAR_MENU_BUTTON_MIN_WIDTH "${LABWC_WAYBAR_MENU_BUTTON_MIN_WIDTH:-52}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_MENU_BUTTON_PADDING_X "${LABWC_WAYBAR_MENU_BUTTON_PADDING_X:-11}"' "$waybar_generator" &&
   ! grep -q 'LABWC_WAYBAR_SANDBOX' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TOOLTIP_FONT_SIZE "${LABWC_WAYBAR_TOOLTIP_FONT_SIZE:-15}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TOOLTIP_PADDING_Y "${LABWC_WAYBAR_TOOLTIP_PADDING_Y:-7}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TOOLTIP_PADDING_X "${LABWC_WAYBAR_TOOLTIP_PADDING_X:-10}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_WORKSPACE_BUTTON_MIN_WIDTH "${LABWC_WAYBAR_WORKSPACE_BUTTON_MIN_WIDTH:-26}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TASKBAR_BUTTON_MIN_WIDTH "${LABWC_WAYBAR_TASKBAR_BUTTON_MIN_WIDTH:-0}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TASKBAR_BUTTON_PADDING_X "${LABWC_WAYBAR_TASKBAR_BUTTON_PADDING_X:-4}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_FONT_SIZE "${LABWC_WAYBAR_INTERNAL_FONT_SIZE:-${LABWC_WAYBAR_FONT_SIZE:-15}}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_APP_BUTTON_MIN_WIDTH "${LABWC_WAYBAR_INTERNAL_APP_BUTTON_MIN_WIDTH:-28}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_STATUS_MODULE_PADDING_X "${LABWC_WAYBAR_INTERNAL_STATUS_MODULE_PADDING_X:-4}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_BUTTON_PADDING_X "${LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_BUTTON_PADDING_X:-4}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_INTERNAL_SESSION_BUTTON_PADDING_X "${LABWC_WAYBAR_INTERNAL_SESSION_BUTTON_PADDING_X:-6}"' "$waybar_generator" &&
   grep -q 'margin-left: 1px;' "$waybar_style_template" &&
   grep -q '^#quick-controls #custom-bluetooth:hover,$' "$waybar_style_template" &&
   ! grep -q '#custom-backlight:hover' "$waybar_style_template" &&
   ! grep -q '^#custom-lock:hover,$' "$waybar_style_template" &&
   grep -A7 '^#custom-lock {$' "$waybar_style_template" | grep -q '^  background: rgba(203, 213, 225, 0.14);$' &&
   grep -A7 '^#custom-lock {$' "$waybar_style_template" | grep -q '^  border-color: rgba(203, 213, 225, 0.46);$' &&
   grep -A7 '^#custom-lock {$' "$waybar_style_template" | grep -q '^  color: #d8dee9;$' &&
   grep -q '^#custom-lock:hover {$' "$waybar_style_template" &&
   grep -q '#custom-screenshot {' "$waybar_style_template" &&
   grep -q 'color: @text;' "$waybar_style_template" &&
   grep -A2 '^#custom-screenshot.recording {$' "$waybar_style_template" | grep -q '^  color: @red;$' &&
   grep -q '#custom-power:hover' "$waybar_style_template" &&
   grep -q '^LABWC_WAYBAR_FONT_SIZE="15"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q 'waybar/style.css.tmpl' "$waybar_generator" &&
   ! grep -q '^LABWC_WAYBAR_SANDBOX' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_WAYBAR_TOOLTIP_FONT_SIZE="15"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_WAYBAR_TOOLTIP_PADDING_Y="7"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_WAYBAR_TOOLTIP_PADDING_X="10"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_WAYBAR_INTERNAL_HEIGHT="\$LABWC_WAYBAR_HEIGHT"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_WAYBAR_INTERNAL_SESSION_BUTTON_PADDING_X="6"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"; then
  pass "Waybar styling keeps one quick-control pill with per-button hover borders"
else
  fail "Waybar styling keeps one quick-control pill with per-button hover borders"
fi

desktop_profile_sizing_ok=true
desktop_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
labwc_defaults_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/labwc-desktop.tmpl"
for profile_file in \
  "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" \
  "$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env" \
  "$ROOT_DIR/d-i/forky/hosts/profiles/vm/desktop.env" \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/override/*-de*.env
do
  grep -qx 'LABWC_IDLE_LOCK_SECONDS="1800"' "$profile_file" ||
    desktop_profile_sizing_ok=false
  grep -qx 'LABWC_IDLE_DPMS_SECONDS="3600"' "$profile_file" ||
    desktop_profile_sizing_ok=false
  grep -qx 'LABWC_IDLE_SUSPEND_SECONDS="0"' "$profile_file" ||
    desktop_profile_sizing_ok=false
  for setting_name in \
    LABWC_WAYBAR_INTERNAL_HEIGHT \
    LABWC_WAYBAR_INTERNAL_TASKBAR_ICON_SIZE \
    LABWC_WAYBAR_INTERNAL_TRAY_ICON_SIZE \
    LABWC_WAYBAR_INTERNAL_FONT_SIZE \
    LABWC_WAYBAR_INTERNAL_MENU_BUTTON_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_MENU_BUTTON_PADDING_X \
    LABWC_WAYBAR_INTERNAL_WORKSPACE_BUTTON_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_WORKSPACE_BUTTON_PADDING_X \
    LABWC_WAYBAR_INTERNAL_TASKBAR_BUTTON_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_TASKBAR_BUTTON_PADDING_X \
    LABWC_WAYBAR_INTERNAL_APP_BUTTON_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_APP_BUTTON_PADDING_X \
    LABWC_WAYBAR_INTERNAL_STATUS_MODULE_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_STATUS_MODULE_PADDING_X \
    LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_GROUP_PADDING_X \
    LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_BUTTON_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_QUICK_CONTROL_BUTTON_PADDING_X \
    LABWC_WAYBAR_INTERNAL_SESSION_BUTTON_MIN_WIDTH \
    LABWC_WAYBAR_INTERNAL_SESSION_BUTTON_PADDING_X \
    LABWC_FUZZEL_CONTAINER_MANAGEMENT_WIDTH \
    LABWC_FUZZEL_CONTAINER_MANAGEMENT_LINES \
    LABWC_FUZZEL_CONTAINER_MANAGEMENT_FONT_SIZE \
    LABWC_FUZZEL_REMOTE_DESKTOP_WIDTH \
    LABWC_FUZZEL_REMOTE_DESKTOP_LINES \
    LABWC_FUZZEL_REMOTE_DESKTOP_FONT_SIZE \
    LABWC_FUZZEL_ENDPOINT_SECURITY_WIDTH \
    LABWC_FUZZEL_ENDPOINT_SECURITY_LINES \
    LABWC_FUZZEL_ENDPOINT_SECURITY_FONT_SIZE \
    LABWC_FUZZEL_USERS_GROUPS_WIDTH \
    LABWC_FUZZEL_USERS_GROUPS_LINES \
    LABWC_FUZZEL_USERS_GROUPS_FONT_SIZE \
    LABWC_FUZZEL_NETWORK_MANAGEMENT_WIDTH \
    LABWC_FUZZEL_NETWORK_MANAGEMENT_LINES \
    LABWC_FUZZEL_NETWORK_MANAGEMENT_FONT_SIZE \
    LABWC_FUZZEL_FIREWALL_SECURITY_WIDTH \
    LABWC_FUZZEL_FIREWALL_SECURITY_LINES \
    LABWC_FUZZEL_FIREWALL_SECURITY_FONT_SIZE \
    LABWC_FUZZEL_SYSTEM_CONFIGURATION_WIDTH \
    LABWC_FUZZEL_SYSTEM_CONFIGURATION_LINES \
    LABWC_FUZZEL_SYSTEM_CONFIGURATION_FONT_SIZE \
    LABWC_FUZZEL_PHONE_MANAGEMENT_WIDTH \
    LABWC_FUZZEL_PHONE_MANAGEMENT_LINES \
    LABWC_FUZZEL_PHONE_MANAGEMENT_FONT_SIZE \
    LABWC_FUZZEL_BACKUP_RECOVERY_WIDTH \
    LABWC_FUZZEL_BACKUP_RECOVERY_LINES \
    LABWC_FUZZEL_BACKUP_RECOVERY_FONT_SIZE \
    LABWC_FUZZEL_HARDWARE_PERIPHERALS_WIDTH \
    LABWC_FUZZEL_HARDWARE_PERIPHERALS_LINES \
    LABWC_FUZZEL_HARDWARE_PERIPHERALS_FONT_SIZE
  do
    grep -q "^${setting_name}=" "$profile_file" ||
      desktop_profile_sizing_ok=false
    grep -q "desktop_validate_uint_range ${setting_name} " "$desktop_detect" ||
      desktop_profile_sizing_ok=false
    grep -q "^${setting_name}=__INSTALLER_${setting_name}__$" "$labwc_defaults_template" ||
      desktop_profile_sizing_ok=false
  done
done
if [ "$desktop_profile_sizing_ok" = true ]; then
  pass "every desktop profile exposes validated sizing plus 30-minute lock, one-hour DPMS, and disabled idle suspend"
else
  fail "every desktop profile exposes validated sizing plus 30-minute lock, one-hour DPMS, and disabled idle suspend"
fi

kanshi_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kanshi/config"
if grep -q '^profile external-lg-ultragear-1080p120 {$' "$kanshi_config" &&
   grep -q '^  output "LG Electronics LG ULTRAGEAR 310INAR0E000" enable mode __INSTALLER_LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH__x__INSTALLER_LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT__@__INSTALLER_LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ__Hz position 0,0 scale __INSTALLER_LABWC_OUTPUT_EXTERNAL_SCALE__$' "$kanshi_config" &&
   grep -q '^  output eDP-1 enable position 0,0 scale __INSTALLER_LABWC_OUTPUT_INTERNAL_SCALE__$' "$kanshi_config" &&
   grep -q '^profile any-output {$' "$kanshi_config" &&
   grep -q '^  output \* enable position 0,0 scale __INSTALLER_LABWC_OUTPUT_SCALE__$' "$kanshi_config" &&
   ! grep -q '^  exec ' "$kanshi_config" &&
   grep -q '"etc/skel/.config/kanshi/config"' "$desktop_components" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH "${LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH:-1920}"' "$desktop_components" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT "${LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT:-1080}"' "$desktop_components" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ "${LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ:-120}"' "$desktop_components" &&
   grep -q 'LABWC_OUTPUT_EXTERNAL_SCALE "${LABWC_OUTPUT_EXTERNAL_SCALE:-1}"' "$desktop_components" &&
   grep -q 'LABWC_OUTPUT_INTERNAL_SCALE "${LABWC_OUTPUT_INTERNAL_SCALE:-1}"' "$desktop_components" &&
   grep -q 'LABWC_OUTPUT_SCALE "${LABWC_OUTPUT_SCALE:-1}"' "$desktop_components"; then
  pass "Kanshi renders output policy without racing the serialized DRM hotplug refresher"
else
  fail "Kanshi renders output policy without racing the serialized DRM hotplug refresher"
fi

if grep -q 'monitor.bluez-midi = disabled' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf" &&
   ! grep -q 'monitor.libcamera = disabled' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf" &&
   cmp -s \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf" \
     "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf" &&
   grep -q 'desktop_stage_role_asset etc/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf /etc/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf 0644' "$desktop_components" &&
   grep -q '/etc/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"; then
  pass "WirePlumber disables BlueZ MIDI system-wide and for staged user homes without disabling libcamera"
else
  fail "WirePlumber disables BlueZ MIDI system-wide and for staged user homes without disabling libcamera"
fi

desktop_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
terminal_profile_policy_ok=true
terminal_profile_count=0
for terminal_profile in $(grep -l '^LABWC_TERMINAL_PRIMARY=' \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/btrfs/desktop.env \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/f2fs/desktop.env \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/vm/desktop.env \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/override/*.env)
do
  terminal_profile_count=$((terminal_profile_count + 1))
  grep -q '^LABWC_TERMINAL_FONT_FAMILY="Noto Sans Mono"$' "$terminal_profile" ||
    terminal_profile_policy_ok=false
  grep -Eq '^LABWC_TERMINAL_FONT_SIZE="([89]|[12][0-9]|3[0-2])"$' "$terminal_profile" ||
    terminal_profile_policy_ok=false
done

if [ "$terminal_profile_policy_ok" = true ] &&
   [ "$terminal_profile_count" -eq 13 ] &&
   grep -q '^LABWC_TERMINAL_FONT_SIZE="10"$' "$ROOT_DIR/d-i/forky/hosts/profiles/override/f2fs-de-cbook.env" &&
   grep -q '^LABWC_TERMINAL_FONT_SIZE="11"$' "$ROOT_DIR/d-i/forky/hosts/profiles/override/btrfs-de-main.env" &&
   grep -q '^\[colors-dark\]$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini" &&
   grep -q '^pad=4x4 center$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini" &&
   grep -q '^font=__INSTALLER_LABWC_TERMINAL_FONT_FAMILY__:size=__INSTALLER_LABWC_TERMINAL_FONT_SIZE__$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini" &&
   grep -q '^alpha=__INSTALLER_LABWC_TERMINAL_BACKGROUND_OPACITY__$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini" &&
   grep -q '^initial-window-size-chars=__INSTALLER_LABWC_TERMINAL_WINDOW_COLUMNS__x__INSTALLER_LABWC_TERMINAL_WINDOW_ROWS__$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini" &&
   grep -q '^font_family __INSTALLER_LABWC_TERMINAL_FONT_FAMILY__$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kitty/kitty.conf" &&
   grep -q '^font_size __INSTALLER_LABWC_TERMINAL_FONT_SIZE__$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kitty/kitty.conf" &&
   grep -q '^window_padding_width 4$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kitty/kitty.conf" &&
   grep -q '^background_opacity __INSTALLER_LABWC_TERMINAL_BACKGROUND_OPACITY__$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kitty/kitty.conf" &&
   grep -q '^initial_window_width __INSTALLER_LABWC_TERMINAL_WINDOW_COLUMNS__c$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kitty/kitty.conf" &&
   grep -q '^initial_window_height __INSTALLER_LABWC_TERMINAL_WINDOW_ROWS__c$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/kitty/kitty.conf" &&
   grep -q '^desktop_render_terminal_configs() {$' "$desktop_components" &&
   grep -Fq 'LABWC_TERMINAL_FONT_FAMILY "${LABWC_TERMINAL_FONT_FAMILY:-Noto Sans Mono}"' "$desktop_detect" &&
   grep -Fq 'LABWC_TERMINAL_FONT_SIZE "${LABWC_TERMINAL_FONT_SIZE:-12}"' "$desktop_detect" &&
   grep -Fq 'desktop_validate_font_family LABWC_TERMINAL_FONT_FAMILY "${LABWC_TERMINAL_FONT_FAMILY:-Noto Sans Mono}"' "$desktop_detect" &&
   grep -Fq 'desktop_validate_uint_range LABWC_TERMINAL_FONT_SIZE "${LABWC_TERMINAL_FONT_SIZE:-12}" 8 32' "$desktop_detect" &&
   grep -q '^LABWC_TERMINAL_BACKGROUND_OPACITY="0.985"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_TERMINAL_WINDOW_COLUMNS="96"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_TERMINAL_WINDOW_ROWS="26"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   ! grep -q '^\[colors\]$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini"; then
  pass "Foot and Kitty render validated profile-owned fonts, geometry, and opacity"
else
  fail "Foot and Kitty render validated profile-owned fonts, geometry, and opacity"
fi

chromium_flags="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/chromium.d/90-performance-flags.tmpl"
vivaldi_policy_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/vivaldi/policies"
retroarch_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/retroarch/retroarch.cfg"
vivaldi_class="$ROOT_DIR/d-i/forky/classes/class-apps/vivaldi.cfg"
retroarch_class="$ROOT_DIR/d-i/forky/classes/class-apps/retroarch.cfg"
apps_config="$ROOT_DIR/d-i/forky/classes/configs/apps.cfg"
if grep -q '^CHROMIUM_FLAGS=.*--ozone-platform=wayland' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--enable-wayland-ime' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--enable-features=UseOzonePlatform' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*VaapiVideoDecoder' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*--enable-zero-copy' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--use-gl=angle' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*--use-angle=vulkan' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--use-angle=gl' "$chromium_flags" &&
   grep -q '^CHROMIUM_FLAGS=.*--disable-features=WaylandWindowDecorations,WaylandWpColorManagerV1,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*VaapiOnNvidiaGPUs' "$chromium_flags" &&
   grep -q '^d-i apt-setup/local10/repository string https://repo.vivaldi.com/archive/deb stable main$' "$vivaldi_class" &&
   grep -q '^d-i pkgsel/include string vivaldi-stable$' "$vivaldi_class" &&
   grep -q '^d-i pkgsel/include string retroarch retroarch-assets$' "$retroarch_class" &&
   grep -A5 '^Name: vivaldi$' "$apps_config" | grep -q '^RequiresClasses: role/desktop$' &&
   grep -A5 '^Name: vivaldi$' "$apps_config" | grep -q '^RejectedClasses: addon/software$' &&
   grep -A5 '^Name: retroarch$' "$apps_config" | grep -q '^RequiresClasses: role/desktop$' &&
   grep -A5 '^Name: retroarch$' "$apps_config" | grep -q '^RejectedClasses: addon/software$' &&
   grep -q '^video_driver = "gl"$' "$retroarch_config" &&
   ! grep -R -q 'retroarch-vulkan.cfg' "$ROOT_DIR/d-i/forky" &&
   grep -q '^width=__INSTALLER_LABWC_FUZZEL_WIDTH__$' "$fuzzel_launcher_template" &&
   grep -q '^lines=__INSTALLER_LABWC_FUZZEL_LINES__$' "$fuzzel_launcher_template" &&
   grep -q '^width=__INSTALLER_LABWC_FUZZEL_MENU_WIDTH__$' "$fuzzel_menu_template" &&
   grep -q 'etc/skel/.config/fuzzel/base.ini.tmpl' "$desktop_components" &&
   grep -q 'etc/skel/.config/fuzzel/fuzzel.ini.tmpl' "$desktop_components" &&
   grep -q '^LABWC_FUZZEL_WIDTH="36"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_FUZZEL_LINES="15"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_FUZZEL_MENU_WIDTH="22"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   grep -q '^LABWC_FUZZEL_MENU_LINES="8"$' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"; then
  pass "Chromium normal launch stays Wayland-only while RetroArch uses the managed OpenGL driver"
else
  fail "Chromium normal launch stays Wayland-only while RetroArch uses the managed OpenGL driver"
fi

vivaldi_policy_wiring_ok=true
for policy_relpath in \
  managed/telemetry.json \
  managed/extensions.json \
  managed/security.json \
  managed/performance.json \
  recommended/defaults.json
do
  source_relpath="etc/vivaldi/policies/$policy_relpath"
  target_path="/etc/vivaldi/policies/$policy_relpath"
  [ -f "$vivaldi_policy_root/$policy_relpath" ] || vivaldi_policy_wiring_ok=false
  grep -Fq \
    "desktop_stage_role_asset $source_relpath $target_path 0644" \
    "$desktop_components" || vivaldi_policy_wiring_ok=false
  grep -Fq "  $target_path \\" "$desktop_verify" ||
    vivaldi_policy_wiring_ok=false
done
if [ "$vivaldi_policy_wiring_ok" = true ] &&
   python3 - "$vivaldi_policy_root" <<'PY'
import json
import pathlib
import sys

policy_root = pathlib.Path(sys.argv[1])

expected = {
    "managed/telemetry.json": {
        "MetricsReportingEnabled": False,
        "UserFeedbackAllowed": False,
        "CloudReportingEnabled": False,
        "CloudProfileReportingEnabled": False,
        "UserSecuritySignalsReporting": False,
        "UserSecurityAuthenticatedReporting": False,
        "SafeBrowsingProtectionLevel": 1,
        "SafeBrowsingExtendedReportingEnabled": False,
        "SafeBrowsingProxiedRealTimeChecksAllowed": False,
        "SafeBrowsingSurveysEnabled": False,
        "UrlKeyedAnonymizedDataCollectionEnabled": False,
        "SearchSuggestEnabled": False,
        "SpellCheckServiceEnabled": False,
        "AlternateErrorPagesEnabled": False,
        "AutofillAddressEnabled": False,
        "AutofillCreditCardEnabled": False,
        "PasswordManagerEnabled": False,
        "PasswordManagerPasskeysEnabled": False,
        "ShoppingListEnabled": False,
        "SigninInterceptionEnabled": False,
    },
    "managed/extensions.json": {
        "ExtensionDeveloperModeSettings": 1,
        "ExtensionSettings": {
            "jplgfhpmjnbigmhklmmbgecoobifkmpa": {
                "blocked_install_message": (
                    "Proton VPN is disabled by managed browser policy."
                ),
                "installation_mode": "removed",
            },
            "doojmbjmlfjjnbmnoijecmcbfeoakpjm": {
                "blocked_permissions": [
                    "bookmarks",
                    "clipboardRead",
                    "clipboardWrite",
                    "downloads",
                    "history",
                    "management",
                    "nativeMessaging",
                    "proxy",
                ],
                "file_url_navigation_allowed": False,
                "installation_mode": "force_installed",
                "toolbar_pin": "force_pinned",
                "update_url": "https://clients2.google.com/service/update2/crx",
            },
            "ddkjiahejlhfcafbddmgiahcphecmpfh": {
                "blocked_permissions": [
                    "bookmarks",
                    "clipboardRead",
                    "clipboardWrite",
                    "cookies",
                    "debugger",
                    "downloads",
                    "history",
                    "management",
                    "nativeMessaging",
                    "privacy",
                    "proxy",
                    "tabs",
                    "webRequest",
                    "webRequestBlocking",
                ],
                "file_url_navigation_allowed": False,
                "installation_mode": "force_installed",
                "toolbar_pin": "force_pinned",
                "update_url": "https://clients2.google.com/service/update2/crx",
            },
            "pkehgijcmpdhfbdbbnkijodmdjhbjlgp": {
                "blocked_permissions": [
                    "bookmarks",
                    "clipboardRead",
                    "clipboardWrite",
                    "debugger",
                    "downloads",
                    "history",
                    "management",
                    "nativeMessaging",
                    "proxy",
                ],
                "file_url_navigation_allowed": False,
                "installation_mode": "force_installed",
                "toolbar_pin": "force_pinned",
                "update_url": "https://clients2.google.com/service/update2/crx",
            },
        },
        # NoScript does not publish a Chromium managed-storage schema. Its
        # supported managed boundary is therefore ExtensionSettings above.
        "3rdparty": {
            "extensions": {
                "ddkjiahejlhfcafbddmgiahcphecmpfh": {
                    "defaultFiltering": "complete",
                    "disabledFeatures": ["dashboard", "develop"],
                    "disableFirstRunPage": True,
                    "noFiltering": [],
                    "popupBlockMode": True,
                    "rulesets": [
                        "+default",
                        "+adguard-spyware-url",
                        "+block-lan",
                    ],
                    "showBlockedCount": True,
                    "strictBlockMode": True,
                },
                "pkehgijcmpdhfbdbbnkijodmdjhbjlgp": {
                    "checkForDNTPolicy": False,
                    "disabledSites": [],
                    "learnLocally": False,
                    "learnInIncognito": False,
                    "sendDNTSignal": True,
                    "showCounter": True,
                    "showIntroPage": False,
                    "trackingDomains": [],
                },
            },
        },
    },
    "managed/security.json": {
        "DefaultClipboardSetting": 2,
        "DefaultControlledFrameSetting": 2,
        "DefaultDirectSocketsPrivateNetworkAccessSetting": 2,
        "DefaultDirectSocketsSetting": 2,
        "DefaultFileSystemReadGuardSetting": 2,
        "DefaultFileSystemWriteGuardSetting": 2,
        "DefaultGeolocationSetting": 2,
        "DefaultIdleDetectionSetting": 2,
        "DefaultInsecureContentSetting": 2,
        "DefaultLocalFontsSetting": 2,
        "DefaultNotificationsSetting": 2,
        "DefaultPopupsSetting": 2,
        "DefaultSensorsSetting": 2,
        "DefaultSerialGuardSetting": 2,
        "DefaultSubAppsWithoutPromptsSetting": 2,
        "DefaultWebBluetoothGuardSetting": 2,
        "DefaultWebHidGuardSetting": 2,
        "DefaultWebUsbGuardSetting": 2,
        "DefaultWindowManagementSetting": 2,
        "WebRtcIPHandling": "default_public_interface_only",
        "HttpsOnlyMode": "force_enabled",
        "HttpsUpgradesEnabled": True,
        "DisableSafeBrowsingProceedAnyway": True,
        "SSLErrorOverrideAllowed": False,
        "DNSInterceptionChecksEnabled": False,
        "RemoteDebuggingAllowed": False,
        "DownloadRestrictions": 1,
    },
    "managed/performance.json": {
        "HighEfficiencyModeEnabled": True,
        "MemorySaverModeSavings": 1,
        "BatterySaverModeAvailability": 1,
        "HardwareAccelerationModeEnabled": True,
        "IntensiveWakeUpThrottlingEnabled": True,
        "TabDiscardingExceptions": [],
    },
    "recommended/defaults.json": {
        "BackgroundModeEnabled": False,
        "BlockThirdPartyCookies": True,
        "NetworkPredictionOptions": 2,
    },
}

for relpath, expected_policy in expected.items():
    with (policy_root / relpath).open(encoding="utf-8") as policy_file:
        actual_policy = json.load(policy_file)
    assert actual_policy == expected_policy, relpath
PY
then
  pass "Vivaldi managed and recommended policies are valid, hardened, and staged by the desktop role"
else
  fail "Vivaldi managed and recommended policies are valid, hardened, and staged by the desktop role"
fi

chromium_policy_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/chromium/policies"
edge_policy_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/opt/edge/policies"
browser_policy_wiring_ok=true
for policy_relpath in \
  managed/telemetry.json \
  managed/security.json \
  managed/performance.json \
  recommended/defaults.json
do
  chromium_source_relpath="etc/chromium/policies/$policy_relpath"
  chromium_target_path="/etc/chromium/policies/$policy_relpath"
  edge_source_relpath="etc/opt/edge/policies/$policy_relpath"
  edge_target_path="/etc/opt/edge/policies/$policy_relpath"

  [ -f "$chromium_policy_root/$policy_relpath" ] ||
    browser_policy_wiring_ok=false
  grep -Fq \
    "desktop_stage_role_asset $chromium_source_relpath $chromium_target_path 0644" \
    "$desktop_components" || browser_policy_wiring_ok=false
  grep -Fq "  $chromium_target_path \\" "$desktop_verify" ||
    browser_policy_wiring_ok=false

  [ -f "$edge_policy_root/$policy_relpath" ] ||
    browser_policy_wiring_ok=false
  grep -Fq \
    "desktop_stage_role_asset $edge_source_relpath $edge_target_path 0644" \
    "$desktop_components" || browser_policy_wiring_ok=false
  grep -Fq "  $edge_target_path \\" "$desktop_verify" ||
    browser_policy_wiring_ok=false
done
grep -Fq 'require_mode "$path" 644' "$desktop_verify" ||
  browser_policy_wiring_ok=false
if [ "$browser_policy_wiring_ok" = true ] &&
   python3 - "$chromium_policy_root" "$edge_policy_root" <<'PY'
import json
import pathlib
import sys

chromium_policy_root = pathlib.Path(sys.argv[1])
edge_policy_root = pathlib.Path(sys.argv[2])

expected = {
    chromium_policy_root: {
        "managed/telemetry.json": {
            "MetricsReportingEnabled": False,
            "UserFeedbackAllowed": False,
            "SafeBrowsingProtectionLevel": 1,
            "SafeBrowsingExtendedReportingEnabled": False,
            "UrlKeyedAnonymizedDataCollectionEnabled": False,
            "SearchSuggestEnabled": False,
            "SpellCheckServiceEnabled": False,
            "AlternateErrorPagesEnabled": False,
            "AutofillAddressEnabled": False,
            "AutofillCreditCardEnabled": False,
            "PasswordManagerEnabled": False,
        },
        "managed/security.json": {
            "DefaultWebUsbGuardSetting": 2,
            "DefaultWebBluetoothGuardSetting": 2,
            "DefaultSerialGuardSetting": 2,
            "DefaultWebHidGuardSetting": 2,
            "DefaultSensorsSetting": 2,
            "DefaultClipboardSetting": 2,
            "DefaultWindowManagementSetting": 2,
            "WebRtcIPHandlingPolicy": "default_public_interface_only",
            "HttpsOnlyMode": "force_enabled",
            "HttpsUpgradesEnabled": True,
            "DisableSafeBrowsingProceedAnyway": True,
            "SSLErrorOverrideAllowed": False,
            "DNSInterceptionChecksEnabled": False,
            "RemoteDebuggingAllowed": False,
            "DownloadRestrictions": 1,
        },
        "managed/performance.json": {
            "HighEfficiencyModeEnabled": True,
            "MemorySaverModeSavings": 1,
            "BatterySaverModeAvailability": 1,
            "HardwareAccelerationModeEnabled": True,
            "IntensiveWakeUpThrottlingEnabled": True,
            "TabDiscardingExceptions": [],
        },
        "recommended/defaults.json": {
            "DefaultInsecureContentSetting": 2,
            "DefaultPopupsSetting": 2,
            "DefaultGeolocationSetting": 2,
            "DefaultNotificationsSetting": 2,
            "BackgroundModeEnabled": False,
            "BlockThirdPartyCookies": True,
            "NetworkPredictionOptions": 2,
        },
    },
    edge_policy_root: {
        "managed/telemetry.json": {
            "DiagnosticData": 0,
            "UrlDiagnosticDataEnabled": False,
            "UserFeedbackAllowed": False,
            "PersonalizationReportingEnabled": False,
            "ShowRecommendationsEnabled": False,
            "SafeBrowsingExtendedReportingEnabled": False,
            "SearchSuggestEnabled": False,
            "AlternateErrorPagesEnabled": False,
            "AutofillAddressEnabled": False,
            "AutofillCreditCardEnabled": False,
            "PasswordManagerEnabled": False,
        },
        "managed/security.json": {
            "SafeBrowsingProtectionLevel": 1,
            "SmartScreenEnabled": True,
            "SmartScreenPuaEnabled": True,
            "PreventSmartScreenPromptOverride": True,
            "PreventSmartScreenPromptOverrideForFiles": True,
            "TyposquattingCheckerEnabled": True,
            "PreventTyposquattingPromptOverride": True,
            "EnhanceSecurityMode": 1,
            "EnhanceSecurityModeAllowUserBypass": False,
            "DefaultWebUsbGuardSetting": 2,
            "DefaultWebBluetoothGuardSetting": 2,
            "DefaultSerialGuardSetting": 2,
            "DefaultWebHidGuardSetting": 2,
            "DefaultSensorsSetting": 2,
            "DefaultClipboardSetting": 2,
            "DefaultWindowManagementSetting": 2,
            "WebRtcLocalhostIpHandling": "default_public_interface_only",
            "HttpsOnlyMode": "force_enabled",
            "HttpsUpgradesEnabled": True,
            "SSLErrorOverrideAllowed": False,
            "DNSInterceptionChecksEnabled": False,
            "RemoteDebuggingAllowed": False,
            "DownloadRestrictions": 1,
        },
        "managed/performance.json": {
            "HardwareAccelerationModeEnabled": True,
            "EfficiencyModeEnabled": True,
            "EfficiencyMode": 4,
            "SleepingTabsEnabled": True,
            "SleepingTabsTimeout": 1800,
            "AutoDiscardSleepingTabsEnabled": True,
            "SleepingTabsBlockedForUrls": [],
            "IntensiveWakeUpThrottlingEnabled": True,
        },
        "recommended/defaults.json": {
            "DefaultInsecureContentSetting": 2,
            "DefaultPopupsSetting": 2,
            "DefaultGeolocationSetting": 2,
            "DefaultNotificationsSetting": 2,
            "BackgroundModeEnabled": False,
            "BlockThirdPartyCookies": True,
            "NetworkPredictionOptions": 2,
            "PromptForDownloadLocation": True,
            "RestoreOnStartup": 1,
        },
    },
}

for policy_root, policies in expected.items():
    for relpath, expected_policy in policies.items():
        with (policy_root / relpath).open(encoding="utf-8") as policy_file:
            actual_policy = json.load(policy_file)
        assert actual_policy == expected_policy, f"{policy_root.name}/{relpath}"
PY
then
  pass "Chromium and Microsoft Edge policies are valid, comprehensive, mode 0644, and staged by the desktop role"
else
  fail "Chromium and Microsoft Edge policies are valid, comprehensive, mode 0644, and staged by the desktop role"
fi

managed_app_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-managed-app"
managed_app_package_parent="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages"
managed_app_package="$managed_app_package_parent/labwc_managed_app"
managed_app="$TMP_DIR/labwc-managed-app-package.py"
cat "$managed_app_wrapper" "$managed_app_package"/*.py >"$managed_app"
qbittorrent_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-qbittorrent"
launcher_sync="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sync-application-launchers"
keepassxc_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/keepassxc/keepassxc.ini"
chromium_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/chromium/Default/Preferences"
edge_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/microsoft-edge/Default/Preferences"
vivaldi_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/vivaldi/Default/Preferences"
code_settings="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/Code/User/settings.json"
obsidian_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/obsidian/obsidian.json"
obsidian_vault="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/Syncthing/obsidian-md"
obsidian_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian"
managed_wrapper_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
managed_exec_profiles_ok=true
for managed_exec_profile in \
  "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" \
  "$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env" \
  "$ROOT_DIR/d-i/forky/hosts/profiles/vm/desktop.env" \
  "$ROOT_DIR"/d-i/forky/hosts/profiles/override/*-de*.env
do
  grep -Eq '^LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-managed-app (launch|pure-privacy|intel|nvidia)"$' \
    "$managed_exec_profile" ||
    managed_exec_profiles_ok=false
done
unset managed_exec_profile
if [ -r "$obsidian_vault/.obsidian/app.json" ] &&
   [ -r "$obsidian_vault/.obsidian/appearance.json" ] &&
   [ -r "$obsidian_vault/.obsidian/core-plugins.json" ] &&
   [ -r "$obsidian_vault/.obsidian/themes/evergreen-notes/manifest.json" ] &&
   [ -r "$obsidian_vault/.obsidian/themes/evergreen-notes/theme.css" ] &&
   [ -r "$obsidian_vault/.obsidian/snippets/managed-ux.css" ] &&
   [ -r "$obsidian_vault/home.md" ] &&
   [ -r "$obsidian_vault/../.stignore" ] &&
   grep -Fqx '(?d)obsidian-md/.obsidian/workspace*.json' "$obsidian_vault/../.stignore" &&
   grep -q '^desktop_stage_obsidian_default_vault() {$' "$desktop_components" &&
   grep -q 'desktop_stage_obsidian_default_vault' "$desktop_components" &&
   grep -q 'Syncthing/obsidian-md \\' "$desktop_components" &&
   grep -q '"\$account_home/Syncthing/obsidian-md"' "$desktop_verify" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/ rw,$' "$managed_wrapper_apparmor" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/\*\* rwkl,$' "$managed_wrapper_apparmor" &&
   grep -q '^  owner @{HOME}/Syncthing/.stignore rwkl,$' "$managed_wrapper_apparmor" &&
   ! grep -q '^  /etc/skel/.config/obsidian/obsidian.json r,$' "$managed_wrapper_apparmor" &&
   ! grep -q '^  /etc/skel/Syncthing/.stignore r,$' "$managed_wrapper_apparmor" &&
   ! grep -q '^  /etc/skel/Syncthing/obsidian-md/\*\* r,$' "$managed_wrapper_apparmor" &&
   grep -q '^  owner @{HOME}/Syncthing/ r,$' "$obsidian_apparmor" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/ rw,$' "$obsidian_apparmor" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/\*\* rwkl,$' "$obsidian_apparmor" &&
   python3 - "$managed_app_package_parent" "$obsidian_config" "$obsidian_vault" <<'PY' >/dev/null 2>&1
import contextlib
import hashlib
import io
import json
import os
import pathlib
import shutil
import stat
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
from labwc_managed_app.environment import ensure_obsidian_registry, load_user_json_object
from labwc_managed_app.profiles import (
    MANAGED_RUNTIME_STATE,
    OBSIDIAN_REGISTRY_MAX_BYTES,
    OBSIDIAN_VAULT_RELATIVE_PATH,
)

module = {
    "MANAGED_RUNTIME_STATE": MANAGED_RUNTIME_STATE,
    "OBSIDIAN_REGISTRY_MAX_BYTES": OBSIDIAN_REGISTRY_MAX_BYTES,
    "OBSIDIAN_VAULT_RELATIVE_PATH": OBSIDIAN_VAULT_RELATIVE_PATH,
    "ensure_obsidian_registry": ensure_obsidian_registry,
    "load_user_json_object": load_user_json_object,
}
global_config_path = pathlib.Path(sys.argv[2])
vault = pathlib.Path(sys.argv[3])

with global_config_path.open(encoding="utf-8") as handle:
    global_config = json.load(handle)
assert global_config == {
    "frame": "native",
    "openSchemes": {},
    "vaults": {},
}

def load(relative_path):
    with (vault / relative_path).open(encoding="utf-8") as handle:
        return json.load(handle)

app = load(".obsidian/app.json")
assert app["newFileLocation"] == "folder"
assert app["newFileFolderPath"] == "inbox"
assert app["attachmentFolderPath"] == "attachments"
assert app["trashOption"] == "local"
assert app["alwaysUpdateLinks"] is True
assert app["spellcheckLanguages"] == ["en-US", "sv-SE"]
assert app["propertiesInDocument"] == "visible"

appearance = load(".obsidian/appearance.json")
assert appearance["theme"] == "obsidian"
assert appearance["cssTheme"] == "evergreen-notes"
assert appearance["enabledCssSnippets"] == ["managed-ux"]
assert appearance["interfaceFontFamily"] == "Noto Sans"
assert appearance["monospaceFontFamily"] == "Noto Sans Mono"
assert appearance["translucency"] is False

core_plugins = load(".obsidian/core-plugins.json")
for plugin_id in (
    "file-explorer",
    "global-search",
    "graph",
    "backlink",
    "canvas",
    "properties",
    "daily-notes",
    "templates",
    "file-recovery",
    "bases",
):
    assert core_plugins[plugin_id] is True
for plugin_id in ("publish", "sync", "webviewer", "audio-recorder"):
    assert core_plugins[plugin_id] is False
assert load(".obsidian/community-plugins.json") == []
assert load(".obsidian/templates.json") == {"folder": "templates"}
assert load(".obsidian/daily-notes.json") == {
    "folder": "daily",
    "format": "YYYY-MM-DD",
    "template": "templates/daily-note-template",
}
assert load(".obsidian/backlink.json") == {"backlinkInDocument": True}

manifest = load(".obsidian/themes/evergreen-notes/manifest.json")
assert manifest == {
    "name": "evergreen-notes",
    "version": "1.0.0",
    "minAppVersion": "1.12.0",
    "author": "Matthew Cramer",
}
theme_css = (vault / ".obsidian/themes/evergreen-notes/theme.css").read_text(encoding="utf-8")
for required_css in (
    ".theme-dark",
    ".theme-light",
    "--background-primary:",
    "--interactive-accent:",
    "--text-normal:",
    "--graph-node:",
    "--canvas-background:",
    "@media print",
):
    assert required_css in theme_css
ux_css = (vault / ".obsidian/snippets/managed-ux.css").read_text(encoding="utf-8")
assert ":focus-visible" in ux_css
assert "@media (prefers-reduced-motion: reduce)" in ux_css
home_note = (vault / "home.md").read_text(encoding="utf-8")
assert home_note.startswith("---\n")
assert "[[inbox/welcome|Inbox]]" in home_note
assert "[[templates/daily-note-template|Daily-note template]]" in home_note

assert module["OBSIDIAN_VAULT_RELATIVE_PATH"] == "Syncthing/obsidian-md"
assert "obsidian" not in module["MANAGED_RUNTIME_STATE"]

with tempfile.TemporaryDirectory() as temporary_home:
    home = pathlib.Path(temporary_home)
    registry_dir = home / ".config/obsidian"
    registry_dir.mkdir(parents=True, mode=0o700)
    managed_vault = home / "Syncthing/obsidian-md"
    managed_vault.mkdir(parents=True, mode=0o700)
    registry_path = registry_dir / "obsidian.json"
    shutil.copyfile(global_config_path, registry_path)
    os.chmod(registry_path, 0o600)

    module["ensure_obsidian_registry"](temporary_home)
    first_render = registry_path.read_text(encoding="utf-8")
    registry = json.loads(first_render)
    expected_id = hashlib.sha256(str(managed_vault).encode("utf-8")).hexdigest()[:16]
    assert list(registry["vaults"]) == [expected_id]
    assert registry["vaults"][expected_id]["path"] == str(managed_vault)
    assert registry["vaults"][expected_id]["open"] is True
    assert isinstance(registry["vaults"][expected_id]["ts"], int)
    assert stat.S_IMODE(registry_path.stat().st_mode) == 0o600

    module["ensure_obsidian_registry"](temporary_home)
    assert registry_path.read_text(encoding="utf-8") == first_render

with tempfile.TemporaryDirectory() as temporary_home:
    home = pathlib.Path(temporary_home)
    registry_dir = home / ".config/obsidian"
    registry_dir.mkdir(parents=True, mode=0o700)
    (home / "Syncthing/obsidian-md").mkdir(parents=True, mode=0o700)
    registry_path = registry_dir / "obsidian.json"
    registry_path.write_text(
        json.dumps(
            {
                "frame": "native",
                "openSchemes": {},
                "vaults": {
                    "existing-vault": {
                        "path": str(home / "other-vault"),
                        "ts": 1,
                        "open": True,
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    os.chmod(registry_path, 0o600)
    module["ensure_obsidian_registry"](temporary_home)
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    managed_entries = [
        entry
        for entry in registry["vaults"].values()
        if entry.get("path") == str(home / "Syncthing/obsidian-md")
    ]
    assert len(managed_entries) == 1
    assert "open" not in managed_entries[0]

with tempfile.TemporaryDirectory() as temporary_home:
    invalid_json = pathlib.Path(temporary_home) / "duplicate.json"
    invalid_json.write_text('{"vaults": {}, "vaults": {}}\n', encoding="utf-8")
    os.chmod(invalid_json, 0o600)
    with contextlib.redirect_stderr(io.StringIO()):
        try:
            module["load_user_json_object"](
                str(invalid_json),
                module["OBSIDIAN_REGISTRY_MAX_BYTES"],
            )
        except SystemExit:
            pass
        else:
            raise AssertionError("duplicate Obsidian registry keys were accepted")
PY
then
  pass "Obsidian receives a private comprehensive default vault and idempotent per-user registration"
else
  fail "Obsidian receives a private comprehensive default vault and idempotent per-user registration"
fi

if [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sandbox" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/incus/sandbox-blueprint.yaml.tmpl" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/fuzzel/sandbox.ini.tmpl" ] &&
   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/fuzzel/sandbox-apps.tsv" ] &&
   ! grep -q 'LABWC_SANDBOX' "$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env" &&
   ! grep -q 'labwc-sandbox' "$desktop_components" &&
   ! grep -q 'SANDBOX_STATUS_FILE' "$firstboot_validation"; then
  pass "desktop staging omits the retired Incus app-container UI and backend assets"
else
  fail "desktop staging omits the retired Incus app-container UI and backend assets"
fi

if ! grep -q '^PRIVACY_VULKAN_ICD_CANDIDATES = ($' "$managed_app" &&
   grep -q '^BROWSER_PROFILES = {$' "$managed_app" &&
   grep -q '^ELECTRON_PROFILES = {$' "$managed_app" &&
   grep -q '^ELECTRON_OLD_SPACE_SIZE_MB = {$' "$managed_app" &&
   grep -q '^def electron_js_flags(app_name: str) -> str:$' "$managed_app" &&
   grep -q 'value >= 2024' "$managed_app" &&
   grep -q '^VULKAN_DISABLE_FEATURES = ($' "$managed_app" &&
   grep -q '^MANAGED_NO_VULKAN_ENVIRONMENT = {$' "$managed_app" &&
   grep -q '^MANAGED_WAYLAND_OPENGL_ENVIRONMENT = {$' "$managed_app" &&
   grep -q '"ANGLE_DEFAULT_PLATFORM": "gl"' "$managed_app" &&
   grep -q '"WGPU_BACKEND": "gl"' "$managed_app" &&
   grep -q '"SDL_RENDER_DRIVER": "opengl"' "$managed_app" &&
   grep -q '"GSK_RENDERER": "opengl"' "$managed_app" &&
   grep -q '"GDK_DISABLE": "vulkan"' "$managed_app" &&
   grep -q '"QT_WAYLAND_DISABLE_WINDOWDECORATION": "1"' "$managed_app" &&
   grep -q '"QSG_RHI_BACKEND": "opengl"' "$managed_app" &&
   ! grep -q '"--use-angle=vulkan"' "$managed_app" &&
   ! grep -q 'VK_DRIVER_FILES' "$managed_app" &&
   grep -q '"--use-angle=gl"' "$managed_app" &&
   grep -q '^def validate_managed_arguments(mode: str, extra_args: list\[str\]) -> None:$' "$managed_app" &&
   grep -q '"FONTCONFIG_FILE": "/etc/fonts/fonts.conf"' "$managed_app" &&
   grep -q '"FONTCONFIG_PATH": "/etc/fonts"' "$managed_app" &&
   grep -q 'normal launch accepts Wayland flags only' "$managed_app" &&
   grep -q '__NV_PRIME_RENDER_OFFLOAD' "$managed_app" &&
   grep -q '__GLX_VENDOR_LIBRARY_NAME' "$managed_app" &&
   grep -q '"LIBVA_DRIVER_NAME": "iHD"' "$managed_app" &&
   grep -q '"LIBVA_DRIVER_NAME": "nvidia"' "$managed_app" &&
   ! grep -q 'env.pop("XAUTHORITY", None)' "$managed_app" &&
   grep -q '^def run_wayland_compat_sandbox($' "$managed_app" &&
   grep -q '^SANDBOX_LIFECYCLE_HELPER = "/usr/local/libexec/labwc-zoom-discord-compat-runtime"$' "$managed_app" &&
   grep -q 'command.extend(\["--ro-bind", "/usr", "/usr"\])' "$managed_app" &&
   grep -q '^def add_private_xkbcomp_overlay(command: list\[str\], overlay_directory: str) -> None:$' "$managed_app" &&
   grep -Fq 'add_private_xkbcomp_overlay(command, private_xkbcomp_overlay_directory)' "$managed_app" &&
   [ "$(grep -c -- '"--overlay-src",' "$managed_app")" -eq 2 ] &&
   grep -Fq '"--ro-overlay",' "$managed_app" &&
   ! grep -Fq 'command.extend(["--ro-bind", source, PRIVATE_XKBCOMP_DESTINATION])' "$managed_app" &&
   ! grep -q -- '--tmp-overlay' "$managed_app" &&
   ! grep -q -- '--remount-ro' "$managed_app" &&
   grep -q 'env\["WLR_XWAYLAND"\] = private_xwayland_binary' "$managed_app" &&
   grep -q 'env\["LD_LIBRARY_PATH"\] = PRIVATE_XWAYLAND_LIBRARY_DIRECTORY' "$managed_app" &&
   grep -q '^def create_slirp4netns_resolver_file(temp_root: str) -> str:$' "$managed_app" &&
   grep -q '^def reserve_outer_wayland_socket_name($' "$managed_app" &&
   grep -Fq 'outer_wayland_lock_fd = reserve_outer_wayland_socket_name(' "$managed_app" &&
   grep -q '"WLR_BACKENDS": "wayland"' "$managed_app" &&
   grep -q '"WLR_WL_OUTPUTS": "1"' "$managed_app" &&
   grep -q '^def require_cage_wayland_socket() -> None:$' "$managed_app" &&
   grep -q '^def require_cage_x11_display() -> str:$' "$managed_app" &&
   grep -q 'application_environment.get("DISPLAY") != expected_display' "$managed_app" &&
   ! grep -q '^def xwayland_arguments($' "$managed_app" &&
   ! grep -q -- '-decorate' "$managed_app" &&
   ! grep -q -- '-geometry' "$managed_app" &&
   ! grep -q -- '--display-number' "$managed_app" &&
   ! grep -q -- '--listen-fd' "$managed_app" &&
   grep -q '^def add_gpu_device_binds(command: list\[str\], mode: str) -> None:$' "$managed_app" &&
   grep -q 'privacy_home_ro_paths' "$managed_app" &&
   grep -q 'resolve_home_relative_file' "$managed_app" &&
   grep -q 'validate_pure_privacy_device_isolation(app_name, command)' "$managed_app" &&
   grep -q '^PERSISTENT_SANDBOX_CONFIG = {$' "$managed_app" &&
   grep -q '"Syncthing/keepassxc"' "$managed_app" &&
   grep -q 'xdg-dbus-proxy' "$managed_app" &&
   grep -q 'validate_session_bus_address' "$managed_app" &&
   grep -q '"dbus_names": TUTA_DBUS_NAMES' "$managed_app" &&
   grep -q '"require_session_bus": True' "$managed_app" &&
   grep -q 'required=sandbox.get("require_session_bus", False)' "$managed_app" &&
   ! grep -q '^TUTA_SECRET_SERVICE_UNITS = ($' "$managed_app" &&
   ! grep -q '^SYSTEMCTL_PATH = ' "$managed_app" &&
   ! grep -q '^def ensure_tuta_secret_services() -> None:$' "$managed_app" &&
   ! grep -q 'systemctl' "$managed_app" &&
   grep -q 'gnome-libsecret' "$managed_app" &&
   ! grep -q 'privacy_system_bus_proxy' "$managed_app" &&
   grep -q '^def start_system_bus_proxy($' "$managed_app" &&
   grep -q '^def add_system_bus_proxy_bind(command: list\[str\], proxy_socket: str) -> None:$' "$managed_app" &&
   grep -q '"require_system_bus": True' "$managed_app" &&
   grep -q '"system_dbus_names": ()' "$managed_app" &&
   grep -q 'env\["DBUS_SYSTEM_BUS_ADDRESS"\] = SYSTEM_BUS_ADDRESS' "$managed_app" &&
   grep -q 'env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)' "$managed_app" &&
   grep -q '^SYSTEM_BUS_SOCKET_PATH = "/run/dbus/system_bus_socket"$' "$managed_app" &&
   grep -q '^def ensure_discord_managed_settings(home_dir: str) -> None:$' "$managed_app" &&
   grep -q '"SKIP_HOST_UPDATE": True' "$managed_app" &&
   grep -q '"SKIP_MODULE_UPDATE": True' "$managed_app" &&
   grep -q '^ZOOM_CONFIG_SOURCE = ".config/zoom"$' "$managed_app" &&
   grep -q '"persistent_directory_binds": (' "$managed_app" &&
   grep -Fq '(ZOOM_CONFIG_SOURCE, ".config"),' "$managed_app" &&
   grep -q '^def add_persistent_directory_binds($' "$managed_app" &&
   grep -q 'sandbox.get("persistent_directory_binds", ())' "$managed_app" &&
   ! grep -q '"xdg_config_home": ".config/zoom"' "$managed_app" &&
   grep -q '^    fake_machine_id = uuid.uuid4().hex$' "$managed_app" &&
   grep -q '^    identity_seed = hashlib.sha256($' "$managed_app" &&
   grep -Fq 'identity_seed + b"\0installation-id"' "$managed_app" &&
   grep -q '^MANAGED_CODEX_HOME = "/data/codex/usr/home"$' "$managed_app" &&
   grep -q '^MANAGED_CODEX_INSTALLATION_ID = f"{MANAGED_CODEX_HOME}/installation_id"$' "$managed_app" &&
   grep -q '^def add_synthetic_codex_installation_id_mount($' "$managed_app" &&
   grep -q 'os.chmod(identity\[name\], 0o644 if name == "installation_id" else 0o600)' "$managed_app" &&
   grep -q -- '"--bind",' "$managed_app" &&
   ! grep -q -- '--ro-bind-data' "$managed_app" &&
   grep -q 'synthetic_identity\["installation_id"\]' "$managed_app" &&
   grep -q 'pass_fds=inherited_fds' "$managed_app" &&
   grep -q 'MOZ_WEBRENDER_SOFTWARE' "$managed_app" &&
   grep -q -- '--disable-vulkan' "$managed_app" &&
   grep -q -- '--disable-accelerated-video-decode' "$managed_app" &&
   ! grep -q -- '--disable-userns' "$managed_app" &&
   grep -q '"zoom"' "$managed_app" &&
   grep -q '"telegram-desktop"' "$managed_app" &&
   grep -q '"retroarch"' "$managed_app" &&
   grep -q '"qbittorrent"' "$managed_app" &&
   grep -q '"obsidian"' "$managed_app" &&
   grep -q '"microsoft-edge.desktop"' "$launcher_sync" &&
   grep -q '"vivaldi-stable.desktop"' "$launcher_sync" &&
   grep -q '"bitwarden.desktop"' "$launcher_sync" &&
   grep -q '"obsidian.desktop"' "$launcher_sync" &&
   grep -q '"tuta-mail.desktop"' "$launcher_sync" &&
   grep -q '"org.keepassxc.KeePassXC.desktop"' "$launcher_sync" &&
   grep -q '"Zoom.desktop"' "$launcher_sync" &&
   grep -q '"Filen.desktop"' "$launcher_sync" &&
   grep -q '"discord.desktop"' "$launcher_sync" &&
   grep -q '"ledger-live.desktop"' "$launcher_sync" &&
   grep -q '"org.telegram.desktop.desktop"' "$launcher_sync" &&
   grep -q '"org.qbittorrent.qBittorrent.desktop"' "$launcher_sync" &&
   grep -q '"retroarch.desktop"' "$launcher_sync" &&
   grep -q '"IntelAccelerated": ("intel", "IntelAccelerated")' "$launcher_sync" &&
   grep -q '"NvidiaAccelerated": ("nvidia", "NvidiaAccelerated")' "$launcher_sync" &&
   grep -q '"PurePrivacy": ("pure-privacy", "PurePrivacy")' "$launcher_sync" &&
   grep -q '^def ensure_user_directory(path: str, uid: int, gid: int) -> None:$' "$launcher_sync" &&
   grep -q '^def validate_account_context(account_user: str, account_home: str) -> tuple\[int, int\]:$' "$launcher_sync" &&
   grep -q '^def remove_unmanaged_tuta_launchers(account_home: str, uid: int) -> int:$' "$launcher_sync" &&
   grep -q 'tempfile.mkstemp(' "$launcher_sync" &&
   grep -q 'os.replace(temporary_path, path)' "$launcher_sync" &&
   [ "$managed_exec_profiles_ok" = true ] &&
   grep -q '^MANAGED_APP_DEFAULT_EXEC = "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__"$' "$launcher_sync" &&
   grep -q '^def managed_default_exec($' "$launcher_sync" &&
   grep -q 'default_mode: str | None = None,' "$launcher_sync" &&
   grep -q 'desktop_validate_managed_app_default_exec' "$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh" &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ postman %U$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/postman.desktop" &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ sleek %U$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/sleek.desktop" &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ tutanota %U$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/tuta-mail.desktop" &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ ledger-live %U$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/ledger-live.desktop" &&
   grep -q '^WAYLAND_COMPAT_MANAGED_APP = "/usr/local/bin/labwc-managed-wayland-compat-app"$' "$launcher_sync" &&
   grep -q '^WAYLAND_COMPAT_APPS = {"discord", "zoom"}$' "$launcher_sync" &&
   grep -q '^def managed_exec(mode: str, app_name: str, field_code: str) -> str:$' "$launcher_sync" &&
   grep -q 'if app_name in WAYLAND_COMPAT_APPS' "$launcher_sync" &&
   grep -q 'desktop-file-validate' "$launcher_sync" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-managed-app /usr/local/bin/labwc-managed-app 0755' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-managed-wayland-compat-app /usr/local/bin/labwc-managed-wayland-compat-app 0755' "$desktop_components" &&
   grep -q '^wayland_compat.py$' "$desktop_components" &&
   grep -q '^wayland_compat_runtime.py$' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset usr/local/libexec/labwc-zoom-discord-compat-runtime /usr/local/libexec/labwc-zoom-discord-compat-runtime 0755' "$desktop_components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-qbittorrent /usr/local/bin/labwc-qbittorrent 0755' "$desktop_components" &&
   grep -q 'desktop_render_role_target_template \\' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-sync-application-launchers \\' "$desktop_components" &&
   grep -q 'LABWC_MANAGED_APP_DEFAULT_EXEC "\$LABWC_MANAGED_APP_DEFAULT_EXEC"' "$desktop_components" &&
   grep -q '"\$account_home/.cache/vivaldi"' "$desktop_components" &&
   grep -q '"\$account_home/.config/vivaldi"' "$desktop_components" &&
   grep -q '"\$account_home/.cache/vivaldi"' "$desktop_verify" &&
   grep -q '"\$account_home/.config/vivaldi"' "$desktop_verify" &&
   grep -q 'etc/skel/.config/chromium/Default/Preferences /etc/skel/.config/chromium/Default/Preferences 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/microsoft-edge/Default/Preferences /etc/skel/.config/microsoft-edge/Default/Preferences 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/vivaldi/Default/Preferences /etc/skel/.config/vivaldi/Default/Preferences 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/Code/User/settings.json /etc/skel/.config/Code/User/settings.json 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/obsidian/obsidian.json /etc/skel/.config/obsidian/obsidian.json 0600' "$desktop_components" &&
   grep -q '"\$account_home/.local/share/applications"' "$desktop_verify" &&
   grep -q '/etc/fonts/fonts.conf' "$desktop_verify" &&
   grep -q '/etc/fonts/fonts.conf' "$firstboot_validation" &&
   grep -q 'etc/skel/.config/keepassxc/keepassxc.ini /etc/skel/.config/keepassxc/keepassxc.ini 0600' "$desktop_components" &&
   grep -q '^ClearClipboard=true$' "$keepassxc_config" &&
   grep -q '^BackupFilePath=backups$' "$keepassxc_config" &&
   grep -q '^LockDatabaseScreenLock=true$' "$keepassxc_config" &&
   grep -q '^Enabled=false$' "$keepassxc_config" &&
   grep -q 'MANAGED_PORT = 50309' "$qbittorrent_wrapper" &&
   grep -q '"QSG_RHI_BACKEND": "opengl"' "$qbittorrent_wrapper" &&
   grep -q '"LIBVA_DRIVER_NAME": "iHD"' "$qbittorrent_wrapper" &&
   grep -q '"LIBVA_DRIVER_NAME": "nvidia"' "$qbittorrent_wrapper" &&
   ! grep -q 'VK_DRIVER_FILES' "$qbittorrent_wrapper" &&
   ! grep -q '"QT_QUICK_BACKEND"' "$qbittorrent_wrapper" &&
   ! grep -q '"QT_OPENGL"' "$qbittorrent_wrapper" &&
   ! grep -q '"LIBGL_ALWAYS_SOFTWARE"' "$qbittorrent_wrapper" &&
   ! grep -q 'LABWC_SANDBOX' "$desktop_components" &&
   python3 - "$chromium_preferences" "$edge_preferences" "$vivaldi_preferences" "$code_settings" "$obsidian_config" <<'PY' >/dev/null 2>&1
import json
import sys

for preference_path in sys.argv[1:4]:
    with open(preference_path, encoding="utf-8") as handle:
        preference = json.load(handle)
    assert preference == {"browser": {"custom_chrome_frame": False}}

with open(sys.argv[4], encoding="utf-8") as handle:
    settings = json.load(handle)
assert settings["chat.disableAIFeatures"] is True
assert settings["window.titleBarStyle"] == "native"
assert settings["workbench.colorTheme"] == "Default Dark Modern"
assert settings["workbench.iconTheme"] == "vs-seti"
assert settings["workbench.activityBar.location"] == "top"
assert settings["workbench.reduceMotion"] == "on"
assert settings["editor.semanticHighlighting.enabled"] is True
assert settings["editor.inlineSuggest.enabled"] is False
assert settings["telemetry.telemetryLevel"] == "off"
assert settings["security.workspace.trust.enabled"] is True
assert settings["editor.tokenColorCustomizations"]["comments"] == "#7C948C"
assert settings["editor.semanticTokenColorCustomizations"]["enabled"] is True
colors = settings["workbench.colorCustomizations"]
assert colors["activityBar.background"] == "#0E3B2C"
assert colors["activityBar.activeBorder"] == "#65F0BC"
assert colors["activityBarTop.background"] == "#0E3B2C"
assert colors["activityBarTop.activeBackground"] == "#1F6A50"
assert colors["statusBar.background"] == "#0E3B2C"
assert colors["statusBar.noFolderBackground"] == "#123B31"
assert colors["statusBar.debuggingBackground"] == "#145B3F"
assert colors["statusBarItem.prominentBackground"] == "#1E7D4D"
assert len(colors) >= 150

with open(sys.argv[5], encoding="utf-8") as handle:
    obsidian = json.load(handle)
assert obsidian == {
    "frame": "native",
    "openSchemes": {},
    "vaults": {},
}
PY
then
  pass "managed launchers expose Wayland-only defaults, GPU-specific actions, and bounded privacy"
else
  fail "managed launchers expose Wayland-only defaults, GPU-specific actions, and bounded privacy"
fi

if python3 - "$managed_app_package_parent" "$launcher_sync" <<'PY' >/dev/null 2>&1
import os
import fcntl
import runpy
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
from labwc_managed_app import wayland_compat
from labwc_managed_app.commands import build_argv, managed_library_path
from labwc_managed_app.electron import ELECTRON_OLD_SPACE_SIZE_MB, electron_js_flags
from labwc_managed_app.environment import build_environment, validate_acceleration_mode
from labwc_managed_app.profiles import (
    APPS,
    DISCORD_REQUIRED_FILES,
    DISCORD_ROOT,
    PERSISTENT_SANDBOX_CONFIG,
    WAYLAND_COMPAT_APPS,
    ZOOM_CONFIG_SOURCE,
)
from labwc_managed_app.runtime import MANAGED_PATH
from labwc_managed_app.sandbox import (
    add_home_directory_binds,
    add_persistent_directory_binds,
    add_system_bus_proxy_bind,
    create_slirp4netns_resolver_file,
    pure_privacy_argv,
    pure_privacy_environment,
    reserve_outer_wayland_socket_name,
    slirp4netns_resolv_conf,
    start_system_bus_proxy,
    start_session_bus_proxy,
    SYSTEM_BUS_SOCKET_PATH,
    validate_pure_privacy_device_isolation,
)

module = {
    "APPS": APPS,
    "DISCORD_REQUIRED_FILES": DISCORD_REQUIRED_FILES,
    "DISCORD_ROOT": DISCORD_ROOT,
    "ELECTRON_OLD_SPACE_SIZE_MB": ELECTRON_OLD_SPACE_SIZE_MB,
    "MANAGED_PATH": MANAGED_PATH,
    "PERSISTENT_SANDBOX_CONFIG": PERSISTENT_SANDBOX_CONFIG,
    "PRIVATE_RUNTIME_ROOT": wayland_compat.PRIVATE_RUNTIME_ROOT,
    "PRIVATE_RUNTIME_BINARY": wayland_compat.PRIVATE_RUNTIME_BINARY,
    "PRIVATE_RUNTIME_PROTOCOL": wayland_compat.PRIVATE_RUNTIME_PROTOCOL,
    "PRIVATE_RUNTIME_LIBRARY_DIRECTORY": wayland_compat.PRIVATE_RUNTIME_LIBRARY_DIRECTORY,
    "PRIVATE_RUNTIME_LIBRARY_NAMES": wayland_compat.PRIVATE_RUNTIME_LIBRARY_NAMES,
    "SANDBOX_LIFECYCLE_HELPER": wayland_compat.SANDBOX_LIFECYCLE_HELPER,
    "WAYLAND_COMPAT_APPS": WAYLAND_COMPAT_APPS,
    "ZOOM_CONFIG_SOURCE": ZOOM_CONFIG_SOURCE,
    "add_home_directory_binds": add_home_directory_binds,
    "add_persistent_directory_binds": add_persistent_directory_binds,
    "add_system_bus_proxy_bind": add_system_bus_proxy_bind,
    "create_slirp4netns_resolver_file": create_slirp4netns_resolver_file,
    "build_argv": build_argv,
    "build_environment": build_environment,
    "electron_js_flags": electron_js_flags,
    "managed_library_path": managed_library_path,
    "pure_privacy_argv": pure_privacy_argv,
    "pure_privacy_environment": pure_privacy_environment,
    "reserve_outer_wayland_socket_name": reserve_outer_wayland_socket_name,
    "slirp4netns_resolv_conf": slirp4netns_resolv_conf,
    "start_system_bus_proxy": start_system_bus_proxy,
    "start_session_bus_proxy": start_session_bus_proxy,
    "SYSTEM_BUS_SOCKET_PATH": SYSTEM_BUS_SOCKET_PATH,
    "validate_acceleration_mode": validate_acceleration_mode,
    "validate_pure_privacy_device_isolation": validate_pure_privacy_device_isolation,
}
launcher_module = runpy.run_path(sys.argv[2], run_name="labwc_launcher_sync_test")
apps = module["APPS"]
assert "chatgpt" in apps
generic_apps = {
    app_name: app
    for app_name, app in apps.items()
    if app_name != "chatgpt"
}
build_argv = module["build_argv"]
build_environment = module["build_environment"]
managed_library_path = module["managed_library_path"]
managed_path = module["MANAGED_PATH"]
pure_privacy_argv = module["pure_privacy_argv"]
pure_privacy_environment = module["pure_privacy_environment"]
validate_pure_privacy_device_isolation = module["validate_pure_privacy_device_isolation"]
start_session_bus_proxy = module["start_session_bus_proxy"]
add_system_bus_proxy_bind = module["add_system_bus_proxy_bind"]

assert set(generic_apps) == {
    "bitwarden",
    "chromium",
    "code",
    "discord",
    "filen",
    "gridline",
    "keepassxc",
    "ledger-live",
    "microsoft-edge",
    "mullvad-browser",
    "obsidian",
    "postman",
    "qbittorrent",
    "qoredb",
    "retroarch",
    "sleek",
    "spotify",
    "telegram-desktop",
    "tutanota",
    "vivaldi",
    "zoom",
}
launcher_apps = tuple(
    config["action_app"]
    for config in launcher_module["APP_CONFIG"]
    if config["action_app"] != "chatgpt"
)
assert len(launcher_apps) == len(set(launcher_apps))
assert set(launcher_apps) == set(generic_apps)
assert module["WAYLAND_COMPAT_APPS"] == ("discord", "zoom")
assert launcher_module["WAYLAND_COMPAT_APPS"] == {"discord", "zoom"}
for app_name in module["WAYLAND_COMPAT_APPS"]:
    assert launcher_module["managed_exec"](
        "intel",
        app_name,
        "%U",
    ) == f"/usr/local/bin/labwc-managed-wayland-compat-app intel {app_name} %U"
    assert launcher_module["managed_default_exec"](
        app_name,
        "%U",
    ) == f"/usr/local/bin/labwc-managed-wayland-compat-app auto {app_name} %U"
assert launcher_module["managed_exec"](
    "intel",
    "tutanota",
    "%U",
) == "/usr/local/bin/labwc-managed-app intel tutanota %U"
assert launcher_module["ACTION_SPECS"] == {
    "IntelAccelerated": ("intel", "IntelAccelerated"),
    "NvidiaAccelerated": ("nvidia", "NvidiaAccelerated"),
    "PurePrivacy": ("pure-privacy", "PurePrivacy"),
}
electron_limits = module["ELECTRON_OLD_SPACE_SIZE_MB"]
assert len(set(electron_limits.values())) == len(electron_limits)
assert all(0 < value < 2024 for value in electron_limits.values())

runtime_library_contract = {
    "bitwarden": ("/opt/Bitwarden", "/opt/Bitwarden/libffmpeg.so"),
    "code": ("/usr/share/code", "/usr/share/code/libffmpeg.so"),
    "filen": ("/opt/Filen", "/opt/Filen/libffmpeg.so"),
    "obsidian": ("/opt/Obsidian", "/opt/Obsidian/libffmpeg.so"),
    "postman": ("/opt/postman/app", "/opt/postman/app/libffmpeg.so"),
    "sleek": ("/opt/sleek", "/opt/sleek/libffmpeg.so"),
}
for app_name, (library_dir, runtime_file) in runtime_library_contract.items():
    assert apps[app_name]["library_dirs"] == (library_dir,)
    assert apps[app_name]["required_runtime_files"] == (runtime_file,)
    assert managed_library_path(app_name) == library_dir
    for mode in ("launch", "intel", "nvidia"):
        assert build_environment(app_name, mode)["LD_LIBRARY_PATH"] == library_dir
assert apps["discord"]["exec"] == "/opt/discord/Discord"
assert apps["discord"]["library_dirs"] == (module["DISCORD_ROOT"],)
assert apps["discord"]["required_runtime_files"] == module["DISCORD_REQUIRED_FILES"]
assert "private_runtime" not in apps["discord"]
assert "private_runtime" not in apps["zoom"]
assert "required_runtime_files" not in apps["zoom"]
assert "x11_display" not in apps["discord"]
assert "x11_display" not in apps["zoom"]
assert module["PRIVATE_RUNTIME_ROOT"] == "/opt/xwayland"
assert module["PRIVATE_RUNTIME_BINARY"] == "/opt/xwayland/usr/bin/Xwayland"
assert module["PRIVATE_RUNTIME_PROTOCOL"] == "/opt/xwayland/usr/lib/xorg/protocol.txt"
assert module["PRIVATE_RUNTIME_LIBRARY_DIRECTORY"] == (
    "/opt/xwayland/usr/lib/x86_64-linux-gnu"
)
assert module["PRIVATE_RUNTIME_LIBRARY_NAMES"] == (
    "libXau.so.6",
    "libXdmcp.so.6",
    "libXfont2.so.2",
    "libfontenc.so.1",
    "libxcb-cursor.so.0",
    "libxcb-image.so.0",
    "libxcb-render-util.so.0",
    "libxcb-render.so.0",
    "libxcb-shm.so.0",
    "libxcb-util.so.1",
    "libxcb.so.1",
    "libxcvt.so.0",
    "libxshmfence.so.1",
)
assert module["SANDBOX_LIFECYCLE_HELPER"] == (
    "/usr/local/libexec/labwc-zoom-discord-compat-runtime"
)
for app_name, sandbox_config in module["PERSISTENT_SANDBOX_CONFIG"].items():
    if app_name in module["WAYLAND_COMPAT_APPS"]:
        assert module["PRIVATE_RUNTIME_ROOT"] in sandbox_config["ro_bind_paths"]
    else:
        assert module["PRIVATE_RUNTIME_ROOT"] not in sandbox_config["ro_bind_paths"]
assert managed_library_path("discord") == module["DISCORD_ROOT"]
assert managed_library_path("zoom") == ""
for mode in ("launch", "intel", "nvidia"):
    discord_environment = build_environment("discord", mode)
    zoom_environment = build_environment("zoom", mode)
    assert discord_environment["PATH"] == managed_path
    assert zoom_environment["PATH"] == managed_path
    assert discord_environment["LD_LIBRARY_PATH"] == module["DISCORD_ROOT"]
    assert "LD_LIBRARY_PATH" not in zoom_environment
    assert "DISPLAY" not in discord_environment
    assert "DISPLAY" not in zoom_environment
    assert "XAUTHORITY" not in discord_environment
    assert "XAUTHORITY" not in zoom_environment
    assert module["PRIVATE_RUNTIME_ROOT"] not in discord_environment["PATH"]
    assert module["PRIVATE_RUNTIME_ROOT"] not in zoom_environment["PATH"]
for app_name in runtime_library_contract:
    for mode in ("launch", "intel", "nvidia"):
        managed_environment = build_environment(app_name, mode)
        assert managed_environment["PATH"] == managed_path
        assert "LD_PRELOAD" not in managed_environment
        assert "LD_AUDIT" not in managed_environment
        assert "PYTHONPATH" not in managed_environment
        assert "BASH_ENV" not in managed_environment
for app_name in generic_apps:
    assert module["PRIVATE_RUNTIME_ROOT"] not in build_environment(
        app_name, "launch"
    )["PATH"].split(os.pathsep)
    assert module["PRIVATE_RUNTIME_ROOT"] not in managed_library_path(
        app_name
    ).split(os.pathsep)

for app_name in generic_apps:
    for mode in ("launch", "intel", "nvidia"):
        argv = build_argv(app_name, mode, [])
        env = build_environment(app_name, mode)
        assert env["XDG_SESSION_TYPE"] == "wayland"
        assert env["WAYLAND_DISPLAY"]
        assert env["GDK_BACKEND"] == "wayland"
        assert env["GSK_RENDERER"] == "opengl"
        assert env["GDK_DISABLE"] == "vulkan"
        assert env["ANGLE_DEFAULT_PLATFORM"] == "gl"
        assert env["WGPU_BACKEND"] == "gl"
        assert env["SDL_RENDER_DRIVER"] == "opengl"
        assert env["GTK_CSD"] == "0"
        if app_name == "zoom":
            assert env["QT_QPA_PLATFORM"] == "xcb"
        else:
            assert env["QT_QPA_PLATFORM"] == "wayland"
        assert "DISPLAY" not in env
        assert env["QSG_RHI_BACKEND"] == "opengl"
        assert env["QT_WAYLAND_DISABLE_WINDOWDECORATION"] == "1"
        assert "XAUTHORITY" not in env
        assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in env)

for app_name in ("chromium", "microsoft-edge", "vivaldi", *electron_limits):
    for mode in ("launch", "intel", "nvidia"):
        argv = build_argv(app_name, mode, [])
        assert "--ozone-platform=wayland" in argv
        assert "--use-gl=angle" in argv
        assert "--use-angle=gl" in argv
        features = next(
            argument for argument in argv if argument.startswith("--enable-features=")
        )
        disabled_features = next(
            argument for argument in argv if argument.startswith("--disable-features=")
        )
        assert "UseOzonePlatform" in features
        assert "WaylandWindowDecorations" not in features
        assert "WaylandWindowDecorations" in disabled_features
        for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
            assert feature_name in disabled_features
        assert "--use-angle=vulkan" not in argv

assert apps["discord"]["pure_privacy"] is False
assert apps["tutanota"]["pure_privacy"] is False
for mode in ("launch", "intel", "nvidia"):
    discord_argv = build_argv("discord", mode, [])
    for forbidden_argument in (
        "--disable-gpu",
        "--disable-software-rasterizer",
        "--no-sandbox",
    ):
        assert forbidden_argument not in discord_argv
    assert "--ozone-platform=wayland" in discord_argv
    disabled_features = next(
        argument for argument in discord_argv if argument.startswith("--disable-features=")
    )
    for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
        assert feature_name in disabled_features
    assert "--use-angle=vulkan" not in discord_argv

for app_name in electron_limits:
    expected_js_flag = module["electron_js_flags"](app_name)
    for mode in ("intel", "nvidia"):
        js_flags = [
            argument
            for argument in build_argv(app_name, mode, [])
            if argument.startswith("--js-flags=--max-old-space-size=")
        ]
        assert js_flags == [expected_js_flag]
    if apps[app_name]["pure_privacy"]:
        privacy_js_flags = [
            argument
            for argument in pure_privacy_argv(app_name, [])
            if argument.startswith("--js-flags=--max-old-space-size=")
        ]
        assert privacy_js_flags == [expected_js_flag]

obsidian_launcher = next(
    config
    for config in launcher_module["APP_CONFIG"]
    if config["action_app"] == "obsidian"
)
assert obsidian_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
assert apps["obsidian"]["pure_privacy"] is False
postman_launcher = next(
    config
    for config in launcher_module["APP_CONFIG"]
    if config["action_app"] == "postman"
)
assert postman_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
assert apps["postman"]["pure_privacy"] is False
sleek_launcher = next(
    config
    for config in launcher_module["APP_CONFIG"]
    if config["action_app"] == "sleek"
)
assert sleek_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
assert apps["sleek"]["pure_privacy"] is False
tuta_launcher = next(
    config
    for config in launcher_module["APP_CONFIG"]
    if config["action_app"] == "tutanota"
)
assert tuta_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
discord_launcher = next(
    config
    for config in launcher_module["APP_CONFIG"]
    if config["action_app"] == "discord"
)
assert discord_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")

requested_acceleration_actions = (
    "IntelAccelerated",
    "NvidiaAccelerated",
    "PurePrivacy",
)
assert launcher_module["available_actions"](
    requested_acceleration_actions,
    {"intel": True, "nvidia": False},
) == ("IntelAccelerated", "PurePrivacy")
assert launcher_module["available_actions"](
    requested_acceleration_actions,
    {"intel": False, "nvidia": True},
) == ("NvidiaAccelerated", "PurePrivacy")
assert launcher_module["available_actions"](
    requested_acceleration_actions,
    {"intel": False, "nvidia": False},
) == ("PurePrivacy",)
for unavailable_mode in ("intel", "nvidia"):
    try:
        module["validate_acceleration_mode"](
            unavailable_mode,
            {"intel": False, "nvidia": False},
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError(
            f"managed app accepted unavailable {unavailable_mode} acceleration"
        )

for app_name in generic_apps:
    intel_env = build_environment(app_name, "intel")
    assert intel_env["DRI_PRIME"] == "0"
    assert intel_env["LIBVA_DRIVER_NAME"] == "iHD"
    nvidia_env = build_environment(app_name, "nvidia")
    assert nvidia_env["LIBVA_DRIVER_NAME"] == "nvidia"
    assert nvidia_env["NVD_BACKEND"] == "direct"
    assert nvidia_env["__NV_PRIME_RENDER_OFFLOAD"] == "1"
    assert nvidia_env["__GLX_VENDOR_LIBRARY_NAME"] == "nvidia"

privacy_env = pure_privacy_environment("chromium")
privacy_argv = pure_privacy_argv("chromium", [])
assert privacy_env["GSK_RENDERER"] == "opengl"
assert privacy_env["GDK_DISABLE"] == "vulkan"
assert privacy_env["QSG_RHI_BACKEND"] == "opengl"
assert privacy_env["ANGLE_DEFAULT_PLATFORM"] == "gl"
assert privacy_env["WGPU_BACKEND"] == "gl"
assert privacy_env["SDL_RENDER_DRIVER"] == "opengl"
assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in privacy_env)
assert "--use-angle=gl" in privacy_argv
assert "--use-angle=vulkan" not in privacy_argv
privacy_disabled_features = next(
    argument for argument in privacy_argv if argument.startswith("--disable-features=")
)
for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
    assert feature_name in privacy_disabled_features
assert "--disable-gpu" not in privacy_argv
assert apps["retroarch"]["privacy_home_ro_paths"] == (
    ".config/retroarch/retroarch.cfg",
)
assert apps["retroarch"]["privacy_share_net"] is False
assert apps["keepassxc"]["privacy_share_net"] is False

mullvad_privacy_env = pure_privacy_environment("mullvad-browser")
mullvad_privacy_argv = pure_privacy_argv("mullvad-browser", [])
assert mullvad_privacy_env["MOZ_WEBRENDER"] == "1"
assert mullvad_privacy_env["MOZ_WEBRENDER_SOFTWARE"] == "1"
assert mullvad_privacy_env["GSK_RENDERER"] == "opengl"
assert mullvad_privacy_env["GDK_DISABLE"] == "vulkan"
assert mullvad_privacy_env["QSG_RHI_BACKEND"] == "opengl"
assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in mullvad_privacy_env)
assert not any(argument.startswith("--use-gl=") for argument in mullvad_privacy_argv)
assert not any(argument.startswith("--use-angle=") for argument in mullvad_privacy_argv)
for variable in (
    "LIBGL_ALWAYS_SOFTWARE",
    "GALLIUM_DRIVER",
    "MESA_LOADER_DRIVER_OVERRIDE",
):
    assert variable not in mullvad_privacy_env
validate_pure_privacy_device_isolation(
    "mullvad-browser",
    ["bwrap", "--bind", "/tmp/wayland-0", "/run/user/1000/wayland-0"],
)
try:
    validate_pure_privacy_device_isolation(
        "mullvad-browser",
        ["bwrap", "--dev-bind", "/dev/nvidia0", "/dev/nvidia0"],
    )
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("Mullvad PurePrivacy accepted NVIDIA device access")

assert "keepassxc" not in module["PERSISTENT_SANDBOX_CONFIG"]
assert apps["keepassxc"].get("persistent_sandbox", False) is False
tutanota_sandbox = module["PERSISTENT_SANDBOX_CONFIG"]["tutanota"]
assert tutanota_sandbox["require_session_bus"] is True
assert "require_system_bus" not in tutanota_sandbox
assert "system_dbus_names" not in tutanota_sandbox
assert tutanota_sandbox["dbus_names"] == (
    "org.freedesktop.secrets",
)
assert "privacy_dbus_names" not in apps["tutanota"]
assert "privacy_system_bus_proxy" not in apps["tutanota"]
assert tutanota_sandbox["ro_bind_home_paths"] == (
    ".config/mimeapps.list",
    ".config/user-dirs.dirs",
)
assert tutanota_sandbox["ro_bind_home_directories"] == (
    "Desktop",
    "Documents",
    "Music",
    "Pictures",
    "Public",
    "Templates",
    "Videos",
)
assert tutanota_sandbox["rw_bind_home_directories"] == ("Downloads",)
assert module["SYSTEM_BUS_SOCKET_PATH"] == "/run/dbus/system_bus_socket"
for app_name in module["WAYLAND_COMPAT_APPS"]:
    sandbox_config = module["PERSISTENT_SANDBOX_CONFIG"][app_name]
    assert sandbox_config["camera_devices"] is True
    assert sandbox_config["require_system_bus"] is True
    assert sandbox_config["share_net"] is False
    assert sandbox_config["slirp4netns"] is True
    assert sandbox_config["system_dbus_names"] == ()

with tempfile.TemporaryDirectory() as compatibility_temp_root:
    resolver_path = module["create_slirp4netns_resolver_file"](
        compatibility_temp_root
    )
    with open(resolver_path, encoding="utf-8") as resolver_handle:
        assert resolver_handle.read() == module["slirp4netns_resolv_conf"]()
    assert oct(os.stat(resolver_path).st_mode & 0o777) == "0o600"

    wayland_command = []
    wayland_lock_fd = module["reserve_outer_wayland_socket_name"](
        wayland_command,
        compatibility_temp_root,
        "/run/user/1000",
        "wayland-0",
    )
    try:
        lock_source = wayland_command[-2]
        assert wayland_command[-3:] == [
            "--bind",
            lock_source,
            "/run/user/1000/wayland-0.lock",
        ]
        assert oct(os.stat(lock_source).st_mode & 0o777) == "0o600"
        contender_fd = os.open(lock_source, os.O_RDWR | os.O_CLOEXEC)
        try:
            try:
                fcntl.flock(contender_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                raise AssertionError(
                    "outer Wayland socket reservation did not hold its lock"
                )
        finally:
            os.close(contender_fd)
    finally:
        os.close(wayland_lock_fd)
assert "xdg_config_home" not in apps["zoom"]
assert module["PERSISTENT_SANDBOX_CONFIG"]["zoom"]["persistent_directory_binds"] == (
    (module["ZOOM_CONFIG_SOURCE"], ".config"),
)
assert build_environment("zoom", "launch")["XDG_CONFIG_HOME"].endswith("/.config")
system_bus_command = []
add_system_bus_proxy_bind(system_bus_command, "/run/user/1000/private-system-bus")
assert system_bus_command[-3:] == [
    "--bind",
    "/run/user/1000/private-system-bus",
    "/run/dbus/system_bus_socket",
]
saved_session_bus_address = os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)
try:
    try:
        start_session_bus_proxy("/tmp", required=True)
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("Tuta accepted a missing secret-storage session bus")
finally:
    if saved_session_bus_address is not None:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = saved_session_bus_address
with tempfile.TemporaryDirectory() as attachment_home:
    documents_dir = os.path.join(attachment_home, "Documents")
    downloads_dir = os.path.join(attachment_home, "Downloads")
    os.mkdir(documents_dir, mode=0o700)
    os.mkdir(downloads_dir, mode=0o700)
    attachment_command = []
    module["add_home_directory_binds"](
        attachment_command,
        attachment_home,
        ("Documents", "Missing"),
        "--ro-bind",
    )
    assert attachment_command[-3:] == [
        "--ro-bind",
        documents_dir,
        documents_dir,
    ]
    assert not any("Missing" in argument for argument in attachment_command)
    module["add_home_directory_binds"](
        attachment_command,
        attachment_home,
        ("Downloads",),
        "--bind",
    )
    assert attachment_command[-3:] == [
        "--bind",
        downloads_dir,
        downloads_dir,
    ]
    zoom_bind_command = []
    module["add_persistent_directory_binds"](
        zoom_bind_command,
        attachment_home,
        ((module["ZOOM_CONFIG_SOURCE"], ".config"),),
    )
    zoom_config_source = os.path.join(
        attachment_home,
        module["ZOOM_CONFIG_SOURCE"],
    )
    assert os.path.isdir(zoom_config_source)
    assert oct(os.stat(zoom_config_source).st_mode & 0o777) == "0o700"
    assert zoom_bind_command[-3:] == [
        "--bind",
        zoom_config_source,
        os.path.join(attachment_home, ".config"),
    ]

try:
    build_argv("chromium", "launch", ["--use-angle=gl"])
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("OpenGL overrides must be rejected")
PY
then
  pass "managed apps enforce launch, acceleration, and bounded Electron memory policies"
else
  fail "managed apps enforce launch, acceleration, and bounded Electron memory policies"
fi

gtk3_settings_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/gtk-3.0/settings.ini.tmpl"
gtk4_settings_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/gtk-4.0/settings.ini.tmpl"
wlr_labwc_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
desktop_policy_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
f2fs_desktop_policy_env="$ROOT_DIR/d-i/forky/hosts/profiles/f2fs/desktop.env"
desktop_detect="$ROOT_DIR/d-i/forky/scripts/desktop/detect.sh"
swayidle_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-swayidle"
if grep -q '^gtk-font-name=Noto Sans __INSTALLER_LABWC_GTK_FONT_SIZE__$' "$gtk3_settings_template" &&
   grep -q '^gtk-font-name=Noto Sans __INSTALLER_LABWC_GTK_FONT_SIZE__$' "$gtk4_settings_template" &&
   grep -q '<policy>center</policy>' "$wlr_labwc_template" &&
   grep -q '<repeatRate>__INSTALLER_LABWC_KEYBOARD_REPEAT_RATE__</repeatRate>' "$wlr_labwc_template" &&
   grep -q '<repeatDelay>__INSTALLER_LABWC_KEYBOARD_REPEAT_DELAY__</repeatDelay>' "$wlr_labwc_template" &&
   grep -q '__INSTALLER_LABWC_FONT_WINDOW_SIZE__' "$wlr_labwc_template" &&
   grep -q '__INSTALLER_LABWC_FONT_MENU_SIZE__' "$wlr_labwc_template" &&
   grep -q '__INSTALLER_LABWC_FONT_OSD_SIZE__' "$wlr_labwc_template" &&
   grep -q '<device category="non-touch">' "$wlr_labwc_template" &&
   grep -q '<pointerSpeed>__INSTALLER_LABWC_MOUSE_POINTER_SPEED__</pointerSpeed>' "$wlr_labwc_template" &&
   grep -q '<accelProfile>__INSTALLER_LABWC_MOUSE_ACCEL_PROFILE__</accelProfile>' "$wlr_labwc_template" &&
   grep -q '<device category="touchpad">' "$wlr_labwc_template" &&
   grep -q '<tap>yes</tap>' "$wlr_labwc_template" &&
   grep -q '<tapButtonMap>lrm</tapButtonMap>' "$wlr_labwc_template" &&
   grep -q '<disableWhileTyping>yes</disableWhileTyping>' "$wlr_labwc_template" &&
   grep -q '<tapAndDrag>no</tapAndDrag>' "$wlr_labwc_template" &&
   grep -q '<dragLock>no</dragLock>' "$wlr_labwc_template" &&
   grep -q '<clickMethod>clickfinger</clickMethod>' "$wlr_labwc_template" &&
   grep -q '<scrollMethod>twofinger</scrollMethod>' "$wlr_labwc_template" &&
   grep -q '<keybind key="W-l">' "$wlr_labwc_template" &&
   grep -q 'command="labwc-lock"' "$wlr_labwc_template" &&
   grep -q '<keybind key="Super_L" onRelease="yes">' "$wlr_labwc_template" &&
   sed -n '/<keybind key="Super_L" onRelease="yes">/,/<\/keybind>/p' "$wlr_labwc_template" |
     grep -q '<action name="Execute" command="labwc-run" />' &&
   grep -q '^LABWC_KEYBOARD_REPEAT_RATE="40"$' "$desktop_policy_env" &&
   grep -q '^LABWC_KEYBOARD_REPEAT_DELAY="250"$' "$desktop_policy_env" &&
   grep -q '^LABWC_IDLE_LOCK_SECONDS="1800"$' "$desktop_policy_env" &&
   grep -q '^LABWC_IDLE_DPMS_SECONDS="3600"$' "$desktop_policy_env" &&
   grep -q '^LABWC_FONT_WINDOW_SIZE="12"$' "$desktop_policy_env" &&
   grep -q '^LABWC_FONT_MENU_SIZE="13"$' "$desktop_policy_env" &&
   grep -q '^LABWC_FONT_OSD_SIZE="13"$' "$desktop_policy_env" &&
   grep -q '^LABWC_MOUSE_POINTER_SPEED="0.55"$' "$desktop_policy_env" &&
   grep -q '^LABWC_MOUSE_ACCEL_PROFILE="flat"$' "$desktop_policy_env" &&
   grep -q '^LABWC_GTK_FONT_SIZE="12"$' "$desktop_policy_env" &&
   grep -q '^LABWC_QT_FONT_SIZE="11"$' "$desktop_policy_env" &&
   grep -q '^LABWC_QT_FIXED_FONT_SIZE="12"$' "$desktop_policy_env" &&
   grep -q '^LABWC_FUZZEL_FONT_SIZE="15"$' "$desktop_policy_env" &&
   grep -q '^LABWC_FONT_WINDOW_SIZE="11"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_FONT_MENU_SIZE="12"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_FONT_OSD_SIZE="12"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_WAYBAR_FONT_SIZE="14"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_GTK_FONT_SIZE="11"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_QT_FONT_SIZE="10"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_QT_FIXED_FONT_SIZE="11"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_GREETER_FONT_SIZE="16"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_FUZZEL_FONT_SIZE="14"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_APP_MENU_FONT_SIZE="14"$' "$f2fs_desktop_policy_env" &&
   grep -q '^LABWC_ICON_THEME="Papirus-Dark"$' "$f2fs_desktop_policy_env" &&
   grep -q 'desktop_validate_uint_range LABWC_QT_FONT_SIZE "${LABWC_QT_FONT_SIZE:-11}" 8 32' "$desktop_detect" &&
   grep -q 'desktop_validate_theme_name LABWC_ICON_THEME "${LABWC_ICON_THEME:-Papirus-Dark}"' "$desktop_detect" &&
   grep -q 'desktop_validate_uint_range LABWC_IDLE_LOCK_SECONDS "${LABWC_IDLE_LOCK_SECONDS:-1800}" 60 86400' "$desktop_detect" &&
   grep -q 'desktop_validate_uint_range LABWC_IDLE_DPMS_SECONDS "${LABWC_IDLE_DPMS_SECONDS:-3600}" 60 86400' "$desktop_detect" &&
   grep -q 'LABWC_IDLE_DPMS_SECONDS must be greater than LABWC_IDLE_LOCK_SECONDS' "$desktop_detect" &&
   grep -q 'lock_seconds=${LABWC_IDLE_LOCK_SECONDS:-1800}' "$swayidle_wrapper" &&
   grep -q 'dpms_seconds=${LABWC_IDLE_DPMS_SECONDS:-3600}' "$swayidle_wrapper" &&
   grep -q 'require_idle_timeout_order "$lock_seconds" "$dpms_seconds" "$suspend_seconds"' "$swayidle_wrapper" &&
   grep -q 'LABWC_IDLE_DPMS_SECONDS (%s) must be greater than LABWC_IDLE_LOCK_SECONDS (%s)' "$swayidle_wrapper" &&
   grep -q "resume 'labwc-output-refresh --dpms-on'" "$swayidle_wrapper" &&
   grep -q "after-resume 'labwc-output-refresh --dpms-on'" "$swayidle_wrapper" &&
   grep -q 'lock labwc-lock' "$swayidle_wrapper" &&
   grep -q '^font=Noto Sans:size=__INSTALLER_LABWC_FUZZEL_FONT_SIZE__' "$fuzzel_base_template"; then
  pass "desktop typography stays profile-driven with compact F2FS internal-screen fonts"
else
  fail "desktop typography stays profile-driven with compact F2FS internal-screen fonts"
fi

profile_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile"
bash_profile_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.bash_profile"
bashrc_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.bashrc"
bash_aliases_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.bash_aliases"
zshenv_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zshenv"
zprofile_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zprofile"
zshrc_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zshrc"
zlogout_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zlogout"
zsh_aliases_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zsh_aliases"
labwc_session_file="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-session.tmpl"
if ! grep -q '^alias ' "$profile_file" &&
   sh -n "$profile_file" &&
   bash -n "$bash_profile_file" &&
   bash -n "$bashrc_file" &&
   bash -n "$bash_aliases_file" &&
   zsh -n "$zshenv_file" &&
   zsh -n "$zprofile_file" &&
   zsh -n "$zshrc_file" &&
   zsh -n "$zlogout_file" &&
   zsh -n "$zsh_aliases_file" &&
   grep -q '^profile_init_xdg_env() {$' "$profile_file" &&
   grep -q '^profile_init_fzf_env() {$' "$profile_file" &&
   grep -q '^  profile_append_path_if_dir /usr/local/cuda-12-8/bin$' "$profile_file" &&
   grep -q '^  zshenv_append_path_if_dir "/usr/local/cuda-12-8/bin"$' "$zshenv_file" &&
   grep -q '^  profile_append_path_if_dir /data/bin$' "$profile_file" &&
   ! grep -q '\. "\$HOME/\.bashrc"' "$profile_file" &&
   ! grep -q '\. "\$HOME/\.zshrc"' "$profile_file" &&
   grep -q '^bash_profile_is_interactive() {$' "$bash_profile_file" &&
   grep -q 'bash_profile_source_if_readable "\$HOME/\.profile"' "$bash_profile_file" &&
   grep -q 'bash_profile_source_if_readable "\$HOME/\.bashrc"' "$bash_profile_file" &&
   grep -q '^bashrc_init_history() {$' "$bashrc_file" &&
   grep -q '^bashrc_load_profile_fragments() {$' "$bashrc_file" &&
   grep -q 'bashrc_source_if_readable "\$profile_fragment"' "$bashrc_file" &&
   grep -q '^bashrc_init_devops_completions() {$' "$bashrc_file" &&
   grep -q 'declare -F devops_de_enable_shell_completions' "$bashrc_file" &&
   ! grep -q '^export __MCR_MANAGED_BASHRC_LOADED$' "$bashrc_file" &&
   grep -q '^bashrc_init_prompt() {$' "$bashrc_file" &&
   grep -q 'bashrc_source_if_readable "\$HOME/\.bash_aliases"' "$bashrc_file" &&
   grep -q "^alias ll='ls -lah --color=auto'$" "$bash_aliases_file" &&
   ! grep -q 'luks-mok-' "$bashrc_file" &&
   grep -q '^zprofile_source_sh_file() {$' "$zprofile_file" &&
   grep -q 'zprofile_source_sh_file /etc/profile' "$zprofile_file" &&
   grep -q 'zprofile_source_sh_file "\$HOME/\.profile"' "$zprofile_file" &&
   ! grep -q '\. "\$HOME/\.profile"' "$zshenv_file" &&
   ! grep -q '\. "\$HOME/\.zprofile"' "$zshenv_file" &&
   grep -q '^zshrc_init_completion() {$' "$zshrc_file" &&
   grep -q '^zshrc_load_profile_fragments() {$' "$zshrc_file" &&
   grep -q 'zshrc_source_sh_file "\$profile_fragment"' "$zshrc_file" &&
   grep -q '^zshrc_init_devops_completions() {$' "$zshrc_file" &&
   grep -q 'functions\[devops_de_enable_shell_completions\]' "$zshrc_file" &&
   grep -q '^zshrc_init_prompt() {$' "$zshrc_file" &&
   grep -Fq 'if (( ${+functions[devops_de_enable_zsh_terminal_title]} )); then' "$zshrc_file" &&
   grep -Fq '  devops_de_enable_zsh_terminal_title' "$zshrc_file" &&
   grep -q '^    ZSH_HIGHLIGHT_MAXLENGTH="\${ZSH_HIGHLIGHT_MAXLENGTH:-512}"$' "$zshrc_file" &&
   grep -q '^    typeset -gA ZSH_HIGHLIGHT_STYLES$' "$zshrc_file" &&
   grep -q '^    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)$' "$zshrc_file" &&
   grep -Fq '[[ -o interactive ]] || return 0' "$zshrc_file" &&
   ! grep -Fq '[[ -o zle ]]' "$zshrc_file" &&
   ! grep -q '\. "\$HOME/\.profile"' "$zshrc_file" &&
   ! grep -q '\. "\$HOME/\.zprofile"' "$zshrc_file" &&
   grep -q 'zshrc_source_if_readable "\$HOME/\.zsh_aliases"' "$zshrc_file" &&
   grep -q '^alias ll=' "$zsh_aliases_file" &&
   grep -q '^\[\[ -o interactive \]\] || return 0$' "$zlogout_file" &&
   ! grep -q 'luks-mok-' "$zshrc_file" &&
   ! grep -q 'ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)' "$zshrc_file" &&
   grep -q 'starship init zsh' "$zshrc_file" &&
   grep -q '\. "\$HOME/\.profile"' "$labwc_session_file"; then
  pass "desktop shell dotfiles keep login env in .profile/.zprofile, keep .zshrc interactive-only, finalize the DevOps title hook, and stay syntax-valid"
else
  fail "desktop shell dotfiles keep login env in .profile/.zprofile, keep .zshrc interactive-only, finalize the DevOps title hook, and stay syntax-valid"
fi

zsh_highlight_out="$TMP_DIR/zsh-highlight.out"
zsh_highlight_err="$TMP_DIR/zsh-highlight.err"
if [ ! -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] ||
   env -i \
    HOME="$TMP_DIR/zsh-highlight-home" \
    USER=test \
    LOGNAME=test \
    SHELL=/bin/zsh \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
    ZSHRC_UNDER_TEST="$zshrc_file" \
    zsh -f -ic '
      # The development host can lack zsh completion autoload files even
      # though the target package set supplies them. Keep this probe focused
      # on our syntax-highlighting initialization contract.
      compinit() {
        return 0
      }
      starship() {
        return 1
      }
      source "$ZSHRC_UNDER_TEST"
      [[ ${(t)ZSH_HIGHLIGHT_STYLES} == association* ]] || exit 1
      [[ -n ${ZSH_HIGHLIGHT_STYLES[path]:-} ]] || exit 1
    ' >"$zsh_highlight_out" 2>"$zsh_highlight_err" &&
   ! grep -q '_zsh_highlight_add_highlight.*bad math expression' "$zsh_highlight_err"; then
  pass "zsh syntax highlighting preserves global style state for absolute paths"
else
  fail "zsh syntax highlighting preserves global style state for absolute paths"
fi

shell_home="$TMP_DIR/shell-home"
rm -rf "$shell_home"
mkdir -p "$shell_home/.profile.d" "$shell_home/.config/fzf"
for rel_file in .profile .bash_profile .bashrc .bash_aliases .zshenv .zprofile .zshrc .zlogout .zsh_aliases; do
  cp "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/$rel_file" "$shell_home/$rel_file"
done
printf '%s\n' 'export PROFILE_FRAGMENT_MARKER=ok' >"$shell_home/.profile.d/10-test.sh"
printf '%s\n' 'PROFILE_FRAGMENT_LOAD_COUNT=$((${PROFILE_FRAGMENT_LOAD_COUNT:-0} + 1))' >>"$shell_home/.profile.d/10-test.sh"
printf '%s\n' 'export PROFILE_FRAGMENT_LOAD_COUNT' >>"$shell_home/.profile.d/10-test.sh"
printf '%s\n' '--layout=reverse' >"$shell_home/.config/fzf/default-opts"
bash_shell_out="$TMP_DIR/bash-shell.out"
zsh_shell_out="$TMP_DIR/zsh-shell.out"
bash_terminal_out="$TMP_DIR/bash-terminal.out"
zsh_terminal_out="$TMP_DIR/zsh-terminal.out"
if env -i \
    HOME="$shell_home" \
    USER=test \
    LOGNAME=test \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
    bash --noprofile --norc -ic '
      . "$HOME/.bash_profile"
      printf "PROFILE=%s\nCOUNT=%s\nXDG=%s\nFZF=%s\n" \
        "${PROFILE_FRAGMENT_MARKER:-missing}" \
        "${PROFILE_FRAGMENT_LOAD_COUNT:-missing}" \
        "${XDG_CONFIG_HOME:-missing}" \
        "${FZF_DEFAULT_OPTS:-missing}"
      alias ll
    ' >"$bash_shell_out" 2>&1 &&
   env -i \
    HOME="$shell_home" \
    USER=test \
    LOGNAME=test \
    SHELL=/bin/zsh \
    ZDOTDIR="$shell_home" \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
    zsh -f -ic '
      source "$HOME/.zshenv"
      source "$HOME/.zprofile"
      source "$HOME/.zshrc"
      printf "PROFILE=%s\nCOUNT=%s\nXDG=%s\nFZF=%s\n" \
        "${PROFILE_FRAGMENT_MARKER:-missing}" \
        "${PROFILE_FRAGMENT_LOAD_COUNT:-missing}" \
        "${XDG_CONFIG_HOME:-missing}" \
        "${FZF_DEFAULT_OPTS:-missing}"
    ' >"$zsh_shell_out" 2>&1 &&
   env -i \
    HOME="$shell_home" \
    USER=test \
    LOGNAME=test \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
    __MCR_MANAGED_PROFILE_LOADED=1 \
    bash --noprofile --norc -ic '
      . "$HOME/.bashrc"
      printf "PROFILE=%s\nCOUNT=%s\n" \
        "${PROFILE_FRAGMENT_MARKER:-missing}" \
        "${PROFILE_FRAGMENT_LOAD_COUNT:-missing}"
    ' >"$bash_terminal_out" 2>&1 &&
   env -i \
    HOME="$shell_home" \
    USER=test \
    LOGNAME=test \
    SHELL=/bin/zsh \
    ZDOTDIR="$shell_home" \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
    __MCR_MANAGED_PROFILE_LOADED=1 \
    zsh -f -ic '
      source "$HOME/.zshenv"
      source "$HOME/.zshrc"
      printf "PROFILE=%s\nCOUNT=%s\n" \
        "${PROFILE_FRAGMENT_MARKER:-missing}" \
        "${PROFILE_FRAGMENT_LOAD_COUNT:-missing}"
    ' >"$zsh_terminal_out" 2>&1 &&
   grep -q '^PROFILE=ok$' "$bash_shell_out" &&
   grep -q '^COUNT=1$' "$bash_shell_out" &&
   grep -q '^XDG='"$shell_home"'/.config$' "$bash_shell_out" &&
   grep -q '^FZF=--layout=reverse *$' "$bash_shell_out" &&
   grep -q "ll='ls -lah --color=auto'" "$bash_shell_out" &&
   grep -q '^PROFILE=ok$' "$zsh_shell_out" &&
   grep -q '^COUNT=1$' "$zsh_shell_out" &&
   grep -q '^XDG='"$shell_home"'/.config$' "$zsh_shell_out" &&
   grep -q '^FZF=--layout=reverse *$' "$zsh_shell_out" &&
   grep -q '^PROFILE=ok$' "$bash_terminal_out" &&
   grep -q '^COUNT=1$' "$bash_terminal_out" &&
   grep -q '^PROFILE=ok$' "$zsh_terminal_out" &&
   grep -q '^COUNT=1$' "$zsh_terminal_out"; then
  pass "desktop shell startup loads profile fragments once in Bash and Zsh login and terminal flows"
else
  fail "desktop shell startup loads profile fragments once in Bash and Zsh login and terminal flows"
fi

if grep -q '^TerminalEmulator=foot$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/xfce4/helpers.rc" &&
   grep -q '^foot.desktop$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/xdg-terminals.list" &&
   grep -q '^X-XFCE-Category=TerminalEmulator$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/xfce4/helpers/foot.desktop"; then
  pass "Foot is registered as the XFCE and xdg terminal default"
else
  fail "Foot is registered as the XFCE and xdg terminal default"
fi

thunar_uca="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/Thunar/uca.xml"
thunar_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml"
labwc_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
labwc_theme="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/themerc-override"
mimeapps_list="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mimeapps.list"
xdg_mimeapps_list="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/xdg/mimeapps.list"
polkit_pam="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/pam.d/polkit-1"
systemd_user_pam="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/pam.d/systemd-user"
swaylock_pam="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/pam.d/swaylock"
if grep -q '\.config/Thunar' "$desktop_components" &&
   grep -q 'etc/skel/.config/mimeapps.list' "$desktop_components" &&
   grep -q 'etc/xdg/mimeapps.list' "$desktop_components" &&
   grep -q '/etc/pam.d/polkit-1' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/pam.d/systemd-user' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '<icon>__INSTALLER_LABWC_ICON_THEME__</icon>' "$labwc_rc_template" &&
   grep -q '<showIcons>yes</showIcons>' "$labwc_rc_template" &&
   grep -q '^desktop_verify_optional_staged_files() {$' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q 'label="Terminal" icon="utilities-terminal"' "$labwc_menu" &&
   grep -q 'label="Applications" icon="applications-system"' "$labwc_menu" &&
   grep -q 'label="Files" icon="system-file-manager"' "$labwc_menu" &&
   grep -q 'menu id="productivity-menu" label="Productivity" icon="applications-office"' "$labwc_menu" &&
   grep -q 'menu id="organizer-menu" label="Calendar &amp; Tasks" icon="office-calendar"' "$labwc_menu" &&
   grep -q 'menu id="utilities-menu" label="Media &amp; Utilities" icon="applications-utilities"' "$labwc_menu" &&
   grep -q 'menu id="desktop-settings-menu" label="Desktop Settings" icon="preferences-system"' "$labwc_menu" &&
   grep -q 'label="Text Editor" icon="featherpad"' "$labwc_menu" &&
   grep -q 'label="Diff / Merge Tool" icon="kdiff3"' "$labwc_menu" &&
   grep -q 'label="Calculator" icon="qalculate-qt"' "$labwc_menu" &&
   grep -q 'label="Spreadsheet" icon="gnumeric"' "$labwc_menu" &&
   grep -q 'label="Writing" icon="focuswriter"' "$labwc_menu" &&
   grep -q 'label="PDF Viewer" icon="org.pwmt.zathura"' "$labwc_menu" &&
   grep -q 'label="RetroArch" icon="retroarch"' "$labwc_menu" &&
   grep -q 'label="System Monitor" icon="utilities-system-monitor"' "$labwc_menu" &&
   grep -q 'label="Audio" icon="multimedia-volume-control"' "$labwc_menu" &&
   grep -q 'label="Appearance" icon="preferences-desktop-theme"' "$labwc_menu" &&
   grep -q 'label="Labwc Tweaks" icon="labwc_tweaks"' "$labwc_menu" &&
   grep -q 'command="labwc-tweaks"' "$labwc_menu" &&
   grep -q 'label="Qt6 Settings" icon="qt6ct"' "$labwc_menu" &&
   grep -q 'command="qt6ct"' "$labwc_menu" &&
   grep -q 'label="Calendar" icon="office-calendar"' "$labwc_menu" &&
   grep -q 'command="labwc-calendar"' "$labwc_menu" &&
   grep -q 'label="Tasks" icon="view-calendar-tasks"' "$labwc_menu" &&
   grep -q 'command="labwc-calendar tasks"' "$labwc_menu" &&
   grep -q 'label="Calendar Actions" icon="view-calendar-day"' "$labwc_menu" &&
   grep -q 'command="labwc-calendar menu"' "$labwc_menu" &&
   grep -q 'label="Refresh Outputs" icon="view-refresh"' "$labwc_menu" &&
   grep -q 'label="Restart Dock" icon="view-refresh"' "$labwc_menu" &&
   grep -q 'label="Lock" icon="system-lock-screen"' "$labwc_menu" &&
   grep -q 'label="Power" icon="system-shutdown"' "$labwc_menu" &&
   grep -q 'label="Reconfigure" icon="preferences-system"' "$labwc_menu" &&
   grep -q 'label="Close Window" icon="window-close"' "$labwc_menu" &&
   grep -q 'label="Logout" icon="system-log-out"' "$labwc_menu" &&
   grep -q 'command="labwc-logout"' "$labwc_menu" &&
   grep -q '^menu.width.min: 170$' "$labwc_theme" &&
   grep -q '^menu.width.max: 340$' "$labwc_theme" &&
   grep -q '^menu.items.padding.x: 6$' "$labwc_theme" &&
   grep -q '^menu.items.padding.y: 3$' "$labwc_theme" &&
   grep -q 'name="last-icon-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_100_PERCENT"' "$thunar_preferences" &&
   grep -q 'name="last-details-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_38_PERCENT"' "$thunar_preferences" &&
   grep -q 'name="last-compact-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_38_PERCENT"' "$thunar_preferences" &&
   grep -q 'name="shortcuts-icon-size" type="string" value="THUNAR_ICON_SIZE_24"' "$thunar_preferences" &&
   grep -q 'name="tree-icon-size" type="string" value="THUNAR_ICON_SIZE_24"' "$thunar_preferences" &&
   grep -q '^inode/directory=thunar.desktop;$' "$mimeapps_list" &&
   grep -q '^application/x-directory=thunar.desktop;$' "$mimeapps_list" &&
   grep -q '^x-directory/normal=thunar.desktop;$' "$mimeapps_list" &&
   grep -q '^x-scheme-handler/file=thunar.desktop;$' "$mimeapps_list" &&
   grep -q '^x-scheme-handler/mailto=tuta-mail.desktop;$' "$mimeapps_list" &&
   grep -q '^message/rfc822=tuta-mail.desktop;$' "$mimeapps_list" &&
   grep -q '^inode/directory=thunar.desktop;$' "$xdg_mimeapps_list" &&
   grep -q '^application/x-directory=thunar.desktop;$' "$xdg_mimeapps_list" &&
   grep -q '^x-directory/normal=thunar.desktop;$' "$xdg_mimeapps_list" &&
   grep -q '^@include common-auth$' "$polkit_pam" &&
   grep -q '^@include common-session-noninteractive$' "$polkit_pam" &&
   grep -q '^account  sufficient pam_usertype\.so issystem$' "$systemd_user_pam" &&
   grep -q '^@include common-account$' "$systemd_user_pam" &&
   grep -q '^session  optional pam_systemd.so$' "$systemd_user_pam" &&
   grep -q '^#%PAM-1\.0$' "$swaylock_pam" &&
   grep -q '^@include common-auth$' "$swaylock_pam" &&
   grep -q '^@include common-account$' "$swaylock_pam" &&
   ! grep -q '^@include common-session' "$swaylock_pam" &&
   grep -q '<icon>utilities-terminal</icon>' "$thunar_uca" &&
   grep -q '<icon>package-x-generic</icon>' "$thunar_uca" &&
   grep -q '<name>Extract Text With OCR</name>' "$thunar_uca" &&
   grep -q '<command>labwc-ocr %f</command>' "$thunar_uca"; then
  pass "Labwc and Thunar context menus stage explicit icon coverage, deterministic directory MIME handling, and Debian PAM policies for desktop login and locking"
else
  fail "Labwc and Thunar context menus stage explicit icon coverage, deterministic directory MIME handling, and Debian PAM policies for desktop login and locking"
fi

portal_conf="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/xdg/xdg-desktop-portal/labwc-portals.conf"
shutdown_hook="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/shutdown"
labwc_user_target="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-session.target"
labwc_compositor_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-compositor.service"
user_manager_seatd_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/user@.service.d/20-labwc-seatd.conf"
greetd_service_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/greetd.service.d/20-labwc-vt.conf"
kwallet_portal_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-kwallet-portal.service"
kwallet_daemon_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-kwalletd6.service"
portal_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/xdg-desktop-portal.service.d/10-labwc-session.conf"
lxqt_portal_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/xdg-desktop-portal-lxqt.service.d/10-labwc-session.conf"
hypr_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/hyprpolkitagent.service.d/10-labwc-session.conf"
gvfs_daemon_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/gvfs-daemon.service.d/10-labwc-session.conf"
gvfs_udisks_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/gvfs-udisks2-volume-monitor.service.d/10-labwc-session.conf"
kwallet_portal_activation="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service"
kwallet_secrets_activation="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/dbus-1/services/org.freedesktop.secrets.service"
kwallet_compat_activation="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/dbus-1/services/org.kde.secretservicecompat.service"
kwallet_daemon_activation="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.local/share/dbus-1/services/org.kde.kwalletd6.service"
if grep -q '^org.freedesktop.impl.portal.ScreenCast=wlr$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Screenshot=wlr$' "$portal_conf" &&
   grep -q '^default=none$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.RemoteDesktop=wlr$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.FileChooser=lxqt$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Secret=kwallet$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Notification=gtk$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Inhibit=gtk$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Settings=gtk$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.DynamicLauncher=gtk$' "$portal_conf" &&
   grep -q '^desktop_stage_global_user_unit_dropin_asset() {$' "$desktop_components" &&
   grep -q '^desktop_stage_labwc_package_user_unit_dropins() {$' "$desktop_components" &&
   grep -q '^desktop_stage_kwallet_dbus_activation_assets() {$' "$desktop_components" &&
   grep -q 'desktop_stage_labwc_user_session_assets' "$desktop_components" &&
   ! grep -q '^\[D-BUS Service\]$' "$desktop_components" &&
   ! grep -q 'dpkg-divert' "$desktop_components" &&
   ! grep -q 'verify_account_session_dropin' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q 'primary account package-unit drop-in is still present' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q 'xdg-desktop-portal-lxqt.service' "$desktop_components" &&
   [ ! -e "$kwallet_portal_activation" ] &&
   grep -q '^Name=org.freedesktop.secrets$' "$kwallet_secrets_activation" &&
   grep -q '^SystemdService=labwc-kwallet-portal.service$' "$kwallet_secrets_activation" &&
   [ ! -e "$kwallet_compat_activation" ] &&
   [ ! -e "$kwallet_daemon_activation" ] &&
   [ ! -e "$kwallet_daemon_unit" ] &&
   grep -q 'etc/skel/.local/share/dbus-1/services/org.freedesktop.secrets.service' "$desktop_components" &&
   ! grep -q 'etc/skel/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service' "$desktop_components" &&
   ! grep -q 'etc/skel/.local/share/dbus-1/services/org.kde.secretservicecompat.service' "$desktop_components" &&
   ! grep -q 'etc/skel/.local/share/dbus-1/services/org.kde.kwalletd6.service' "$desktop_components" &&
   ! grep -q 'labwc-kwalletd6.service' "$desktop_components" &&
   ! grep -q '/etc/systemd/user/labwc-kwallet' "$desktop_components" &&
   grep -q '^Environment=QT_QPA_PLATFORM=wayland$' "$lxqt_portal_dropin" &&
   grep -q '^Environment=QT_NO_XDG_DESKTOP_PORTAL=1$' "$lxqt_portal_dropin" &&
   grep -q '/etc/skel/.config/systemd/user/labwc-kwallet-portal.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/skel/.local/share/dbus-1/services/org.freedesktop.secrets.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   ! grep -q '/etc/skel/.config/systemd/user/labwc-kwalletd6.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   ! grep -q '/etc/skel/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   ! grep -q '/etc/skel/.local/share/dbus-1/services/org.kde.secretservicecompat.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   ! grep -q '/etc/skel/.local/share/dbus-1/services/org.kde.kwalletd6.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   ! grep -q 'plasma-kwallet-pam.service' "$desktop_components" &&
   grep -q '^Type=dbus$' "$kwallet_portal_unit" &&
   grep -q '^BusName=org.freedesktop.impl.portal.desktop.kwallet$' "$kwallet_portal_unit" &&
   ! grep -q '^ConditionPathExists=' "$kwallet_portal_unit" &&
   grep -q '^Requisite=labwc-session.target$' "$kwallet_portal_unit" &&
   grep -q '^PartOf=labwc-session.target$' "$kwallet_portal_unit" &&
   grep -q '^Environment=QT_QPA_PLATFORM=wayland$' "$kwallet_portal_unit" &&
   grep -q '^ExecStart=/usr/bin/ksecretd$' "$kwallet_portal_unit" &&
   grep -q '^Restart=on-failure$' "$kwallet_portal_unit" &&
   grep -q '^RestartSec=2s$' "$kwallet_portal_unit" &&
   grep -q '^TimeoutStopSec=5s$' "$kwallet_portal_unit" &&
	   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-session-child" ] &&
	   ! grep -q 'labwc-session-child' "$desktop_components" &&
	   ! grep -q '^ConditionPathExists=' "$labwc_user_target" &&
	   grep -q '^Requires=dbus.service dbus.socket$' "$labwc_user_target" &&
	   grep -q '^BindsTo=labwc-compositor.service$' "$labwc_user_target" &&
	   grep -q '^After=dbus.service dbus.socket labwc-compositor.service$' "$labwc_user_target" &&
	   grep -q '^DefaultDependencies=no$' "$labwc_user_target" &&
	   grep -q '^Conflicts=shutdown.target$' "$labwc_user_target" &&
	   grep -q '^Before=shutdown.target$' "$labwc_user_target" &&
	   grep -q '^DefaultDependencies=no$' "$labwc_compositor_unit" &&
	   grep -q '^Conflicts=shutdown.target$' "$labwc_compositor_unit" &&
	   grep -q '^Before=shutdown.target$' "$labwc_compositor_unit" &&
	   grep -q '^Requires=dbus.service dbus.socket$' "$labwc_compositor_unit" &&
	   grep -q '^After=dbus.service dbus.socket$' "$labwc_compositor_unit" &&
	   grep -q '^PartOf=labwc-session.target$' "$labwc_compositor_unit" &&
	   grep -q '^Before=labwc-session.target$' "$labwc_compositor_unit" &&
	   grep -q '^Environment=LIBSEAT_BACKEND=seatd$' "$labwc_compositor_unit" &&
	   grep -q '^UnsetEnvironment=DISPLAY XAUTHORITY WLR_XWAYLAND XWAYLAND XWAYLAND_PATH XWAYLAND_NO_GLAMOR XWAYLAND_FORCE_SCALE XWAYLAND_RESTART_DELAY _XWAYLAND_GLOBAL_OUTPUT_SCALE WINDOWID SESSION_MANAGER DESKTOP_STARTUP_ID$' "$labwc_compositor_unit" &&
	   ! grep -q '^Environment=WLR_XWAYLAND=' "$labwc_compositor_unit" &&
	   grep -q '^ExecStart=/usr/bin/labwc$' "$labwc_compositor_unit" &&
	   ! grep -Eq '^(After|BindsTo|Requires|Wants)=.*(greetd|seatd|systemd-user-sessions)[.]service' "$labwc_compositor_unit" &&
	   grep -q '^After=seatd.service$' "$user_manager_seatd_dropin" &&
	   ! grep -Eq '^(BindsTo|Conflicts|Requires|Wants)=' "$user_manager_seatd_dropin" &&
	   grep -q '^Wants=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket$' "$greetd_service_dropin" &&
	   grep -q '^After=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket$' "$greetd_service_dropin" &&
	   grep -q 'etc/systemd/system/user@.service.d/20-labwc-seatd.conf' "$desktop_components" &&
	   grep -q 'etc/skel/.config/systemd/user/labwc-compositor.service' "$desktop_components" &&
	   ! grep -q '^BindsTo=graphical-session.target$' "$labwc_user_target" &&
	   ! grep -q '^Wants=graphical-session.target$' "$labwc_user_target" &&
	   ! grep -q '^After=graphical-session.target$' "$labwc_user_target" &&
	   grep -q '^ConditionEnvironment=LABWC_SESSION_OWNER=desktop$' "$portal_dropin" &&
	   grep -q '^ConditionEnvironment=WAYLAND_DISPLAY$' "$portal_dropin" &&
	   ! grep -q '^ConditionPathExists=' "$portal_dropin" &&
	   ! grep -q '^Requisite=labwc-session.target$' "$portal_dropin" &&
	   grep -q '^After=labwc-session.target$' "$portal_dropin" &&
	   grep -q '^PartOf=labwc-session.target$' "$portal_dropin" &&
	   grep -q '^WantedBy=labwc-session.target$' "$portal_dropin" &&
	   ! grep -q 'graphical-session.target' "$portal_dropin" &&
	   grep -q '^ExecCondition=/bin/sh -eu -c ' "$portal_dropin" &&
	   grep -q '^ConditionEnvironment=LABWC_SESSION_OWNER=desktop$' "$hypr_dropin" &&
	   grep -q '^ConditionEnvironment=WAYLAND_DISPLAY$' "$hypr_dropin" &&
	   ! grep -q '^ConditionPathExists=' "$hypr_dropin" &&
	   ! grep -q '^Requisite=labwc-session.target$' "$hypr_dropin" &&
	   grep -q '^After=labwc-session.target$' "$hypr_dropin" &&
	   grep -q '^PartOf=labwc-session.target$' "$hypr_dropin" &&
	   grep -q '^WantedBy=labwc-session.target$' "$hypr_dropin" &&
	   ! grep -q 'graphical-session.target' "$hypr_dropin" &&
	   grep -q '^Environment=QT_QPA_PLATFORM=wayland$' "$hypr_dropin" &&
	   grep -q '^Environment=QT_NO_XDG_DESKTOP_PORTAL=1$' "$hypr_dropin" &&
	   grep -q '^StartLimitIntervalSec=30s$' "$hypr_dropin" &&
	   grep -q '^StartLimitBurst=5$' "$hypr_dropin" &&
	   grep -q '^Restart=on-failure$' "$hypr_dropin" &&
	   grep -q '^RestartSec=2s$' "$hypr_dropin" &&
	   grep -q '^TimeoutStopSec=10s$' "$hypr_dropin" &&
	   grep -q '    hyprpolkitagent.service \\' "$desktop_components" &&
   ! grep -q '^ConditionPathExists=' "$gvfs_daemon_dropin" &&
   ! grep -q '^Requisite=labwc-session.target$' "$gvfs_daemon_dropin" &&
   grep -q '^After=labwc-session.target$' "$gvfs_daemon_dropin" &&
   grep -q '^PartOf=labwc-session.target$' "$gvfs_daemon_dropin" &&
   grep -q '^KillMode=mixed$' "$gvfs_daemon_dropin" &&
   grep -q '^TimeoutStopSec=15s$' "$gvfs_daemon_dropin" &&
   ! grep -q '^ConditionPathExists=' "$gvfs_udisks_dropin" &&
   ! grep -q '^Requisite=labwc-session.target$' "$gvfs_udisks_dropin" &&
   grep -q '^After=labwc-session.target$' "$gvfs_udisks_dropin" &&
   grep -q '^PartOf=labwc-session.target$' "$gvfs_udisks_dropin" &&
   grep -q '    gvfs-daemon.service \\' "$desktop_components" &&
   grep -q '    gvfs-udisks2-volume-monitor.service \\' "$desktop_components" &&
   grep -q '^desktop_verify_staged_files() {$' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
	   grep -q '^shutdown_mode=\${1:-logout}$' "$shutdown_hook" &&
	   ! grep -Eq '^[[:space:]]*(systemctl|gio[[:space:]]+mount|fuser?mount|umount|wl-copy|pkill|kill|sync)([[:space:]]|$)' "$shutdown_hook" &&
   ! grep -q 'xdg-desktop-portal-xapp.service' "$shutdown_hook" &&
   ! grep -q 'gvfs-daemon.service' "$shutdown_hook" &&
   ! grep -q 'desktop_enable_unit_if_available xdg-desktop-portal.service user' "$desktop_components" &&
   ! grep -q 'desktop_enable_unit_if_available xdg-desktop-portal-gtk.service user' "$desktop_components"; then
  pass "Labwc portal preferences and session teardown keep every desktop service target-owned"
else
  fail "Labwc portal preferences and session teardown keep every desktop service target-owned"
fi

if grep -q 'xdg-desktop-portal.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-gtk.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-wlr.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-lxqt.service' "$desktop_components" &&
   grep -q 'labwc-kwallet-portal.service' "$desktop_components" &&
   ! grep -q 'labwc-kwalletd6.service' "$desktop_components" &&
   ! grep -q 'xdg-desktop-portal-xapp.service' "$desktop_components" &&
   grep -q '/etc/systemd/user/xdg-desktop-portal.service.d/10-labwc-session.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/systemd/user/xdg-desktop-portal-gtk.service.d/10-labwc-session.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/systemd/user/xdg-desktop-portal-wlr.service.d/10-labwc-session.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q '/etc/systemd/user/xdg-desktop-portal-lxqt.service.d/10-labwc-session.conf' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"; then
  pass "portal user units are gated on Labwc session readiness"
else
  fail "portal user units are gated on Labwc session readiness"
fi

foot_service_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/foot-server.service.d/10-labwc-session.conf"
foot_socket_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/user/foot-server.socket.d/10-labwc-session.conf"
foot_enablement_block=$(awk '
  /^desktop_enable_target_services\(\) \{$/ { show = 1 }
  show { print }
  show && /^}$/ { exit }
' "$desktop_components")
if grep -Fqx 'Wants=labwc-output-watch.service' "$foot_service_dropin" &&
   ! grep -Fq 'ConditionPathExists=' "$foot_service_dropin" &&
   ! grep -Fqx 'Requisite=labwc-session.target' "$foot_service_dropin" &&
   grep -Fqx 'After=labwc-session.target labwc-output-watch.service' "$foot_service_dropin" &&
   grep -Fqx 'PartOf=labwc-session.target' "$foot_service_dropin" &&
   grep -Fqx 'WantedBy=labwc-session.target' "$foot_service_dropin" &&
   ! grep -Fq 'graphical-session.target' "$foot_service_dropin" &&
   grep -Fqx 'ExecStartPre=/usr/local/libexec/labwc-output-watch --wait-for-output' "$foot_service_dropin" &&
   ! grep -Fqx 'Wants=labwc-output-watch.service' "$foot_socket_dropin" &&
   ! grep -Fq 'ConditionPathExists=' "$foot_socket_dropin" &&
   ! grep -Fqx 'Requisite=labwc-session.target' "$foot_socket_dropin" &&
   grep -Fqx 'After=labwc-session.target' "$foot_socket_dropin" &&
   grep -Fqx 'PartOf=labwc-session.target' "$foot_socket_dropin" &&
   grep -Fqx 'WantedBy=labwc-session.target' "$foot_socket_dropin" &&
   ! grep -Fq 'graphical-session.target' "$foot_socket_dropin" &&
   grep -Fq 'desktop_disable_unit_if_available foot-server.service user' "$desktop_components" &&
   printf '%s\n' "$foot_enablement_block" | grep -Fqx '    foot-server.socket \' &&
   ! printf '%s\n' "$foot_enablement_block" | grep -Fqx '    foot-server.service \' &&
   grep -Fq 'require_absent /etc/systemd/user/graphical-session.target.wants/foot-server.service' "$desktop_verify" &&
   grep -Fq 'require_absent /etc/skel/.config/systemd/user/labwc-session.target.wants/foot-server.service' "$desktop_verify" &&
   grep -Fq 'require_absent "$account_home/.config/systemd/user/labwc-session.target.wants/foot-server.service"' "$desktop_verify"; then
  pass "Foot remains session-bound, waits for client-visible output, and starts only through its socket"
else
  fail "Foot remains session-bound, waits for client-visible output, and starts only through its socket"
fi

if grep -q 'waybar.service' "$desktop_components" &&
   grep -q 'foot-server.service' "$desktop_components" &&
   grep -q 'foot-server.socket' "$desktop_components" &&
   grep -q 'mako.service' "$desktop_components" &&
   ! grep -q 'plasma-kwallet-pam.service' "$desktop_components" &&
   grep -q 'pipewire.service' "$desktop_components" &&
   grep -q 'pipewire-pulse.service' "$desktop_components" &&
   grep -q 'pipewire.socket' "$desktop_components" &&
   grep -q 'pipewire-pulse.socket' "$desktop_components" &&
   grep -q 'wireplumber.service' "$desktop_components" &&
   grep -q 'filter-chain.service' "$desktop_components" &&
   grep -q 'labwc-calendar-sync.timer' "$desktop_components" &&
   grep -q '^desktop_stage_labwc_package_user_unit_dropins() {$' "$desktop_components" &&
   grep -q '^desktop_stage_global_user_unit_dropin_asset() {$' "$desktop_components" &&
   grep -q '^desktop_user_unit_template_dir() {$' "$desktop_components" &&
   grep -q "printf '%s\\\\n' /etc/skel/.config/systemd/user" "$desktop_components" &&
   grep -q 'account_unit_dir="${ACCOUNT_HOME}/.config/systemd/user"' "$desktop_components" &&
   grep -q 'ln -sfn "$link_target" "$template_link"' "$desktop_components" &&
   grep -q 'ln -sfn "$link_target" "$account_link"' "$desktop_components" &&
   grep -q 'chown -h "$account_uid:$account_gid" "$account_link"' "$desktop_components" &&
   grep -q 'desktop user-unit enablement refuses the root account' "$desktop_components" &&
   grep -q 'dropin_relpath="etc/systemd/user/${unit}.d/${dropin_name}"' "$desktop_components" &&
   ! grep -q 'dropin_path="${DIR_SYSTEMD_USER}/' "$desktop_components" &&
   ! grep -q '/etc/systemd/user/labwc-kwallet' "$desktop_components" &&
   ! grep -q 'etc/environment.d/90-labwc-session.conf' "$desktop_components" &&
   grep -q 'desktop_stage_user_unit_wanted_by "$unit" labwc-session.target' "$desktop_components" &&
   grep -q 'unstage_target_systemd_unit_enabled "$unit" user' "$desktop_components" &&
   grep -q 'desktop_disable_unit_if_available mpris-proxy.service user' "$desktop_components" &&
   grep -q 'desktop_disable_unit_if_available waybar.service user' "$desktop_components"; then
  pass "greeter no longer inherits the heavy user audio and timer stack before labwc-session.target"
else
  fail "greeter no longer inherits the heavy user audio and timer stack before labwc-session.target"
fi

dbus_user_hardening_template="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl"
legacy_dbus_user_hardening_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
if [ -r "$dbus_user_hardening_template" ] &&
   [ ! -e "$legacy_dbus_user_hardening_template" ] &&
   grep -Fq '/etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf' "$desktop_verify" &&
   grep -Fq 'require_absent /etc/skel/.config/systemd/user/dbus-broker.service.d/10-broker-hardening.conf' "$desktop_verify" &&
   grep -Fq 'system-wide D-Bus broker hardening was copied into the desktop account' "$desktop_verify" &&
   grep -Fq '/etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf' "$firstboot_validation" &&
   grep -Fq '/etc/skel/.config/systemd/user/dbus-broker.service.d/10-broker-hardening.conf' "$firstboot_validation" &&
   grep -Fq 'desktop-user-unit-dbus-broker-local-hardening-absent' "$firstboot_validation"; then
  pass "desktop validation keeps D-Bus broker hardening global and rejects per-account copies"
else
  fail "desktop validation keeps D-Bus broker hardening global and rejects per-account copies"
fi

waybar_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/waybar.service"
waybar_tray_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/waybar.service.d/20-tray-compat.conf"
if grep -q 'libayatana-appindicator3-1' "$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg" &&
   grep -q 'etc/skel/.config/systemd/user/waybar.service /etc/skel/.config/systemd/user/waybar.service 0644' "$desktop_components" &&
   grep -q 'etc/skel/.config/systemd/user/waybar.service.d/20-tray-compat.conf' "$desktop_components" &&
   grep -q 'desktop_disable_unit_if_available waybar.service user' "$desktop_components" &&
   grep -q '^DefaultDependencies=no$' "$labwc_user_target" &&
   ! grep -q 'graphical-session.target' "$waybar_unit" &&
   grep -q '^ConditionEnvironment=LABWC_SESSION_OWNER=desktop$' "$waybar_unit" &&
	   grep -q '^ConditionPathExists=%h/.config/waybar/config$' "$waybar_unit" &&
	   grep -q '^ConditionPathExists=%h/.config/waybar/style.css$' "$waybar_unit" &&
	   grep -q '^Requisite=labwc-session.target$' "$waybar_unit" &&
	   grep -q '^After=labwc-session.target labwc-output-watch.service$' "$waybar_unit" &&
	   grep -q '^PartOf=labwc-session.target$' "$waybar_unit" &&
	   grep -q '^Type=exec$' "$waybar_unit" &&
   grep -q '^Environment=PATH=/usr/local/bin:/usr/bin:/bin$' "$waybar_unit" &&
   grep -q '^ExecStart=/usr/bin/waybar -c %h/.config/waybar/config -s %h/.config/waybar/style.css$' "$waybar_unit" &&
   ! grep -q '^WantedBy=' "$waybar_unit" &&
   grep -q '^Environment=XDG_CURRENT_DESKTOP=Unity:labwc:wlroots$' "$waybar_tray_dropin" &&
   grep -q '^StandardOutput=null$' "$waybar_tray_dropin" &&
   grep -q '^StandardError=null$' "$waybar_tray_dropin" &&
   grep -q 'require_absent /etc/systemd/user/labwc-session.target.wants/waybar.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh" &&
   grep -q 'require_absent /etc/systemd/user/default.target.wants/mpris-proxy.service' "$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"; then
  pass "Waybar starts after the Labwc session target without an ordering cycle, isolates app output, and keeps the vendor MPRIS proxy off the default user target"
else
  fail "Waybar starts after the Labwc session target without an ordering cycle, isolates app output, and keeps the vendor MPRIS proxy off the default user target"
fi

if grep -q '^ConfigurationDirectoryMode=0755$' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/bluetooth.service.d/override.conf"; then
  pass "bluetooth drop-in matches the managed configuration directory mode"
else
  fail "bluetooth drop-in matches the managed configuration directory mode"
fi

if grep -q '^alias ls=' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.bash_aliases" &&
   grep -q '^alias ls=' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.zsh_aliases" &&
   grep -q 'dircolors' "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.profile" &&
   grep -q 'stage_target_asset "\$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/skel/.dircolors)" /etc/skel/.dircolors 0644' "$desktop_components" &&
   grep -q '^DIR 01;34$' "$ROOT_DIR/d-i/forky/hooks/shared/target/etc/skel/.dircolors"; then
  pass "desktop shell defaults enable dircolors-backed file and directory coloring in Foot and Kitty sessions"
else
  fail "desktop shell defaults enable dircolors-backed file and directory coloring in Foot and Kitty sessions"
fi

bluetooth_main="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/bluetooth/main.conf"
if grep -q '^AutoEnable=true$' "$bluetooth_main" &&
   ! grep -q '^KernelExperimental' "$bluetooth_main" &&
   grep -q '^SecureConnections = on$' "$bluetooth_main" &&
   grep -q '^Privacy = device$' "$bluetooth_main" &&
   grep -q 'desktop_enable_unit_if_available bluetooth-controller-init.service system' "$desktop_components" &&
   grep -q 'desktop_enable_unit_if_available bluetooth.service system' "$desktop_components" &&
   grep -q '^After=bluetooth.service$' "$bluetooth_init_service" &&
   grep -q '^ConditionFileIsExecutable=/usr/bin/timeout$' "$bluetooth_init_service" &&
   grep -q '^TimeoutStartSec=35s$' "$bluetooth_init_service" &&
   grep -q -- '--kill-after="${COMMAND_KILL_GRACE_SECONDS}s"' "$bluetooth_init" &&
   ! grep -q 'desktop_stage_bluetooth_dbus_activation' "$desktop_components" &&
   ! grep -q 'unstage_target_systemd_unit_enabled bluetooth.service system' "$desktop_components"; then
  pass "Bluetooth starts independently before the optional managed btmgmt initializer"
else
  fail "Bluetooth starts independently before the optional managed btmgmt initializer"
fi

nvidia_powerd_override="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/nvidia-powerd.service.d/10-device-guard.conf"
if grep -q '^ConditionPathExists=/dev/nvidiactl$' "$nvidia_powerd_override" &&
   grep -q 'etc/systemd/system/nvidia-powerd.service.d/10-device-guard.conf' "$desktop_components" &&
   grep -q 'desktop_mask_unit_if_available nvidia-persistenced.service system' "$desktop_components" &&
   grep -q 'desktop_mask_unit_if_available nvidia-powerd.service system' "$desktop_components"; then
  pass "NVIDIA helper daemons are guarded and masked so unsupported systems stay quiet"
else
  fail "NVIDIA helper daemons are guarded and masked so unsupported systems stay quiet"
fi

output_refresh="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-output-refresh"
if head -n 1 "$output_refresh" | grep -q '^#!/usr/bin/env perl$'; then
  pass "labwc output refresh helper is implemented in Perl"
else
  fail "labwc output refresh helper is implemented in Perl"
fi

terminal_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-terminal"
if grep -q '^# Accept xterm-style `-e` for callers, but normalize it before we reach Kitty\.$' "$terminal_wrapper" &&
   grep -q '^      kitty)$' "$terminal_wrapper" &&
   grep -q '^        exec "\$terminal_cmd" "\$@"$' "$terminal_wrapper"; then
  pass "labwc-terminal normalizes xterm-style execute flags for kitty"
else
  fail "labwc-terminal normalizes xterm-style execute flags for kitty"
fi

if grep -q '^xterm_execute_mode=0$' "$terminal_wrapper" &&
   grep -q '^  -e\|--execute)$' "$terminal_wrapper" &&
   grep -q '^    if \[ "\$xterm_execute_mode" -eq 1 \]; then$' "$terminal_wrapper" &&
   grep -q '^      exec "\$terminal_cmd" -e "\$@"$' "$terminal_wrapper"; then
  pass "labwc-terminal preserves xterm-style execute flags for xterm-like fallbacks"
else
  fail "labwc-terminal preserves xterm-style execute flags for xterm-like fallbacks"
fi

[ "$FAIL_COUNT" -eq 0 ]
