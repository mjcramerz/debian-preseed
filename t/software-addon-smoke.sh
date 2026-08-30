#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/software-addon-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=25
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

software_class="$ROOT_DIR/d-i/forky/classes/class-addon/software.cfg"
mullvad_class="$ROOT_DIR/d-i/forky/classes/class-apps/mullvad.cfg"
desktop_class="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
addons_cfg="$ROOT_DIR/d-i/forky/classes/configs/addons.cfg"
software_helper="$ROOT_DIR/d-i/forky/scripts/late/software.sh"
mullvad_helper="$ROOT_DIR/d-i/forky/scripts/late/mullvad.sh"
tailscale_helper="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/libexec/tailscale-managed-up"
late_dispatch="$ROOT_DIR/d-i/forky/scripts/late/dispatch.sh"
shared_late_loader="$ROOT_DIR/d-i/forky/hooks/shared/late_command.sh"
btrfs_late="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
f2fs_late="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"
managed_app_package_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages"
managed_app_package="$managed_app_package_root/labwc_managed_app"
launcher_sync="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-sync-application-launchers"
launcher_sync_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-sync-application-launchers.service"
launcher_sync_path="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-sync-application-launchers.path"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
mullvad_dns_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/mullvad-daemon.service.d/20-managed-dns.conf"
mullvad_tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/51-mullvad-version-cache.conf"
mullvad_vpn_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/mullvad-vpn"
mullvad_daemon_start="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/mullvad-daemon-start"
mullvad_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/applications/mullvad-vpn.desktop"
mullvad_autostart="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/autostart/mullvad-vpn.desktop"
managed_system_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-system-wrappers"
keepassxc_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/keepassxc/keepassxc.ini"
keepassxc_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.keepassxc"
chromium_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/chromium/Default/Preferences"
edge_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/microsoft-edge/Default/Preferences"
vivaldi_preferences="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/vivaldi/Default/Preferences"
code_settings="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/Code/User/settings.json"
obsidian_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/obsidian/obsidian.json"
obsidian_vault="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/Syncthing/obsidian-md"
obsidian_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/obsidian"
qoredb_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.qoredb"
gridline_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/usr.bin.gridline"
gridline_gtk_css="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-managed-app/gridline-gtk.css"
labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
managed_desktop_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
postman_desktop_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/postman.desktop"
sleek_desktop_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/sleek.desktop"
tuta_desktop_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/tuta-mail.desktop"
tuta_public_key="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/software/tuta/tutao-pub.pem"
ledger_desktop_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/ledger-live.desktop"
ledger_public_key="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/software/ledger/ledgerlive.pem"
ledger_udev_rules="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/udev/rules.d/53-ledger-wallet.rules"
software_updater="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/managed-external-software-update"
software_notifier="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/managed-external-software-notify"
software_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/external-managed-software"
software_cli="$software_module_root/ExternalSoftware/Servicing/CLI.pm"
software_chatgpt="$software_module_root/ExternalSoftware/Servicing/ChatGPT.pm"
software_deb="$software_module_root/ExternalSoftware/Servicing/Deb.pm"
software_event="$software_module_root/ExternalSoftware/Servicing/Event.pm"
software_state="$software_module_root/ExternalSoftware/Servicing/State.pm"
software_repository="$software_module_root/ExternalSoftware/Servicing/Repository.pm"
software_repository_source="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/apt/sources.list.d/managed-external-software.list"
software_discord="$software_module_root/ExternalSoftware/Servicing/Discord.pm"
software_obsidian="$software_module_root/ExternalSoftware/Servicing/Obsidian.pm"
software_ledger="$software_module_root/ExternalSoftware/Servicing/Ledger.pm"
software_postman="$software_module_root/ExternalSoftware/Servicing/Postman.pm"
software_tuta="$software_module_root/ExternalSoftware/Servicing/Tuta.pm"
software_notifier_module="$software_module_root/ExternalSoftware/Servicing/Notifier.pm"
software_discord_archive_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/managed-discord-distro"
discord_desktop_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/discord.desktop"
software_download_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-external-software-download.service"
software_download_timer="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-external-software-download.timer"
software_update_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-external-software-update.service"
software_update_timer="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-external-software-update.timer"
software_notify_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/managed-external-software-notify.service"
software_notify_path="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/managed-external-software-notify.path"
chatgpt_default="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/default/chatgpt"
chatgpt_launcher="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/chatgpt"
legacy_chatgpt_launcher="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-chatgpt"
chatgpt_log_runner="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-chatgpt-log-runner"
chatgpt_log_socket_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/rsyslog-managed-openai-socket"
chatgpt_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/chatgpt.desktop"
chatgpt_apparmor="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/chatgpt"
chatgpt_rsyslog="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/rsyslog.d/38-openai-chatgpt.conf"
chatgpt_rsyslog_dropin="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/rsyslog.service.d/35-managed-openai-chatgpt-socket.conf"
chatgpt_tmpfiles_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/61-managed-openai-chatgpt.conf.tmpl"
chatgpt_tmpfiles_rendered="$TMP_DIR/61-managed-openai-chatgpt.conf"
chatgpt_logrotate="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/logrotate.d/chatgpt"
postman_install_script="$TMP_DIR/postman-install.sh"
postman_version_parser="$TMP_DIR/postman-version-parser.py"
postman_minified_package="$TMP_DIR/postman-package.json"
postman_desktop="$TMP_DIR/postman.desktop"
sleek_desktop="$TMP_DIR/sleek.desktop"
tuta_desktop="$TMP_DIR/tuta-mail.desktop"
ledger_desktop="$TMP_DIR/ledger-live.desktop"

managed_app_source_contains() {
  grep -R -q --include='*.py' -- "$1" "$managed_app_package"
}

managed_app_source_lacks() {
  ! grep -R -q --include='*.py' -- "$1" "$managed_app_package"
}

chatgpt_tmpfiles_template_renders() {
  /bin/sh -eu -c '
    # shellcheck disable=SC1090
    . "$1"
    installer_apply_scalar_placeholders \
      "$2" \
      "$3" \
      ACCOUNT_USERNAME desktop
    installer_assert_no_unresolved_installer_placeholders \
      "$3" \
      "ChatGPT tmpfiles smoke-test render"
  ' sh \
    "$ROOT_DIR/d-i/forky/scripts/common/lib.sh" \
    "$chatgpt_tmpfiles_template" \
    "$chatgpt_tmpfiles_rendered" ||
    return 1

  LC_ALL=C awk '
    /^[[:space:]]*($|#)/ { next }
    {
      if (NF < 6 || $2 !~ /^\//) {
        exit 1
      }
    }
  ' "$chatgpt_tmpfiles_rendered" &&
    grep -Fqx 'd /var/log/managed/openai 0751 root adm -' "$chatgpt_tmpfiles_rendered" &&
    grep -Fqx 'd /var/log/managed/openai/chatgpt 0751 root adm -' "$chatgpt_tmpfiles_rendered" &&
    grep -Fqx 'd /var/log/managed/openai/chatgpt/runtime 2770 desktop openailogger -' "$chatgpt_tmpfiles_rendered" &&
    grep -Fqx 'f /var/log/managed/openai/chatgpt/chatgpt.log 0640 root adm -' "$chatgpt_tmpfiles_rendered" &&
    grep -Fqx 'd /run/rsyslog/managed-openai 0750 root openailogger -' "$chatgpt_tmpfiles_rendered"
}

perl_stub_root="$TMP_DIR/perl-stubs"
mkdir -p "$perl_stub_root/MooX/Types"
cat >"$perl_stub_root/Moo.pm" <<'EOF'
package Moo;
sub import {
  my $caller = caller;
  no strict 'refs';
  *{"${caller}::has"} = sub { return; };
}
1;
EOF
cat >"$perl_stub_root/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;
sub import { return; }
1;
EOF
mkdir -p "$perl_stub_root/MooX/Types/MooseLike"
cat >"$perl_stub_root/MooX/Types/MooseLike/Base.pm" <<'EOF'
package MooX::Types::MooseLike::Base;
sub import {
  my $caller = caller;
  no strict 'refs';
  for my $name (@_[1 .. $#_]) {
    *{"${caller}::${name}"} = sub { return; };
  }
}
1;
EOF

external_perl_syntax_ok=true
for external_perl_file in \
  $(cd "$software_module_root" && find ExternalSoftware -type f -name '*.pm' -print | LC_ALL=C sort)
do
  if ! PERL5LIB="$perl_stub_root:$software_module_root" \
      /usr/bin/perl -c "$software_module_root/$external_perl_file" >/dev/null 2>&1
  then
    external_perl_syntax_ok=false
  fi
done
for external_perl_entrypoint in "$software_updater" "$software_notifier"; do
  if ! PERL5LIB="$perl_stub_root:$software_module_root" \
      /usr/bin/perl -c "$external_perl_entrypoint" >/dev/null 2>&1
  then
    external_perl_syntax_ok=false
  fi
done
unset external_perl_file external_perl_entrypoint

updater_workspace_behavior_ok=false
if PERL5LIB="$perl_stub_root:$software_module_root" \
    /usr/bin/perl - "$software_state" >/dev/null 2>&1 <<'PERL'
use strict;
use warnings;

use File::Path qw(remove_tree);
use File::Temp qw(tempdir);

my $module_path = shift @ARGV;
require $module_path;

my $state = bless {}, 'ExternalSoftware::Servicing::State';
my @cleanup_paths;

END {
    for my $path (reverse @cleanup_paths) {
        next
            if !defined $path
                || $path !~ m{\A/tmp/managed-external-software-update\.[A-Za-z0-9_]{6}\z};
        if (-l $path) {
            unlink $path;
        } elsif (-e $path) {
            remove_tree($path, { safe => 1 });
        }
    }
}

sub must_die {
    my ($code) = @_;
    return !eval { $code->(); 1 };
}

sub workspace_path {
    my ($suffix) = @_;
    return "/tmp/managed-external-software-update.$suffix";
}

my $valid_suffix = sprintf 'u_%04d', $$ % 10_000;
my $valid_path = workspace_path($valid_suffix);
push @cleanup_paths, $valid_path;
die "managed updater workspace fixture already exists\n"
    if -e $valid_path || -l $valid_path;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::State::tempdir = sub {
        my ($template, %options) = @_;
        $template eq 'managed-external-software-update.XXXXXX'
            && ($options{DIR} // q{}) eq '/tmp'
            && exists $options{CLEANUP}
            && !$options{CLEANUP}
            or die "managed updater workspace creator contract changed\n";
        mkdir $valid_path, 0700
            or die "cannot create managed updater workspace fixture: $!\n";
        return $valid_path;
    };
    my $created_path = $state->work_dir();
    $created_path eq $valid_path
        or die "managed updater workspace creator returned an unexpected path\n";
}
open my $payload_fh, '>', "$valid_path/payload"
    or die "cannot create managed updater workspace payload: $!\n";
print {$payload_fh} "payload\n";
close $payload_fh
    or die "cannot close managed updater workspace payload: $!\n";
$state->cleanup_work_dir($valid_path);
die "managed updater workspace cleanup retained its directory\n"
    if -e $valid_path || -l $valid_path;

for my $invalid_path (
    q{},
    '/',
    '/tmp',
    "/var/tmp/managed-external-software-update.$valid_suffix",
    "$valid_path/child",
) {
    die "managed updater workspace cleanup accepted an unexpected path\n"
        if !must_die(sub { $state->cleanup_work_dir($invalid_path); });
}

my $unsafe_suffix = sprintf 'm_%04d', ($$ + 1) % 10_000;
my $unsafe_path = workspace_path($unsafe_suffix);
push @cleanup_paths, $unsafe_path;
die "unsafe managed updater workspace fixture already exists\n"
    if -e $unsafe_path || -l $unsafe_path;
mkdir $unsafe_path, 0700
    or die "cannot create unsafe managed updater workspace fixture: $!\n";
chmod 0755, $unsafe_path
    or die "cannot set unsafe managed updater workspace mode: $!\n";
die "managed updater workspace cleanup accepted an unsafe mode\n"
    if !must_die(sub { $state->cleanup_work_dir($unsafe_path); });
die "managed updater workspace cleanup removed the unsafe-mode fixture\n"
    if !-d $unsafe_path || -l $unsafe_path;
chmod 0700, $unsafe_path
    or die "cannot restore managed updater workspace fixture mode: $!\n";
$state->cleanup_work_dir($unsafe_path);

my $symlink_target_root = tempdir(
    'managed-updater-symlink-target.XXXXXX',
    DIR     => '/tmp',
    CLEANUP => 1,
);
my $symlink_target = "$symlink_target_root/target";
mkdir $symlink_target, 0700
    or die "cannot create managed updater symlink target: $!\n";
my $symlink_suffix = sprintf 's_%04d', ($$ + 2) % 10_000;
my $symlink_path = workspace_path($symlink_suffix);
push @cleanup_paths, $symlink_path;
die "managed updater symlink fixture already exists\n"
    if -e $symlink_path || -l $symlink_path;
symlink $symlink_target, $symlink_path
    or die "cannot create managed updater symlink fixture: $!\n";
die "managed updater workspace cleanup accepted a symlink\n"
    if !must_die(sub { $state->cleanup_work_dir($symlink_path); });
die "managed updater workspace cleanup followed or removed a symlink\n"
    if !-l $symlink_path || !-d $symlink_target;
unlink $symlink_path
    or die "cannot remove managed updater symlink fixture: $!\n";
PERL
then
  updater_workspace_behavior_ok=true
fi

repository_codename_behavior_ok=false
if PERL5LIB="$perl_stub_root:$software_module_root" \
    /usr/bin/perl - "$software_repository" >/dev/null 2>&1 <<'PERL'
use strict;
use warnings;

my $repository_path = shift @ARGV;
require $repository_path;

my $repository = bless {}, 'ExternalSoftware::Servicing::Repository';
my $fixture_codename;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Atomic::read_limited = sub {
        my (undef, $path, $maximum) = @_;
        $path eq '/usr/lib/os-release'
            or die "managed repository used a non-canonical os-release path\n";
        $maximum == 64 * 1024
            or die "managed repository os-release bound changed\n";
        return "NAME=Debian GNU/Linux\nVERSION_CODENAME=\"$fixture_codename\"\n";
    };
    for my $expected_codename (qw(synthetic-suite future_suite_42)) {
        $fixture_codename = $expected_codename;
        $repository->_codename() eq $expected_codename
            or die "managed repository codename parsing is not dynamic\n";
    }
}
PERL
then
  repository_codename_behavior_ok=true
fi

notification_schema_behavior_ok=false
if PERL5LIB="$perl_stub_root:$software_module_root" \
    /usr/bin/perl - "$software_event" "$software_notifier_module" >/dev/null 2>&1 <<'PERL'
use strict;
use warnings;

my ($event_path, $notifier_path) = @ARGV;
require $event_path;
require $notifier_path;

my $event_sequence = 0;
my $event_content;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Event::directory = sub {
        return '/var/lib/software/events';
    };
    local *ExternalSoftware::Servicing::Event::sequence = sub {
        my ($self, $value) = @_;
        $event_sequence = $value if @_ == 2;
        return $event_sequence;
    };
    local *ExternalSoftware::Servicing::Atomic::ensure_root_directory = sub {
        my (undef, $path, $mode) = @_;
        $path eq '/var/lib/software/events' && $mode == 0755
            or die "notification event directory contract changed\n";
        return $path;
    };
    local *ExternalSoftware::Servicing::Atomic::assert_child = sub {
        my (undef, $directory, $name) = @_;
        $directory eq '/var/lib/software/events'
            or die "notification event escaped its directory\n";
        $name =~ /\A[0-9]{10}-[0-9]{10}-[0-9]{4}\.event\z/
            or die "notification event filename is invalid\n";
        return "$directory/$name";
    };
    local *ExternalSoftware::Servicing::Atomic::write_text = sub {
        my (undef, $path, $content, $mode) = @_;
        $path =~ m{\A/var/lib/software/events/}
            && $mode == 0644
            or die "notification event publication contract changed\n";
        $event_content = $content;
        return $path;
    };

    my $event = bless {}, 'ExternalSoftware::Servicing::Event';
    $event->emit('downloaded', 'chatgpt', 'missing', '1.2.3');
    $event_content eq "downloaded|chatgpt|missing|1.2.3\n"
        or die "ChatGPT notification event was not serialized\n";
    my $unknown_application = eval {
        $event->emit('downloaded', 'unknown-app', 'missing', '1.2.3');
        1;
    };
    die "unknown notification application was accepted\n"
        if $unknown_application || $@ !~ /unsupported notification event application/;
}

my @notifications;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Notifier::_notify = sub {
        my (undef, @notification) = @_;
        push @notifications, \@notification;
        return 1;
    };

    my $notifier = bless {}, 'ExternalSoftware::Servicing::Notifier';
    $notifier->_deliver('checking', 'all', '-', '-');
    $notifier->_deliver('downloaded', 'chatgpt', 'missing', '1.2.3');
    $notifier->_deliver('failed', 'chatgpt', 'policy', '-');
    $notifier->_deliver('failed', 'chatgpt', 'payload', '-');
}
@notifications == 4
    or die "ChatGPT notification delivery count is invalid\n";
$notifications[0]->[4] =~ /ChatGPT\/Codex Desktop/
    or die "managed software checking notification omits ChatGPT\n";
$notifications[1]->[3] eq 'ChatGPT/Codex Desktop download ready'
    or die "ChatGPT download notification label is invalid\n";
$notifications[2]->[3] eq 'ChatGPT/Codex Desktop update failed'
    && $notifications[2]->[4] =~ /security policy/
    or die "ChatGPT policy failure notification is invalid\n";
$notifications[3]->[4] =~ /required managed payload/
    or die "ChatGPT payload failure notification is invalid\n";
PERL
then
  notification_schema_behavior_ok=true
fi

external_apply_no_network=true
if ! python3 - "$software_discord" "$software_postman" "$software_tuta" "$software_ledger" <<'PY'
from pathlib import Path
import re
import sys

for raw_path in sys.argv[1:]:
    text = Path(raw_path).read_text(encoding="utf-8")
    match = re.search(r"^sub apply \{(?P<body>.*?)(?=^sub |\Z)", text, re.M | re.S)
    if match is None or re.search(r"(?:->http\(|->download\(|https?://)", match.group("body")):
        raise SystemExit(1)
PY
then
  external_apply_no_network=false
fi

chatgpt_servicing_behavior_ok=false
if PERL5LIB="$perl_stub_root:$software_module_root" \
    /usr/bin/perl - "$software_chatgpt" "$software_cli" "$software_deb" >/dev/null 2>&1 <<'PERL'
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

my ($chatgpt_path, $cli_path, $deb_path) = @ARGV;
require $chatgpt_path;
require $deb_path;
require $cli_path;

{
    package ChatGPTSmokeState;
    sub new {
        my ($class, $value) = @_;
        return bless { value => $value }, $class;
    }
    sub read_state {
        my ($self, $name, $maximum) = @_;
        die "unexpected ChatGPT marker query\n"
            if $name ne 'chatgpt.enabled' || $maximum != 64;
        return $self->{value};
    }
}

{
    package ChatGPTDisabledGate;
    sub enabled { return 0; }
    sub spec { die "disabled ChatGPT gate queried its package spec\n"; }
}

{
    package ChatGPTEnabledGate;
    sub enabled { return 1; }
    sub spec { return { name => 'chatgpt' }; }
}

{
    no warnings 'redefine';
    *ExternalSoftware::Servicing::ChatGPT::state =
        sub { return $_[0]->{state}; };
}

my $handler = bless {
    state => ChatGPTSmokeState->new(undef),
}, 'ExternalSoftware::Servicing::ChatGPT';
die "missing ChatGPT marker enabled servicing\n"
    if $handler->enabled();

$handler->{state} = ChatGPTSmokeState->new("addon/devops\n");
die "valid ChatGPT marker did not enable servicing\n"
    if !$handler->enabled();

$handler->{state} = ChatGPTSmokeState->new("addon/software\n");
my $invalid_marker = eval { $handler->enabled(); 1 };
die "malformed ChatGPT marker was accepted\n"
    if $invalid_marker || $@ !~ /enable state is invalid/;

my $spec = $handler->spec();
die "ChatGPT package URL is not the approved upstream endpoint\n"
    if $spec->{url}
        ne 'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb';
my @pinned_digest_fields = grep {
    /(?:sha256|checksum|digest)/i
} keys %{$spec};
die "mutable ChatGPT package URL must not use a release-pinned digest field\n"
    if @pinned_digest_fields;
die "ChatGPT package size bound is not 512 MiB\n"
    if $spec->{maximum} != 536_870_912;
die "ChatGPT package host allowlist is invalid\n"
    if join("\0", @{$spec->{hosts}}) ne 'persistent.oaistatic.com';
die "ChatGPT package name allowlist is invalid\n"
    if join("\0", @{$spec->{packages}}) ne 'chatgpt';
die "ChatGPT dependency removal policy is invalid\n"
    if join("\0", @{$spec->{remove_dependencies}}) ne join(
        "\0",
        'mesa-vulkan-drivers',
        'nvidia-*',
        'vulkan-icd',
        '*x11*',
    );
die "ChatGPT package executable is invalid\n"
    if $spec->{executable} ne '/usr/lib/chatgpt/ChatGPT';
die "ChatGPT required payload list is incomplete\n"
    if join("\0", @{$spec->{required_paths}}) ne join(
        "\0",
        '/usr/bin/chatgpt',
        '/usr/lib/chatgpt/codex-launcher',
        '/usr/lib/chatgpt/resources/codex',
        '/usr/lib/chatgpt/resources/codex-code-mode-host',
        '/usr/share/pixmaps/chatgpt.png',
    );
die "ChatGPT required executable list is incomplete\n"
    if join("\0", @{$spec->{required_executables}}) ne join(
        "\0",
        '/usr/bin/chatgpt',
        '/usr/lib/chatgpt/codex-launcher',
        '/usr/lib/chatgpt/resources/codex',
        '/usr/lib/chatgpt/resources/codex-code-mode-host',
    );

my $repack_root = tempdir('chatgpt-repack-smoke.XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $package_root = File::Spec->catdir($repack_root, 'package');
my $control_root = File::Spec->catdir($package_root, 'DEBIAN');
my $payload_root = File::Spec->catdir($package_root, 'usr', 'share');
make_path($control_root, $payload_root);
chmod 0755, $package_root, $control_root, $payload_root
    or die "cannot set ChatGPT repack fixture directory modes: $!\n";
my $control_path = File::Spec->catfile($control_root, 'control');
open my $control_fh, '>', $control_path
    or die "cannot create ChatGPT repack fixture control file: $!\n";
print {$control_fh} <<'CONTROL';
Package: chatgpt
Version: 1.0
Architecture: amd64
Maintainer: Smoke Test <nobody@example.invalid>
Depends: libc6,
 mesa-vulkan-drivers | libgl1,
 nvidia-driver:any (>= 1),
 vulkan-icd | libvulkan1,
 nvidia-utils | nvidia-settings,
 libx11-6,
 libx11-xcb1 | libxcb1,
 x11-utils | wayland-utils,
 libxcb-x11-0:any (>= 1) | libwayland-client0
Description: ChatGPT dependency repack smoke fixture
CONTROL
close $control_fh
    or die "cannot close ChatGPT repack fixture control file: $!\n";
my $payload_path = File::Spec->catfile($payload_root, 'chatgpt-repack-fixture.txt');
open my $payload_fh, '>', $payload_path
    or die "cannot create ChatGPT repack fixture payload: $!\n";
print {$payload_fh} "payload\n";
close $payload_fh
    or die "cannot close ChatGPT repack fixture payload: $!\n";
my $source_deb = File::Spec->catfile($repack_root, 'chatgpt-source.deb');
system(
    '/usr/bin/dpkg-deb',
    '--root-owner-group',
    '--build',
    $package_root,
    $source_deb,
) == 0 or die "cannot build ChatGPT dependency repack fixture\n";
my $repack_work = File::Spec->catdir($repack_root, 'work');
mkdir $repack_work, 0700
    or die "cannot create ChatGPT dependency repack workspace: $!\n";
my $repack_deb = bless {}, 'ExternalSoftware::Servicing::Deb';
my $repacked_deb = $repack_deb->repack_without_dependencies(
    label        => 'ChatGPT/Codex Desktop',
    path         => $source_deb,
    work         => $repack_work,
    name         => 'chatgpt',
    dependencies => $spec->{remove_dependencies},
);
die "ChatGPT repack did not remove the forbidden dependency relations\n"
    if ($repack_deb->control($repacked_deb, 'Depends') // q{})
        ne 'libc6, libgl1, libvulkan1, libxcb1, wayland-utils, libwayland-client0';
die "ChatGPT repack retained an X11 dependency\n"
    if index(
        ($repack_deb->control($repacked_deb, 'Depends') // q{}),
        'x11',
    ) >= 0;
my $invalid_contains_pattern = eval {
    $repack_deb->_dependency_exclusions(['lib*x11*']);
    1;
};
die "unsafe ChatGPT dependency contains pattern was accepted\n"
    if $invalid_contains_pattern
        || $@ !~ /dependency exclusion pattern is invalid/;
for my $field (qw(Package Version Architecture)) {
    die "ChatGPT repack changed package identity field $field\n"
        if ($repack_deb->control($repacked_deb, $field) // q{})
            ne ($repack_deb->control($source_deb, $field) // q{});
}
die "ChatGPT repack lost the package payload\n"
    if !$repack_deb->_contains(
        $repacked_deb,
        '/usr/share/chatgpt-repack-fixture.txt',
    );

{
    package ChatGPTOfflineSyntaxProbe;
    our @ISA = ('ExternalSoftware::Servicing::ChatGPT');
    sub _assert_root_owned_regular_executable {
        my ($self, $label, $path) = @_;
        $self->{assertion} = [$label, $path];
        return 1;
    }
    sub _run_policy_syntax_validation {
        $_[0]->{runs}++;
        return $_[0]->{syntax_ok};
    }
}

my $syntax_probe = bless {
    runs      => 0,
    syntax_ok => 1,
}, 'ChatGPTOfflineSyntaxProbe';
$syntax_probe->_validate_policy_syntax();
die "offline ChatGPT policy validation did not require the managed parser\n"
    if join("\0", @{$syntax_probe->{assertion}}) ne join(
        "\0",
        'managed ChatGPT AppArmor parser',
        '/usr/sbin/apparmor_parser',
    );
die "offline ChatGPT policy validation did not run exactly once\n"
    if $syntax_probe->{runs} != 1;
$syntax_probe->{syntax_ok} = 0;
my $invalid_syntax = eval { $syntax_probe->_validate_policy_syntax(); 1 };
die "invalid ChatGPT policy passed offline validation\n"
    if $invalid_syntax || $@ !~ /failed offline validation/;

{
    package ChatGPTFinalizationProbe;
    our @ISA = ('ExternalSoftware::Servicing::ChatGPT');
    sub _validate_policy_syntax {
        push @{$_[0]->{calls}}, 'offline-syntax';
        return 1;
    }
    sub _reload_policy_if_available {
        push @{$_[0]->{calls}}, 'live-reload';
        return 1;
    }
}

my @finalization_calls;
my $finalization_probe = bless {
    calls => \@finalization_calls,
}, 'ChatGPTFinalizationProbe';
$finalization_probe->_finalize_policy('installer');
die "installer ChatGPT finalization attempted a live AppArmor reload\n"
    if join("\0", @finalization_calls) ne 'offline-syntax';
$finalization_probe->_finalize_policy('runtime');
die "runtime ChatGPT finalization did not validate then reload AppArmor policy\n"
    if join("\0", @finalization_calls) ne join(
        "\0",
        'offline-syntax',
        'offline-syntax',
        'live-reload',
    );
my $invalid_context = eval { $finalization_probe->_finalize_policy('unknown'); 1 };
die "invalid ChatGPT finalization context was accepted\n"
    if $invalid_context || $@ !~ /finalization context is invalid/;

{
    package ChatGPTLiveReloadProbe;
    our @ISA = ('ExternalSoftware::Servicing::ChatGPT');
    sub _live_apparmor_interface_is_available { return $_[0]->{available}; }
    sub _assert_root_owned_regular_executable {
        $_[0]->{assertions}++;
        return 1;
    }
    sub _run_managed_modes {
        $_[0]->{runs}++;
        return $_[0]->{helper_ok};
    }
}

my $unavailable_reload_probe = bless {
    available  => 0,
    assertions => 0,
    helper_ok  => 0,
    runs       => 0,
}, 'ChatGPTLiveReloadProbe';
$unavailable_reload_probe->_reload_policy_if_available();
die "missing AppArmor interface invoked the managed mode helper\n"
    if $unavailable_reload_probe->{assertions} != 0
        || $unavailable_reload_probe->{runs} != 0;

my $available_reload_probe = bless {
    available  => 1,
    assertions => 0,
    helper_ok  => 1,
    runs       => 0,
}, 'ChatGPTLiveReloadProbe';
$available_reload_probe->_reload_policy_if_available();
die "available AppArmor interface did not invoke the managed mode helper\n"
    if $available_reload_probe->{assertions} != 1
        || $available_reload_probe->{runs} != 1;

my $failed_reload_probe = bless {
    available  => 1,
    assertions => 0,
    helper_ok  => 0,
    runs       => 0,
}, 'ChatGPTLiveReloadProbe';
my $failed_reload = eval { $failed_reload_probe->_reload_policy_if_available(); 1 };
die "failed runtime ChatGPT AppArmor reload was accepted\n"
    if $failed_reload || $@ !~ /failed to reload managed AppArmor policy/;

my $cli = bless {}, 'ExternalSoftware::Servicing::CLI';
my @disabled_specs = $cli->_generic_deb_specs(
    bless({}, 'ChatGPTDisabledGate'),
);
die "software-only servicing exposed ChatGPT\n"
    if grep { $_->{name} eq 'chatgpt' } @disabled_specs;
my @enabled_specs = $cli->_generic_deb_specs(
    bless({}, 'ChatGPTEnabledGate'),
);
die "DevOps servicing did not expose ChatGPT\n"
    if !grep { $_->{name} eq 'chatgpt' } @enabled_specs;

{
    package ChatGPTBootstrapPolicy;
    sub enabled { return 1; }
    sub spec { return $_[0]->{spec}; }
}

{
    package ChatGPTBootstrapState;
    sub deb_dir { return '/var/lib/software/debs'; }
}

my $bootstrap_policy = bless { spec => $spec }, 'ChatGPTBootstrapPolicy';
my $bootstrap_context;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::ChatGPT::new =
        sub { return $bootstrap_policy; };
    local *ExternalSoftware::Servicing::HTTP::new =
        sub { return bless {}, 'ChatGPTBootstrapHTTP'; };
    local *ExternalSoftware::Servicing::Repository::new =
        sub { return bless {}, 'ChatGPTBootstrapRepository'; };
    local *ExternalSoftware::Servicing::Deb::new =
        sub { return bless {}, 'ChatGPTBootstrapDeb'; };
    local *ExternalSoftware::Servicing::CLI::_fetch_generic_deb =
        sub { return (0, 'downloaded'); };
    local *ExternalSoftware::Servicing::CLI::_apply_deb =
        sub {
            $bootstrap_context = $_[-1];
            return (0, 'updated');
        };
    my $bootstrap_result = $cli->_run_bootstrap_chatgpt(
        bless({}, 'ChatGPTBootstrapState'),
        bless({}, 'ChatGPTStageEvent'),
        '/tmp',
    );
    die "ChatGPT bootstrap did not complete\n"
        if $bootstrap_result != 0;
}
die "ChatGPT bootstrap did not select installer finalization context\n"
    if !defined($bootstrap_context) || $bootstrap_context ne 'installer';

{
    package ChatGPTStageDeb;
    sub installed_version { return '1.0'; }
}

{
    package ChatGPTStageRepository;
    sub retain {
        my ($self) = @_;
        $self->{retained}++;
        return ('/var/lib/software/debs/chatgpt_1.0_amd64.deb', 1);
    }
}

{
    package ChatGPTStageEvent;
    sub emit {
        my ($self, @event) = @_;
        $self->{event} = \@event;
        return 1;
    }
}

my $stage_repository = bless { retained => 0 }, 'ChatGPTStageRepository';
my $stage_event = bless {}, 'ChatGPTStageEvent';
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::CLI::_version_compare = sub {
        my (undef, undef, $operator) = @_;
        return 0 if $operator eq 'lt';
        die "unexpected stage version comparison operator\n";
    };
    my ($stage_result, $stage_reason) = $cli->_stage_deb(
        bless({}, 'ChatGPTStageDeb'),
        $stage_event,
        $stage_repository,
        $spec,
        '/tmp/chatgpt.deb',
        {
            package      => 'chatgpt',
            version      => '1.0',
            architecture => 'amd64',
        },
    );
    die "same-version ChatGPT archive was not retained\n"
        if $stage_result != 0 || $stage_reason ne 'downloaded';
}
die "same-version ChatGPT archive retention did not call the repository\n"
    if $stage_repository->{retained} != 1;
die "same-version ChatGPT archive retention did not emit a download event\n"
    if join("\0", @{$stage_event->{event}}) ne join(
        "\0",
        'downloaded',
        'chatgpt',
        '1.0',
        '1.0',
    );

my $deb = bless {}, 'ExternalSoftware::Servicing::Deb';
my $quiet_stderr_path = File::Spec->catfile(
    $repack_root,
    'quiet-capture.stderr',
);
open my $saved_stderr, '>&', \*STDERR
    or die "cannot preserve smoke-test stderr: $!\n";
open STDERR, '>', $quiet_stderr_path
    or die "cannot redirect smoke-test stderr: $!\n";
my $quiet_output = $deb->_capture_quiet(
    '/usr/bin/perl',
    '-e',
    'print STDERR "unexpected stderr\n"; print "captured stdout\n";',
);
my $quiet_failure = $deb->_capture_quiet(
    '/usr/bin/perl',
    '-e',
    'print STDERR "unexpected failure stderr\n"; exit 7;',
);
open STDERR, '>&', $saved_stderr
    or die "cannot restore smoke-test stderr: $!\n";
close $saved_stderr
    or die "cannot close preserved smoke-test stderr: $!\n";
open my $quiet_stderr_fh, '<', $quiet_stderr_path
    or die "cannot read quiet-capture smoke-test stderr: $!\n";
my $quiet_stderr = do { local $/; <$quiet_stderr_fh> // q{} };
close $quiet_stderr_fh
    or die "cannot close quiet-capture smoke-test stderr: $!\n";
die "quiet direct-argv capture lost stdout\n"
    if !defined($quiet_output) || $quiet_output ne "captured stdout\n";
die "quiet direct-argv capture accepted a failed child\n"
    if defined $quiet_failure;
die "quiet direct-argv capture leaked child stderr\n"
    if $quiet_stderr ne q{};

{
    no warnings 'redefine';
    my @queries;
    local *ExternalSoftware::Servicing::Deb::_capture = sub {
        die "installed package probe used noisy capture\n";
    };
    local *ExternalSoftware::Servicing::Deb::_capture_quiet = sub {
        my (undef, @command) = @_;
        push @queries, \@command;
        return undef;
    };
    die "missing ChatGPT package was reported as installed\n"
        if defined $deb->installed_version('chatgpt');
    die "missing ChatGPT package probe command is invalid\n"
        if @queries != 1
            || join("\0", @{$queries[0]}) ne join(
                "\0",
                '/usr/bin/dpkg-query',
                '-W',
                '-f=${Status}',
                'chatgpt',
            );
}

{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Deb::_capture = sub {
        return "-rwxr-xr-x root/root 123 2026-01-01 00:00 ./usr/lib/chatgpt/resources/codex\n";
    };
    die "world-executable ChatGPT archive payload was rejected\n"
        if !$deb->_contains_executable(
            '/tmp/chatgpt.deb',
            '/usr/lib/chatgpt/resources/codex',
        );
}
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Deb::_capture = sub {
        return "-rw-r--r-- root/root 123 2026-01-01 00:00 ./usr/lib/chatgpt/resources/codex\n";
    };
    die "non-world-executable ChatGPT archive payload was accepted\n"
        if $deb->_contains_executable(
            '/tmp/chatgpt.deb',
            '/usr/lib/chatgpt/resources/codex',
        );
}
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Deb::_capture = sub {
        return "lrwxrwxrwx root/root 0 2026-01-01 00:00 ./usr/bin/chatgpt -> ../lib/chatgpt/codex-launcher\n";
    };
    die "approved ChatGPT launcher symlink was rejected\n"
        if !$deb->_contains_executable('/tmp/chatgpt.deb', '/usr/bin/chatgpt');
}

{
    package ChatGPTApplyRepository;
    sub latest { return $_[0]->{candidate}; }
}

{
    package ChatGPTApplyEvent;
    sub emit {
        my ($self, $name) = @_;
        push @{$self->{order}}, "event:$name";
        return 1;
    }
}

{
    package ChatGPTApplyDeb;
    sub installed_version {
        my ($self) = @_;
        return $self->{installed_version}
            if defined $self->{installed_version};
        return $self->{installed} ? '1.0' : undef;
    }
    sub installed_payload_valid {
        my ($self) = @_;
        return $self->{payload_valid}
            if exists $self->{payload_valid};
        return 1;
    }
    sub install {
        my ($self, undef, $reinstall) = @_;
        push @{$self->{order}}, 'install';
        push @{$self->{order}}, "reinstall:$reinstall";
        $self->{installed} = 1;
        $self->{installed_version} = '1.0';
        $self->{payload_valid} = 1;
        return 1;
    }
}

{
    package ChatGPTApplyPolicy;
    sub prepare_install {
        push @{$_[0]->{order}}, 'prepare';
        return 1;
    }
    sub finalize_install {
        my ($self, $execution_context) = @_;
        push @{$self->{order}}, "finalize:$execution_context";
        return 1;
    }
    sub policy_valid { return 1; }
}

my @transaction_order;
my $candidate = {
    path     => '/tmp/chatgpt.deb',
    metadata => {
        package      => 'chatgpt',
        version      => '1.0',
        architecture => 'amd64',
    },
};
my ($apply_result, $apply_reason) = $cli->_apply_deb(
    bless({ order => \@transaction_order }, 'ChatGPTApplyDeb'),
    bless({ order => \@transaction_order }, 'ChatGPTApplyEvent'),
    bless({ candidate => $candidate }, 'ChatGPTApplyRepository'),
    $spec,
    bless({ order => \@transaction_order }, 'ChatGPTApplyPolicy'),
);
die "ChatGPT install transaction failed\n"
    if $apply_result != 0 || $apply_reason ne 'updated';
my @transaction_steps =
    grep {
        $_ eq 'prepare' || $_ eq 'install' || $_ eq 'finalize:runtime'
    }
    @transaction_order;
die "ChatGPT policy was not prepared before package installation\n"
    if join("\0", @transaction_steps) ne join(
        "\0",
        qw(prepare install finalize:runtime),
    );

my @current_order;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::CLI::_version_compare = sub {
        my (undef, undef, $operator) = @_;
        return $operator eq 'eq' ? 1 : 0;
    };
    my ($current_result, $current_reason) = $cli->_apply_deb(
        bless({
            installed => 1,
            order     => \@current_order,
        }, 'ChatGPTApplyDeb'),
        bless({ order => \@current_order }, 'ChatGPTApplyEvent'),
        bless({ candidate => $candidate }, 'ChatGPTApplyRepository'),
        $spec,
        bless({ order => \@current_order }, 'ChatGPTApplyPolicy'),
    );
    die "same-version ChatGPT policy repair failed\n"
        if $current_result != 2 || $current_reason ne 'current';
}
die "same-version ChatGPT policy repair reinstalled the package\n"
    if grep { $_ eq 'install' || $_ eq 'prepare' } @current_order;
die "same-version ChatGPT policy repair did not restore canonical policy\n"
    if !grep { $_ eq 'finalize:runtime' } @current_order;

my @reinstall_order;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::CLI::_version_compare = sub {
        my (undef, undef, $operator) = @_;
        return $operator eq 'eq' ? 1 : 0;
    };
    my ($reinstall_result, $reinstall_reason) = $cli->_apply_deb(
        bless({
            installed     => 1,
            payload_valid => 0,
            order         => \@reinstall_order,
        }, 'ChatGPTApplyDeb'),
        bless({ order => \@reinstall_order }, 'ChatGPTApplyEvent'),
        bless({ candidate => $candidate }, 'ChatGPTApplyRepository'),
        $spec,
        bless({ order => \@reinstall_order }, 'ChatGPTApplyPolicy'),
    );
    die "same-version ChatGPT payload repair failed\n"
        if $reinstall_result != 0 || $reinstall_reason ne 'updated';
}
die "same-version ChatGPT payload repair did not force APT reinstall\n"
    if !grep { $_ eq 'reinstall:1' } @reinstall_order;
die "same-version ChatGPT payload repair skipped package policy boundaries\n"
    if join(
        "\0",
        grep {
            $_ eq 'prepare' || $_ eq 'install' || $_ eq 'finalize:runtime'
        }
        @reinstall_order,
    ) ne join("\0", qw(prepare install finalize:runtime));

my @newer_broken_order;
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::CLI::_version_compare = sub {
        my (undef, undef, $operator) = @_;
        return $operator eq 'lt' ? 1 : 0;
    };
    my ($newer_result, $newer_reason) = $cli->_apply_deb(
        bless({
            installed_version => '2.0',
            payload_valid     => 0,
            order             => \@newer_broken_order,
        }, 'ChatGPTApplyDeb'),
        bless({ order => \@newer_broken_order }, 'ChatGPTApplyEvent'),
        bless({ candidate => $candidate }, 'ChatGPTApplyRepository'),
        $spec,
        bless({ order => \@newer_broken_order }, 'ChatGPTApplyPolicy'),
    );
    die "newer broken ChatGPT payload was reported healthy\n"
        if $newer_result != 1 || $newer_reason ne 'payload';
}
die "newer broken ChatGPT payload attempted an unsafe downgrade\n"
    if grep { $_ eq 'install' || $_ eq 'prepare' || $_ eq 'finalize' }
        @newer_broken_order;

{
    package ChatGPTRepairState;
    sub deb_dir { return '/var/lib/software/debs'; }
}

{
    package ChatGPTRepairDeb;
    sub installed_version { return '1.0'; }
    sub installed_payload_valid { return 1; }
    sub install { die "offline ChatGPT policy repair attempted reinstall\n"; }
}

{
    package ChatGPTRepairPolicy;
    sub finalize_install {
        my ($self, $execution_context) = @_;
        ${$self->{count}}++;
        ${$self->{context}} = $execution_context;
        return 1;
    }
}

{
    package ChatGPTRepairDiscord;
    sub repair { return (2, 'current'); }
}

my $repair_count = 0;
my $repair_context = q{};
my $repair_policy = bless {
    count   => \$repair_count,
    context => \$repair_context,
}, 'ChatGPTRepairPolicy';
{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Repository::new =
        sub { return bless {}, 'ChatGPTRepairRepository'; };
    local *ExternalSoftware::Servicing::Deb::new =
        sub { return bless {}, 'ChatGPTRepairDeb'; };
    local *ExternalSoftware::Servicing::ChatGPT::new =
        sub { return $repair_policy; };
    local *ExternalSoftware::Servicing::HTTP::new =
        sub { return bless {}, 'ChatGPTRepairHTTP'; };
    local *ExternalSoftware::Servicing::Discord::new =
        sub { return bless {}, 'ChatGPTRepairDiscord'; };
    local *ExternalSoftware::Servicing::CLI::_all_deb_specs =
        sub { return ($spec); };
    local *ExternalSoftware::Servicing::CLI::_log = sub { return 1; };
    my $repair_result = $cli->_run_repair(
        bless({}, 'ChatGPTRepairState'),
        bless({}, 'ChatGPTApplyEvent'),
        '/tmp',
    );
    die "offline ChatGPT policy repair failed\n"
        if $repair_result != 0;
}
die "offline ChatGPT policy repair did not restore canonical policy\n"
    if $repair_count != 1;
die "offline ChatGPT policy repair did not use runtime finalization context\n"
    if $repair_context ne 'runtime';
PERL
then
  chatgpt_servicing_behavior_ok=true
fi

discord_servicing_behavior_ok=false
if PERL5LIB="$perl_stub_root:$software_module_root" \
    /usr/bin/perl - "$software_discord" >/dev/null 2>&1 <<'PERL'
use strict;
use warnings;

use File::Temp qw(tempdir);
use Storable qw(dclone);

my $module_path = shift @ARGV;
require $module_path;

{
    package DiscordSmokeState;
    sub new { return bless { deleted => [] }, shift; }
    sub delete_state {
        my ($self, $name) = @_;
        push @{ $self->{deleted} }, $name;
        return 1;
    }
    sub deleted { return $_[0]->{deleted}; }
}

{
    package DiscordSmokeEvent;
    sub new { return bless { emitted => [] }, shift; }
    sub emit {
        my ($self, @event) = @_;
        push @{ $self->{emitted} }, \@event;
        return 1;
    }
    sub emitted { return $_[0]->{emitted}; }
}

{
    no warnings 'redefine';
    *ExternalSoftware::Servicing::Discord::state = sub { return $_[0]->{state}; };
    *ExternalSoftware::Servicing::Discord::event = sub { return $_[0]->{event}; };
    *ExternalSoftware::Servicing::Discord::http = sub { return $_[0]->{http}; };
}

sub release_record {
    my ($version, $host_digest, $module_version) = @_;
    my $manifest_digest = 'a' x 64;
    my @required = qw(
      discord_desktop_core
      discord_erlpack
      discord_spellcheck
      discord_utils
      discord_voice
    );
    my %modules = map {
        my $digest = 'c' x 64;
        $_ => {
            file    => "discord-$version-$_-$module_version-$digest.full.distro",
            path    => "/tmp/discord-$_",
            sha256  => $digest,
            version => $module_version,
        }
    } @required;
    return {
        version  => $version,
        manifest => {
            file   => "discord-$version-manifest-$manifest_digest.json",
            path   => '/tmp/discord-manifest',
            sha256 => $manifest_digest,
        },
        host => {
            file   => "discord-$version-host-$host_digest.full.distro",
            path   => '/tmp/discord-host',
            sha256 => $host_digest,
        },
        modules => \%modules,
    };
}

sub must_die {
    my ($code) = @_;
    return !eval { $code->(); 1 };
}

sub path_mode {
    my ($path) = @_;
    my @st = lstat $path;
    @st or die "cannot inspect Discord test path $path: $!\n";
    return $st[2] & 07777;
}

my $state = DiscordSmokeState->new();
my $handler = bless {
    event => undef,
    http  => undef,
    state => $state,
}, 'ExternalSoftware::Servicing::Discord';

my $candidate = release_record('1.0.153', 'b' x 64, 2);
my $installed = $handler->_state_record($candidate);
$handler->_assert_non_downgrade($candidate, $installed);

my $downgrade = dclone($candidate);
$downgrade->{version} = '1.0.152';
die "Discord host downgrade was accepted\n"
    if !must_die(sub { $handler->_assert_non_downgrade($downgrade, $installed); });

my $host_substitution = dclone($candidate);
$host_substitution->{host}->{sha256} = 'd' x 64;
die "Discord same-version host digest substitution was accepted\n"
    if !must_die(
        sub { $handler->_assert_non_downgrade($host_substitution, $installed); },
    );

my $module_substitution = dclone($candidate);
$module_substitution->{modules}->{discord_voice}->{sha256} = 'e' x 64;
die "Discord same-version module digest substitution was accepted\n"
    if !must_die(
        sub { $handler->_assert_non_downgrade($module_substitution, $installed); },
    );

my $module_downgrade = dclone($candidate);
$module_downgrade->{modules}->{discord_voice}->{version} = 1;
die "Discord same-host module downgrade was accepted\n"
    if !must_die(
        sub { $handler->_assert_non_downgrade($module_downgrade, $installed); },
    );

my $host_upgrade = release_record('1.0.154', 'f' x 64, 1);
$handler->_assert_non_downgrade($host_upgrade, $installed);

my $valid_metadata = {
    filesystem_entries => 1,
    members             => 2,
    regular_files       => 1,
    unpacked_bytes      => 1,
};
$handler->_validate_distribution_metadata($valid_metadata, 'module');
die "Discord malformed archive metadata was accepted\n"
    if !must_die(
        sub {
            $handler->_validate_distribution_metadata(
                { %{$valid_metadata}, filesystem_entries => 0 },
                'module',
            );
        },
    );
die "Discord aggregate expanded-file limit was not enforced\n"
    if !must_die(
        sub {
            $handler->_accumulate_distribution_bounds(
                { bytes => 0, files => 39_936 },
                $valid_metadata,
            );
        },
    );

{
    my $staging_root = tempdir(CLEANUP => 1);
    my $modules_root = "$staging_root/modules";
    mkdir $modules_root, 0700
        or die "cannot create Discord host module fixture\n";
    mkdir "$modules_root/discord_arborium", 0700
        or die "cannot create Discord bundled module fixture\n";
    open my $bundled_fh, '>', "$modules_root/discord_arborium/host-copy"
        or die "cannot create Discord bundled module payload\n";
    print {$bundled_fh} "host copy\n";
    close $bundled_fh
        or die "cannot close Discord bundled module payload\n";

    my $prepared_modules = $handler->_prepare_module_root($staging_root);
    die "Discord module root preparation returned an unexpected path\n"
        if $prepared_modules ne $modules_root;
    opendir my $modules_fh, $modules_root
        or die "cannot inspect prepared Discord module root\n";
    my @module_entries = grep { $_ ne q{.} && $_ ne q{..} } readdir $modules_fh;
    closedir $modules_fh
        or die "cannot close prepared Discord module root\n";
    die "Discord host-supplied modules were not discarded\n"
        if @module_entries;
    my @modules_st = lstat $modules_root;
    die "Discord module root was not created mode 0755\n"
        if !@modules_st || ($modules_st[2] & 07777) != 0755;

    $handler->_remove_tree_checked($modules_root);
    symlink "$staging_root/missing", $modules_root
        or die "cannot create unsafe Discord module-root fixture\n";
    die "Discord accepted a symlinked module staging root\n"
        if !must_die(sub { $handler->_prepare_module_root($staging_root); });
    unlink $modules_root
        or die "cannot remove unsafe Discord module-root fixture\n";
}

{
    my $runtime_root = tempdir(CLEANUP => 1);
    my @directories = (
        $runtime_root,
        "$runtime_root/modules",
        "$runtime_root/modules/discord_arborium",
        "$runtime_root/modules/discord_arborium/resources",
        "$runtime_root/modules/discord_arborium/resources/nested",
    );
    for my $directory (@directories[1 .. $#directories]) {
        mkdir $directory, 0700
            or die "cannot create Discord normalization directory $directory: $!\n";
    }
    chmod 0700, $_
        or die "cannot set Discord normalization directory mode on $_: $!\n"
        for @directories;

    my %file_modes = (
        Discord => 0600,
        'chrome-sandbox' => 0700,
        chrome_crashpad_handler => 0600,
        'modules/discord_arborium/resources/nested/module-tool' => 0711,
        'modules/discord_arborium/resources/nested/runtime-data' => 0666,
    );
    for my $relative (sort keys %file_modes) {
        my $path = "$runtime_root/$relative";
        open my $fh, '>', $path
            or die "cannot create Discord normalization file $path: $!\n";
        print {$fh} $relative eq 'runtime-data' ? "data\n" : "\x7fELFfixture\n";
        close $fh
            or die "cannot close Discord normalization file $path: $!\n";
        chmod $file_modes{$relative}, $path
            or die "cannot set Discord normalization file mode on $path: $!\n";
    }

    my @owned_paths;
    {
        no warnings 'redefine';
        local *ExternalSoftware::Servicing::Discord::_set_root_owner =
            sub {
                my (undef, $path) = @_;
                push @owned_paths, $path;
                return 1;
            };
        $handler->_normalize_tree($runtime_root);
    }

    for my $directory (@directories) {
        die "Discord normalizer did not set directory $directory mode 0755\n"
            if path_mode($directory) != 0755;
    }
    my %expected_file_modes = (
        Discord => 0755,
        'chrome-sandbox' => 04755,
        chrome_crashpad_handler => 0755,
        'modules/discord_arborium/resources/nested/module-tool' => 0755,
        'modules/discord_arborium/resources/nested/runtime-data' => 0644,
    );
    for my $relative (sort keys %expected_file_modes) {
        my $path = "$runtime_root/$relative";
        die "Discord normalizer set an unsafe mode on $path\n"
            if path_mode($path) != $expected_file_modes{$relative};
    }
    my %owned = map { $_ => 1 } @owned_paths;
    for my $path (
        @directories,
        map { "$runtime_root/$_" } sort keys %expected_file_modes
    ) {
        die "Discord normalizer skipped root ownership for $path\n"
            if !$owned{$path};
    }

    my $unsafe_root = tempdir(CLEANUP => 1);
    my $unsafe_link = "$unsafe_root/module-link";
    symlink "$unsafe_root/missing", $unsafe_link
        or die "cannot create Discord normalization symlink fixture: $!\n";
    my $normalization_error;
    {
        no warnings 'redefine';
        local *ExternalSoftware::Servicing::Discord::_set_root_owner =
            sub { return 1; };
        eval { $handler->_normalize_tree($unsafe_root); 1 };
        $normalization_error = $@;
    }
    die "Discord normalizer accepted a symlinked runtime entry\n"
        if !$normalization_error;
    die "Discord normalizer symlink error omitted the offending path\n"
        if index($normalization_error, $unsafe_link) < 0;
}

my $failure_detail = $handler->_record_failure_detail(
    'module-discord_arborium',
    "first line\nsecond line\x1b",
);
die "Discord staging failure detail was not sanitized or bounded\n"
    if $failure_detail ne 'module-discord_arborium: first line second line?'
        || $handler->failure_detail() ne $failure_detail;
$handler->_clear_failure_detail();
die "Discord staging failure detail was not cleared\n"
    if defined $handler->failure_detail();
die "Discord accepted an unsafe staging failure label\n"
    if !must_die(
        sub { $handler->_record_failure_detail('../unsafe', 'failure'); },
    );

{
    my $rollback_root = tempdir(CLEANUP => 1);
    my $install = "$rollback_root/install";
    my $backup = "$rollback_root/backup";
    mkdir $install or die "cannot create Discord rollback install fixture\n";
    open my $new_fh, '>', "$install/new"
        or die "cannot create Discord rollback new fixture\n";
    print {$new_fh} "new\n";
    close $new_fh;
    my $rollback_state = DiscordSmokeState->new();
    my $rollback_handler = bless {
        event => undef,
        http  => undef,
        state => $rollback_state,
    }, 'ExternalSoftware::Servicing::Discord';
    $rollback_handler->_rollback($install, $backup, undef, 0);
    die "Discord rollback without a prior install left the new runtime\n"
        if -e $install || -l $install;
    die "Discord rollback without a prior install retained installed state\n"
        if join("\0", @{ $rollback_state->deleted() })
            ne 'discord.installed.json';
}

{
    my $rollback_root = tempdir(CLEANUP => 1);
    my $install = "$rollback_root/install";
    my $backup = "$rollback_root/backup";
    mkdir $install or die "cannot create Discord rollback install fixture\n";
    mkdir $backup or die "cannot create Discord rollback backup fixture\n";
    open my $new_fh, '>', "$install/new"
        or die "cannot create Discord rollback new fixture\n";
    print {$new_fh} "new\n";
    close $new_fh;
    open my $old_fh, '>', "$backup/old"
        or die "cannot create Discord rollback old fixture\n";
    print {$old_fh} "old\n";
    close $old_fh;
    my $rollback_state = DiscordSmokeState->new();
    my $rollback_handler = bless {
        event => undef,
        http  => undef,
        state => $rollback_state,
    }, 'ExternalSoftware::Servicing::Discord';
    my $written_release;
    {
        no warnings 'redefine';
        local *ExternalSoftware::Servicing::Discord::_assert_runtime =
            sub { return 1; };
        local *ExternalSoftware::Servicing::Discord::_write_release_state =
            sub {
                my (undef, $name, $release) = @_;
                $written_release = [$name, $release];
                return 1;
            };
        $rollback_handler->_rollback($install, $backup, $installed, 1);
    }
    die "Discord rollback did not restore the prior runtime\n"
        if !-f "$install/old" || -e $backup || -l $backup;
    die "Discord rollback did not restore the prior release state\n"
        if !defined $written_release
            || $written_release->[0] ne 'discord.installed.json'
            || $written_release->[1] != $installed;
}

{
    no warnings 'redefine';
    local *ExternalSoftware::Servicing::Discord::_download_release =
        sub { return $candidate; };
    local *ExternalSoftware::Servicing::Discord::_installed =
        sub { return $installed; };
    local *ExternalSoftware::Servicing::Discord::runtime_valid =
        sub { return 1; };
    my ($result, $reason) = $handler->fetch('/tmp');
    die "Discord current-release fetch returned an unexpected result\n"
        if $result != 2 || $reason ne 'current';
}
die "Discord current-release fetch retained stale pending state\n"
    if join("\0", @{ $state->deleted() }) ne 'discord.pending.json';

{
    my $repair_state = DiscordSmokeState->new();
    my $repair_event = DiscordSmokeEvent->new();
    my $repair_handler = bless {
        event => $repair_event,
        http  => undef,
        state => $repair_state,
    }, 'ExternalSoftware::Servicing::Discord';
    my (@retained, @written, @published);
    {
        no warnings 'redefine';
        local *ExternalSoftware::Servicing::Discord::_pending =
            sub { return undef; };
        local *ExternalSoftware::Servicing::Discord::_installed =
            sub { return $installed; };
        local *ExternalSoftware::Servicing::Discord::runtime_valid =
            sub { return 0; };
        local *ExternalSoftware::Servicing::Discord::_retained_path =
            sub {
                my (undef, $artifact) = @_;
                push @retained, $artifact->{file};
                return "/var/lib/software/artifacts/discord/$artifact->{file}";
            };
        local *ExternalSoftware::Servicing::Discord::_write_release_state =
            sub {
                my (undef, $name, $release) = @_;
                push @written, [$name, $release];
                return 1;
            };
        local *ExternalSoftware::Servicing::Discord::_publish =
            sub {
                my (undef, $work, $pending, $previous) = @_;
                push @published, [$work, $pending, $previous];
                return (0, 'updated');
            };
        my ($result, $reason) = $repair_handler->apply('/tmp/discord-repair');
        die "Discord invalid current runtime was not rebuilt from retained artifacts\n"
            if $result != 0 || $reason ne 'updated';
    }
    die "Discord repair did not validate every retained distribution\n"
        if @retained != 7;
    die "Discord repair did not reconstruct pending state from the installed release\n"
        if @written != 1
            || $written[0]->[0] ne 'discord.pending.json'
            || $written[0]->[1] != $installed;
    die "Discord repair preserved an invalid runtime as the rollback candidate\n"
        if @published != 1
            || $published[0]->[0] ne '/tmp/discord-repair'
            || $published[0]->[1] != $installed
            || defined $published[0]->[2];
    die "Discord repair did not emit applying and updated events\n"
        if @{ $repair_event->emitted() } != 2
            || $repair_event->emitted()->[0]->[0] ne 'applying'
            || $repair_event->emitted()->[1]->[0] ne 'updated';
}
PERL
then
  discord_servicing_behavior_ok=true
fi

for desktop_template_pair in \
  "$postman_desktop_template:$postman_desktop" \
  "$sleek_desktop_template:$sleek_desktop" \
  "$tuta_desktop_template:$tuta_desktop" \
  "$ledger_desktop_template:$ledger_desktop"
do
  desktop_template=${desktop_template_pair%%:*}
  rendered_desktop=${desktop_template_pair#*:}
  sed \
    's|__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__|/usr/local/bin/labwc-managed-app nvidia|g' \
    "$desktop_template" >"$rendered_desktop"
done
unset desktop_template_pair desktop_template rendered_desktop

awk '
  index($0, "<<\047POSTMAN_INSTALL_SH\047") {
    capture = 1
    next
  }
  capture && /^POSTMAN_INSTALL_SH$/ {
    exit
  }
  capture {
    print
  }
' "$software_helper" >"$postman_install_script"
if /bin/sh -n "$postman_install_script"; then
  postman_install_syntax_ok=true
else
  postman_install_syntax_ok=false
fi
awk '
  index($0, "<<\047PY\047") {
    capture = 1
    next
  }
  capture && /^PY$/ {
    exit
  }
  capture {
    print
  }
' "$postman_install_script" >"$postman_version_parser"
printf '%s\n' '{"name":"Postman","version":"12.20.1","private":true}' >"$postman_minified_package"
postman_minified_version=$(
  python3 "$postman_version_parser" "$postman_minified_package" 2>/dev/null ||
    true
)

discord_distro_fixtures_ok=false
if PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 - \
    "$software_discord_archive_helper" \
    "$TMP_DIR/discord-distro-fixtures" <<'PY'
import copy
import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tarfile

helper = pathlib.Path(sys.argv[1])
fixture_root = pathlib.Path(sys.argv[2])
fixture_root.mkdir(mode=0o700)
version = "1.0.153"
required_modules = (
    "discord_desktop_core",
    "discord_erlpack",
    "discord_spellcheck",
    "discord_utils",
    "discord_voice",
)
all_modules = (
    "discord_arborium",
    "discord_cloudsync",
    "discord_desktop_core",
    "discord_dispatch",
    "discord_erlpack",
    "discord_game_utils",
    "discord_krisp",
    "discord_modules",
    "discord_rpc",
    "discord_spellcheck",
    "discord_utils",
    "discord_voice",
    "discord_zstd",
)
digest = "a" * 64

loader = importlib.machinery.SourceFileLoader(
    "managed_discord_distro_fixture",
    str(helper),
)
spec = importlib.util.spec_from_loader(loader.name, loader)
if spec is None:
    raise AssertionError("cannot load Discord archive helper fixture")
distro_helper = importlib.util.module_from_spec(spec)
loader.exec_module(distro_helper)


def run_helper(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-I", str(helper), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def expect_ok(*arguments: str) -> dict[str, object]:
    result = run_helper(*arguments)
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)


def expect_bad(*arguments: str) -> None:
    result = run_helper(*arguments)
    if result.returncode == 0:
        raise AssertionError(f"unexpected helper success: {arguments}")


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def add_directory(archive: tarfile.TarFile, name: str) -> None:
    member = tarfile.TarInfo(name)
    member.type = tarfile.DIRTYPE
    member.mode = 0o755
    archive.addfile(member)


def add_file(
    archive: tarfile.TarFile,
    name: str,
    payload: bytes,
    mode: int = 0o644,
) -> None:
    member = tarfile.TarInfo(name)
    member.mode = mode
    member.size = len(payload)
    archive.addfile(member, io.BytesIO(payload))


def create_host(
    path: pathlib.Path,
    *,
    omit: str | None = None,
    include_legacy_asar: bool = False,
) -> None:
    payloads = {
        "files/Discord": b"\x7fELFdiscord-host",
        "files/chrome-sandbox": b"\x7fELFchromium-sandbox",
        "files/chrome_crashpad_handler": b"\x7fELFcrashpad",
        "files/discord.png": b"\x89PNG\r\n\x1a\n",
        "files/libffmpeg.so": b"\x7fELFffmpeg",
    }
    if include_legacy_asar:
        payloads["files/resources/app.asar"] = b"asar"
    with tarfile.open(path, mode="w", format=tarfile.PAX_FORMAT) as archive:
        add_file(
            archive,
            "delta_manifest.json",
            b'{"files":[],"manifest_version":1}',
        )
        add_directory(archive, "files/")
        add_directory(archive, "files/resources/")
        for name, payload in payloads.items():
            if name == omit:
                continue
            add_file(
                archive,
                name,
                payload,
                0o755
                if name
                in {
                    "files/Discord",
                    "files/chrome-sandbox",
                    "files/chrome_crashpad_handler",
                }
                else 0o644,
            )


def create_module(path: pathlib.Path) -> None:
    with tarfile.open(path, mode="w", format=tarfile.PAX_FORMAT) as archive:
        add_file(
            archive,
            "delta_manifest.json",
            b'{"files":[],"manifest_version":1}',
        )
        add_directory(archive, "files/")
        add_file(archive, "files/module.node", b"\x7fELFmodule", 0o755)
        add_file(archive, "files/package.json", b'{"name":"module"}')


modules = {
    name: {
        "deltas": [
            {
                "host_version": [1, 0, 152],
                "module_version": 1,
                "package_sha256": "b" * 64,
                "url": (
                    "https://stable.dl2.discordapp.net/distro/app/stable/"
                    f"linux/x64/{version}/{name}/1/from/1.0.152/1"
                ),
            }
        ],
        "full": {
            "host_version": [1, 0, 153],
            "module_version": 1,
            "package_sha256": digest,
            "url": (
                "https://stable.dl2.discordapp.net/distro/app/stable/"
                f"linux/x64/{version}/{name}/1/full.distro"
            ),
        },
    }
    for name in all_modules
}
manifest = {
    "deltas": [
        {
            "host_version": [1, 0, 152],
            "package_sha256": "b" * 64,
            "url": (
                "https://stable.dl2.discordapp.net/distro/app/stable/"
                f"linux/x64/{version}/from/1.0.152"
            ),
        }
    ],
    "full": {
        "host_version": [1, 0, 153],
        "package_sha256": digest,
        "url": (
            "https://stable.dl2.discordapp.net/distro/app/stable/"
            f"linux/x64/{version}/full.distro"
        ),
    },
    "metadata_version": None,
    "modules": modules,
    "required_modules": list(required_modules),
    "required_update": True,
}
manifest_path = fixture_root / "manifest.json"
write_json(manifest_path, manifest)
normalized = expect_ok("manifest", "--path", str(manifest_path))
assert normalized["version"] == version
assert set(normalized["required_modules"]) == set(required_modules)
assert set(normalized["modules"]) == set(all_modules)

invalid_manifest = copy.deepcopy(manifest)
invalid_manifest["unexpected"] = True
invalid_manifest_path = fixture_root / "manifest-extra-field.json"
write_json(invalid_manifest_path, invalid_manifest)
expect_bad("manifest", "--path", str(invalid_manifest_path))

invalid_manifest = copy.deepcopy(manifest)
invalid_manifest["required_modules"].remove("discord_voice")
invalid_manifest_path = fixture_root / "manifest-missing-required.json"
write_json(invalid_manifest_path, invalid_manifest)
expect_bad("manifest", "--path", str(invalid_manifest_path))

invalid_manifest = copy.deepcopy(manifest)
invalid_manifest["full"]["url"] = invalid_manifest["full"]["url"].replace(
    "/stable/",
    "/canary/",
)
invalid_manifest_path = fixture_root / "manifest-wrong-channel.json"
write_json(invalid_manifest_path, invalid_manifest)
expect_bad("manifest", "--path", str(invalid_manifest_path))

invalid_manifest = copy.deepcopy(manifest)
invalid_manifest["full"]["package_sha256"] = digest.upper()
invalid_manifest_path = fixture_root / "manifest-invalid-digest.json"
write_json(invalid_manifest_path, invalid_manifest)
expect_bad("manifest", "--path", str(invalid_manifest_path))

host_path = fixture_root / "host.tar"
create_host(host_path)
host_metadata = expect_ok(
    "inspect",
    "--path",
    str(host_path),
    "--kind",
    "host",
    "--version",
    version,
)
assert host_metadata["regular_files"] >= 5
assert set(host_metadata) == {
    "filesystem_entries",
    "members",
    "regular_files",
    "unpacked_bytes",
}
assert host_metadata["members"] == 8
assert host_metadata["filesystem_entries"] == 6

legacy_host_path = fixture_root / "host-legacy-asar.tar"
create_host(legacy_host_path, include_legacy_asar=True)
legacy_host_metadata = expect_ok(
    "inspect",
    "--path",
    str(legacy_host_path),
    "--kind",
    "host",
    "--version",
    version,
)
assert legacy_host_metadata["members"] == 9
assert legacy_host_metadata["regular_files"] == 6

module_path = fixture_root / "module.tar"
create_module(module_path)
module_arguments = (
    "--path",
    str(module_path),
    "--kind",
    "module",
    "--version",
    version,
    "--module-name",
    "discord_voice",
    "--module-version",
    "1",
)
module_metadata = expect_ok("inspect", *module_arguments)
assert module_metadata["members"] == 4
assert module_metadata["regular_files"] == 2
assert module_metadata["filesystem_entries"] == 2

implicit_directories_archive = fixture_root / "module-implicit-directories.tar"
with tarfile.open(
    implicit_directories_archive,
    mode="w",
    format=tarfile.PAX_FORMAT,
) as archive:
    add_directory(archive, "files/")
    add_file(
        archive,
        "files/implicit/parents/module.node",
        b"\x7fELFmodule",
    )
implicit_metadata = expect_ok(
    "inspect",
    "--path",
    str(implicit_directories_archive),
    "--kind",
    "module",
    "--version",
    version,
    "--module-name",
    "discord_voice",
    "--module-version",
    "1",
)
assert implicit_metadata["members"] == 2
assert implicit_metadata["filesystem_entries"] == 3


def root_owned_lstat(path: pathlib.Path) -> os.stat_result:
    metadata = original_path_lstat(path)
    values = list(metadata)
    values[4] = 0
    values[5] = 0
    return os.stat_result(values)


def extract_in_process(
    archive_path: pathlib.Path,
    destination: pathlib.Path,
    *,
    kind: str,
    module_name: str | None = None,
) -> dict[str, int]:
    archive, members, metadata = distro_helper.inspect_archive(
        str(archive_path),
        kind=kind,
        version=version,
        module_name=module_name,
        module_version=1 if module_name is not None else None,
    )
    try:
        distro_helper.extract_archive(archive, members, str(destination))
    finally:
        archive.close()
    return metadata


original_path_lstat = distro_helper.pathlib.Path.lstat
original_chown = distro_helper.os.chown
distro_helper.pathlib.Path.lstat = root_owned_lstat
distro_helper.os.chown = lambda *args, **kwargs: None
try:
    host_destination = fixture_root / "host-extracted"
    host_destination.mkdir(mode=0o700)
    extracted_host_metadata = extract_in_process(
        host_path,
        host_destination,
        kind="host",
    )
    assert extracted_host_metadata == host_metadata
    assert oct(host_destination.stat().st_mode & 0o7777) == "0o755"
    assert not (host_destination / "delta_manifest.json").exists()
    for name in ("Discord", "chrome-sandbox", "chrome_crashpad_handler"):
        assert oct((host_destination / name).stat().st_mode & 0o7777) == "0o755"
    for name in ("discord.png", "libffmpeg.so"):
        assert oct((host_destination / name).stat().st_mode & 0o7777) == "0o644"
    assert oct((host_destination / "resources").stat().st_mode & 0o7777) == "0o755"

    for name in all_modules:
        module_destination = fixture_root / f"module-extracted-{name}"
        module_destination.mkdir(mode=0o700)
        extracted_module_metadata = extract_in_process(
            module_path,
            module_destination,
            kind="module",
            module_name=name,
        )
        assert extracted_module_metadata == module_metadata
        assert oct(module_destination.stat().st_mode & 0o7777) == "0o755"
        assert (
            oct((module_destination / "module.node").stat().st_mode & 0o7777)
            == "0o755"
        )
        assert (
            oct((module_destination / "package.json").stat().st_mode & 0o7777)
            == "0o644"
        )

    implicit_destination = fixture_root / "module-implicit-extracted"
    implicit_destination.mkdir(mode=0o700)
    extract_in_process(
        implicit_directories_archive,
        implicit_destination,
        kind="module",
        module_name="discord_voice",
    )
    for relative_path in ("implicit", "implicit/parents"):
        assert (
            oct((implicit_destination / relative_path).stat().st_mode & 0o7777)
            == "0o755"
        )
    assert (
        oct(
            (implicit_destination / "implicit/parents/module.node").stat().st_mode
            & 0o7777
        )
        == "0o644"
    )

    archive, members, _ = distro_helper.inspect_archive(
        str(module_path),
        kind="module",
        version=version,
        module_name="discord_voice",
        module_version=1,
    )
    try:
        try:
            distro_helper.extract_archive(
                archive,
                members,
                str(fixture_root / "module-extracted-discord_voice"),
            )
        except SystemExit:
            pass
        else:
            raise AssertionError("Discord extraction accepted a nonempty destination")
    finally:
        archive.close()
finally:
    distro_helper.pathlib.Path.lstat = original_path_lstat
    distro_helper.os.chown = original_chown

incomplete_host = fixture_root / "host-incomplete.tar"
create_host(incomplete_host, omit="files/libffmpeg.so")
expect_bad(
    "inspect",
    "--path",
    str(incomplete_host),
    "--kind",
    "host",
    "--version",
    version,
)

for label, member_name in (
    ("traversal", "files/../escape"),
    ("absolute", "/files/escape"),
    ("unexpected-root", "unexpected.json"),
):
    invalid_archive = fixture_root / f"module-{label}.tar"
    with tarfile.open(
        invalid_archive,
        mode="w",
        format=tarfile.PAX_FORMAT,
    ) as archive:
        add_file(archive, member_name, b"unsafe")
    expect_bad(
        "inspect",
        "--path",
        str(invalid_archive),
        "--kind",
        "module",
        "--version",
        version,
        "--module-name",
        "discord_voice",
        "--module-version",
        "1",
    )

invalid_metadata_archive = fixture_root / "module-metadata-directory.tar"
with tarfile.open(
    invalid_metadata_archive,
    mode="w",
    format=tarfile.PAX_FORMAT,
) as archive:
    add_directory(archive, "delta_manifest.json/")
    add_file(archive, "files/module.node", b"\x7fELFmodule")
expect_bad(
    "inspect",
    "--path",
    str(invalid_metadata_archive),
    "--kind",
    "module",
    "--version",
    version,
    "--module-name",
    "discord_voice",
    "--module-version",
    "1",
)

duplicate_archive = fixture_root / "module-duplicate.tar"
with tarfile.open(duplicate_archive, mode="w", format=tarfile.PAX_FORMAT) as archive:
    add_file(archive, "files/duplicate", b"one")
    add_file(archive, "files/duplicate", b"two")
expect_bad(
    "inspect",
    "--path",
    str(duplicate_archive),
    "--kind",
    "module",
    "--version",
    version,
    "--module-name",
    "discord_voice",
    "--module-version",
    "1",
)

parent_collision_archive = fixture_root / "module-parent-collision.tar"
with tarfile.open(
    parent_collision_archive,
    mode="w",
    format=tarfile.PAX_FORMAT,
) as archive:
    add_file(archive, "files/collision", b"file")
    add_file(archive, "files/collision/child", b"child")
expect_bad(
    "inspect",
    "--path",
    str(parent_collision_archive),
    "--kind",
    "module",
    "--version",
    version,
    "--module-name",
    "discord_voice",
    "--module-version",
    "1",
)

for label, member_type in (
    ("symlink", tarfile.SYMTYPE),
    ("hardlink", tarfile.LNKTYPE),
    ("character-device", tarfile.CHRTYPE),
    ("fifo", tarfile.FIFOTYPE),
):
    invalid_archive = fixture_root / f"module-{label}.tar"
    with tarfile.open(
        invalid_archive,
        mode="w",
        format=tarfile.PAX_FORMAT,
    ) as archive:
        member = tarfile.TarInfo("files/unsupported")
        member.type = member_type
        member.mode = 0o644
        member.linkname = "files/module.node"
        if member_type == tarfile.CHRTYPE:
            member.devmajor = 1
            member.devminor = 3
        archive.addfile(member)
    expect_bad(
        "inspect",
        "--path",
        str(invalid_archive),
        "--kind",
        "module",
        "--version",
        version,
        "--module-name",
        "discord_voice",
        "--module-version",
        "1",
    )

unsafe_destination = fixture_root / "user-owned-destination"
unsafe_destination.mkdir(mode=0o700)
unsafe_destination.chmod(0o777)
expect_bad(
    "extract",
    *module_arguments,
    "--destination",
    str(unsafe_destination),
)
PY
then
  discord_distro_fixtures_ok=true
fi

if grep -Eq '(^|[[:space:]])vivaldi-stable([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])telegram-desktop([[:space:]]|$)' "$software_class" &&
   grep -q '^d-i apt-setup/local10/repository string https://repo.vivaldi.com/archive/deb stable main$' "$software_class" &&
   grep -q '^d-i apt-setup/local10/key string https://repo.vivaldi.com/archive/linux_signing_key.pub$' "$software_class" &&
   grep -q '^LateHelper: software$' "$addons_cfg"; then
  pass "software class installs Vivaldi and Telegram Desktop and dispatches its late helper"
else
  fail "software class installs Vivaldi and Telegram Desktop and dispatches its late helper"
fi

if grep -Fq 'https://bitwarden.com/download/?app=desktop&platform=linux&variant=deb' "$software_helper" &&
   grep -q '^work_dir=/tmp/installer-software$' "$software_helper" &&
   ! grep -q '/var/tmp' "$software_helper" &&
   grep -q '^managed_application_minimum_bytes=1048576$' "$software_helper" &&
   [ "$(grep -c '"\$managed_application_minimum_bytes" \\$' "$software_helper")" -eq 6 ] &&
   ! grep -Eq '^[[:space:]]+(10485760|20971520|52428800) \\$' "$software_helper" &&
   grep -q -- "--proto '=https'" "$software_helper" &&
   grep -q -- "--proto-redir '=https'" "$software_helper" &&
   grep -q -- '--connect-timeout 15' "$software_helper" &&
   grep -q -- '--max-time 300' "$software_helper" &&
   grep -q -- "--max-filesize \"\\\$maximum_bytes\"" "$software_helper" &&
   grep -q "dpkg-deb -f \"\\\$deb_path\" Package" "$software_helper" &&
   grep -q "dpkg-deb -f \"\\\$deb_path\" Architecture" "$software_helper" &&
   grep -q '/opt/Bitwarden/bitwarden' "$software_helper" &&
   ! grep -q '^if software_download \\$' "$software_helper" &&
   ! grep -q '^[[:space:]]*defer$' "$software_helper" &&
   ! grep -q 'Bitwarden Desktop was not installed during Debian setup' "$software_helper" &&
   grep -q '^software_configure_chromium_sandbox() {$' "$software_helper" &&
   grep -Fq "chroot \"\$target_root\" /usr/bin/stat -c '%u:%g:%a' -- \"\$sandbox_path\"" "$software_helper" &&
   grep -Eq '^[[:space:]]+/opt/Bitwarden/chrome-sandbox$' "$software_helper" &&
   grep -q '^sub chromium_sandbox_valid {' "$software_deb" &&
   grep -q '^sub repair_chromium_sandbox {' "$software_deb" &&
   grep -Fq 'chown 0, 0, $path' "$software_deb" &&
   grep -Fq 'chmod 04755, $path' "$software_deb" &&
   grep -Fq 'return 0 if $st[4] != 0 || $st[5] != 0;' "$software_deb" &&
   grep -Fq "sandbox    => '/opt/Bitwarden/chrome-sandbox'," "$software_cli" &&
   grep -Fq "sandbox_presence => 'required'," "$software_cli" &&
   grep -Fq '$deb->repair_chromium_sandbox($app->{sandbox}, $app->{sandbox_presence})' "$software_cli"; then
  pass "Bitwarden installation is mandatory and updates preserve a verified root-owned Chromium sandbox"
else
  fail "Bitwarden installation is mandatory and updates preserve a verified root-owned Chromium sandbox"
fi

if grep -q '^obsidian_version=1.12.7$' "$software_helper" &&
   grep -Fq 'obsidian_url="https://github.com/obsidianmd/obsidian-releases/releases/download/v${obsidian_version}/obsidian_${obsidian_version}_amd64.deb"' "$software_helper" &&
   grep -q '^obsidian_sha256=3644e3ef19bcd23db4d17f7c73311b5245429391a2a48b361da93375f59712b0$' "$software_helper" &&
   grep -q '^obsidian_size=85762386$' "$software_helper" &&
   grep -q 'Obsidian package SHA-256 does not match the pinned release asset' "$software_helper" &&
   grep -q '/opt/Obsidian/obsidian' "$software_helper" &&
   grep -q '/usr/share/applications/obsidian.desktop' "$software_helper" &&
   grep -Fq 'chroot "$target_root" /usr/bin/desktop-file-validate \' "$software_helper" &&
   grep -Fq '/usr/share/applications/obsidian.desktop >/dev/null 2>&1' "$software_helper" &&
   grep -q '^sub _release {' "$software_obsidian" &&
   grep -Fq "url => 'https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest'," "$software_obsidian" &&
   grep -Fq '\Av([0-9]+\.[0-9]+\.[0-9]+)\z' "$software_obsidian" &&
   grep -Fq '\Asha256:([0-9a-f]{64})\z' "$software_obsidian" &&
   grep -q '^sub download {' "$software_obsidian" &&
   grep -Fq 'Obsidian package digest or size does not match release metadata' "$software_obsidian" &&
   grep -Fq "packages => ['obsidian']," "$software_obsidian" &&
   grep -q '^sub _stage_deb {' "$software_cli" &&
   grep -Fq "obsidian  => 'Obsidian'," "$software_notifier_module" &&
   grep -Fq 'Bitwarden, ChatGPT/Codex Desktop, Obsidian, Zoom, Filen, Discord, Sleek, Postman, Ledger, and Tuta Mail are being checked; QoreDB and Gridline remain checksum-pinned for local repair.' "$software_notifier_module"; then
  pass "Obsidian uses a pinned verified first install and digest-verified GitHub release updates"
else
  fail "Obsidian uses a pinned verified first install and digest-verified GitHub release updates"
fi

qoredb_profile_count=$(grep -R -l -F 'SOFTWARE_QOREDB_SHA256="59d6dc6c17009b90eba22dd2585969c9869518cb843ce4e50f29f6439824c6cb"' \
  "$ROOT_DIR/d-i/forky/hosts/profiles" | wc -l | awk '{print $1}')
gridline_profile_count=$(grep -R -l -F 'SOFTWARE_GRIDLINE_SHA256="13487e4eab3b0c47a21a26d95c69f0dd47fd592ffdc3509a93f1f39143482b56"' \
  "$ROOT_DIR/d-i/forky/hosts/profiles" | wc -l | awk '{print $1}')
software_install_deb_block=$(sed -n '/^software_install_deb() {$/,/^}$/p' "$software_helper")
software_download_block=$(sed -n '/^sub _run_download {$/,/^sub _run_apply {$/p' "$software_cli")
if [ "$qoredb_profile_count" -eq 13 ] &&
   [ "$gridline_profile_count" -eq 13 ] &&
   grep -Eq '(^|[[:space:]])usql([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])duckdb([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])mariadb-client([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])postgresql-client([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])default-mysql-client([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])mysql-shell([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])redis-tools([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])valkey-tools([[:space:]]|$)' "$software_class" &&
   ! grep -Eq '(^|[[:space:]])sqlite-utils([[:space:]]|$)' "$software_class" &&
   grep -Fq 'SOFTWARE_QOREDB_BYTES "$SOFTWARE_QOREDB_BYTES"' "$software_helper" &&
   grep -Fq 'SOFTWARE_GRIDLINE_BYTES "$SOFTWARE_GRIDLINE_BYTES"' "$software_helper" &&
   grep -Fq 'QoreDB package SHA-256 does not match the pinned release asset' "$software_helper" &&
   grep -Fq 'Gridline package SHA-256 does not match the pinned release asset' "$software_helper" &&
   grep -Fq '"qore-db" \' "$software_helper" &&
   grep -Fq '"gridline" \' "$software_helper" &&
   printf '%s\n' "$software_install_deb_block" | grep -Fq 'software_store_managed_deb_archive \' &&
   printf '%s\n' "$software_install_deb_block" | grep -Fq 'software_refresh_managed_deb_repository' &&
   printf '%s\n' "$software_install_deb_block" | grep -Fq 'install "$managed_archive_path"' &&
   ! printf '%s\n' "$software_install_deb_block" | grep -Fq 'install "$deb_path"' &&
   ! grep -Fq "'/usr/bin/dpkg', '--install'" "$software_repository" &&
   grep -Fq '$deb->install($archive, 1);' "$software_repository" &&
   grep -q '^sub _pinned_deb_specs {$' "$software_cli" &&
   grep -Fq "name       => 'qoredb'," "$software_cli" &&
   grep -Fq "name       => 'gridline'," "$software_cli" &&
   grep -Fq '$self->_pinned_deb_specs(),' "$software_cli" &&
   ! printf '%s\n' "$software_download_block" | grep -Fq '_pinned_deb_specs' &&
   grep -Fq 'mullvad_repository_dir=/var/lib/software/debs' "$mullvad_helper" &&
   grep -Fq 'install "$mullvad_install_deb_path"' "$mullvad_helper" &&
   managed_app_source_contains '"qoredb": {' &&
   managed_app_source_contains '"gridline": {' &&
   managed_app_source_contains '"database_state_directory": "qoredb"' &&
   managed_app_source_contains '"database_state_directory": "gridline"' &&
   managed_app_source_contains '^def ensure_managed_database_runtime_state(app_name: str) -> None:$' &&
   managed_app_source_contains '^def ensure_gridline_native_wayland_css($' &&
   grep -Fq 'usr/local/share/labwc-managed-app/gridline-gtk.css /usr/local/share/labwc-managed-app/gridline-gtk.css 0644' "$desktop_components" &&
   [ -s "$gridline_gtk_css" ] &&
   grep -Fq '"QoreDB.desktop"' "$launcher_sync" &&
   grep -Fq '"Gridline.desktop"' "$launcher_sync" &&
   grep -Fq 'profile qoredb /usr/bin/qoredb' "$qoredb_apparmor" &&
   grep -Fq 'profile gridline /usr/bin/gridline' "$gridline_apparmor" &&
   grep -Fq '/usr/lib/Gridline/resources/** mrix,' "$gridline_apparmor" &&
   grep -Fq 'owner /pool/db/*/** rwkl,' "$qoredb_apparmor" &&
   grep -Fq 'owner /pool/db/*/** rwkl,' "$gridline_apparmor" &&
   grep -Fq '/usr/bin/{gridline,qoredb} rPx,' "$managed_desktop_apparmor"; then
  pass "QoreDB and Gridline are checksum-pinned managed database apps with repository-first APT and AppArmor coverage"
else
  fail "QoreDB and Gridline are checksum-pinned managed database apps with repository-first APT and AppArmor coverage"
fi

if PYTHONPATH="$managed_app_package_root" python3 - "$gridline_gtk_css" "$labwc_rc" <<'PY'
import os
import pathlib
import stat
import sys
import tempfile
import xml.etree.ElementTree as ET

from labwc_managed_app import commands, environment, profiles

css_path = pathlib.Path(sys.argv[1])
css = css_path.read_text(encoding="utf-8")
assert 0 < len(css.encode("utf-8")) <= environment.GRIDLINE_GTK_CSS_MAXIMUM_BYTES
assert "eventbox.titlebar" in css
assert "eventbox.titlebar > headerbar" in css
assert "-gtk-icon-transform: scale(0);" in css

root = ET.parse(sys.argv[2]).getroot()
window_rules = [
    node.attrib
    for node in root.iter()
    if node.tag.rsplit("}", 1)[-1] == "windowRule"
]
assert window_rules == [
    {"identifier": "com.adrianbonpin.gridline", "serverDecoration": "yes"},
    {"identifier": "*", "serverDecoration": "yes"},
]

assert profiles.WAYLAND_COMPAT_APPS == ("discord", "zoom")
assert "gridline" not in profiles.WAYLAND_COMPAT_APPS
original_home = environment.current_user_home
original_name = environment.current_user_name
original_runtime = environment.current_user_runtime_dir
environment.current_user_home = lambda: "/home/gridline-test"
environment.current_user_name = lambda: "gridline-test"
environment.current_user_runtime_dir = lambda: "/run/user/1000"
try:
    gridline_environment = environment.build_environment("gridline", "launch")
finally:
    environment.current_user_home = original_home
    environment.current_user_name = original_name
    environment.current_user_runtime_dir = original_runtime
assert gridline_environment["GDK_BACKEND"] == "wayland"
assert gridline_environment["XDG_CONFIG_HOME"] == "/pool/db/gridline-test/gridline/config"
assert "DISPLAY" not in gridline_environment
assert "XAUTHORITY" not in gridline_environment
assert "/opt/xwayland" not in commands.managed_library_path("gridline").split(os.pathsep)

original_require_directory = environment.require_root_owned_directory
original_load_text = environment.load_root_owned_text
environment.require_root_owned_directory = lambda _path: None
environment.load_root_owned_text = lambda _path, _maximum: css
try:
    with tempfile.TemporaryDirectory() as temporary_root:
        state_root = pathlib.Path(temporary_root) / "gridline"
        config_directory = state_root / "config"
        config_directory.mkdir(parents=True, mode=0o700)
        environment.ensure_gridline_native_wayland_css(
            str(state_root),
            os.getuid(),
            os.getgid(),
        )
        gtk_directory = config_directory / "gtk-3.0"
        managed_css = gtk_directory / "gtk.css"
        assert managed_css.read_text(encoding="utf-8") == css
        assert stat.S_IMODE(gtk_directory.stat().st_mode) == 0o700
        assert stat.S_IMODE(managed_css.stat().st_mode) == 0o600

        managed_css.write_text("stale\n", encoding="utf-8")
        os.chmod(managed_css, 0o666)
        environment.ensure_gridline_native_wayland_css(
            str(state_root),
            os.getuid(),
            os.getgid(),
        )
        assert managed_css.read_text(encoding="utf-8") == css
        assert stat.S_IMODE(managed_css.stat().st_mode) == 0o600

        sentinel = pathlib.Path(temporary_root) / "sentinel"
        sentinel.write_text("unchanged\n", encoding="utf-8")
        managed_css.unlink()
        managed_css.symlink_to(sentinel)
        try:
            environment.ensure_gridline_native_wayland_css(
                str(state_root),
                os.getuid(),
                os.getgid(),
            )
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("Gridline GTK CSS accepted a symlink destination")
        assert sentinel.read_text(encoding="utf-8") == "unchanged\n"
finally:
    environment.require_root_owned_directory = original_require_directory
    environment.load_root_owned_text = original_load_text
PY
then
  pass "Gridline stays native Wayland while its private GTK headerbar policy is refreshed atomically"
else
  fail "Gridline stays native Wayland while its private GTK headerbar policy is refreshed atomically"
fi

if grep -q '^software_restore_managed_apparmor_profiles() {$' "$software_helper" &&
   grep -q '^    opt.Bitwarden.bitwarden \\$' "$software_helper" &&
   grep -q '^    usr.bin.qoredb \\$' "$software_helper" &&
   grep -q '^    usr.bin.gridline \\$' "$software_helper" &&
   grep -q '^    obsidian \\$' "$software_helper" &&
   grep -q '^    sleek \\$' "$software_helper" &&
   grep -q '^    Discord \\$' "$software_helper" &&
   grep -q '^software_restore_managed_apparmor_profiles$' "$software_helper"; then
  pass "vendor package installation restores repository-managed AppArmor profiles"
else
  fail "vendor package installation restores repository-managed AppArmor profiles"
fi

if grep -q '^postman_url=https://dl.pstmn.io/download/latest/linux64$' "$software_helper" &&
   grep -q '^postman_install_dir=/opt/postman$' "$software_helper" &&
   grep -q '^postman_desktop_file=/usr/share/applications/postman.desktop$' "$software_helper" &&
   grep -q '^postman_icon_file="${postman_install_dir}/app/resources/app/assets/icon.png"$' "$software_helper" &&
   grep -q '^software_install_postman() {$' "$software_helper" &&
   grep -Fq 'chroot "$target_root" /bin/sh -eu -s -- \' "$software_helper" &&
   grep -Fq "<<'POSTMAN_INSTALL_SH'" "$software_helper" &&
   [ "$postman_install_syntax_ok" = true ] &&
   grep -Fq '$0 !~ /^Postman\//' "$software_helper" &&
   grep -q 'tar --numeric-owner -tvzf "$postman_archive"' "$software_helper" &&
   grep -q 'Postman archive contains an unsupported node or symlink' "$software_helper" &&
   grep -q '\$6 != "Postman/Postman"' "$software_helper" &&
   grep -q '\$8 != "app/Postman"' "$software_helper" &&
   grep -q 'Postman archive contains too many members' "$software_helper" &&
   grep -q '^    Postman/app/libffmpeg.so \\$' "$software_helper" &&
   grep -q '\\[ -f "\\$new_dir/app/libffmpeg.so" \\].*\\[ -r "\\$new_dir/app/libffmpeg.so" \\]' "$software_helper" &&
   grep -q 'Postman/app/resources/app/assets/icon.png' "$software_helper" &&
   grep -q -- '--strip-components=1' "$software_helper" &&
   grep -q 'chmod 4755 "$new_dir/app/chrome-sandbox"' "$software_helper" &&
   grep -q 'if os.path.getsize(package_path) > 1048576:' "$software_helper" &&
   grep -q 'package = json.load(stream)' "$software_helper" &&
   grep -Fq 're.fullmatch(r"[0-9]+(?:[.][0-9]+)*", version)' "$software_helper" &&
   [ "$postman_minified_version" = 12.20.1 ] &&
   grep -q 'archive_sha256=${archive_sha256}' "$software_helper" &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ postman %U$' "$postman_desktop_template" &&
   grep -q '^software_render_seed_asset() {$' "$software_helper" &&
   grep -q 'LABWC_MANAGED_APP_DEFAULT_EXEC "\$LABWC_MANAGED_APP_DEFAULT_EXEC"' "$software_helper" &&
   grep -q '^TryExec=/opt/postman/app/Postman$' "$postman_desktop" &&
   grep -q '^Exec=/usr/local/bin/labwc-managed-app nvidia postman %U$' "$postman_desktop" &&
   grep -q '^Icon=/opt/postman/app/resources/app/assets/icon.png$' "$postman_desktop" &&
   if command -v desktop-file-validate >/dev/null 2>&1; then
     desktop-file-validate "$postman_desktop"
   else
     true
   fi
then
  pass "Postman is archive-validated, parses minified package metadata, atomically publishes below /opt/postman, and exposes its bundled icon"
else
  fail "Postman is archive-validated, parses minified package metadata, atomically publishes below /opt/postman, and exposes its bundled icon"
fi

if grep -q '^sleek_version=2.0.26$' "$software_helper" &&
   grep -Fq 'sleek_url="https://github.com/ransome1/sleek/releases/download/v${sleek_version}/sleek-${sleek_version}-linux-amd64.deb"' "$software_helper" &&
   grep -q '^sleek_sha256=f2531c41b70c04bbafc27af83e195aa9268845a58d3ead4b58fa58b301223fcb$' "$software_helper" &&
   grep -q '^sleek_size=107065664$' "$software_helper" &&
   grep -q 'Sleek package SHA-256 does not match the pinned release asset' "$software_helper" &&
   grep -q '^  "Sleek" \\$' "$software_helper" &&
   grep -q '^  /opt/sleek/sleek \\$' "$software_helper" &&
   grep -q '^  /usr/share/applications/sleek.desktop \\$' "$software_helper" &&
   grep -q '^  /opt/sleek/libffmpeg.so$' "$software_helper" &&
   grep -q 'Sleek installed version does not match the pinned release' "$software_helper" &&
   grep -q 'target/usr/share/applications/sleek.desktop' "$software_helper" &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ sleek %U$' "$sleek_desktop_template" &&
   grep -q '^TryExec=/opt/sleek/sleek$' "$sleek_desktop" &&
   grep -q '^Exec=/usr/local/bin/labwc-managed-app nvidia sleek %U$' "$sleek_desktop" &&
   grep -q '^Categories=Office;ProjectManagement;$' "$sleek_desktop" &&
   if command -v desktop-file-validate >/dev/null 2>&1; then
     desktop-file-validate "$sleek_desktop"
   else
     true
   fi
then
  pass "Sleek 2.0.26 is size- and digest-pinned before target APT installation"
else
  fail "Sleek 2.0.26 is size- and digest-pinned before target APT installation"
fi

if grep -q 'chroot "$target_root" /usr/bin/env -i' "$software_helper" &&
   grep -Eq '^d-i pkgsel/include string .* mullvad-browser([[:space:]]|$)' "$software_class" &&
   ! grep -Eq '^d-i pkgsel/include string .* resolvconf([[:space:]]|$)' "$software_class" &&
   ! grep -Eq '^d-i pkgsel/include string .* systemd-resolved([[:space:]]|$)' "$software_class" &&
   ! grep -Eq '^d-i pkgsel/include string .* mullvad-vpn([[:space:]]|$)' "$software_class" &&
   grep -Eq '^d-i pkgsel/include string mullvad-browser$' "$mullvad_class" &&
   ! grep -Eq '^d-i pkgsel/include string .* resolvconf([[:space:]]|$)' "$mullvad_class" &&
   ! grep -Eq '^d-i pkgsel/include string .* systemd-resolved([[:space:]]|$)' "$mullvad_class" &&
   ! grep -Eq '^d-i pkgsel/include string .* mullvad-vpn([[:space:]]|$)' "$mullvad_class" &&
   ! grep -q '^resolvconf resolvconf/linkify-resolvconf ' "$software_class" &&
   ! grep -q '^resolvconf resolvconf/linkify-resolvconf ' "$mullvad_class" &&
   grep -q '^MULLVAD_CODE_SIGNING_FINGERPRINT=A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF$' "$mullvad_helper" &&
   grep -q '^MULLVAD_AMD64_DEB_URL=https://mullvad.net/en/download/app/deb/latest$' "$mullvad_helper" &&
   grep -q '^MULLVAD_ARM64_DEB_URL=https://mullvad.net/en/download/app/arm-deb/latest$' "$mullvad_helper" &&
   grep -q -- "--proto '=https'" "$mullvad_helper" &&
   grep -q -- "--proto-redir '=https'" "$mullvad_helper" &&
   grep -q -- '--max-filesize "$mullvad_download_maximum"' "$mullvad_helper" &&
   grep -q -- '--import-options show-only' "$mullvad_helper" &&
   grep -q -- '--status-fd 1' "$mullvad_helper" &&
   grep -q 'Mullvad code signing key fingerprint mismatch' "$mullvad_helper" &&
   grep -q 'Mullvad VPN artifact has unexpected Package field' "$mullvad_helper" &&
   grep -q 'Mullvad VPN artifact architecture mismatch' "$mullvad_helper" &&
   grep -q 'installer_selected_class_reference_is_selected addon/software' "$mullvad_helper" &&
   grep -q 'installer_selected_class_reference_is_selected apps/mullvad' "$mullvad_helper" &&
   grep -q '^mullvad_capture_target_resolver() {$' "$mullvad_helper" &&
   grep -q '^install_target_systemd_resolved_for_mullvad() {$' "$mullvad_helper" &&
   grep -q '^mullvad_seed_target_resolved_stub() {$' "$mullvad_helper" &&
   grep -q 'install systemd-resolved for Mullvad DNS integration' "$mullvad_helper" &&
   grep -q 'legacy resolvconf must not remain installed with systemd-resolved' "$mullvad_helper" &&
   ! grep -q 'install resolvconf' "$mullvad_helper" &&
   grep -q '^MULLVAD_RESOLVER_SOURCE=/tmp/installer-mullvad-resolv.conf$' "$mullvad_helper" &&
   grep -q '^MULLVAD_RESOLVED_STUB=/run/systemd/resolve/stub-resolv.conf$' "$mullvad_helper" &&
   grep -Fq 'mullvad_target_root=$(target_root_dir)' "$mullvad_helper" &&
   grep -Fq 'mullvad_target_run="${mullvad_target_root%/}/run"' "$mullvad_helper" &&
   grep -Fq 'target_mount_source "$mullvad_target_run"' "$mullvad_helper" &&
   grep -Fq 'refusing to refresh the persistent target resolver while ${mullvad_target_run} is mounted from ${mullvad_target_run_source}' "$mullvad_helper" &&
   grep -Fq 'chroot "$mullvad_target_root" /usr/bin/env -i' "$mullvad_helper" &&
   ! sed -n '/^mullvad_seed_target_resolved_stub() {$/,/^}$/p' "$mullvad_helper" | grep -q 'run_in_target' &&
   grep -Fq '[ "$resolver_owner_group" = 0:0 ]' "$mullvad_helper" &&
   grep -Fq '[ "$(/usr/bin/readlink -f /usr/sbin/resolvconf)" = /usr/bin/resolvectl ]' "$mullvad_helper" &&
   grep -q 'resolver_path=.*readlink -m /etc/resolv.conf' "$mullvad_helper" &&
   grep -Fq '[ "$resolver_path" = "$resolved_stub" ]' "$mullvad_helper" &&
   grep -Fq '/bin/cat -- "$resolver_source" >"$resolved_stub_tmp"' "$mullvad_helper" &&
   grep -Fq '[ "$(/usr/bin/stat -c %a -- "$resolved_stub")" = 644 ]' "$mullvad_helper" &&
   grep -Fq '/usr/bin/getent ahosts "$resolver_host"' "$mullvad_helper" &&
   grep -q '^MULLVAD_BITWARDEN_RESOLVER_HOST=bitwarden.com$' "$mullvad_helper" &&
   grep -q '^MULLVAD_GITHUB_RESOLVER_HOST=github.com$' "$mullvad_helper" &&
   [ "$(grep -c '^  mullvad_seed_target_resolved_stub ' "$mullvad_helper")" -eq 2 ] &&
   grep -q '^install_target_mullvad_vpn_if_selected() ($' "$mullvad_helper" &&
   [ "$(grep -n '^  install_target_systemd_resolved_for_mullvad$' "$mullvad_helper" | cut -d: -f1)" -lt "$(grep -n '^  mullvad_existing_status=' "$mullvad_helper" | cut -d: -f1)" ] &&
   [ "$(grep -n '^  mullvad_seed_target_resolved_stub mullvad-vpn-installation$' "$mullvad_helper" | cut -d: -f1)" -gt "$(grep -n '    \"install verified Mullvad VPN package\"' "$mullvad_helper" | cut -d: -f1)" ] &&
   grep -q 'install verified Mullvad VPN package' "$mullvad_helper" &&
   grep -q 'shared_modules=.* mullvad ' "$late_dispatch" &&
   grep -q '^  mullvad \\$' "$shared_late_loader" &&
   grep -q '^install_target_mullvad_vpn_if_selected$' "$btrfs_late" &&
   grep -q '^install_target_mullvad_vpn_if_selected$' "$f2fs_late" &&
	   grep -q '^Environment=TALPID_DNS_MODULE=systemd$' "$mullvad_dns_dropin" &&
	   grep -q '^Environment=MULLVAD_CACHE_DIR=/var/lib/mullvad-version-cache$' "$mullvad_dns_dropin" &&
	   grep -q '^Requires=systemd-resolved.service systemd-tmpfiles-setup.service$' "$mullvad_dns_dropin" &&
	   grep -q '^After=local-fs.target systemd-resolved.service systemd-tmpfiles-setup.service$' "$mullvad_dns_dropin" &&
	   grep -q '^RequiresMountsFor=/var/lib/mullvad-version-cache$' "$mullvad_dns_dropin" &&
	   ! grep -q '^CacheDirectory=' "$mullvad_dns_dropin" &&
	   ! grep -q '^CacheDirectoryMode=' "$mullvad_dns_dropin" &&
	   grep -q '^StateDirectory=mullvad-version-cache$' "$mullvad_dns_dropin" &&
	   grep -q '^StateDirectoryMode=0755$' "$mullvad_dns_dropin" &&
	   ! grep -q '^BindPaths=' "$mullvad_dns_dropin" &&
	   grep -q '^d /var/lib/mullvad-version-cache 0755 root root -$' "$mullvad_tmpfiles" &&
	   ! grep -q 'version-info.json' "$mullvad_tmpfiles" &&
	   grep -q 'cache_seed=vendor-managed' "$desktop_components" &&
	   ! grep -q 'cache_file_mode=' "$desktop_components" &&
	   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/mullvad-version-cache-primer" ] &&
	   [ ! -e "$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/mullvad-version-cache-primer.service" ] &&
	   ! grep -q '^profile managed-mullvad-version-cache-primer ' "$managed_system_apparmor" &&
	   grep -q '^desktop_mullvad_selected() {$' "$desktop_components" &&
   grep -q 'installer_selected_class_reference_is_selected addon/software' "$desktop_components" &&
   grep -q 'installer_selected_class_reference_is_selected apps/mullvad' "$desktop_components" &&
	   grep -q '^desktop_stage_mullvad_dns_policy() {$' "$desktop_components" &&
	   grep -q 'for package_name in mullvad-vpn systemd-resolved; do' "$desktop_components" &&
	   grep -q 'legacy resolvconf must not be installed with systemd-resolved' "$desktop_components" &&
	   grep -q 'systemd-resolved resolvconf compatibility link is invalid' "$desktop_components" &&
	   grep -q '/etc/resolv.conf is not owned by systemd-resolved' "$desktop_components" &&
	   grep -q 'target_systemd_unit_path mullvad-daemon.service system' "$desktop_components" &&
	   grep -q 'etc/systemd/system/mullvad-daemon.service.d/20-managed-dns.conf' "$desktop_components" &&
	   grep -q 'etc/tmpfiles.d/51-mullvad-version-cache.conf' "$desktop_components" &&
	   ! grep -q 'mullvad-version-cache-primer' "$desktop_components" &&
	   grep -q 'desktop_enable_unit_if_available systemd-resolved.service system' "$desktop_components" &&
	   grep -q 'desktop_disable_unit_if_available mullvad-daemon.service system' "$desktop_components" &&
	   ! grep -q 'desktop_enable_unit_if_available mullvad-daemon.service system' "$desktop_components" &&
	   grep -q '^desktop_stage_mullvad_application_policy() {$' "$desktop_components" &&
	   grep -q 'usr/local/bin/mullvad-vpn' "$desktop_components" &&
	   grep -q 'usr/local/libexec/mullvad-daemon-start' "$desktop_components" &&
	   grep -q 'usr/local/share/applications/mullvad-vpn.desktop' "$desktop_components" &&
	   grep -q 'etc/skel/.config/autostart/mullvad-vpn.desktop' "$desktop_components" &&
	   grep -q '^    [. ]*config/autostart \\$' "$desktop_components" &&
	   /bin/sh -n "$mullvad_vpn_wrapper" &&
	   /bin/sh -n "$mullvad_daemon_start" &&
	   grep -Fqx '[ "$#" -eq 0 ] || fatal "usage: mullvad-vpn"' "$mullvad_vpn_wrapper" &&
	   grep -Fqx '[ "$(/usr/bin/id -u)" -ne 0 ] || fatal "Mullvad VPN must not run as root"' "$mullvad_vpn_wrapper" &&
	   grep -Fqx "vendor_launcher='/opt/Mullvad VPN/mullvad-vpn'" "$mullvad_vpn_wrapper" &&
	   grep -Fq '/usr/bin/systemctl --quiet is-active "$daemon_unit"' "$mullvad_vpn_wrapper" &&
	   grep -q '^      /usr/bin/pkexec \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^      --kill-after=5s \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^      120s \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^  DISPLAY \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^  WLR_XWAYLAND \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^  XAUTHORITY \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^  XWAYLAND_PATH \\$' "$mullvad_vpn_wrapper" &&
	   grep -q '^  _XWAYLAND_GLOBAL_OUTPUT_SCALE$' "$mullvad_vpn_wrapper" &&
	   grep -Fqx 'ELECTRON_OZONE_PLATFORM_HINT=wayland' "$mullvad_vpn_wrapper" &&
	   grep -Fqx 'GDK_BACKEND=wayland' "$mullvad_vpn_wrapper" &&
	   grep -Fqx 'QT_QPA_PLATFORM=wayland' "$mullvad_vpn_wrapper" &&
	   grep -Fqx 'SDL_VIDEODRIVER=wayland' "$mullvad_vpn_wrapper" &&
	   grep -Fqx '  --enable-features=UseOzonePlatform \' "$mullvad_vpn_wrapper" &&
	   grep -Fqx '  --ozone-platform=wayland' "$mullvad_vpn_wrapper" &&
	   grep -Fqx '[ "$(/usr/bin/id -u)" -eq 0 ] ||' "$mullvad_daemon_start" &&
	   grep -Fqx '  fatal "Mullvad daemon start helper must run as root"' "$mullvad_daemon_start" &&
	   grep -Fq 'case "${PKEXEC_UID:-}" in' "$mullvad_daemon_start" &&
	   grep -Fqx '/usr/bin/systemctl start "$daemon_unit"' "$mullvad_daemon_start" &&
	   grep -Fqx 'Exec=/usr/local/bin/mullvad-vpn' "$mullvad_desktop" &&
	   grep -Fqx 'DBusActivatable=false' "$mullvad_desktop" &&
	   grep -Fqx 'Exec=/usr/local/bin/mullvad-vpn' "$mullvad_autostart" &&
	   grep -Fqx 'Hidden=true' "$mullvad_autostart" &&
	   grep -Fqx 'X-GNOME-Autostart-enabled=false' "$mullvad_autostart" &&
	   ! grep -R -q '^TAILSCALE_ACCEPT_DNS="true"$' "$ROOT_DIR/d-i/forky/hosts/profiles" &&
	   grep -Fq -- '--accept-dns="$TAILSCALE_ACCEPT_DNS"' "$tailscale_helper" &&
	   ! grep -Eq '(^|[[:space:]])systemd-resolved([[:space:]]|$)' "$desktop_class"; then
  pass "Mullvad keeps systemd-resolved DNS ownership while boot and GUI autostart stay disabled and manual launch is native Wayland"
else
  fail "Mullvad keeps systemd-resolved DNS ownership while boot and GUI autostart stay disabled and manual launch is native Wayland"
fi

if grep -Fq 'https://zoom.us/client/latest/zoom_amd64.deb' "$software_helper" &&
   grep -Fq 'https://cdn.filen.io/@filen/desktop/release/latest/Filen_linux_amd64.deb' "$software_helper" &&
   grep -q '^software_install_deb() {$' "$software_helper" &&
   grep -q -- "--write-out '%{http_code}\\\\n%{url_effective}\\\\n%{content_type}'" "$software_helper" &&
   grep -q 'partial_destination="${destination}.part"' "$software_helper" &&
   grep -q 'normalized_content_type' "$software_helper" &&
   grep -q 'artifact:text/html|artifact:text/plain|artifact:text/xml|artifact:application/json|artifact:application/xml' "$software_helper" &&
   grep -q '^software_deb_contains_path() {$' "$software_helper" &&
   grep -q 'dpkg-deb --info "\$deb_path"' "$software_helper" &&
   grep -q "\[ \"\\\$deb_magic\" = '!<arch>' \]" "$software_helper" &&
   grep -q 'dpkg-deb -f "\$deb_path" Package' "$software_helper" &&
   grep -q 'dpkg-deb -f "\$deb_path" Version' "$software_helper" &&
   grep -q 'dpkg-deb -f "\$deb_path" Architecture' "$software_helper" &&
   grep -q '^  expected_runtime_library=${7:-}$' "$software_helper" &&
   grep -q 'package payload is missing runtime library' "$software_helper" &&
   grep -q 'runtime library is missing after package installation' "$software_helper" &&
   grep -q '^    NEEDRESTART_SUSPEND=1 \\$' "$software_helper" &&
   grep -q 'The scheduled external-software updater uses the same policy' "$software_helper" &&
   grep -q '^software_ensure_temporary_unshare() {$' "$software_helper" &&
   grep -q '^temporary_unshare_hook=/usr/lib/pre-pkgsel.d/89temporary-unshare$' "$software_helper" &&
   grep -q '^software_ensure_temporary_unshare$' "$software_helper" &&
   grep -q '^  for expected_package in \$expected_packages; do$' "$software_helper" &&
   grep -q '^  "filen filen-desktop" \\$' "$software_helper" &&
   ! grep -q 'expected package names contain unsupported characters' "$software_helper" &&
   grep -q '^sub validate {' "$software_deb" &&
   grep -Fq "ExternalSoftware::Servicing::Atomic->read_limited(\$args{path}, 536_870_912) =~ /\\A!<arch>\\n/" "$software_deb" &&
   grep -Fq "'NEEDRESTART_SUSPEND=1'," "$software_deb" &&
   grep -Fq "'-o', 'DPkg::Lock::Timeout=120', '-o', 'DPkg::Use-Pty=0'," "$software_deb" &&
   grep -Fq "my @reinstall_args = \$reinstall ? ('--reinstall') : ();" "$software_deb" &&
   grep -Fq "'--no-remove', '--no-install-recommends', '--no-install-suggests'," "$software_deb" &&
   grep -Fq "@reinstall_args," "$software_deb" &&
   grep -q 'package is missing its expected runtime library' "$software_deb" &&
   grep -Fq "packages   => [qw(filen filen-desktop)]," "$software_cli" &&
   grep -Fq "library    => '/opt/Filen/libffmpeg.so'," "$software_cli" &&
   grep -Fq '$deb->install($candidate->{path}, $reinstall);' "$software_cli" &&
   grep -q -- '-o DPkg::Use-Pty=0' "$software_helper" &&
   grep -q -- "-f='\\\${Status}'" "$software_helper" &&
   grep -q '\[ "\$installed_package_status" = "install ok installed" \]' "$software_helper" &&
   ! grep -q '\${db:Status-Abbrev}' "$software_helper" &&
   grep -q 'chroot "\$target_root" /usr/bin/test -x "\$expected_executable"' "$software_helper" &&
   grep -q 'chroot "\$target_root" /usr/bin/test -r "\$expected_desktop_file"' "$software_helper" &&
   ! grep -q '\[ -x "\${target_root}\${expected_executable}" \]' "$software_helper" &&
   grep -q '/usr/share/applications/Zoom.desktop' "$software_helper" &&
   grep -q '/opt/Filen/Filen' "$software_helper" &&
   grep -q '/opt/Filen/libffmpeg.so' "$software_helper" &&
   grep -q '/usr/share/applications/Filen.desktop' "$software_helper" &&
   grep -q '/opt/sleek/libffmpeg.so' "$software_helper" &&
   grep -q '/usr/share/applications/sleek.desktop' "$software_helper"; then
  pass "automatic vendor Debian transactions suppress needrestart handling and validate in-target payloads"
else
  fail "automatic vendor Debian transactions suppress needrestart handling and validate in-target payloads"
fi

if grep -Eq '(^|[[:space:]])brotli([[:space:]]|$)' "$software_class" &&
   [ -x "$software_discord_archive_helper" ] &&
   [ "$discord_distro_fixtures_ok" = true ] &&
   [ "$discord_servicing_behavior_ok" = true ] &&
   grep -Fq 'https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=linux&arch=x64' "$software_discord" &&
   grep -Fq "use constant DISTRO_USER_AGENT => 'Discord-Updater/1';" "$software_discord" &&
   grep -Fq 'use constant HOST_MINIMUM_BYTES => 8 * 1024 * 1024;' "$software_discord" &&
   grep -Fq "'/usr/bin/brotli', '--decompress', '--stdout', \$source" "$software_discord" &&
   grep -Fq "retain_artifact(" "$software_discord" &&
   grep -Fq "'discord'," "$software_discord" &&
   grep -Fq "discord.installed.json" "$software_discord" &&
   grep -Fq "discord.pending.json" "$software_discord" &&
   grep -Fq 'my $staged = "/opt/.discord.new.$$";' "$software_discord" &&
   grep -Fq "my \$backup = '/opt/.discord.previous';" "$software_discord" &&
   grep -Fq 'sub bootstrap {' "$software_discord" &&
   grep -Fq 'sub repair {' "$software_discord" &&
   grep -Fq "ExternalSoftware::Servicing::Discord" "$software_cli" &&
   grep -Fq -- '--bootstrap-discord' "$software_cli" &&
   grep -Fq 'ExternalSoftware/Servicing/Discord.pm' "$software_helper" &&
   grep -Fq 'target/usr/local/libexec/managed-discord-distro' "$software_helper" &&
   grep -Fq 'software_discord_artifact_dir="${software_artifact_dir}/discord"' "$software_helper" &&
   grep -Fq 'discord_install_dir=/opt/discord' "$software_helper" &&
   grep -Fq -- '--bootstrap-discord' "$software_helper" &&
   ! grep -Fq '"${discord_install_dir}/resources/app.asar" \' "$software_helper" &&
   ! grep -Fq 'resources/app.asar' "$software_discord" "$software_discord_archive_helper" &&
   grep -Fq 'managed Discord runtime is incomplete after bootstrap' "$software_helper" &&
   grep -Fq 'chroot "$target_root" /usr/bin/test -u "${discord_install_dir}/chrome-sandbox"' "$software_helper" &&
   grep -Fq 'managed Discord runtime executables are invalid after bootstrap' "$software_helper" &&
   grep -Fq 'managed Discord runtime directory mode is unsafe:' "$software_discord" &&
   grep -Fq '(mode $actual_mode, expected 0755)' "$software_discord" &&
   ! grep -Fq 'https://discord.com/api/download?platform=linux&format=deb' "$software_helper" "$software_cli" &&
   grep -Fq 'TryExec=/opt/discord/Discord' "$discord_desktop_template" &&
   grep -Fq 'Exec=/usr/local/bin/discord %U' "$discord_desktop_template" &&
   grep -Fq 'Icon=/opt/discord/discord.png' "$discord_desktop_template" &&
   [ "$external_apply_no_network" = true ] &&
   if command -v desktop-file-validate >/dev/null 2>&1; then
     desktop-file-validate "$discord_desktop_template"
   else
     true
   fi
then
  pass "Discord uses validated Brotli host and module distributions, retained root-owned state, and atomic /opt publication"
else
  fail "Discord uses validated Brotli host and module distributions, retained root-owned state, and atomic /opt publication"
fi

if grep -Fq 'https://app.tuta.com/desktop/tutanota-desktop-linux.AppImage' "$software_helper" &&
   grep -Fq 'https://app.tuta.com/desktop/linux-sig.bin' "$software_helper" &&
   grep -q '9566e054634a75f540b64db71b92b040bc77f9a3954d737cb01c4630c1225127' "$software_helper" &&
   grep -q '/usr/bin/openssl dgst' "$software_helper" &&
   grep -q -- '-sha512' "$software_helper" &&
   grep -q -- "-verify \"\\\$tuta_public_key\"" "$software_helper" &&
   grep -q -- '--appimage-extract' "$software_helper" &&
   grep -q "chown -R root:root \"\\\$new_dir\"" "$software_helper" &&
   grep -Fq '/usr/bin/find "$new_dir" -xdev -type d -exec /bin/chmod 0755 {} +' "$software_helper" &&
   grep -Fq '/usr/bin/find "$new_dir" -xdev -type f -exec /bin/chmod a-s,go-w {} +' "$software_helper" &&
   grep -Fq '/bin/chmod 0755 "$new_dir/AppRun"' "$software_helper" &&
   grep -q 'tuta_icon_file=/usr/share/icons/hicolor/512x512/apps/tuta-mail.png' "$software_helper"; then
  pass "Tuta AppImage is signature-verified, extracted atomically, root-owned, fully traversable, set-ID-free, and given a managed icon"
else
  fail "Tuta AppImage is signature-verified, extracted atomically, root-owned, fully traversable, set-ID-free, and given a managed icon"
fi

if openssl pkey -pubin -in "$tuta_public_key" -noout >/dev/null 2>&1 &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ tutanota %U$' "$tuta_desktop_template" &&
   grep -q '^Exec=/usr/local/bin/labwc-managed-app nvidia tutanota %U$' "$tuta_desktop" &&
   grep -q '^Icon=tuta-mail$' "$tuta_desktop" &&
   grep -q '^Categories=Network;Email;$' "$tuta_desktop" &&
   if command -v desktop-file-validate >/dev/null 2>&1; then
     desktop-file-validate "$tuta_desktop"
   else
     true
   fi
then
  pass "Tuta public key and desktop launcher parse cleanly"
else
  fail "Tuta public key and desktop launcher parse cleanly"
fi

if grep -Fq 'ledger_requested_latest_url=https://download.live.ledger.com/latest/linux' "$software_helper" &&
   grep -Fq 'ledger_metadata_url=https://download.live.ledger.com/latest-linux.yml' "$software_helper" &&
   grep -Fq 'resources.live.ledger.app/public_resources/signatures' "$software_helper" &&
   grep -q '0381bccfa5505e834f9fda30eeba257055782f30c495ba0604a0cd37b548c6fc' "$software_helper" &&
   grep -q '^software_parse_ledger_metadata() {$' "$software_helper" &&
   grep -Fq "grep -c '^    size: '" "$software_helper" &&
   grep -Fq "sed -n 's/^    size: //p'" "$software_helper" &&
   grep -q '^software_ledger_signed_sha512() {$' "$software_helper" &&
   grep -q 'Ledger Live AppImage SHA-512 does not match the signed vendor manifest' "$software_helper" &&
   grep -q 'extracted_file_count=.*find "\$extracted" -xdev -printf' "$software_helper" &&
   grep -q '\[ "\$extracted_file_count" -le 20000 \]' "$software_helper" &&
   grep -q '\[ "\$extracted_kib" -le 1048576 \]' "$software_helper" &&
   grep -q 'chmod 4755 "\$new_dir/chrome-sandbox"' "$software_helper" &&
   grep -q '^account_env=${INSTALLER_LATE_ACCOUNT_ENV:-/tmp/install-env-late/account.env}$' "$software_helper" &&
   grep -q '^runtime_common=/tmp/install-env-late/runtime-common.sh$' "$software_helper" &&
   grep -q '^account_runtime=/tmp/install-env-late/account-runtime.sh$' "$software_helper" &&
   grep -q '^runtime_apply_account_from_cmdline$' "$software_helper" &&
   [ "$(grep -c "tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'" "$software_helper")" -eq 2 ] &&
   ! grep -Fq "tr '[:upper:]' '[:lower:]'" "$software_helper" &&
   ! grep -Fq "tr -d '[:space:]'" "$software_helper" &&
   ! grep -Fq 'tr -d "[:space:]"' "$software_helper" &&
   grep -q 'metadata:application/yaml' "$software_helper" &&
   grep -q 'metadata:text/plain' "$software_helper" &&
   grep -q '^sub _parse_metadata {' "$software_ledger" &&
   grep -Fq "url => 'https://download.live.ledger.com/latest-linux.yml'," "$software_ledger" &&
   grep -Fq 'resources.live.ledger.app/public_resources/signatures' "$software_ledger" &&
   grep -Fq 'Ledger public key fingerprint does not match its pinned key' "$software_ledger" &&
   grep -Fq 'Ledger checksum signature verification failed' "$software_ledger" &&
   grep -Fq 'Ledger extracted AppImage payload exceeds safe bounds' "$software_ledger" &&
   grep -Fq 'chmod 04755, $sandbox' "$software_ledger" &&
   grep -q '^sub fetch {' "$software_ledger" &&
   grep -q '^sub apply {' "$software_ledger" &&
   grep -Fq -- "->retain_artifact('ledger', \$image, \$release->{path})" "$software_ledger" &&
   grep -Fq "artifact_path('ledger', \$pending->{name})" "$software_ledger" &&
   grep -Fq "emit('updated', 'ledger'" "$software_ledger" &&
   awk '
     /^runtime_apply_account_from_cmdline$/ { account_line = NR }
     /^software_install_ledger$/ { ledger_line = NR }
     END { exit !(account_line && ledger_line && account_line < ledger_line) }
   ' "$software_helper" &&
   grep -q 'usermod -a -G plugdev "\$account_user"' "$software_helper" &&
   grep -q 'udevadm verify --resolve-names=never "\$udev_rule"' "$software_helper" &&
   openssl pkey -pubin -in "$ledger_public_key" -noout >/dev/null 2>&1 &&
   [ "$(openssl pkey -pubin -in "$ledger_public_key" -outform DER 2>/dev/null | sha256sum | awk '{print $1}')" = 0381bccfa5505e834f9fda30eeba257055782f30c495ba0604a0cd37b548c6fc ] &&
   grep -q '^Exec=__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ ledger-live %U$' "$ledger_desktop_template" &&
   grep -q '^Exec=/usr/local/bin/labwc-managed-app nvidia ledger-live %U$' "$ledger_desktop" &&
   grep -q '^Icon=ledger-live-desktop$' "$ledger_desktop" &&
   grep -q 'ATTR{idVendor}=="2c97".*MODE="0660", GROUP="plugdev", TAG+="uaccess"' "$ledger_udev_rules" &&
   grep -q 'SUBSYSTEM=="hidraw".*ATTRS{idVendor}=="2c97".*MODE="0660", GROUP="plugdev", TAG+="uaccess"' "$ledger_udev_rules" &&
   ! grep -q 'MODE="0666"' "$ledger_udev_rules" &&
   if command -v desktop-file-validate >/dev/null 2>&1; then
     desktop-file-validate "$ledger_desktop"
   else
     true
   fi &&
   if command -v udevadm >/dev/null 2>&1; then
     if udevadm verify --resolve-names=never "$ledger_udev_rules" \
          >"$TMP_DIR/ledger-udev-verify.stdout" \
          2>"$TMP_DIR/ledger-udev-verify.stderr"; then
       true
     else
       cat "$TMP_DIR/ledger-udev-verify.stderr" >&2
       false
     fi
   else
     true
   fi
then
  pass "Ledger AppImage uses signed release metadata, a pinned key, a managed launcher, and least-privilege Stax udev access"
else
  fail "Ledger AppImage uses signed release metadata, a pinned key, a managed launcher, and least-privilege Stax udev access"
fi

if grep -q '^software_stage_perl_modules() {$' "$software_helper" &&
   grep -q 'target/usr/local/lib/perl5/site_perl/external-managed-software/' "$software_helper" &&
   grep -q 'target/usr/local/libexec/managed-external-software-update' "$software_helper" &&
   grep -q 'target/usr/local/libexec/managed-external-software-notify' "$software_helper" &&
   grep -q 'target/etc/systemd/system/managed-external-software-download.service' "$software_helper" &&
   grep -q 'target/etc/systemd/system/managed-external-software-download.timer' "$software_helper" &&
   grep -q 'target/etc/systemd/system/managed-external-software-update.service' "$software_helper" &&
   grep -q 'target/etc/systemd/system/managed-external-software-update.timer' "$software_helper" &&
   grep -q 'target/etc/skel/.config/systemd/user/managed-external-software-notify.service' "$software_helper" &&
   grep -q 'target/etc/skel/.config/systemd/user/managed-external-software-notify.path' "$software_helper" &&
   grep -q '^software_state_dir=/var/lib/software$' "$software_helper" &&
   grep -q '^software_deb_archive_dir="${software_state_dir}/debs"$' "$software_helper" &&
   grep -q '^software_deb_repository_inrelease="${software_deb_archive_dir}/InRelease"$' "$software_helper" &&
   grep -q '^software_deb_repository_release_gpg="${software_deb_archive_dir}/Release.gpg"$' "$software_helper" &&
   grep -q '^software_deb_repository_signing_home="${software_state_dir}/repository-signing"$' "$software_helper" &&
   grep -q '^software_deb_repository_keyring=/etc/apt/keyrings/managed-external-software.gpg$' "$software_helper" &&
   grep -q '^software_artifact_dir="${software_state_dir}/artifacts"$' "$software_helper" &&
   grep -q '^software_metadata_dir="${software_state_dir}/state"$' "$software_helper" &&
   grep -q 'tuta_hash_file="${software_metadata_dir}/tuta.installed.sha256"' "$software_helper" &&
   grep -q '^software_ensure_managed_deb_repository_signing_key() {$' "$software_helper" &&
   grep -q '^software_sign_managed_deb_repository() {$' "$software_helper" &&
   grep -Fq 'HOME="$software_deb_repository_signing_home" \' "$software_helper" &&
   grep -Eq '(^|[[:space:]])gpgv([[:space:]]|$)' "$software_class" &&
   grep -Eq '(^|[[:space:]])gpg-agent([[:space:]]|$)' "$desktop_class" &&
   grep -Fq -- '--quick-generate-key' "$software_helper" &&
   grep -Fq -- '--export-options export-minimal' "$software_helper" &&
   grep -Fq -- '--clearsign "$software_deb_repository_release"' "$software_helper" &&
   grep -Fq -- '--detach-sign "$software_deb_repository_release"' "$software_helper" &&
   [ "$(grep -Fc 'chroot "$target_root" /usr/bin/gpgv \' "$software_helper")" -eq 2 ] &&
   grep -q '^software_target_file_owner() {$' "$software_helper" &&
   grep -Fq 'chroot "$target_root" /usr/bin/stat -c '\''%u:%g'\'' -- "$target_path"' "$software_helper" &&
   ! grep -Eq '\$\((stat|/bin/stat|/usr/bin/stat) -c.*generated_host_path' "$software_helper" &&
   grep -Fqx 'deb [signed-by=/etc/apt/keyrings/managed-external-software.gpg] file:/var/lib/software/debs ./' "$software_repository_source" &&
   ! grep -Fq 'trusted=yes' "$software_helper" "$software_repository_source" &&
   grep -q 'systemctl --root=/ enable managed-external-software-download.timer' "$software_helper" &&
   grep -q 'systemctl --root=/ enable managed-external-software-update.timer' "$software_helper" &&
   ! grep -q 'systemctl --root=/ --global enable' "$software_helper" &&
   ! grep -q 'cron.weekly' "$software_helper"; then
  pass "software late helper stages Perl servicing plus download, apply, and Mako units"
else
  fail "software late helper stages Perl servicing plus download, apply, and Mako units"
fi

if [ "$external_perl_syntax_ok" = true ] &&
   [ "$updater_workspace_behavior_ok" = true ] &&
   [ "$repository_codename_behavior_ok" = true ] &&
   [ "$notification_schema_behavior_ok" = true ] &&
   [ "$external_apply_no_network" = true ] &&
   grep -Fxq '#!/usr/bin/perl' "$software_updater" &&
   grep -Fxq '#!/usr/bin/perl' "$software_notifier" &&
   grep -Fq 'use ExternalSoftware::Servicing::CLI;' "$software_updater" &&
   grep -Fq 'use ExternalSoftware::Servicing::CLI;' "$software_notifier" &&
   grep -q '^sub run_updater {' "$software_cli" &&
   grep -Fq -- '--download-only|--apply-only|--repair-only' "$software_cli" &&
   grep -Fq 'this updater must run as root' "$software_cli" &&
   grep -Fq 'managed external software updates are supported only on amd64' "$software_cli" &&
   grep -q '^sub _run_download {' "$software_cli" &&
   grep -q '^sub _run_apply {' "$software_cli" &&
   grep -Fq "event->emit('downloaded'" "$software_cli" &&
   grep -Fq "event->emit('updated'" "$software_cli" &&
   grep -Fq "event->emit('failed'" "$software_cli" &&
   grep -Fq "default => sub { '/var/lib/software' }" "$software_state" &&
   grep -Fq 'return $_[0]->root() . '\''/debs'\'';' "$software_state" &&
   grep -Fq 'return $_[0]->root() . '\''/artifacts'\'';' "$software_state" &&
   grep -Fq 'return $_[0]->root() . '\''/state'\'';' "$software_state" &&
   grep -Fq 'O_CREAT | O_NOFOLLOW | O_RDWR' "$software_state" &&
   grep -Fq 'LOCK_EX | LOCK_NB' "$software_state" &&
   grep -Fq "default => sub { '/var/lib/software/repository-signing' }" "$software_repository" &&
   grep -Fq "default => sub { '/etc/apt/keyrings/managed-external-software.gpg' }" "$software_repository" &&
   grep -A 5 '^has release_path => ($' "$software_repository" | grep -Fq 'lazy    => 1,' &&
   grep -A 5 '^has inrelease_path => ($' "$software_repository" | grep -Fq 'lazy    => 1,' &&
   grep -A 5 '^has release_signature_path => ($' "$software_repository" | grep -Fq 'lazy    => 1,' &&
   grep -A 5 '^has apt_temp_directory => ($' "$software_repository" | grep -Fq 'lazy    => 1,' &&
   grep -Fq "'HOME=' . \$self->signing_home()," "$software_repository" &&
   grep -q '^sub _ensure_signing_key {' "$software_repository" &&
   grep -q '^sub _sign_release {' "$software_repository" &&
   grep -Fq "'--quick-generate-key'," "$software_repository" &&
   grep -Fq "'--export-options', 'export-minimal'," "$software_repository" &&
   grep -Fq "'ed25519'," "$software_repository" &&
   grep -Fq "'--clearsign', \$self->release_path()," "$software_repository" &&
   grep -Fq "'--detach-sign', \$self->release_path()," "$software_repository" &&
   [ "$(grep -Fc "'/usr/bin/gpgv'," "$software_repository")" -eq 2 ] &&
   grep -Fq 'deb [signed-by=' "$software_repository" &&
   grep -Fq '] file:/var/lib/software/debs ./' "$software_repository" &&
   ! grep -Fq 'trusted=yes' "$software_repository" &&
   grep -Fq "'NEEDRESTART_SUSPEND=1'," "$software_repository"; then
  pass "Perl updater serializes work, retains validated artifacts, applies offline, and records outcomes"
else
  fail "Perl updater serializes work, retains validated artifacts, applies offline, and records outcomes"
fi

if [ "$external_perl_syntax_ok" = true ] &&
   grep -q '^OnCalendar=Sun \*-\*-\* 01:30:00$' "$software_download_timer" &&
   grep -q '^RandomizedDelaySec=30min$' "$software_download_timer" &&
   grep -q '^ExecStart=/usr/local/libexec/managed-external-software-update --download-only$' "$software_download_service" &&
   grep -q '^OnCalendar=Sun \*-\*-\* 05:30:00$' "$software_update_timer" &&
   grep -q '^Persistent=true$' "$software_update_timer" &&
   grep -q '^RandomizedDelaySec=30min$' "$software_update_timer" &&
   grep -q '^WantedBy=timers.target$' "$software_update_timer" &&
   grep -q '^ConditionFileIsExecutable=/usr/local/libexec/managed-external-software-update$' "$software_update_service" &&
   ! grep -q '^ConditionPathIsExecutable=' "$software_update_service" &&
   grep -q '^ExecStart=/usr/local/libexec/managed-external-software-update --apply-only$' "$software_update_service" &&
   grep -q '^NoNewPrivileges=false$' "$software_update_service" &&
   grep -q '^ProtectSystem=full$' "$software_update_service" &&
   grep -q '^StateDirectory=software$' "$software_update_service" &&
   grep -q '^TimeoutStopSec=10min$' "$software_update_service" &&
   grep -q '^ReadWritePaths=/etc /opt /usr /var/lib/software$' "$software_update_service" &&
   grep -q '^RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6$' "$software_update_service" &&
   grep -q '^Wants=mako.service$' "$software_notify_service" &&
   grep -q '^After=labwc-session.target mako.service$' "$software_notify_service" &&
   grep -q '^ExecStart=/usr/local/libexec/managed-external-software-notify$' "$software_notify_service" &&
   grep -q '^ReadOnlyPaths=/var/lib/software$' "$software_notify_service" &&
   ! grep -q '^\[Install\]$' "$software_notify_service" &&
   grep -q '^PathChanged=/var/lib/software/events$' "$software_notify_path" &&
   grep -q '^WantedBy=labwc-session.target$' "$software_notify_path" &&
   grep -q 'desktop_stage_user_unit_wanted_by managed-external-software-notify.path labwc-session.target' "$desktop_components" &&
   ! grep -q 'desktop_stage_user_unit_wanted_by managed-external-software-notify.service labwc-session.target' "$desktop_components" &&
   grep -Fq "'/usr/bin/notify-send', '-a', 'Software Updater', '-u', \$urgency," "$software_notifier_module" &&
   grep -Fq "'-i', \$icon, '-c', 'system.software-update', '-t', \$timeout," "$software_notifier_module" &&
   grep -Fq 'download ready' "$software_notifier_module" &&
   grep -Fq "chatgpt   => 'ChatGPT/Codex Desktop'," "$software_notifier_module" &&
   grep -Fq "payload    => 'The installed package is missing required managed payload files.'," "$software_notifier_module" &&
   grep -Fq "policy     => 'The managed application security policy could not be restored or verified.'," "$software_notifier_module" &&
   grep -Fq 'Applying $APP_LABEL{$app}' "$software_notifier_module" &&
   grep -Fq '$APP_LABEL{$app} update failed' "$software_notifier_module"; then
  pass "download and apply timers deliver retained-state events through the Labwc Mako bridge"
else
  fail "download and apply timers deliver retained-state events through the Labwc Mako bridge"
fi

if [ "$chatgpt_servicing_behavior_ok" = true ] &&
   grep -Fq "use constant ENABLE_STATE_CONTENT      => \"addon/devops\\n\";" "$software_chatgpt" &&
   grep -Fq "url        => 'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb'," "$software_chatgpt" &&
   grep -Fq 'maximum    => 536_870_912,' "$software_chatgpt" &&
   grep -Fq "hosts      => ['persistent.oaistatic.com']," "$software_chatgpt" &&
   grep -Fq "packages   => ['chatgpt']," "$software_chatgpt" &&
   grep -Fq 'remove_dependencies => [' "$software_chatgpt" &&
   grep -Fq "'mesa-vulkan-drivers'," "$software_chatgpt" &&
   grep -Fq "'nvidia-*'," "$software_chatgpt" &&
   grep -Fq "'vulkan-icd'," "$software_chatgpt" &&
   grep -Fq "'*x11*'," "$software_chatgpt" &&
   grep -q '^sub _capture_quiet {$' "$software_deb" &&
   grep -Fq 'exec { $command[0] } @command or _exit(127);' "$software_deb" &&
   ! grep -Fq 'exec { $command[0] } @command;' "$software_deb" &&
   grep -Fq '$self->_capture_quiet(' "$software_deb" &&
   grep -q '^sub repack_without_dependencies {$' "$software_deb" &&
   grep -Fq "'--raw-extract'," "$software_deb" &&
   grep -Fq "'--root-owner-group'," "$software_deb" &&
   grep -Fq '$deb->repack_without_dependencies(' "$software_cli" &&
   grep -Fq "use constant DIVERSION_PATH            => '/var/lib/software/vendor/chatgpt.apparmor';" "$software_chatgpt" &&
   grep -Fq "'--local'," "$software_chatgpt" &&
   grep -Fq "'--divert', DIVERSION_PATH," "$software_chatgpt" &&
   grep -Fq "\$self->_diversion_owner() eq 'LOCAL'" "$software_chatgpt" &&
   grep -Fq "use constant VENDOR_SOURCE_PATH        => '/etc/apt/sources.list.d/chatgpt.sources';" "$software_chatgpt" &&
   grep -Fq "use constant VENDOR_KEYRING_PATH       => '/usr/share/keyrings/chatgpt-archive-keyring.gpg';" "$software_chatgpt" &&
   grep -Fq "use constant MANAGED_MODES_HELPER      => '/usr/local/libexec/apparmor-managed-modes-run';" "$software_chatgpt" &&
   grep -Fq "use constant APPARMOR_PARSER           => '/usr/sbin/apparmor_parser';" "$software_chatgpt" &&
   grep -Fq "use constant APPARMOR_SECURITYFS       => '/sys/kernel/security/apparmor';" "$software_chatgpt" &&
   grep -q '^sub prepare_install {$' "$software_chatgpt" &&
   grep -q '^sub finalize_install {$' "$software_chatgpt" &&
   grep -q '^sub _validate_policy_syntax {$' "$software_chatgpt" &&
   grep -q '^sub _finalize_policy {$' "$software_chatgpt" &&
   grep -q '^sub _reload_policy_if_available {$' "$software_chatgpt" &&
   grep -Fq "'--debug'," "$software_chatgpt" &&
   grep -Fq "'--skip-kernel-load'," "$software_chatgpt" &&
   grep -Fq "'--skip-cache'," "$software_chatgpt" &&
   grep -Fq '$self->_reload_policy_if_available() if $execution_context eq '"'"'runtime'"'"';' "$software_chatgpt" &&
   grep -Fq '$self->_finalize_policy($execution_context);' "$software_chatgpt" &&
   grep -q '^ReadWritePaths=/sys/kernel/security/apparmor /var/cache/apparmor$' "$software_update_service" &&
   grep -Fq 'push @specs, $chatgpt->spec() if $chatgpt->enabled();' "$software_cli" &&
   grep -Fq "\$chatgpt->prepare_install() if \$app->{name} eq 'chatgpt';" "$software_cli" &&
   grep -Fq '$chatgpt->finalize_install($execution_context) if $app->{name} eq '"'"'chatgpt'"'"';' "$software_cli" &&
   grep -Fq "\$chatgpt->finalize_install('runtime');" "$software_cli" &&
   grep -Fq -- '--bootstrap-chatgpt' "$software_cli" "$software_helper" &&
   grep -q '^chatgpt_enabled=false$' "$software_helper" &&
   grep -q 'installer_selected_class_reference_is_selected addon/devops' "$software_helper" &&
   grep -q '^software_enable_chatgpt_integration() {$' "$software_helper" &&
   grep -q '^  \[ "$chatgpt_enabled" = true \] || return 0$' "$software_helper" &&
   grep -q '^software_enable_chatgpt_integration$' "$software_helper" &&
   grep -Fq '/usr/bin/slirp4netns' "$software_helper" &&
   ! sed -n '/^software_restore_managed_apparmor_profiles() {$/,/^}$/p' "$software_helper" |
     grep -q 'chatgpt' &&
   ! grep -q 'labwc-chatgpt' "$desktop_components" &&
   grep -Fxq 'repo_add_once="false"' "$chatgpt_default"; then
  pass "ChatGPT package servicing is DevOps-gated, dependency-repacked, bounded, locally diverted, policy-repairable, and absent from software-only staging"
else
  fail "ChatGPT package servicing is DevOps-gated, dependency-repacked, bounded, locally diverted, policy-repairable, and absent from software-only staging"
fi

chatgpt_launcher_stdout="$TMP_DIR/chatgpt-launcher.stdout"
chatgpt_launcher_stderr="$TMP_DIR/chatgpt-launcher.stderr"
chatgpt_launcher_rejects_silently=false
if "$chatgpt_launcher" invalid-mode \
     >"$chatgpt_launcher_stdout" \
     2>"$chatgpt_launcher_stderr"; then
  :
elif [ ! -s "$chatgpt_launcher_stdout" ] &&
     [ ! -s "$chatgpt_launcher_stderr" ]; then
  chatgpt_launcher_rejects_silently=true
fi

if [ "$chatgpt_launcher_rejects_silently" = true ] &&
   /bin/sh -n "$chatgpt_launcher" &&
   [ ! -e "$legacy_chatgpt_launcher" ] &&
   grep -Fq 'exec </dev/null >/dev/null 2>&1' "$chatgpt_launcher" &&
   grep -Fq 'umask 077' "$chatgpt_launcher" &&
   grep -Fq '0)' "$chatgpt_launcher" &&
   grep -Fq 'mode=auto' "$chatgpt_launcher" &&
   grep -Fq 'auto|launch|intel|nvidia)' "$chatgpt_launcher" &&
   ! grep -Fq 'pure-privacy' "$chatgpt_launcher" "$chatgpt_desktop" &&
   grep -Fq 'actual_user=$(/usr/bin/id -un)' "$chatgpt_launcher" &&
   grep -Fq '[ "$USER" = "$actual_user" ]' "$chatgpt_launcher" &&
   grep -Fq 'LOGNAME does not match the current account' "$chatgpt_launcher" &&
   grep -Fq 'profile_path="${HOME}/.profile.d/71-devops-de.sh"' "$chatgpt_launcher" &&
   grep -Fq 'profile_real=$(/usr/bin/readlink -f -- "$profile_path" 2>/dev/null)' "$chatgpt_launcher" &&
   grep -Fq 'profile_metadata=$(' "$chatgpt_launcher" &&
   grep -Fq 'regular file:$(/usr/bin/id -u):600' "$chatgpt_launcher" &&
   grep -Fq 'managed DevOps profile is unsafe' "$chatgpt_launcher" &&
   grep -Fq '. "$profile_path"' "$chatgpt_launcher" &&
   grep -Fq 'devops_de_apply_environment' "$chatgpt_launcher" &&
   grep -Fq 'SHELL=/bin/zsh' "$chatgpt_launcher" &&
   grep -Fq "/bin/sh -eu -c '" "$chatgpt_launcher" &&
   grep -Fq 'exec "$@"' "$chatgpt_launcher" &&
   ! grep -Eq 'CARGO_HOME=|MISE_DATA_DIR=|PYTHONUSERBASE=|/usr/local/cuda|/usr/lib/llvm|/usr/local/lib/node|/usr/local/lib/rustup' "$chatgpt_launcher" &&
   ! grep -Fq 'DEVOPS_DE_VAGRANT_ENABLED=' "$chatgpt_launcher" &&
   ! grep -Fq 'LIBVIRT_DEFAULT_URI=' "$chatgpt_launcher" &&
   grep -Fq 'exec /usr/bin/env -i \' "$chatgpt_launcher" &&
   grep -Fq '/usr/local/libexec/labwc-chatgpt-log-runner \' "$chatgpt_launcher" &&
   ! grep -Fq '/usr/local/bin/labwc-managed-app \' "$chatgpt_launcher" &&
   grep -Fq '  </dev/null \' "$chatgpt_launcher" &&
   grep -Fq '  >/dev/null \' "$chatgpt_launcher" &&
   grep -Fq '  2>&1' "$chatgpt_launcher" &&
   ! grep -R -q -- 'devops-de-bin' "$ROOT_DIR/d-i/forky" &&
   grep -Fxq 'TryExec=/usr/local/bin/chatgpt' "$chatgpt_desktop" &&
   grep -Fxq 'Exec=/usr/local/bin/chatgpt auto %U' "$chatgpt_desktop" &&
   grep -Fxq 'Actions=IntelAccelerated;NvidiaAccelerated;' "$chatgpt_desktop" &&
   [ "$(grep -c '^Exec=/usr/local/bin/chatgpt ' "$chatgpt_desktop")" -eq 3 ] &&
   grep -Fqx 'profile chatgpt /{usr/bin/chatgpt,usr/lib/chatgpt/{ChatGPT,browser_crashpad_handler,codex-launcher,resources/{codex,codex-code-mode-host}}} flags=(attach_disconnected, mediate_deleted) {' "$chatgpt_apparmor" &&
   grep -Fqx '  deny /tmp/.X11-unix/ rw,' "$chatgpt_apparmor" &&
   grep -Fqx '  deny /tmp/.X11-unix/** rw,' "$chatgpt_apparmor" &&
   ! grep -Eq 'flags=.*(unconfined|complain|userns)' "$chatgpt_apparmor" &&
   if command -v desktop-file-validate >/dev/null 2>&1; then
     desktop-file-validate "$chatgpt_desktop"
   else
     true
   fi
then
  pass "ChatGPT launcher detaches inherited consoles, activates the complete profile-owned DevOps environment with Zsh, and sends native-Wayland launches through the capture runner"
else
  fail "ChatGPT launcher detaches inherited consoles, activates the complete profile-owned DevOps environment with Zsh, and sends native-Wayland launches through the capture runner"
fi

if /usr/bin/perl -c "$chatgpt_log_runner" >/dev/null 2>&1 &&
   python3 - "$chatgpt_log_runner" <<'PY' >/dev/null 2>&1
from pathlib import Path
import re
import subprocess
import sys
import tempfile

runner_source_path = Path(sys.argv[1])
temporary_directory = tempfile.TemporaryDirectory(prefix="cg-log-", dir="/tmp")
temporary_root = Path(temporary_directory.name)
child_path = temporary_root / "managed-app-child"
runner_path = temporary_root / "runner"
captured_log_path = temporary_root / "captured.log"
missing_socket_path = temporary_root / "missing.sock"
fail_closed_child = temporary_root / "fail-closed-child"
fail_closed_runner = temporary_root / "fail-closed-runner"
fail_closed_marker = temporary_root / "child-started"

source = runner_source_path.read_text(encoding="utf-8")
assert source.count("/usr/local/bin/labwc-managed-app") == 1
assert source.count("/usr/bin/setsid") == 1
assert source.count("/run/rsyslog/managed-openai/chatgpt.sock") == 1
assert "MAXIMUM_LINE_BYTES      => 1_800" in source
assert "SEND_RETRY_LIMIT        => 5" in source
assert "O_NONBLOCK" in source
assert "AF_UNIX" in source
assert "SOCK_DGRAM" in source
assert "SYSLOG_TAG              => 'managed-openai-chatgpt'" in source
assert "print STDOUT" not in source
assert "print STDERR" not in source
assert "/var/log/managed/openai" not in source

child_path.write_text(
    """#!/usr/bin/python3
import os
import sys

assert sys.argv[1:3] == ["intel", "chatgpt"]
assert os.getsid(0) == os.getpid()
assert not any(os.isatty(descriptor) for descriptor in (0, 1, 2))
os.write(1, b"stdout-line\\n" + b"L" * 5000)
os.write(2, b"stderr-binary\\x00value\\n")
raise SystemExit(23)
""",
    encoding="utf-8",
)
child_path.chmod(0o755)
assert "'" not in str(captured_log_path)
transport_pattern = re.compile(
    r"sub _connect_log_socket \{.*?^}\n\n"
    r"sub _send_syslog \{.*?^}\n",
    re.MULTILINE | re.DOTALL,
)
test_transport = f"""sub _connect_log_socket {{
    open $log_socket, '>', '{captured_log_path}'
        or die "cannot open the test log sink\\n";
    return;
}}

sub _send_syslog {{
    my ($priority, $message) = @_;

    print {{$log_socket}} "$priority $message\\n"
        or die "cannot write the test log sink\\n";
    return;
}}
"""
test_source, replacement_count = transport_pattern.subn(test_transport, source)
assert replacement_count == 1
runner_path.write_text(
    test_source.replace("/usr/local/bin/labwc-managed-app", str(child_path)),
    encoding="utf-8",
)
runner_path.chmod(0o755)

process = subprocess.run(
    [str(runner_path), "intel"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
    timeout=10,
)
payload = captured_log_path.read_text(encoding="ascii")
assert process.returncode == 23
assert process.stdout == b""
assert process.stderr == b""
assert "event=started mode=intel" in payload
assert "stream=stdout message=stdout-line" in payload
assert r"stream=stderr message=stderr-binary\x00value" in payload
assert "continued=true" in payload
assert "event=completed status=23" in payload
records = payload.splitlines()
assert records
assert max(len(record.encode("ascii")) for record in records) < 1900

fail_closed_child.write_text(
    f"""#!/bin/sh
printf '%s\\n' started >'{fail_closed_marker}'
exit 0
""",
    encoding="utf-8",
)
fail_closed_child.chmod(0o755)
fail_closed_runner.write_text(
    source.replace(
        "/usr/local/bin/labwc-managed-app",
        str(fail_closed_child),
    ).replace(
        "/run/rsyslog/managed-openai/chatgpt.sock",
        str(missing_socket_path),
    ),
    encoding="utf-8",
)
fail_closed_runner.chmod(0o755)
failed_process = subprocess.run(
    [str(fail_closed_runner), "launch"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
    timeout=5,
)
assert failed_process.returncode != 0
assert failed_process.stdout == b""
assert failed_process.stderr == b""
assert not fail_closed_marker.exists()
temporary_directory.cleanup()
PY
then
  pass "ChatGPT capture runner bounds and sanitizes both streams, preserves child status, never mirrors output, and fails closed without its private socket"
else
  fail "ChatGPT capture runner bounds and sanitizes both streams, preserves child status, never mirrors output, and fails closed without its private socket"
fi

chatgpt_staging_block=$(
  sed -n \
    '/^software_enable_chatgpt_integration() {$/,/^software_restore_managed_apparmor_profiles() {$/p' \
    "$software_helper"
)
if /bin/sh -n "$chatgpt_log_socket_helper" &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/usr/local/bin/chatgpt' &&
   ! printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/usr/local/bin/labwc-chatgpt' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/usr/local/libexec/labwc-chatgpt-log-runner' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/usr/local/libexec/rsyslog-managed-openai-socket' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/etc/rsyslog.d/38-openai-chatgpt.conf' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/etc/systemd/system/rsyslog.service.d/35-managed-openai-chatgpt-socket.conf' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/etc/tmpfiles.d/61-managed-openai-chatgpt.conf.tmpl' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'software_render_seed_asset' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'ACCOUNT_USERNAME "$ACCOUNT_USERNAME"' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'target/etc/logrotate.d/chatgpt' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'writer_group=openailogger' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq '/usr/bin/systemd-tmpfiles' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq '/usr/sbin/rsyslogd' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq '/usr/sbin/logrotate' &&
   ! grep -Eq '38-openai-chatgpt|61-managed-openai-chatgpt|rsyslog-managed-openai-socket' "$desktop_components" &&
   grep -Fq 'ruleset(name="managed_openai_chatgpt_input") {' "$chatgpt_rsyslog" &&
   grep -Fq 'if ($programname == "managed-openai-chatgpt") then {' "$chatgpt_rsyslog" &&
   grep -Fq 'file="/var/log/managed/openai/chatgpt/chatgpt.log"' "$chatgpt_rsyslog" &&
   grep -Fq 'fileOwner="root"' "$chatgpt_rsyslog" &&
   grep -Fq 'fileGroup="adm"' "$chatgpt_rsyslog" &&
   grep -Fq 'fileCreateMode="0640"' "$chatgpt_rsyslog" &&
   grep -Fq 'dirCreateMode="0751"' "$chatgpt_rsyslog" &&
   grep -Fq 'Socket="/run/rsyslog/managed-openai/chatgpt.sock"' "$chatgpt_rsyslog" &&
   grep -Fq 'RateLimit.Interval="60"' "$chatgpt_rsyslog" &&
   grep -Fq 'RateLimit.Burst="4000"' "$chatgpt_rsyslog" &&
   grep -Eq '^[[:space:]]+stop$' "$chatgpt_rsyslog" &&
   grep -Fxq 'd /var/log/managed/openai 0751 root adm -' "$chatgpt_tmpfiles_template" &&
   grep -Fxq 'd /var/log/managed/openai/chatgpt 0751 root adm -' "$chatgpt_tmpfiles_template" &&
   grep -Fxq 'd /var/log/managed/openai/chatgpt/runtime 2770 __INSTALLER_ACCOUNT_USERNAME__ openailogger -' "$chatgpt_tmpfiles_template" &&
   grep -Fxq 'f /var/log/managed/openai/chatgpt/chatgpt.log 0640 root adm -' "$chatgpt_tmpfiles_template" &&
   grep -Fxq 'd /run/rsyslog/managed-openai 0750 root openailogger -' "$chatgpt_tmpfiles_template" &&
   chatgpt_tmpfiles_template_renders &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq '/etc/tmpfiles.d/65-audit-syslog.conf' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'verify managed ChatGPT log path policy' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'chatgpt_verify_stat "0:${adm_gid}:751" /var/log/managed/openai/chatgpt' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'chatgpt_verify_stat "${account_uid}:${writer_gid}:2770" /var/log/managed/openai/chatgpt/runtime' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq 'chatgpt_verify_stat "0:${adm_gid}:640" /var/log/managed/openai/chatgpt/chatgpt.log' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq '/usr/bin/test ! -w /var/log/managed/openai/chatgpt' &&
   printf '%s\n' "$chatgpt_staging_block" |
     grep -Fq '/usr/bin/test -w /var/log/managed/openai/chatgpt/runtime' &&
   grep -Fxq 'socket_path=/run/rsyslog/managed-openai/chatgpt.sock' "$chatgpt_log_socket_helper" &&
   grep -Fxq 'socket_group=openailogger' "$chatgpt_log_socket_helper" &&
   grep -Fxq 'ExecStartPre=/usr/bin/install -d -o root -g openailogger -m 0750 /run/rsyslog/managed-openai' "$chatgpt_rsyslog_dropin" &&
   grep -Fxq 'ExecStartPost=/usr/local/libexec/rsyslog-managed-openai-socket' "$chatgpt_rsyslog_dropin" &&
   grep -Fxq '/var/log/managed/openai/chatgpt/chatgpt.log' "$chatgpt_logrotate" &&
   grep -Eq '^[[:space:]]+daily$' "$chatgpt_logrotate" &&
   grep -Eq '^[[:space:]]+rotate 4$' "$chatgpt_logrotate" &&
   grep -Eq '^[[:space:]]+maxage 7$' "$chatgpt_logrotate" &&
   grep -Eq '^[[:space:]]+maxsize 4M$' "$chatgpt_logrotate" &&
   grep -Eq '^[[:space:]]+create 0640 root adm$' "$chatgpt_logrotate" &&
   grep -Eq '^[[:space:]]+su root adm$' "$chatgpt_logrotate" &&
   grep -Fq '/usr/lib/rsyslog/rsyslog-rotate' "$chatgpt_logrotate"; then
  pass "ChatGPT logging assets are DevOps-only and route through a protected stopped rsyslog ruleset with bounded root-owned rotation"
else
  fail "ChatGPT logging assets are DevOps-only and route through a protected stopped rsyslog ruleset with bounded root-owned rotation"
fi
unset chatgpt_staging_block

if /usr/bin/python3 - "$managed_app_package_root" "$launcher_sync" <<'PY' >/dev/null 2>&1
import configparser
import contextlib
import io
import json
import os
import pathlib
import re
import runpy
import stat
import sys
import tempfile
import types

sys.path.insert(0, sys.argv[1])
from labwc_managed_app import (
    cli,
    commands,
    electron,
    environment,
    profiles,
    runtime,
    sandbox,
    wayland_compat,
    wayland_compat_runtime,
)
sys.path.remove(sys.argv[1])

module = {
    "APPS": profiles.APPS,
    "DISCORD_REQUIRED_FILES": profiles.DISCORD_REQUIRED_FILES,
    "DISCORD_REQUIRED_MODULES": profiles.DISCORD_REQUIRED_MODULES,
    "DISCORD_ROOT": profiles.DISCORD_ROOT,
    "CAGE_BINARY": wayland_compat.CAGE_BINARY,
    "PRIVATE_RUNTIME_ROOT": wayland_compat.PRIVATE_RUNTIME_ROOT,
    "PRIVATE_RUNTIME_BINARY": wayland_compat.PRIVATE_RUNTIME_BINARY,
    "PRIVATE_RUNTIME_XKBCOMP": wayland_compat.PRIVATE_RUNTIME_XKBCOMP,
    "PRIVATE_RUNTIME_XKBCOMP_OVERLAY_DIRECTORY": wayland_compat.PRIVATE_RUNTIME_XKBCOMP_OVERLAY_DIRECTORY,
    "PRIVATE_RUNTIME_PROTOCOL": wayland_compat.PRIVATE_RUNTIME_PROTOCOL,
    "PRIVATE_RUNTIME_LIBRARY_DIRECTORY": wayland_compat.PRIVATE_RUNTIME_LIBRARY_DIRECTORY,
    "PRIVATE_RUNTIME_LIBRARY_NAMES": wayland_compat.PRIVATE_RUNTIME_LIBRARY_NAMES,
    "SANDBOX_LIFECYCLE_HELPER": wayland_compat.SANDBOX_LIFECYCLE_HELPER,
    "WAYLAND_COMPAT_APPS": profiles.WAYLAND_COMPAT_APPS,
    "MANAGED_PATH": runtime.MANAGED_PATH,
    "PERSISTENT_SANDBOX_CONFIG": profiles.PERSISTENT_SANDBOX_CONFIG,
    "CHATGPT_FORBIDDEN_AMBIENT_ENVIRONMENT": environment.CHATGPT_FORBIDDEN_AMBIENT_ENVIRONMENT,
    "FORBIDDEN_INHERITED_X11_ENVIRONMENT": wayland_compat_runtime.FORBIDDEN_INHERITED_X11_ENVIRONMENT,
    "TUTA_DBUS_NAMES": profiles.TUTA_DBUS_NAMES,
    "MANAGED_RUNTIME_STATE": profiles.MANAGED_RUNTIME_STATE,
    "ZOOM_CONFIG_SOURCE": profiles.ZOOM_CONFIG_SOURCE,
    "build_argv": commands.build_argv,
    "build_environment": environment.build_environment,
    "managed_library_path": commands.managed_library_path,
    "validate_required_runtime_files": commands.validate_required_runtime_files,
    "resolved_executable": commands.resolved_executable,
    "ensure_managed_runtime_state": environment.ensure_managed_runtime_state,
    "ensure_discord_managed_settings": environment.ensure_discord_managed_settings,
    "validated_chatgpt_devops_environment": environment.validated_chatgpt_devops_environment,
    "validate_chatgpt_work_areas": environment.validate_chatgpt_work_areas,
    "validate_managed_work_directory": environment.validate_managed_work_directory,
    "persistent_sandbox_argv": sandbox.persistent_sandbox_argv,
    "select_persistent_sandbox_chdir": sandbox.select_persistent_sandbox_chdir,
    "pure_privacy_environment": sandbox.pure_privacy_environment,
    "pure_privacy_argv": sandbox.pure_privacy_argv,
    "add_private_tmpfs_mounts": sandbox.add_private_tmpfs_mounts,
    "validate_pure_privacy_device_isolation": sandbox.validate_pure_privacy_device_isolation,
    "validate_no_host_audio_device_binds": sandbox.validate_no_host_audio_device_binds,
    "add_runtime_bind": sandbox.add_runtime_bind,
    "add_system_usr_mount": sandbox.add_system_usr_mount,
    "create_synthetic_identity_files": sandbox.create_synthetic_identity_files,
    "add_synthetic_codex_installation_id_mount": sandbox.add_synthetic_codex_installation_id_mount,
    "add_synthetic_identity_mounts": sandbox.add_synthetic_identity_mounts,
    "add_synthetic_sysfs_masks": sandbox.add_synthetic_sysfs_masks,
    "add_home_directory_binds": sandbox.add_home_directory_binds,
    "add_persistent_directory_binds": sandbox.add_persistent_directory_binds,
    "start_session_bus_proxy": sandbox.start_session_bus_proxy,
    "start_system_bus_proxy": sandbox.start_system_bus_proxy,
    "add_system_bus_proxy_bind": sandbox.add_system_bus_proxy_bind,
    "run_slirp4netns_sandbox": sandbox.run_slirp4netns_sandbox,
    "slirp4netns_resolv_conf": sandbox.slirp4netns_resolv_conf,
    "run_wayland_compat_sandbox": wayland_compat.run_wayland_compat_sandbox,
    "SYSTEM_BUS_SOCKET_PATH": sandbox.SYSTEM_BUS_SOCKET_PATH,
    "ELECTRON_PASSWORD_STORE": electron.ELECTRON_PASSWORD_STORE,
    "electron_password_store_arg": electron.electron_password_store_arg,
    "electron_js_flags": electron.electron_js_flags,
    "ELECTRON_OLD_SPACE_SIZE_MB": electron.ELECTRON_OLD_SPACE_SIZE_MB,
    "os": os,
}
launcher_module = runpy.run_path(sys.argv[2], run_name="software_addon_launcher_sync_test")
apps = module["APPS"]
build_argv = module["build_argv"]
build_environment = module["build_environment"]
managed_library_path = module["managed_library_path"]
validate_required_runtime_files = module["validate_required_runtime_files"]
managed_path = module["MANAGED_PATH"]
persistent_sandbox_argv = module["persistent_sandbox_argv"]
pure_privacy_environment = module["pure_privacy_environment"]
pure_privacy_argv = module["pure_privacy_argv"]
add_private_tmpfs_mounts = module["add_private_tmpfs_mounts"]
validate_pure_privacy_device_isolation = module["validate_pure_privacy_device_isolation"]
validate_no_host_audio_device_binds = module["validate_no_host_audio_device_binds"]
add_runtime_bind = module["add_runtime_bind"]
add_system_usr_mount = module["add_system_usr_mount"]
add_persistent_directory_binds = module["add_persistent_directory_binds"]
start_session_bus_proxy = module["start_session_bus_proxy"]
start_system_bus_proxy = module["start_system_bus_proxy"]
add_system_bus_proxy_bind = module["add_system_bus_proxy_bind"]
run_wayland_compat_sandbox = module["run_wayland_compat_sandbox"]
electron_password_store = module["ELECTRON_PASSWORD_STORE"]
electron_password_store_arg = module["electron_password_store_arg"]
electron_limits = module["ELECTRON_OLD_SPACE_SIZE_MB"]
app_config = launcher_module["APP_CONFIG"]
action_specs = launcher_module["ACTION_SPECS"]
add_actions = launcher_module["add_actions"]
available_actions = launcher_module["available_actions"]
ensure_user_directory = launcher_module["ensure_user_directory"]
remove_unmanaged_tuta_launchers = launcher_module["remove_unmanaged_tuta_launchers"]
synchronize_bitwarden_autostart = launcher_module["synchronize_bitwarden_autostart"]
write_desktop_file = launcher_module["write_desktop_file"]

forbidden_x11_environment = module["FORBIDDEN_INHERITED_X11_ENVIRONMENT"]
assert forbidden_x11_environment == (
    "DESKTOP_STARTUP_ID",
    "SESSION_MANAGER",
    "WINDOWID",
    "XAUTHORITY",
    "XWAYLAND",
    "XWAYLAND_FORCE_SCALE",
    "XWAYLAND_NO_GLAMOR",
    "XWAYLAND_PATH",
    "XWAYLAND_RESTART_DELAY",
    "_XWAYLAND_GLOBAL_OUTPUT_SCALE",
)
assert set(forbidden_x11_environment).issubset(
    module["CHATGPT_FORBIDDEN_AMBIENT_ENVIRONMENT"]
)

assert apps["vivaldi"]["exec"] == "/usr/bin/vivaldi-stable"
assert apps["bitwarden"]["exec"] == "/opt/Bitwarden/bitwarden"
assert module["MANAGED_RUNTIME_STATE"]["bitwarden"] == {
    "directories": (
        (".config/autostart", 0o700),
        (".config/chromium/NativeMessagingHosts", 0o700),
        (".config/microsoft-edge/NativeMessagingHosts", 0o700),
        (".config/vivaldi/NativeMessagingHosts", 0o700),
    ),
}
assert apps["chatgpt"]["exec"] == "/usr/lib/chatgpt/ChatGPT"
assert apps["chatgpt"]["library_dirs"] == ("/usr/lib/chatgpt",)
assert apps["chatgpt"]["required_runtime_files"] == (
    "/usr/lib/chatgpt/codex-launcher",
    "/usr/lib/chatgpt/resources/codex",
    "/usr/lib/chatgpt/resources/codex-code-mode-host",
)
assert apps["chatgpt"]["bind_workspace"] is True
assert apps["chatgpt"]["pure_privacy"] is False
assert apps["chatgpt"]["persistent_sandbox"] is True
assert apps["chatgpt"]["requires_devops_environment"] is True
assert apps["obsidian"]["exec"] == "/opt/Obsidian/obsidian"
assert apps["obsidian"]["exec_candidates"] == ("/usr/bin/obsidian",)
assert apps["postman"]["exec"] == "/opt/postman/app/Postman"
assert apps["sleek"]["exec"] == "/opt/sleek/sleek"
assert apps["sleek"]["exec_candidates"] == ("/usr/bin/sleek",)
assert apps["keepassxc"]["exec"] == "/usr/bin/keepassxc"
assert apps["filen"]["exec"] == "/opt/Filen/Filen"
assert apps["filen"]["exec_candidates"] == ("/usr/bin/filen", "/usr/bin/filen-desktop")
assert apps["discord"]["exec"] == "/opt/discord/Discord"
assert apps["ledger-live"]["exec"] == "/opt/ledger-live/AppRun"
assert apps["spotify"]["exec"] == "/usr/bin/spotify"
assert apps["tutanota"]["exec"] == "/opt/tuta-mail/AppRun"
assert apps["keepassxc"].get("persistent_sandbox", False) is False
assert apps["tutanota"]["persistent_sandbox"] is True
chatgpt_sandbox = module["PERSISTENT_SANDBOX_CONFIG"]["chatgpt"]
assert chatgpt_sandbox["dbus_names"] == ("org.freedesktop.secrets",)
assert chatgpt_sandbox["dbus_own_names"] == ()
assert chatgpt_sandbox["require_session_bus"] is True
assert chatgpt_sandbox["require_system_bus"] is True
assert chatgpt_sandbox["system_dbus_names"] == ("org.freedesktop.UPower",)
assert chatgpt_sandbox["required_runtime_sockets"] == (
    "pipewire-0",
    "pulse/native",
)
assert (
    chatgpt_sandbox["ro_bind_home_directories"]
    == profiles.CHATGPT_DEVOPS_READ_ONLY_HOME_DIRECTORIES
)
assert (
    chatgpt_sandbox["ro_bind_home_optional_files"]
    == profiles.CHATGPT_DEVOPS_READ_ONLY_HOME_FILES
)
chatgpt_read_only_home_paths = (
    *chatgpt_sandbox["ro_bind_home_directories"],
    *chatgpt_sandbox["ro_bind_home_optional_files"],
)
assert ".cmake/packages" in chatgpt_read_only_home_paths
assert ".config/bazel" in chatgpt_read_only_home_paths
assert ".config/cargo/config.toml" in chatgpt_read_only_home_paths
assert ".config/powershell" in chatgpt_read_only_home_paths
assert ".local/share/powershell/Modules" in chatgpt_read_only_home_paths
assert ".profile.d/71-devops-de.sh" in chatgpt_read_only_home_paths
assert ".bash_logout" in chatgpt_read_only_home_paths
assert ".zlogin" in chatgpt_read_only_home_paths
for sensitive_path in (
    ".cache",
    ".config/age",
    ".config/containers/auth.json",
    ".config/npm",
    ".config/sccache",
    ".config/sops",
    ".gnupg",
    ".ssh",
    ".bash_history",
    ".git-credentials",
    ".npmrc",
    ".zsh_history",
):
    assert sensitive_path not in chatgpt_read_only_home_paths
    assert not any(
        path.startswith(f"{sensitive_path}/")
        for path in chatgpt_read_only_home_paths
    )
assert chatgpt_sandbox["rw_bind_home_directories"] == (
    "Downloads",
    "Workspace",
)
assert chatgpt_sandbox["rw_bind_paths"] == (
    "/pool",
    "/data/codex",
    "/data/downloads",
)
assert chatgpt_sandbox["rw_bind_directory_pairs"] == (
    (
        "/var/log/managed/openai/chatgpt/runtime",
        "/data/codex/log",
    ),
)
assert chatgpt_sandbox["ro_bind_directory_paths"] == (
    "/data",
    "/opt",
    "/var/cache/apt",
    "/var/lib/apt/lists",
    "/var/lib/dpkg",
)
assert chatgpt_sandbox["ro_bind_paths"] == (
    *profiles.CHATGPT_VIRTUALIZATION_READ_ONLY_SYSTEM_PATHS,
    "/etc/codex",
    "/etc/llama",
)
assert chatgpt_sandbox["runtime_sockets"] == (
    "pipewire-0",
    "pulse/native",
)
assert chatgpt_sandbox["share_net"] is False
assert chatgpt_sandbox["shared_temp_directory"] == "labwc-chatgpt-tmp"
assert chatgpt_sandbox["slirp4netns"] is True
assert chatgpt_sandbox["synthetic_identity"] is True
assert chatgpt_sandbox["preserve_working_directory"] is True
assert "camera_devices" not in chatgpt_sandbox
assert "/dev/snd" not in json.dumps(chatgpt_sandbox, sort_keys=True)

with tempfile.TemporaryDirectory() as chatgpt_workspace_home:
    chatgpt_work_directories = tuple(
        pathlib.Path(chatgpt_workspace_home, relative_path)
        for relative_path in chatgpt_sandbox["rw_bind_home_directories"]
    )
    for directory in chatgpt_work_directories:
        directory.mkdir(mode=0o700)
    chatgpt_workspace_command = []
    module["add_home_directory_binds"](
        chatgpt_workspace_command,
        chatgpt_workspace_home,
        chatgpt_sandbox["rw_bind_home_directories"],
        "--bind",
    )
    for directory in chatgpt_work_directories:
        expected = ["--bind", str(directory), str(directory)]
        assert any(
            chatgpt_workspace_command[index : index + 3] == expected
            for index in range(len(chatgpt_workspace_command) - 2)
        )

    original_workspace_access = sandbox.os.access

    def deny_workspace_write(path, mode):
        if path == str(chatgpt_work_directories[0]) and mode & os.W_OK:
            return False
        return original_workspace_access(path, mode)

    sandbox.os.access = deny_workspace_write
    try:
        try:
            module["add_home_directory_binds"](
                [],
                chatgpt_workspace_home,
                chatgpt_sandbox["rw_bind_home_directories"],
                "--bind",
            )
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError(
                "ChatGPT accepted a managed home work directory without write access"
            )
    finally:
        sandbox.os.access = original_workspace_access

with tempfile.TemporaryDirectory() as absolute_bind_root:
    absolute_bind_command = []
    sandbox.add_absolute_directory_binds(
        absolute_bind_command,
        (absolute_bind_root,),
        "--ro-bind",
    )
    assert absolute_bind_command[-3:] == [
        "--ro-bind",
        absolute_bind_root,
        absolute_bind_root,
    ]
    sandbox.add_absolute_directory_binds(
        absolute_bind_command,
        (absolute_bind_root,),
        "--bind",
    )
    assert absolute_bind_command[-3:] == [
        "--bind",
        absolute_bind_root,
        absolute_bind_root,
    ]

with tempfile.TemporaryDirectory() as private_bind_parent:
    private_bind_root = os.path.join(private_bind_parent, "private")
    os.mkdir(private_bind_root, mode=0o700)
    private_bind_command = []
    sandbox.add_absolute_directory_binds(
        private_bind_command,
        (private_bind_root,),
        "--bind",
        require_user_private=True,
    )
    assert private_bind_command[-3:] == [
        "--bind",
        private_bind_root,
        private_bind_root,
    ]
    os.chmod(private_bind_root, 0o750)
    try:
        sandbox.add_absolute_directory_binds(
            [],
            (private_bind_root,),
            "--bind",
            require_user_private=True,
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("ChatGPT accepted a non-private bind directory")

with tempfile.TemporaryDirectory() as bind_pair_root:
    bind_pair_source = os.path.join(bind_pair_root, "source")
    bind_pair_destination = os.path.join(bind_pair_root, "destination")
    os.mkdir(bind_pair_source, mode=0o700)
    os.mkdir(bind_pair_destination, mode=0o700)
    bind_pair_command = []
    sandbox.add_absolute_directory_bind_pairs(
        bind_pair_command,
        ((bind_pair_source, bind_pair_destination),),
        "--bind",
    )
    assert bind_pair_command == [
        "--bind",
        bind_pair_source,
        bind_pair_destination,
    ]

    bind_pair_symlink = os.path.join(bind_pair_root, "source-link")
    os.symlink(bind_pair_source, bind_pair_symlink)
    try:
        sandbox.add_absolute_directory_bind_pairs(
            [],
            ((bind_pair_symlink, bind_pair_destination),),
            "--bind",
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("ChatGPT accepted a symlinked absolute bind source")

    os.chmod(bind_pair_source, 0o707)
    try:
        sandbox.add_absolute_directory_bind_pairs(
            [],
            ((bind_pair_source, bind_pair_destination),),
            "--bind",
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("ChatGPT accepted a world-writable absolute bind source")

with tempfile.TemporaryDirectory() as working_directory_root:
    working_home = os.path.join(working_directory_root, "home")
    working_downloads = os.path.join(working_home, "Downloads")
    working_workspace = os.path.join(working_home, "Workspace")
    working_pool = os.path.join(working_directory_root, "pool")
    working_codex = os.path.join(working_directory_root, "data-codex")
    working_shared_downloads = os.path.join(
        working_directory_root,
        "data-downloads",
    )
    allowed_working_roots = (
        working_downloads,
        working_workspace,
        working_pool,
        working_codex,
        working_shared_downloads,
    )
    for root in allowed_working_roots:
        pathlib.Path(root, "nested").mkdir(parents=True)
    test_sandbox = {
        "chdir": "Workspace",
        "preserve_working_directory": True,
        "rw_bind_home_directories": ("Downloads", "Workspace"),
        "rw_bind_paths": (
            working_pool,
            working_codex,
            working_shared_downloads,
        ),
    }
    original_working_directory = os.getcwd()
    try:
        for root in allowed_working_roots:
            expected_working_directory = os.path.join(root, "nested")
            os.chdir(expected_working_directory)
            assert module["select_persistent_sandbox_chdir"](
                working_home,
                test_sandbox,
            ) == expected_working_directory
        os.chdir(working_directory_root)
        assert module["select_persistent_sandbox_chdir"](
            working_home,
            test_sandbox,
        ) == working_workspace
    finally:
        os.chdir(original_working_directory)

chatgpt_user = runtime.current_user_name()
chatgpt_home = runtime.current_user_home()
chatgpt_pool_build = f"/pool/build/{chatgpt_user}"
chatgpt_pool_cache = f"/pool/cache/{chatgpt_user}"
chatgpt_pool_db = f"/pool/db/{chatgpt_user}"
assert environment.CHATGPT_POOL_STORAGE_ROOTS == (
    "/pool/cache",
    "/pool/build",
    "/pool/db",
)


def expect_work_area_validation_failure(callback):
    try:
        callback()
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("managed ChatGPT work-area validation accepted unsafe storage")


original_work_area_validator = environment.validate_chatgpt_work_areas
original_directory_validator = environment.validate_managed_work_directory
original_group_lookup = environment.grp.getgrnam
original_getgroups = environment.os.getgroups
original_work_area_access = environment.os.access
with tempfile.TemporaryDirectory() as chatgpt_pool_parent:
    current_uid = os.getuid()
    current_gid = os.getgid()
    test_pool_roots = tuple(
        os.path.join(chatgpt_pool_parent, name)
        for name in ("cache", "build", "db")
    )
    for pool_root in test_pool_roots:
        os.mkdir(pool_root, mode=0o700)
        os.chmod(pool_root, 0o2770)
        account_root = os.path.join(pool_root, chatgpt_user)
        os.mkdir(account_root, mode=0o700)
        os.chmod(account_root, 0o2770)

    def fake_devops_group(name):
        assert name == "devops"
        return types.SimpleNamespace(gr_gid=current_gid)

    environment.grp.getgrnam = fake_devops_group
    environment.os.getgroups = lambda: [current_gid]
    try:
        module["validate_managed_work_directory"](
            "test managed ChatGPT work directory",
            test_pool_roots[0],
            expected_uid=current_uid,
            expected_gid=current_gid,
            expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
        )
        expect_work_area_validation_failure(
            lambda: module["validate_managed_work_directory"](
                "missing managed ChatGPT work directory",
                os.path.join(chatgpt_pool_parent, "missing"),
                expected_uid=current_uid,
                expected_gid=current_gid,
                expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
            )
        )
        expect_work_area_validation_failure(
            lambda: module["validate_managed_work_directory"](
                "misowned managed ChatGPT work directory",
                test_pool_roots[0],
                expected_uid=current_uid + 1,
                expected_gid=current_gid,
                expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
            )
        )
        expect_work_area_validation_failure(
            lambda: module["validate_managed_work_directory"](
                "misgrouped managed ChatGPT work directory",
                test_pool_roots[0],
                expected_uid=current_uid,
                expected_gid=current_gid + 1,
                expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
            )
        )

        pool_symlink = os.path.join(chatgpt_pool_parent, "pool-symlink")
        os.symlink(test_pool_roots[0], pool_symlink)
        expect_work_area_validation_failure(
            lambda: module["validate_managed_work_directory"](
                "indirect managed ChatGPT work directory",
                pool_symlink,
                expected_uid=current_uid,
                expected_gid=current_gid,
                expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
            )
        )

        account_root = os.path.join(test_pool_roots[0], chatgpt_user)
        os.chmod(account_root, 0o2750)
        expect_work_area_validation_failure(
            lambda: module["validate_managed_work_directory"](
                "mis-moded managed ChatGPT work directory",
                account_root,
                expected_uid=current_uid,
                expected_gid=current_gid,
                expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
            )
        )
        os.chmod(account_root, 0o2770)

        environment.os.access = (
            lambda path, mode: False
            if path == account_root and mode & os.W_OK
            else original_work_area_access(path, mode)
        )
        expect_work_area_validation_failure(
            lambda: module["validate_managed_work_directory"](
                "unwritable managed ChatGPT work directory",
                account_root,
                expected_uid=current_uid,
                expected_gid=current_gid,
                expected_mode=environment.CHATGPT_POOL_STORAGE_MODE,
            )
        )
        environment.os.access = original_work_area_access

        recorded_work_directories = []

        def record_work_directory(label, path, **expectations):
            recorded_work_directories.append((label, path, expectations))

        environment.validate_managed_work_directory = record_work_directory
        original_work_area_validator(chatgpt_user, chatgpt_home)
        expected_work_directories = [
            (
                os.path.join(chatgpt_home, relative_path),
                {
                    "expected_uid": current_uid,
                    "expected_gid": current_gid,
                    "expected_mode": environment.CHATGPT_HOME_WORK_DIRECTORY_MODE,
                },
            )
            for relative_path in profiles.CHATGPT_DEVOPS_READ_WRITE_HOME_DIRECTORIES
        ]
        expected_work_directories.append(
            (
                "/pool",
                {
                    "expected_uid": 0,
                    "expected_gid": current_gid,
                    "expected_mode": environment.CHATGPT_POOL_ROOT_MODE,
                },
            )
        )
        for pool_root in environment.CHATGPT_POOL_STORAGE_ROOTS:
            expected_work_directories.extend(
                (
                    (
                        pool_root,
                        {
                            "expected_uid": 0,
                            "expected_gid": current_gid,
                            "expected_mode": environment.CHATGPT_POOL_STORAGE_MODE,
                        },
                    ),
                    (
                        os.path.join(pool_root, chatgpt_user),
                        {
                            "expected_uid": current_uid,
                            "expected_gid": current_gid,
                            "expected_mode": environment.CHATGPT_POOL_STORAGE_MODE,
                        },
                    ),
                )
            )
        expected_work_directories.extend(
            (
                (
                    "/data/codex",
                    {
                        "expected_uid": 0,
                        "expected_gid": current_gid,
                        "expected_mode": environment.CHATGPT_CODEX_ROOT_MODE,
                    },
                ),
                (
                    "/data/downloads",
                    {
                        "expected_uid": current_uid,
                        "expected_gid": current_gid,
                        "expected_mode": environment.CHATGPT_SHARED_DOWNLOADS_ROOT_MODE,
                    },
                ),
            )
        )
        assert [
            (path, expectations)
            for _label, path, expectations in recorded_work_directories
        ] == expected_work_directories
        environment.validate_managed_work_directory = original_directory_validator

        environment.grp.getgrnam = lambda name: types.SimpleNamespace(
            gr_gid=current_gid + 1
        )
        environment.os.getgroups = lambda: []
        expect_work_area_validation_failure(
            lambda: original_work_area_validator(chatgpt_user, chatgpt_home)
        )
    finally:
        environment.validate_managed_work_directory = original_directory_validator
        environment.grp.getgrnam = original_group_lookup
        environment.os.getgroups = original_getgroups
        environment.os.access = original_work_area_access

chatgpt_work_area_validation_calls = []
environment.validate_chatgpt_work_areas = (
    lambda user_name, home_dir: chatgpt_work_area_validation_calls.append(
        (user_name, home_dir)
    )
)
chatgpt_devops_environment = {
    "DEVOPS_DE_ACTIVE": "1",
    "DEVOPS_PROFILE_ONLY": "from-profile",
    "PYTHONUSERBASE": "/profile/python",
    "XDG_CONFIG_HOME": f"{chatgpt_home}/.config",
    "PATH": ":".join(
        (
            "/opt/profile-only/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/data/codex/lib",
        )
    ),
}
os.environ.clear()
os.environ.update(
    {
        "HOME": chatgpt_home,
        "USER": chatgpt_user,
        "LOGNAME": chatgpt_user,
        "SHELL": "/bin/zsh",
        "WAYLAND_DISPLAY": "wayland-0",
        **chatgpt_devops_environment,
    }
)
assert module["validated_chatgpt_devops_environment"]() == chatgpt_devops_environment
assert chatgpt_work_area_validation_calls == [(chatgpt_user, chatgpt_home)]
os.environ["PATH"] = "relative/bin:" + chatgpt_devops_environment["PATH"]
try:
    module["validated_chatgpt_devops_environment"]()
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("ChatGPT accepted an unsafe profile-derived PATH")
os.environ["PATH"] = chatgpt_devops_environment["PATH"]
chatgpt_environment = build_environment("chatgpt", "launch")
expected_chatgpt_sandbox_path = ":".join(
    entry
    for entry in chatgpt_devops_environment["PATH"].split(":")
    if entry != "/data/codex/lib"
)
expected_chatgpt_sandbox_path = (
    f"{expected_chatgpt_sandbox_path}:/data/codex/share/bin"
)
assert chatgpt_environment["PATH"] == expected_chatgpt_sandbox_path
assert "/data/codex/lib" not in chatgpt_environment["PATH"].split(":")
assert chatgpt_environment["DEVOPS_PROFILE_ONLY"] == "from-profile"
assert chatgpt_environment["PYTHONUSERBASE"] == "/profile/python"
assert chatgpt_environment["SHELL"] == "/bin/zsh"
assert "LIBVIRT_DEFAULT_URI" not in chatgpt_environment
assert "VIRSH_DEFAULT_CONNECT_URI" not in chatgpt_environment
assert chatgpt_environment["LD_LIBRARY_PATH"] == "/usr/lib/chatgpt"
assert chatgpt_environment["WAYLAND_DISPLAY"]
assert chatgpt_environment["XDG_SESSION_TYPE"] == "wayland"
for forbidden_name in forbidden_x11_environment:
    assert forbidden_name not in chatgpt_environment
assert module["PERSISTENT_SANDBOX_CONFIG"]["tutanota"]["inner_sandbox_args"] == (
    "--no-sandbox",
)
tutanota_sandbox = module["PERSISTENT_SANDBOX_CONFIG"]["tutanota"]
assert tutanota_sandbox["require_session_bus"] is True
assert "require_system_bus" not in tutanota_sandbox
assert "system_dbus_names" not in tutanota_sandbox
assert module["PERSISTENT_SANDBOX_CONFIG"]["tutanota"]["ro_bind_home_paths"] == (
    ".config/mimeapps.list",
    ".config/user-dirs.dirs",
)
assert module["PERSISTENT_SANDBOX_CONFIG"]["tutanota"]["ro_bind_home_directories"] == (
    "Desktop",
    "Documents",
    "Music",
    "Pictures",
    "Public",
    "Templates",
    "Videos",
)
assert module["PERSISTENT_SANDBOX_CONFIG"]["tutanota"]["rw_bind_home_directories"] == (
    "Downloads",
)
assert module["TUTA_DBUS_NAMES"] == ("org.freedesktop.secrets",)
assert tutanota_sandbox["dbus_names"] == module["TUTA_DBUS_NAMES"]
assert "privacy_dbus_names" not in apps["tutanota"]
assert "privacy_system_bus_proxy" not in apps["tutanota"]
assert apps["tutanota"]["env"]["APPDIR"] == "/opt/tuta-mail"
zoom_config = next(config for config in app_config if config["action_app"] == "zoom")
assert "default_mode" not in zoom_config
assert module["WAYLAND_COMPAT_APPS"] == ("discord", "zoom")
assert set(wayland_compat_runtime.ALLOWED_APPLICATIONS) == set(
    module["WAYLAND_COMPAT_APPS"]
)
assert wayland_compat_runtime.ALLOWED_APPLICATIONS == {
    "discord": "/opt/discord/Discord",
    "zoom": "/usr/bin/zoom",
}
assert (
    wayland_compat_runtime.XWAYLAND_BINARY
    == "/opt/xwayland/usr/bin/Xwayland"
)
assert module["CAGE_BINARY"] == "/usr/bin/cage"
assert module["PRIVATE_RUNTIME_XKBCOMP"] == "/opt/xwayland/usr/bin/xkbcomp"
assert (
    module["PRIVATE_RUNTIME_XKBCOMP_OVERLAY_DIRECTORY"]
    == "/opt/xwayland/usr/lib/xkbcomp-overlay"
)
assert wayland_compat_runtime.XKBCOMP_BINARY == "/usr/bin/xkbcomp"
assert wayland_compat_runtime.PRIVATE_RUNTIME_LIBRARY_NAMES == (
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
assert (
    wayland_compat_runtime.PRIVATE_RUNTIME_LIBRARY_NAMES
    == module["PRIVATE_RUNTIME_LIBRARY_NAMES"]
)
assert wayland_compat_runtime.PRIVATE_APPLICATION_LIBRARY_DIRECTORIES == {
    "discord": (
        module["PRIVATE_RUNTIME_LIBRARY_DIRECTORY"],
        module["DISCORD_ROOT"],
    ),
    "zoom": (module["PRIVATE_RUNTIME_LIBRARY_DIRECTORY"],),
}
assert apps["zoom"]["persistent_sandbox"] is True
assert apps["discord"]["persistent_sandbox"] is True
assert "xdg_config_home" not in apps["zoom"]
zoom_sandbox = module["PERSISTENT_SANDBOX_CONFIG"]["zoom"]
assert zoom_sandbox["persistent_directory_binds"] == (
    (module["ZOOM_CONFIG_SOURCE"], ".config"),
)
for app_name in module["WAYLAND_COMPAT_APPS"]:
    sandbox_config = module["PERSISTENT_SANDBOX_CONFIG"][app_name]
    assert sandbox_config["camera_devices"] is True
    assert sandbox_config["require_system_bus"] is True
    assert sandbox_config["system_dbus_names"] == ()
for mode in ("launch", "intel", "nvidia"):
    discord_environment = build_environment("discord", mode)
    assert discord_environment["QT_QPA_PLATFORM"] == "wayland"
    assert discord_environment["QT_WAYLAND_DISABLE_WINDOWDECORATION"] == "1"
    assert discord_environment["WAYLAND_DISPLAY"]
    assert discord_environment["XDG_SESSION_TYPE"] == "wayland"
    for forbidden_name in forbidden_x11_environment:
        assert forbidden_name not in discord_environment

    zoom_environment = build_environment("zoom", mode)
    assert zoom_environment["QT_QPA_PLATFORM"] == "xcb"
    assert zoom_environment["QT_WAYLAND_DISABLE_WINDOWDECORATION"] == "1"
    assert zoom_environment["WAYLAND_DISPLAY"]
    assert zoom_environment["XDG_SESSION_TYPE"] == "wayland"
    for forbidden_name in forbidden_x11_environment:
        assert forbidden_name not in zoom_environment
assert build_environment("zoom", "launch")["XDG_CONFIG_HOME"].endswith("/.config")
assert apps["ledger-live"]["env"]["APPDIR"] == "/opt/ledger-live"
assert apps["ledger-live"]["pure_privacy"] is False
assert apps["obsidian"]["pure_privacy"] is False
assert apps["postman"]["pure_privacy"] is False
assert apps["sleek"]["pure_privacy"] is False
assert apps["discord"]["pure_privacy"] is False
assert apps["tutanota"]["pure_privacy"] is False
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
assert apps["discord"]["library_dirs"] == (module["DISCORD_ROOT"],)
assert "private_runtime" not in apps["discord"]
assert apps["discord"]["required_runtime_files"] == module["DISCORD_REQUIRED_FILES"]
assert all(
    not path.endswith("/resources/app.asar")
    for path in module["DISCORD_REQUIRED_FILES"]
)
assert "private_runtime" not in apps["zoom"]
assert "required_runtime_files" not in apps["zoom"]
assert "x11_display" not in apps["zoom"]
assert "x11_display" not in apps["discord"]
assert managed_library_path("discord") == module["DISCORD_ROOT"]
assert managed_library_path("zoom") == ""
for mode in ("launch", "intel", "nvidia"):
    assert build_environment("discord", mode)["LD_LIBRARY_PATH"] == module["DISCORD_ROOT"]
    assert "LD_LIBRARY_PATH" not in build_environment("zoom", mode)
for app_name in runtime_library_contract:
    for mode in ("launch", "intel", "nvidia"):
        managed_environment = build_environment(app_name, mode)
        assert managed_environment["PATH"] == managed_path
        assert "LD_PRELOAD" not in managed_environment
        assert "LD_AUDIT" not in managed_environment
        assert "PYTHONPATH" not in managed_environment
        assert "BASH_ENV" not in managed_environment
runtime_files = {
    *(runtime_file for _, runtime_file in runtime_library_contract.values()),
    *module["DISCORD_REQUIRED_FILES"],
}
original_isfile = module["os"].path.isfile
original_access = module["os"].access
try:
    module["os"].path.isfile = lambda path: path in runtime_files
    module["os"].access = lambda path, mode: path in runtime_files
    for app_name in (*runtime_library_contract, *module["WAYLAND_COMPAT_APPS"]):
        validate_required_runtime_files(app_name)
finally:
    module["os"].path.isfile = original_isfile
    module["os"].access = original_access
with tempfile.TemporaryDirectory() as attachment_home:
    documents_dir = os.path.join(attachment_home, "Documents")
    downloads_dir = os.path.join(attachment_home, "Downloads")
    os.mkdir(documents_dir)
    os.mkdir(downloads_dir)
    os.chmod(documents_dir, 0o700)
    os.chmod(downloads_dir, 0o700)
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
    add_persistent_directory_binds(
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
vivaldi_environment = build_environment("vivaldi", "launch")
assert vivaldi_environment["FONTCONFIG_FILE"] == "/etc/fonts/fonts.conf"
assert vivaldi_environment["FONTCONFIG_PATH"] == "/etc/fonts"
assert vivaldi_environment["GTK_CSD"] == "0"
assert vivaldi_environment["QT_WAYLAND_DISABLE_WINDOWDECORATION"] == "1"
assert vivaldi_environment["VIVALDI_FFMPEG_AUTO"] == "0"
assert vivaldi_environment["XDG_CONFIG_HOME"].endswith("/.config")
assert vivaldi_environment["XDG_CACHE_HOME"].endswith("/.cache")
assert vivaldi_environment["XDG_DATA_HOME"].endswith("/.local/share")
resolved_executable = module["resolved_executable"]
original_isfile = module["os"].path.isfile
original_access = module["os"].access
try:
    module["os"].path.isfile = lambda path: path in {
        "/usr/bin/obsidian",
        "/usr/bin/sleek",
        "/usr/bin/filen",
    }
    module["os"].access = lambda path, mode: path in {
        "/usr/bin/obsidian",
        "/usr/bin/sleek",
        "/usr/bin/filen",
    }
    assert resolved_executable("obsidian", "launch") == "/usr/bin/obsidian"
    assert resolved_executable("sleek", "launch") == "/usr/bin/sleek"
    assert resolved_executable("filen", "launch") == "/usr/bin/filen"
finally:
    module["os"].path.isfile = original_isfile
    module["os"].access = original_access
assert "--no-sandbox" in persistent_sandbox_argv(
    "tutanota",
    "launch",
    [],
    "/home/tester",
)
chatgpt_payload_argv = persistent_sandbox_argv(
    "chatgpt",
    "launch",
    [],
    chatgpt_home,
)
assert chatgpt_payload_argv[0] == "/usr/lib/chatgpt/ChatGPT"
assert "--ozone-platform=wayland" in chatgpt_payload_argv
assert "--no-sandbox" not in chatgpt_payload_argv
for mode in ("intel", "nvidia"):
    assert "--js-flags=--max-old-space-size=2016" in persistent_sandbox_argv(
        "chatgpt",
        mode,
        [],
        chatgpt_home,
    )

with tempfile.TemporaryDirectory() as identity_root:
    first_root = os.path.join(identity_root, "first")
    second_root = os.path.join(identity_root, "second")
    third_root = os.path.join(identity_root, "third")
    host_machine_id = pathlib.Path(identity_root, "host-machine-id")
    host_machine_id.write_text(
        "0123456789abcdef0123456789abcdef\n",
        encoding="ascii",
    )
    os.mkdir(first_root)
    os.mkdir(second_root)
    os.mkdir(third_root)
    original_require_regular_file = sandbox.require_root_owned_regular_file
    sandbox.require_root_owned_regular_file = (
        lambda label, path: str(host_machine_id)
    )
    try:
        first_identity = module["create_synthetic_identity_files"](
            first_root,
            chatgpt_home,
            shell_path="/bin/zsh",
        )
        second_identity = module["create_synthetic_identity_files"](
            second_root,
            chatgpt_home,
            shell_path="/bin/zsh",
        )
        host_machine_id.write_text(
            "fedcba9876543210fedcba9876543210\n",
            encoding="ascii",
        )
        third_identity = module["create_synthetic_identity_files"](
            third_root,
            chatgpt_home,
            shell_path="/bin/zsh",
        )
    finally:
        sandbox.require_root_owned_regular_file = original_require_regular_file
    first_machine_id = pathlib.Path(first_identity["machine_id"]).read_text(
        encoding="utf-8"
    )
    second_machine_id = pathlib.Path(second_identity["machine_id"]).read_text(
        encoding="utf-8"
    )
    third_machine_id = pathlib.Path(third_identity["machine_id"]).read_text(
        encoding="utf-8"
    )
    assert first_machine_id == second_machine_id
    assert first_machine_id != third_machine_id
    assert first_identity["hostname_value"] == second_identity["hostname_value"]
    assert first_identity["hostname_value"] != third_identity["hostname_value"]
    assert first_identity["hostname_value"].startswith("chatgpt-")
    first_installation_id = pathlib.Path(
        first_identity["installation_id"]
    ).read_bytes()
    second_installation_id = pathlib.Path(
        second_identity["installation_id"]
    ).read_bytes()
    third_installation_id = pathlib.Path(
        third_identity["installation_id"]
    ).read_bytes()
    assert first_installation_id == second_installation_id
    assert first_installation_id != third_installation_id
    assert re.fullmatch(
        rb"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        first_installation_id,
    )
    assert re.fullmatch(
        rb"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        second_installation_id,
    )
    assert b"\n" not in first_installation_id
    assert b"\r" not in first_installation_id
    assert pathlib.Path(first_identity["installation_id"]).parent == pathlib.Path(
        first_root
    )
    assert stat.S_IMODE(
        pathlib.Path(first_identity["installation_id"]).stat().st_mode
    ) == 0o644
    installation_id_command = []
    module["add_synthetic_codex_installation_id_mount"](
        installation_id_command,
        first_identity["installation_id"],
    )
    assert installation_id_command == [
        "--bind",
        first_identity["installation_id"],
        "/data/codex/usr/home/installation_id",
    ]
    synthetic_passwd = pathlib.Path(first_identity["passwd"]).read_text(
        encoding="utf-8"
    )
    assert "developer:x:" in synthetic_passwd
    assert synthetic_passwd.rstrip().endswith(":/bin/zsh")
    identity_command = []
    module["add_synthetic_identity_mounts"](
        identity_command,
        first_identity,
    )
    for source_name, destination in (
        ("machine_id", "/etc/machine-id"),
        ("machine_id", "/var/lib/dbus/machine-id"),
        ("hostname", "/etc/hostname"),
        ("passwd", "/etc/passwd"),
        ("group", "/etc/group"),
        ("hosts", "/etc/hosts"),
        ("resolv", "/etc/resolv.conf"),
        ("nsswitch", "/etc/nsswitch.conf"),
        ("boot_id", "/proc/sys/kernel/random/boot_id"),
        ("hostname", "/proc/sys/kernel/hostname"),
        ("cmdline", "/proc/cmdline"),
    ):
        expected_mount = [
            "--ro-bind",
            first_identity[source_name],
            destination,
        ]
        assert any(
            identity_command[index : index + 3] == expected_mount
            for index in range(len(identity_command) - 2)
        )

with tempfile.TemporaryDirectory() as network_test_root:
    network_root = pathlib.Path(network_test_root)
    fake_bwrap = network_root / "fake-bwrap"
    fake_slirp = network_root / "fake-slirp4netns"
    slirp_capture = network_root / "slirp.json"
    fake_bwrap.write_text(
        """#!/usr/bin/python3
import json
import os
import sys

arguments = sys.argv[1:]
info_fd = int(arguments[arguments.index("--info-fd") + 1])
block_fd = int(arguments[arguments.index("--block-fd") + 1])
os.write(
    info_fd,
    json.dumps({"child-pid": os.getpid()}).encode("utf-8"),
)
os.close(info_fd)
if os.read(block_fd, 1) != b"1":
    raise SystemExit(90)
raise SystemExit(37)
""",
        encoding="utf-8",
    )
    fake_slirp.write_text(
        f"""#!/usr/bin/python3
import json
import os
import sys

arguments = sys.argv[1:]
ready_fd = int(arguments[arguments.index("--ready-fd") + 1])
exit_fd = int(arguments[arguments.index("--exit-fd") + 1])
with open({str(slirp_capture)!r}, "w", encoding="utf-8") as handle:
    json.dump({{"arguments": arguments}}, handle)
os.write(ready_fd, b"1")
os.close(ready_fd)
while os.read(exit_fd, 4096):
    pass
""",
        encoding="utf-8",
    )
    fake_bwrap.chmod(0o755)
    fake_slirp.chmod(0o755)

    original_require_executable = sandbox.require_root_owned_executable
    sandbox.require_root_owned_executable = (
        lambda label, path: str(fake_slirp)
    )
    try:
        assert module["run_slirp4netns_sandbox"](
            [str(fake_bwrap), "--unshare-all"],
            ["/usr/bin/true"],
            str(network_root),
            (),
        ) == 37
    finally:
        sandbox.require_root_owned_executable = original_require_executable

    slirp_invocation = json.loads(slirp_capture.read_text(encoding="utf-8"))
    slirp_arguments = slirp_invocation["arguments"]
    assert "--configure" in slirp_arguments
    assert "--mtu=65520" in slirp_arguments
    assert "--disable-host-loopback" in slirp_arguments
    assert "--ready-fd" in slirp_arguments
    assert "--exit-fd" in slirp_arguments
    assert slirp_arguments[-1] == "tap0"
    assert re.fullmatch(r"[1-9][0-9]*", slirp_arguments[-2])

    failing_slirp = network_root / "failing-slirp4netns"
    failing_slirp.write_text(
        """#!/usr/bin/python3
raise SystemExit(73)
""",
        encoding="utf-8",
    )
    failing_slirp.chmod(0o755)
    failure_output = io.StringIO()
    sandbox.require_root_owned_executable = (
        lambda label, path: str(failing_slirp)
    )
    try:
        with contextlib.redirect_stderr(failure_output):
            try:
                module["run_slirp4netns_sandbox"](
                    [str(fake_bwrap), "--unshare-all"],
                    ["/usr/bin/true"],
                    str(network_root),
                    (),
                )
            except SystemExit as exc:
                assert exc.code == 1
            else:
                raise AssertionError(
                    "ChatGPT accepted slirp4netns exiting before readiness"
                )
    finally:
        sandbox.require_root_owned_executable = original_require_executable
    assert (
        "slirp4netns exited before configuring the isolated network namespace "
        "(status 73)"
        in failure_output.getvalue()
    )

    invalid_info_bwrap = network_root / "invalid-info-bwrap"
    invalid_info_bwrap.write_text(
        """#!/usr/bin/python3
import os
import sys

arguments = sys.argv[1:]
info_fd = int(arguments[arguments.index("--info-fd") + 1])
block_fd = int(arguments[arguments.index("--block-fd") + 1])
os.write(info_fd, b"[]")
os.close(info_fd)
os.read(block_fd, 1)
""",
        encoding="utf-8",
    )
    invalid_info_bwrap.chmod(0o755)
    failure_output = io.StringIO()
    sandbox.require_root_owned_executable = (
        lambda label, path: str(fake_slirp)
    )
    try:
        with contextlib.redirect_stderr(failure_output):
            try:
                module["run_slirp4netns_sandbox"](
                    [str(invalid_info_bwrap), "--unshare-all"],
                    ["/usr/bin/true"],
                    str(network_root),
                    (),
                )
            except SystemExit as exc:
                assert exc.code == 1
            else:
                raise AssertionError(
                    "ChatGPT accepted non-object Bubblewrap sandbox information"
                )
    finally:
        sandbox.require_root_owned_executable = original_require_executable
    assert (
        "Bubblewrap sandbox information must be a JSON object"
        in failure_output.getvalue()
    )

    invalid_ready_slirp = network_root / "invalid-ready-slirp4netns"
    invalid_ready_slirp.write_text(
        """#!/usr/bin/python3
import os
import sys

arguments = sys.argv[1:]
ready_fd = int(arguments[arguments.index("--ready-fd") + 1])
exit_fd = int(arguments[arguments.index("--exit-fd") + 1])
os.write(ready_fd, b"0")
os.close(ready_fd)
while os.read(exit_fd, 4096):
    pass
""",
        encoding="utf-8",
    )
    invalid_ready_slirp.chmod(0o755)
    failure_output = io.StringIO()
    sandbox.require_root_owned_executable = (
        lambda label, path: str(invalid_ready_slirp)
    )
    try:
        with contextlib.redirect_stderr(failure_output):
            try:
                module["run_slirp4netns_sandbox"](
                    [str(fake_bwrap), "--unshare-all"],
                    ["/usr/bin/true"],
                    str(network_root),
                    (),
                )
            except SystemExit as exc:
                assert exc.code == 1
            else:
                raise AssertionError(
                    "ChatGPT accepted an invalid slirp4netns readiness marker"
                )
    finally:
        sandbox.require_root_owned_executable = original_require_executable
    assert (
        "slirp4netns returned an invalid readiness marker"
        in failure_output.getvalue()
    )

    slow_bwrap = network_root / "slow-bwrap"
    slow_bwrap.write_text(
        """#!/usr/bin/python3
import json
import os
import sys
import time

arguments = sys.argv[1:]
info_fd = int(arguments[arguments.index("--info-fd") + 1])
block_fd = int(arguments[arguments.index("--block-fd") + 1])
os.write(
    info_fd,
    json.dumps({"child-pid": os.getpid()}).encode("utf-8"),
)
os.close(info_fd)
if os.read(block_fd, 1) != b"1":
    raise SystemExit(90)
time.sleep(30)
""",
        encoding="utf-8",
    )
    runtime_failing_slirp = network_root / "runtime-failing-slirp4netns"
    runtime_failing_slirp.write_text(
        """#!/usr/bin/python3
import os
import sys
import time

arguments = sys.argv[1:]
ready_fd = int(arguments[arguments.index("--ready-fd") + 1])
os.write(ready_fd, b"1")
os.close(ready_fd)
time.sleep(0.1)
print("managed runtime failure", file=sys.stderr)
raise SystemExit(74)
""",
        encoding="utf-8",
    )
    slow_bwrap.chmod(0o755)
    runtime_failing_slirp.chmod(0o755)
    failure_output = io.StringIO()
    sandbox.require_root_owned_executable = (
        lambda label, path: str(runtime_failing_slirp)
    )
    try:
        with contextlib.redirect_stderr(failure_output):
            try:
                module["run_slirp4netns_sandbox"](
                    [str(slow_bwrap), "--unshare-all"],
                    ["/usr/bin/true"],
                    str(network_root),
                    (),
                )
            except SystemExit as exc:
                assert exc.code == 1
            else:
                raise AssertionError(
                    "ChatGPT accepted slirp4netns exiting during sandbox runtime"
                )
    finally:
        sandbox.require_root_owned_executable = original_require_executable
    assert (
        "slirp4netns exited while the managed application sandbox was running (status 74): "
        "managed runtime failure"
        in failure_output.getvalue()
    )

original_isdir = sandbox.os.path.isdir
original_islink = sandbox.os.path.islink
try:
    sandbox.os.path.isdir = lambda path: path.startswith("/sys/")
    sandbox.os.path.islink = lambda path: False
    sysfs_command = []
    module["add_synthetic_sysfs_masks"](sysfs_command)
finally:
    sandbox.os.path.isdir = original_isdir
    sandbox.os.path.islink = original_islink
assert sysfs_command == [
    "--tmpfs",
    "/sys/block",
    "--tmpfs",
    "/sys/bus/scsi/devices",
    "--tmpfs",
    "/sys/class/block",
    "--tmpfs",
    "/sys/class/dmi/id",
    "--tmpfs",
    "/sys/class/net",
    "--tmpfs",
    "/sys/class/nvme",
    "--tmpfs",
    "/sys/devices/virtual/block",
    "--tmpfs",
    "/sys/devices/virtual/dmi/id",
    "--tmpfs",
    "/sys/devices/virtual/net",
    "--tmpfs",
    "/sys/firmware",
]

captured_chatgpt_launches = {}
with tempfile.TemporaryDirectory() as chatgpt_capture_home, tempfile.TemporaryDirectory() as chatgpt_capture_runtime:
    chatgpt_capture_config = module["PERSISTENT_SANDBOX_CONFIG"]["chatgpt"]
    for relative_path in (
        *chatgpt_capture_config["ro_bind_home_directories"],
        *chatgpt_capture_config["rw_bind_home_directories"],
    ):
        fixture_directory = pathlib.Path(chatgpt_capture_home, relative_path)
        fixture_directory.mkdir(
            parents=True,
            exist_ok=True,
        )
        fixture_directory.chmod(0o700)
    for relative_path in chatgpt_capture_config["ro_bind_home_optional_files"]:
        optional_file = pathlib.Path(chatgpt_capture_home, relative_path)
        optional_file.parent.mkdir(parents=True, exist_ok=True)
        optional_file.write_text("# managed test fixture\n", encoding="utf-8")
        optional_file.chmod(0o644)
    pathlib.Path(chatgpt_capture_runtime, "doc").mkdir()
    pathlib.Path(chatgpt_capture_runtime, "pulse").mkdir()

    original_sandbox_build_environment = sandbox.build_environment
    original_runtime_socket = sandbox.current_user_runtime_socket
    original_require_executable = sandbox.require_root_owned_executable
    original_require_regular_file = sandbox.require_root_owned_regular_file
    original_start_session_proxy = sandbox.start_session_bus_proxy
    original_start_system_proxy = sandbox.start_system_bus_proxy
    original_optional_bind = sandbox.add_optional_bind
    original_absolute_binds = sandbox.add_absolute_directory_binds
    original_absolute_bind_pairs = sandbox.add_absolute_directory_bind_pairs
    original_runtime_bind = sandbox.add_runtime_bind
    original_video_binds = sandbox.add_video_device_binds
    original_gpu_binds = sandbox.add_gpu_device_binds
    original_sysfs_masks = sandbox.add_synthetic_sysfs_masks
    original_filtered_resolv = sandbox.filtered_resolv_conf
    original_slirp4netns_runner = sandbox.run_slirp4netns_sandbox

    def simulated_chatgpt_environment(app_name, mode):
        assert app_name == "chatgpt"
        assert mode in {"launch", "intel", "nvidia"}
        simulated = dict(chatgpt_environment)
        simulated.update(
            {
                "HOME": chatgpt_capture_home,
                "USER": "managed-user",
                "LOGNAME": "managed-user",
                "XDG_CONFIG_HOME": f"{chatgpt_capture_home}/.config",
                "XDG_CACHE_HOME": f"{chatgpt_capture_home}/.cache",
                "XDG_DATA_HOME": f"{chatgpt_capture_home}/.local/share",
                "XDG_STATE_HOME": f"{chatgpt_capture_home}/.local/state",
                "XDG_RUNTIME_DIR": chatgpt_capture_runtime,
                "WAYLAND_DISPLAY": "wayland-9",
                "DBUS_SESSION_BUS_ADDRESS": (
                    f"unix:path={chatgpt_capture_runtime}/bus"
                ),
            }
        )
        simulated.pop("DISPLAY", None)
        simulated.pop("XAUTHORITY", None)
        return simulated

    def simulated_absolute_binds(command, paths, option):
        assert option in {"--bind", "--ro-bind"}
        expected_paths = (
            chatgpt_capture_config["rw_bind_paths"]
            if option == "--bind"
            else chatgpt_capture_config["ro_bind_directory_paths"]
        )
        assert paths == expected_paths
        for path in paths:
            command.extend([option, path, path])

    def simulated_absolute_bind_pairs(command, path_pairs, option):
        assert option == "--bind"
        assert path_pairs == chatgpt_capture_config["rw_bind_directory_pairs"]
        for source, destination in path_pairs:
            command.extend([option, source, destination])

    def simulated_runtime_bind(
        command,
        host_runtime_dir,
        sandbox_runtime_dir,
        relative_path,
        expected_kind,
        *,
        required=False,
    ):
        assert expected_kind in {"directory", "socket"}
        assert required is (
            relative_path in chatgpt_capture_config["required_runtime_sockets"]
        )
        command.extend(
            [
                "--bind",
                os.path.join(host_runtime_dir, relative_path),
                os.path.join(sandbox_runtime_dir, relative_path),
            ]
        )

    def simulated_video_binds(command, enabled):
        assert enabled is False

    def simulated_gpu_binds(command, mode):
        if mode == "intel":
            command.extend(
                [
                    "--dev-bind",
                    "/dev/dri/renderD128",
                    "/dev/dri/renderD128",
                    "--dev-bind",
                    "/dev/kfd",
                    "/dev/kfd",
                    "--dev-bind",
                    "/dev/accel",
                    "/dev/accel",
                ]
            )
        elif mode == "nvidia":
            command.extend(
                [
                    "--dev-bind",
                    "/dev/dri/renderD128",
                    "/dev/dri/renderD128",
                    "--dev-bind",
                    "/dev/kfd",
                    "/dev/kfd",
                    "--dev-bind",
                    "/dev/accel",
                    "/dev/accel",
                    "--dev-bind",
                    "/dev/nvidiactl",
                    "/dev/nvidiactl",
                ]
            )

    def capture_chatgpt_slirp4netns(
        command,
        payload_argv,
        temp_root,
        inherited_fds,
    ):
        mode = next(
            selected_mode
            for selected_mode in ("launch", "intel", "nvidia")
            if selected_mode not in captured_chatgpt_launches
        )
        captured_chatgpt_launches[mode] = {
            "command": [*command, *payload_argv],
            "kwargs": {
                "cwd": "/",
                "pass_fds": inherited_fds,
            },
            "resolv_conf": pathlib.Path(
                temp_root,
                "resolv.conf",
            ).read_text(encoding="utf-8"),
        }
        return {"launch": 41, "intel": 42, "nvidia": 43}[mode]

    sandbox.build_environment = simulated_chatgpt_environment
    sandbox.current_user_runtime_socket = (
        lambda label, entry_name: os.path.join(
            chatgpt_capture_runtime,
            entry_name,
        )
    )
    sandbox.require_root_owned_executable = lambda label, path: path
    captured_host_machine_id = pathlib.Path(
        chatgpt_capture_runtime,
        "host-machine-id",
    )
    captured_host_machine_id.write_text(
        "0123456789abcdef0123456789abcdef\n",
        encoding="ascii",
    )
    sandbox.require_root_owned_regular_file = (
        lambda label, path: str(captured_host_machine_id)
    )
    sandbox.start_session_bus_proxy = (
        lambda *args, **kwargs: (
            None,
            os.path.join(chatgpt_capture_runtime, "filtered-session-bus"),
            None,
        )
    )
    sandbox.start_system_bus_proxy = (
        lambda temp_root, additional_talk_names, required=False: (
            None,
            os.path.join(chatgpt_capture_runtime, "filtered-system-bus"),
            None,
        )
        if additional_talk_names == ("org.freedesktop.UPower",) and required
        else (_ for _ in ()).throw(AssertionError("unexpected system bus policy"))
    )
    sandbox.add_optional_bind = (
        lambda command, option, source, destination: command.extend(
            [option, source, destination]
        )
    )
    sandbox.add_absolute_directory_binds = simulated_absolute_binds
    sandbox.add_absolute_directory_bind_pairs = simulated_absolute_bind_pairs
    sandbox.add_runtime_bind = simulated_runtime_bind
    sandbox.add_video_device_binds = simulated_video_binds
    sandbox.add_gpu_device_binds = simulated_gpu_binds
    sandbox.add_synthetic_sysfs_masks = (
        lambda command: command.extend(sysfs_command)
    )
    sandbox.filtered_resolv_conf = lambda: (_ for _ in ()).throw(
        AssertionError(
            "ChatGPT must use the slirp4netns DNS endpoint, not the host resolver"
        )
    )
    sandbox.run_slirp4netns_sandbox = capture_chatgpt_slirp4netns
    try:
        assert sandbox._run_persistent_sandbox(
            "chatgpt",
            "launch",
            [],
        ) == 41
        assert sandbox._run_persistent_sandbox(
            "chatgpt",
            "intel",
            [],
        ) == 42
        assert sandbox._run_persistent_sandbox(
            "chatgpt",
            "nvidia",
            [],
        ) == 43
    finally:
        sandbox.build_environment = original_sandbox_build_environment
        sandbox.current_user_runtime_socket = original_runtime_socket
        sandbox.require_root_owned_executable = original_require_executable
        sandbox.require_root_owned_regular_file = original_require_regular_file
        sandbox.start_session_bus_proxy = original_start_session_proxy
        sandbox.start_system_bus_proxy = original_start_system_proxy
        sandbox.add_optional_bind = original_optional_bind
        sandbox.add_absolute_directory_binds = original_absolute_binds
        sandbox.add_absolute_directory_bind_pairs = original_absolute_bind_pairs
        sandbox.add_runtime_bind = original_runtime_bind
        sandbox.add_video_device_binds = original_video_binds
        sandbox.add_gpu_device_binds = original_gpu_binds
        sandbox.add_synthetic_sysfs_masks = original_sysfs_masks
        sandbox.filtered_resolv_conf = original_filtered_resolv
        sandbox.run_slirp4netns_sandbox = original_slirp4netns_runner
    shared_temp_directory = os.path.join(
        chatgpt_capture_runtime,
        chatgpt_capture_config["shared_temp_directory"],
    )
    shared_temp_metadata = os.stat(shared_temp_directory)
    assert stat.S_ISDIR(shared_temp_metadata.st_mode)
    assert stat.S_IMODE(shared_temp_metadata.st_mode) == 0o700
    assert shared_temp_metadata.st_uid == os.getuid()
    lifecycle_lock = pathlib.Path(
        chatgpt_capture_runtime,
        sandbox.CHATGPT_LIFECYCLE_LOCK_NAME,
    )
    lifecycle_lock_metadata = lifecycle_lock.stat()
    assert stat.S_ISREG(lifecycle_lock_metadata.st_mode)
    assert stat.S_IMODE(lifecycle_lock_metadata.st_mode) == 0o600
    assert lifecycle_lock_metadata.st_uid == os.getuid()

def command_contains(command, sequence):
    width = len(sequence)
    return any(
        command[index : index + width] == sequence
        for index in range(len(command) - width + 1)
    )

for mode in ("launch", "intel", "nvidia"):
    captured = captured_chatgpt_launches[mode]
    chatgpt_command = captured["command"]
    assert captured["kwargs"]["cwd"] == "/"
    assert captured["kwargs"]["pass_fds"] == ()
    for required_flag in (
        "--unshare-all",
        "--new-session",
        "--die-with-parent",
        "--clearenv",
        "--cap-drop",
        "--proc",
        "--dev",
    ):
        assert required_flag in chatgpt_command
    assert "--share-net" not in chatgpt_command
    assert (
        captured["resolv_conf"]
        == module["slirp4netns_resolv_conf"]()
        == "nameserver 10.0.2.3\noptions timeout:2 attempts:3\n"
    )
    assert command_contains(chatgpt_command, ["--cap-drop", "ALL"])
    assert command_contains(
        chatgpt_command,
        ["--chdir", f"{chatgpt_capture_home}/Workspace"],
    )
    assert command_contains(chatgpt_command, ["--ro-bind", "/usr", "/usr"])
    assert command_contains(
        chatgpt_command,
        [
            "--tmpfs",
            chatgpt_capture_home,
            "--chmod",
            "0700",
            chatgpt_capture_home,
        ],
    )
    for relative_path in chatgpt_capture_config["rw_bind_home_directories"]:
        assert command_contains(
            chatgpt_command,
            [
                "--bind",
                f"{chatgpt_capture_home}/{relative_path}",
                f"{chatgpt_capture_home}/{relative_path}",
            ],
        )
    for relative_path in chatgpt_capture_config["ro_bind_home_directories"]:
        assert command_contains(
            chatgpt_command,
            [
                "--ro-bind",
                f"{chatgpt_capture_home}/{relative_path}",
                f"{chatgpt_capture_home}/{relative_path}",
            ],
        )
    for relative_path in chatgpt_capture_config["ro_bind_home_optional_files"]:
        assert command_contains(
            chatgpt_command,
            [
                "--ro-bind",
                f"{chatgpt_capture_home}/{relative_path}",
                f"{chatgpt_capture_home}/{relative_path}",
            ],
        )
    for writable_path in chatgpt_capture_config["rw_bind_paths"]:
        assert command_contains(
            chatgpt_command,
            ["--bind", writable_path, writable_path],
        )
    for source_path, destination_path in chatgpt_capture_config[
        "rw_bind_directory_pairs"
    ]:
        assert command_contains(
            chatgpt_command,
            ["--bind", source_path, destination_path],
        )
        broad_bind = ["--bind", "/data/codex", "/data/codex"]
        overlay_bind = ["--bind", source_path, destination_path]
        broad_index = next(
            index
            for index in range(len(chatgpt_command) - len(broad_bind) + 1)
            if chatgpt_command[index : index + len(broad_bind)] == broad_bind
        )
        overlay_index = next(
            index
            for index in range(len(chatgpt_command) - len(overlay_bind) + 1)
            if chatgpt_command[index : index + len(overlay_bind)] == overlay_bind
        )
        assert broad_index < overlay_index
    installation_id_destination_index = chatgpt_command.index(
        "/data/codex/usr/home/installation_id"
    )
    assert chatgpt_command[installation_id_destination_index - 2] == "--bind"
    assert chatgpt_command[installation_id_destination_index - 1].endswith(
        "/installation_id"
    )
    assert (
        chatgpt_command[installation_id_destination_index - 1]
        != "/data/codex/usr/home/installation_id"
    )
    for read_only_path in chatgpt_capture_config["ro_bind_directory_paths"]:
        assert command_contains(
            chatgpt_command,
            ["--ro-bind", read_only_path, read_only_path],
        )
    sandbox_runtime_dir = f"/run/user/{os.getuid()}"
    assert command_contains(
        chatgpt_command,
        [
            "--bind",
            f"{chatgpt_capture_runtime}/filtered-session-bus",
            f"{sandbox_runtime_dir}/bus",
        ],
    )
    assert command_contains(
        chatgpt_command,
        [
            "--bind",
            f"{chatgpt_capture_runtime}/filtered-system-bus",
            "/run/dbus/system_bus_socket",
        ],
    )
    shared_temp_directory = os.path.join(
        chatgpt_capture_runtime,
        chatgpt_capture_config["shared_temp_directory"],
    )
    assert command_contains(
        chatgpt_command,
        [
            "--bind",
            shared_temp_directory,
            shared_temp_directory,
        ],
    )
    for relative_socket in chatgpt_capture_config["runtime_sockets"]:
        assert command_contains(
            chatgpt_command,
            [
                "--bind",
                f"{chatgpt_capture_runtime}/{relative_socket}",
                f"{sandbox_runtime_dir}/{relative_socket}",
            ],
        )
    assert not any(
        path == "/dev/snd" or path.startswith("/dev/snd/")
        for path in chatgpt_command
    )
    for identity_destination in (
        "/etc/machine-id",
        "/var/lib/dbus/machine-id",
        "/etc/hostname",
        "/etc/passwd",
        "/etc/group",
        "/etc/hosts",
        "/etc/resolv.conf",
        "/etc/nsswitch.conf",
        "/proc/sys/kernel/random/boot_id",
        "/proc/sys/kernel/hostname",
        "/proc/cmdline",
    ):
        assert identity_destination in chatgpt_command
    for masked_sysfs_path in (
        "/sys/block",
        "/sys/class/dmi/id",
        "/sys/class/net",
        "/sys/firmware",
    ):
        assert command_contains(
            chatgpt_command,
            ["--tmpfs", masked_sysfs_path],
        )
    command_environment = {}
    for index, argument in enumerate(chatgpt_command):
        if argument == "--setenv":
            command_environment[chatgpt_command[index + 1]] = (
                chatgpt_command[index + 2]
            )
    assert command_environment["USER"] == "developer"
    assert command_environment["LOGNAME"] == "developer"
    assert command_environment["HOSTNAME"].startswith("chatgpt-")
    assert command_environment["TMPDIR"] == shared_temp_directory
    assert command_environment["XDG_SESSION_TYPE"] == "wayland"
    assert command_environment["WAYLAND_DISPLAY"] == "wayland-9"
    assert (
        command_environment["DBUS_SYSTEM_BUS_ADDRESS"]
        == "unix:path=/run/dbus/system_bus_socket"
    )
    assert command_environment["XDG_CONFIG_HOME"] == f"{chatgpt_capture_home}/.config"
    assert command_environment["DEVOPS_PROFILE_ONLY"] == "from-profile"
    assert command_environment["PYTHONUSERBASE"] == "/profile/python"
    assert command_environment["SHELL"] == "/bin/zsh"
    assert command_environment["PATH"] == chatgpt_environment["PATH"]
    assert "LIBVIRT_DEFAULT_URI" not in command_environment
    assert "VIRSH_DEFAULT_CONNECT_URI" not in command_environment
    assert (
        command_environment["PATH"].index("/opt/profile-only/bin")
        < command_environment["PATH"].index("/usr/local/bin")
    )
    assert "DISPLAY" not in command_environment
    assert "XAUTHORITY" not in command_environment
    expected_payload = persistent_sandbox_argv(
        "chatgpt",
        mode,
        [],
        chatgpt_capture_home,
    )
    assert chatgpt_command[-len(expected_payload) :] == expected_payload
    assert "--ozone-platform=wayland" in expected_payload
    assert "--disable-vulkan" in expected_payload
    assert "--no-sandbox" not in expected_payload
    assert "/tmp/.X11-unix" not in chatgpt_command

assert "/dev/dri/renderD128" not in captured_chatgpt_launches["launch"]["command"]
assert "/dev/kfd" not in captured_chatgpt_launches["launch"]["command"]
assert "/dev/accel" not in captured_chatgpt_launches["launch"]["command"]
assert "/dev/nvidiactl" not in captured_chatgpt_launches["launch"]["command"]
assert "/dev/dri/renderD128" in captured_chatgpt_launches["intel"]["command"]
assert "/dev/kfd" in captured_chatgpt_launches["intel"]["command"]
assert "/dev/accel" in captured_chatgpt_launches["intel"]["command"]
assert "/dev/nvidiactl" not in captured_chatgpt_launches["intel"]["command"]
assert "/dev/dri/renderD128" in captured_chatgpt_launches["nvidia"]["command"]
assert "/dev/kfd" in captured_chatgpt_launches["nvidia"]["command"]
assert "/dev/accel" in captured_chatgpt_launches["nvidia"]["command"]
assert "/dev/nvidiactl" in captured_chatgpt_launches["nvidia"]["command"]

assert "--no-sandbox" not in pure_privacy_argv("keepassxc", [])
assert module["SYSTEM_BUS_SOCKET_PATH"] == "/run/dbus/system_bus_socket"
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
assert electron_password_store == "--password-store=gnome-libsecret"
assert electron_password_store_arg("tutanota") == "--password-store=gnome-libsecret"
assert electron_password_store_arg("discord") == electron_password_store
for app_name in electron_limits:
    for mode in ("launch", "intel", "nvidia"):
        assert build_argv(app_name, mode, []).count(electron_password_store) == 1
assert "TUTA_SECRET_SERVICE_UNITS" not in module
assert "SYSTEMCTL_PATH" not in module
assert "ensure_tuta_secret_services" not in module
assert "validate_bitwarden_secret_service" not in vars(environment)
assert "validate_bitwarden_secret_service" not in vars(cli)
assert not any(name.startswith("BITWARDEN_SECRET_SERVICE_") for name in vars(environment))

original_cli_geteuid = cli.os.geteuid
original_cli_execvpe = cli.os.execvpe
original_cli_load_policy = cli.load_managed_launch_policy
original_cli_validate_mode = cli.validate_acceleration_mode
original_cli_resolved_executable = cli.resolved_executable
original_cli_validate_runtime = cli.validate_required_runtime_files
original_cli_home = cli.current_user_home
original_cli_runtime_state = cli.ensure_managed_runtime_state
original_cli_build_environment = cli.build_environment
original_cli_build_argv = cli.build_argv
saved_cli_argv = list(sys.argv)
saved_cli_session_bus = os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)
cli_events = []
try:
    cli.os.geteuid = lambda: 1000
    cli.os.execvpe = lambda *_args: cli_events.append("exec")
    cli.load_managed_launch_policy = lambda _path: ({}, "launch")
    cli.validate_acceleration_mode = lambda _mode, _availability: None
    cli.resolved_executable = lambda _application, _mode: sys.executable
    cli.validate_required_runtime_files = lambda _application: None
    cli.current_user_home = lambda: "/home/developer"
    cli.ensure_managed_runtime_state = (
        lambda _application, _home: cli_events.append("runtime-state")
    )
    cli.build_environment = (
        lambda _application, _mode: cli_events.append("build-environment") or {}
    )
    cli.build_argv = (
        lambda _application, _mode, _args: cli_events.append("build-argv")
        or [sys.executable]
    )
    sys.argv = ["labwc-managed-app", "launch", "bitwarden"]
    assert cli.main() == 0
    assert cli_events == [
        "runtime-state",
        "build-environment",
        "build-argv",
        "exec",
    ]
finally:
    cli.os.geteuid = original_cli_geteuid
    cli.os.execvpe = original_cli_execvpe
    cli.load_managed_launch_policy = original_cli_load_policy
    cli.validate_acceleration_mode = original_cli_validate_mode
    cli.resolved_executable = original_cli_resolved_executable
    cli.validate_required_runtime_files = original_cli_validate_runtime
    cli.current_user_home = original_cli_home
    cli.ensure_managed_runtime_state = original_cli_runtime_state
    cli.build_environment = original_cli_build_environment
    cli.build_argv = original_cli_build_argv
    sys.argv = saved_cli_argv
    if saved_cli_session_bus is not None:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = saved_cli_session_bus
assert set(electron_limits) == {
    "code",
    "bitwarden",
    "chatgpt",
    "filen",
    "discord",
    "ledger-live",
    "obsidian",
    "postman",
    "sleek",
    "spotify",
    "tutanota",
}
assert electron_limits["chatgpt"] == 2016
assert len(set(electron_limits.values())) == len(electron_limits)
assert all(0 < value < 2024 for value in electron_limits.values())
assert action_specs == {
    "IntelAccelerated": ("intel", "IntelAccelerated"),
    "NvidiaAccelerated": ("nvidia", "NvidiaAccelerated"),
    "PurePrivacy": ("pure-privacy", "PurePrivacy"),
}
launcher_apps = tuple(config["action_app"] for config in app_config)
assert len(launcher_apps) == len(set(launcher_apps))
assert set(launcher_apps) == set(apps)
chatgpt_launcher = next(
    config for config in app_config if config["action_app"] == "chatgpt"
)
assert launcher_module["CHATGPT_MANAGED_APP"] == "/usr/local/bin/chatgpt"
assert chatgpt_launcher["desktop_names"] == ("chatgpt.desktop",)
assert chatgpt_launcher["actions"] == (
    "IntelAccelerated",
    "NvidiaAccelerated",
)
assert chatgpt_launcher["default_mode"] == "auto"
assert available_actions(
    chatgpt_launcher["actions"],
    {"intel": True, "nvidia": False},
) == ("IntelAccelerated",)
assert available_actions(
    chatgpt_launcher["actions"],
    {"intel": False, "nvidia": True},
) == ("NvidiaAccelerated",)
obsidian_launcher = next(
    config for config in app_config if config["action_app"] == "obsidian"
)
assert obsidian_launcher["desktop_names"] == ("obsidian.desktop",)
assert obsidian_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
postman_launcher = next(
    config for config in app_config if config["action_app"] == "postman"
)
assert postman_launcher["desktop_names"] == ("postman.desktop",)
assert postman_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
sleek_launcher = next(
    config for config in app_config if config["action_app"] == "sleek"
)
assert sleek_launcher["desktop_names"] == ("sleek.desktop",)
assert sleek_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
spotify_launcher = next(
    config for config in app_config if config["action_app"] == "spotify"
)
assert spotify_launcher["desktop_names"] == ("spotify.desktop",)
assert spotify_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
tuta_launcher = next(
    config for config in app_config if config["action_app"] == "tutanota"
)
assert tuta_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
discord_launcher = next(
    config for config in app_config if config["action_app"] == "discord"
)
assert discord_launcher["actions"] == ("IntelAccelerated", "NvidiaAccelerated")
runtime_state = module["MANAGED_RUNTIME_STATE"]
ensure_managed_runtime_state = module["ensure_managed_runtime_state"]
with tempfile.TemporaryDirectory() as home_dir:
    home_path = pathlib.Path(home_dir)
    seed_path = home_path / "seed-keepassxc.ini"
    seed_path.write_text("[General]\nAutoSaveOnExit=true\n", encoding="utf-8")
    discord_version = "1.0.153"
    discord_modules = {
        name: {"installedVersion": 1}
        for name in module["DISCORD_REQUIRED_MODULES"]
    }
    original_keepass = runtime_state["keepassxc"]
    original_load_discord_release = environment.load_discord_release
    original_require_root_owned_directory = environment.require_root_owned_directory
    runtime_state["keepassxc"] = {
        **original_keepass,
        "files": (
            (".config/keepassxc/keepassxc.ini", 0o600, str(seed_path)),
        ),
    }
    environment.load_discord_release = lambda: (
        discord_version,
        discord_modules,
    )
    environment.require_root_owned_directory = lambda path: None
    try:
        ensure_managed_runtime_state("keepassxc", home_dir)
        ensure_managed_runtime_state("telegram-desktop", home_dir)
        ensure_managed_runtime_state("discord", home_dir)
        ensure_managed_runtime_state("zoom", home_dir)
        module["ensure_discord_managed_settings"](home_dir)
        discord_settings_fixture = (
            home_path / ".config" / "discord" / "settings.json"
        )
        discord_settings_fixture.chmod(0o666)
        module["ensure_discord_managed_settings"](home_dir)
        assert oct(discord_settings_fixture.stat().st_mode & 0o777) == "0o600"
    finally:
        runtime_state["keepassxc"] = original_keepass
        environment.load_discord_release = original_load_discord_release
        environment.require_root_owned_directory = (
            original_require_root_owned_directory
        )
    keepassxc_config_path = home_path / ".config" / "keepassxc" / "keepassxc.ini"
    telegram_log_path = home_path / ".local" / "share" / "TelegramDesktop" / "log.txt"
    discord_settings_path = home_path / ".config" / "discord" / "settings.json"
    zoom_config_source = home_path / module["ZOOM_CONFIG_SOURCE"]
    discord_modules_path = (
        home_path
        / ".config"
        / "discord"
        / discord_version
        / "modules"
    )
    assert keepassxc_config_path.read_text(encoding="utf-8") == "[General]\nAutoSaveOnExit=true\n"
    assert telegram_log_path.exists()
    assert json.loads(discord_settings_path.read_text(encoding="utf-8")) == {
        "SKIP_HOST_UPDATE": True,
        "SKIP_MODULE_UPDATE": True,
    }
    assert json.loads(
        (discord_modules_path / "installed.json").read_text(encoding="utf-8")
    ) == discord_modules
    for name in discord_modules:
        module_link = discord_modules_path / name
        assert module_link.is_symlink()
        assert os.readlink(module_link) == f"/opt/discord/modules/{name}"
    assert oct(keepassxc_config_path.stat().st_mode & 0o777) == "0o600"
    assert oct(discord_settings_path.stat().st_mode & 0o777) == "0o600"
    assert oct((discord_modules_path / "installed.json").stat().st_mode & 0o777) == "0o600"
    assert oct((home_path / ".local" / "share" / "TelegramDesktop").stat().st_mode & 0o777) == "0o700"
    assert oct(zoom_config_source.stat().st_mode & 0o777) == "0o700"

with tempfile.TemporaryDirectory() as discord_metadata_root:
    metadata_root = pathlib.Path(discord_metadata_root)
    modules_file = metadata_root / "installed.json"
    state_file = metadata_root / "discord.installed.json"
    discord_version = "1.0.153"
    host_sha256 = "a" * 64
    manifest_sha256 = "b" * 64
    state_modules = {
        name: {
            "file": (
                f"discord-{discord_version}-{name}-1-"
                f"{'c' * 64}.full.distro"
            ),
            "sha256": "c" * 64,
            "version": 1,
        }
        for name in module["DISCORD_REQUIRED_MODULES"]
    }
    valid_state = {
        "host": {
            "file": (
                f"discord-{discord_version}-host-"
                f"{host_sha256}.full.distro"
            ),
            "sha256": host_sha256,
        },
        "manifest": {
            "file": (
                f"discord-{discord_version}-manifest-"
                f"{manifest_sha256}.json"
            ),
            "sha256": manifest_sha256,
        },
        "modules": state_modules,
        "version": discord_version,
    }
    expected_modules = {
        name: {"installedVersion": 1}
        for name in module["DISCORD_REQUIRED_MODULES"]
    }
    original_modules_file = environment.DISCORD_MODULES_FILE
    original_state_file = environment.DISCORD_STATE_FILE
    original_require_root_directory = environment.require_root_owned_directory
    original_require_root_file = environment.require_root_owned_regular_file
    original_environment_lstat = environment.os.lstat
    environment.DISCORD_MODULES_FILE = str(modules_file)
    environment.DISCORD_STATE_FILE = str(state_file)
    environment.require_root_owned_directory = lambda path: None
    environment.require_root_owned_regular_file = (
        lambda path, **kwargs: os.lstat(path)
    )

    def write_state(value):
        state_file.write_text(
            json.dumps(value, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def expect_metadata_failure():
        try:
            environment.load_discord_module_metadata(discord_version)
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("Discord accepted invalid module metadata")

    try:
        write_state(valid_state)
        assert environment.load_discord_module_metadata(
            discord_version
        ) == expected_modules

        modules_file.write_text(
            json.dumps(expected_modules, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        write_state({})
        assert environment.load_discord_module_metadata(
            discord_version
        ) == expected_modules
        modules_file.unlink()

        invalid_states = []
        invalid = json.loads(json.dumps(valid_state))
        invalid["version"] = "1.0.154"
        invalid_states.append(invalid)
        invalid = json.loads(json.dumps(valid_state))
        invalid["host"]["sha256"] = "invalid"
        invalid_states.append(invalid)
        invalid = json.loads(json.dumps(valid_state))
        invalid["manifest"]["file"] = "unexpected.json"
        invalid_states.append(invalid)
        invalid = json.loads(json.dumps(valid_state))
        first_module = next(iter(invalid["modules"]))
        invalid["modules"][first_module]["version"] = 0
        invalid_states.append(invalid)
        invalid = json.loads(json.dumps(valid_state))
        first_module = next(iter(invalid["modules"]))
        invalid["modules"][first_module]["file"] = "unexpected.full.distro"
        invalid_states.append(invalid)
        invalid = json.loads(json.dumps(valid_state))
        invalid["unexpected"] = True
        invalid_states.append(invalid)
        for invalid_state in invalid_states:
            write_state(invalid_state)
            expect_metadata_failure()

        state_file.unlink()
        environment.require_root_owned_regular_file = original_require_root_file
        expect_metadata_failure()
        environment.require_root_owned_regular_file = (
            lambda path, **kwargs: os.lstat(path)
        )

        state_file.write_bytes(
            b"x" * (environment.DISCORD_STATE_MAX_BYTES + 1)
        )
        expect_metadata_failure()

        write_state(valid_state)
        modules_file.symlink_to(state_file)
        expect_metadata_failure()
        modules_file.unlink()

        environment.require_root_owned_regular_file = original_require_root_file

        def non_root_state_lstat(path):
            metadata = original_environment_lstat(path)
            if path == str(state_file):
                values = list(metadata)
                values[4] = 1000
                values[5] = 1000
                return os.stat_result(values)
            return metadata

        environment.os.lstat = non_root_state_lstat
        expect_metadata_failure()
    finally:
        environment.os.lstat = original_environment_lstat
        environment.require_root_owned_regular_file = original_require_root_file
        environment.require_root_owned_directory = original_require_root_directory
        environment.DISCORD_MODULES_FILE = original_modules_file
        environment.DISCORD_STATE_FILE = original_state_file

with tempfile.TemporaryDirectory() as discord_runtime:
    runtime_path = pathlib.Path(discord_runtime)
    (runtime_path / "nested").mkdir()
    payload = runtime_path / "nested" / "payload"
    payload.write_bytes(b"payload")
    payload.chmod(0o644)
    chrome_sandbox = runtime_path / "chrome-sandbox"
    chrome_sandbox.write_bytes(b"\x7fELF")
    chrome_sandbox.chmod(0o4755)
    original_discord_root = environment.DISCORD_ROOT
    original_lstat = environment.os.lstat

    def root_owned_lstat(path):
        current = original_lstat(path)
        values = list(current)
        values[4] = 0
        values[5] = 0
        return os.stat_result(values)

    environment.DISCORD_ROOT = str(runtime_path)
    environment.os.lstat = root_owned_lstat
    try:
        try:
            environment.validate_discord_runtime_tree()
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("Discord accepted a runtime root not mode 0755")
        runtime_path.chmod(0o755)
        (runtime_path / "nested").chmod(0o755)
        environment.validate_discord_runtime_tree()
        payload.chmod(0o666)
        try:
            environment.validate_discord_runtime_tree()
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("Discord accepted a group-writable runtime file")
        payload.chmod(0o644)
        unsafe_link = runtime_path / "unsafe-link"
        unsafe_link.symlink_to("nested/payload")
        try:
            environment.validate_discord_runtime_tree()
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("Discord accepted a runtime symlink")
    finally:
        environment.os.lstat = original_lstat
        environment.DISCORD_ROOT = original_discord_root

desktop = configparser.ConfigParser(interpolation=None, strict=False)
desktop.optionxform = str
desktop.add_section("Desktop Entry")
desktop["Desktop Entry"]["Actions"] = "Existing;IntelAccelerated;Existing;"
add_actions(desktop, "mullvad-browser", "%u")
assert desktop["Desktop Entry"]["Actions"] == (
    "Existing;IntelAccelerated;NvidiaAccelerated;PurePrivacy;"
)
for action, (mode, display_name) in action_specs.items():
    section = desktop[f"Desktop Action {action}"]
    assert section["Name"] == display_name
    assert section["Exec"] == (
        f"/usr/local/bin/labwc-managed-app {mode} mullvad-browser %u"
    )

ledger_entry = configparser.ConfigParser(interpolation=None, strict=False)
ledger_entry.optionxform = str
ledger_entry.add_section("Desktop Entry")
add_actions(ledger_entry, "ledger-live", "%U", ())
assert "Actions" not in ledger_entry["Desktop Entry"]
assert not any(section.startswith("Desktop Action ") for section in ledger_entry.sections())

with tempfile.TemporaryDirectory() as temporary_root:
    home_dir = os.path.join(temporary_root, "home")
    local_dir = os.path.join(home_dir, ".local")
    data_dir = os.path.join(local_dir, "share")
    desktop_dir = os.path.join(data_dir, "applications")
    os.mkdir(home_dir)
    for directory in (local_dir, data_dir, desktop_dir):
        ensure_user_directory(directory, os.getuid(), os.getgid())
        assert os.stat(directory).st_uid == os.getuid()
        assert os.stat(directory).st_gid == os.getgid()
        assert stat.S_IMODE(os.stat(directory).st_mode) == 0o700

    generated = configparser.ConfigParser(interpolation=None, strict=False)
    generated.optionxform = str
    generated.add_section("Desktop Entry")
    generated["Desktop Entry"]["Type"] = "Application"
    generated["Desktop Entry"]["Name"] = "Vivaldi"
    generated["Desktop Entry"]["Exec"] = (
        "/usr/local/bin/labwc-managed-app nvidia vivaldi %U"
    )
    generated_path = os.path.join(desktop_dir, "vivaldi-stable.desktop")
    write_desktop_file(
        generated_path,
        generated,
        os.getuid(),
        os.getgid(),
        None,
    )
    assert os.path.isfile(generated_path)
    assert os.stat(generated_path).st_uid == os.getuid()
    assert stat.S_IMODE(os.stat(generated_path).st_mode) == 0o600
    assert not any(name.startswith(".vivaldi-stable.desktop.") for name in os.listdir(desktop_dir))

    stale_tuta_path = os.path.join(desktop_dir, "appimagekit-tutanota-desktop.desktop")
    with open(stale_tuta_path, "w", encoding="utf-8") as handle:
        handle.write(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Tuta Mail\n"
            "Exec=/opt/tuta-main/AooRun\n"
        )
    assert remove_unmanaged_tuta_launchers(home_dir, os.getuid()) == 1
    assert not os.path.exists(stale_tuta_path)

    autostart_dir = os.path.join(home_dir, ".config", "autostart")
    os.makedirs(autostart_dir, mode=0o700)
    bitwarden_autostart = os.path.join(autostart_dir, "bitwarden.desktop")
    with open(bitwarden_autostart, "w", encoding="utf-8") as handle:
        handle.write(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Bitwarden\n"
            "Exec=/opt/Bitwarden/bitwarden --autostart\n"
        )
    assert synchronize_bitwarden_autostart(
        home_dir,
        os.getuid(),
        os.getgid(),
        None,
    ) is True
    rewritten_autostart = configparser.ConfigParser(interpolation=None, strict=False)
    rewritten_autostart.optionxform = str
    rewritten_autostart.read(bitwarden_autostart, encoding="utf-8")
    assert rewritten_autostart["Desktop Entry"]["Exec"] == (
        "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__ bitwarden --autostart"
    )
    assert synchronize_bitwarden_autostart(
        home_dir,
        os.getuid(),
        os.getgid(),
        None,
    ) is False

for app_name in (
    "vivaldi",
    "bitwarden",
    "chatgpt",
    "obsidian",
    "postman",
    "sleek",
    "spotify",
    "filen",
    "discord",
    "ledger-live",
    "tutanota",
):
    launch_argv = build_argv(app_name, "launch", [])
    nvidia_argv = build_argv(app_name, "nvidia", [])
    assert "--ozone-platform=wayland" in launch_argv
    assert launch_argv.count("--disable-skia-graphite") == 1
    assert "--use-gl=angle" in launch_argv
    assert "--use-angle=gl" in launch_argv
    launch_features = next(
        argument for argument in launch_argv if argument.startswith("--enable-features=")
    )
    launch_disabled_features = next(
        argument for argument in launch_argv if argument.startswith("--disable-features=")
    )
    assert "UseOzonePlatform" in launch_features
    assert "WaylandWindowDecorations" not in launch_features
    assert "WaylandWindowDecorations" in launch_disabled_features
    for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
        assert feature_name in launch_disabled_features
    assert "--ozone-platform=wayland" in nvidia_argv
    assert nvidia_argv.count("--disable-skia-graphite") == 1
    assert "--enable-zero-copy" not in nvidia_argv
    assert "--use-gl=angle" in nvidia_argv
    assert "--use-angle=gl" in nvidia_argv
    nvidia_disabled_features = next(
        argument for argument in nvidia_argv if argument.startswith("--disable-features=")
    )
    for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
        assert feature_name in nvidia_disabled_features
    intel_env = build_environment(app_name, "intel")
    assert intel_env["DRI_PRIME"] == "0"
    assert intel_env["LIBVA_DRIVER_NAME"] == "iHD"
    nvidia_env = build_environment(app_name, "nvidia")
    assert nvidia_env["LIBVA_DRIVER_NAME"] == "nvidia"
    assert nvidia_env["NVD_BACKEND"] == "direct"
    assert nvidia_env["__NV_PRIME_RENDER_OFFLOAD"] == "1"
    assert nvidia_env["__GLX_VENDOR_LIBRARY_NAME"] == "nvidia"

for app_name in (
    "code",
    "bitwarden",
    "chatgpt",
    "obsidian",
    "postman",
    "sleek",
    "filen",
    "discord",
    "ledger-live",
    "tutanota",
):
    expected = module["electron_js_flags"](app_name)
    for mode in ("intel", "nvidia"):
        js_flags = [
            argument
            for argument in build_argv(app_name, mode, [])
            if argument.startswith("--js-flags=--max-old-space-size=")
        ]
        assert js_flags == [expected]
    if apps[app_name]["pure_privacy"]:
        privacy_js_flags = [
            argument
            for argument in pure_privacy_argv(app_name, [])
            if argument.startswith("--js-flags=--max-old-space-size=")
        ]
        assert privacy_js_flags == [expected]

for app_name in electron_limits:
    for mode in ("launch", "intel", "nvidia"):
        assert build_argv(app_name, mode, []).count(electron_password_store) == 1
    if apps[app_name]["pure_privacy"]:
        assert pure_privacy_argv(app_name, []).count(electron_password_store) == 1
ledger_launch_argv = build_argv("ledger-live", "launch", [])
assert "--no-sandbox" not in ledger_launch_argv

code_argv = build_argv("code", "launch", [])
for app_name in ("filen", "discord", "chatgpt"):
    launch_argv = build_argv(app_name, "launch", [])
    nvidia_argv = build_argv(app_name, "nvidia", [])
    for argument in (
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-renderer-backgrounding",
    ):
        assert argument not in launch_argv
        assert argument in nvidia_argv
    for argument in (
        "--use-gl=angle",
        "--use-angle=gl",
    ):
        assert argument in code_argv
        assert argument in launch_argv
        assert argument in nvidia_argv
assert "WebRTCPipeWireCapturer" not in next(
    argument for argument in build_argv("filen", "launch", []) if argument.startswith("--enable-features=")
)
assert "WebRTCPipeWireCapturer" in next(
    argument for argument in build_argv("discord", "launch", []) if argument.startswith("--enable-features=")
)
assert "WebRTCPipeWireCapturer" in next(
    argument for argument in build_argv("chatgpt", "launch", []) if argument.startswith("--enable-features=")
)
for mode in ("launch", "intel", "nvidia"):
    discord_argv = build_argv("discord", mode, [])
    for forbidden_argument in (
        "--disable-gpu",
        "--disable-software-rasterizer",
        "--no-sandbox",
    ):
        assert forbidden_argument not in discord_argv
    chatgpt_argv = build_argv("chatgpt", mode, [])
    for forbidden_argument in (
        "--disable-gpu",
        "--disable-software-rasterizer",
        "--no-sandbox",
    ):
        assert forbidden_argument not in chatgpt_argv
for forbidden_argument in (
    "--ozone-platform=x11",
    "--ozone-platform-hint=x11",
    "--disable-features=UseOzonePlatform",
    "--enable-skia-graphite",
    "--disable-skia-graphite",
):
    try:
        build_argv("chatgpt", "launch", [forbidden_argument])
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError(
            f"ChatGPT accepted a non-Wayland override: {forbidden_argument}"
        )
for app_name in ("chromium", "microsoft-edge", "vivaldi", *electron_limits):
    for mode in ("launch", "intel", "nvidia"):
        argv = build_argv(app_name, mode, [])
        disabled_features = next(
            argument for argument in argv if argument.startswith("--disable-features=")
        )
        for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
            assert feature_name in disabled_features
        assert "--use-gl=angle" in argv
        assert "--use-angle=gl" in argv
        assert argv.count("--disable-skia-graphite") == 1
        assert "--use-angle=vulkan" not in argv

vivaldi_privacy_argv = pure_privacy_argv("vivaldi", [])
vivaldi_privacy_env = pure_privacy_environment("vivaldi")
assert "--disable-gpu" not in vivaldi_privacy_argv
assert vivaldi_privacy_argv.count("--disable-skia-graphite") == 1
assert "--use-angle=gl" in vivaldi_privacy_argv
assert "--use-angle=vulkan" not in vivaldi_privacy_argv
assert "--disable-accelerated-video-decode" in vivaldi_privacy_argv
vivaldi_privacy_disabled_features = [
    argument
    for argument in vivaldi_privacy_argv
    if argument.startswith("--disable-features=")
]
assert len(vivaldi_privacy_disabled_features) == 1
assert "WaylandWindowDecorations" in vivaldi_privacy_disabled_features[0]
for feature_name in ("Vulkan", "DefaultANGLEVulkan", "VulkanFromANGLE"):
    assert feature_name in vivaldi_privacy_disabled_features[0]
assert vivaldi_privacy_env["GSK_RENDERER"] == "opengl"
assert vivaldi_privacy_env["QSG_RHI_BACKEND"] == "opengl"
assert vivaldi_privacy_env["GDK_DISABLE"] == "vulkan"
assert vivaldi_privacy_env["ANGLE_DEFAULT_PLATFORM"] == "gl"
assert vivaldi_privacy_env["WGPU_BACKEND"] == "gl"
assert vivaldi_privacy_env["SDL_RENDER_DRIVER"] == "opengl"
assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in vivaldi_privacy_env)

for app_name in apps:
    privacy_env = pure_privacy_environment(app_name)
    assert privacy_env["GSK_RENDERER"] == "opengl"
    assert privacy_env["QSG_RHI_BACKEND"] == "opengl"
    assert privacy_env["GDK_DISABLE"] == "vulkan"
    assert privacy_env["ANGLE_DEFAULT_PLATFORM"] == "gl"
    assert privacy_env["WGPU_BACKEND"] == "gl"
    assert privacy_env["SDL_RENDER_DRIVER"] == "opengl"
    assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in privacy_env)
    for forbidden_name in forbidden_x11_environment:
        assert forbidden_name not in privacy_env

mullvad_privacy_env = pure_privacy_environment("mullvad-browser")
mullvad_privacy_argv = pure_privacy_argv("mullvad-browser", [])
assert mullvad_privacy_env["MOZ_WEBRENDER"] == "1"
assert mullvad_privacy_env["MOZ_WEBRENDER_SOFTWARE"] == "1"
assert not any(argument.startswith("--use-gl=") for argument in mullvad_privacy_argv)
assert not any(argument.startswith("--use-angle=") for argument in mullvad_privacy_argv)
assert not any(name.startswith(("VK_", "__VK_", "MESA_VK_")) for name in mullvad_privacy_env)
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
        ["bwrap", "--dev-bind", "/dev/dri", "/dev/dri"],
    )
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("Mullvad PurePrivacy accepted hardware GPU device access")
validate_no_host_audio_device_binds(
    "tutanota",
    ["bwrap", "--bind", "/run/user/1000/pipewire-0", "/run/user/1000/pipewire-0"],
)
validate_no_host_audio_device_binds(
    "chatgpt",
    ["bwrap", "--bind", "/run/user/1000/pipewire-0", "/run/user/1000/pipewire-0"],
)
try:
    validate_no_host_audio_device_binds(
        "chatgpt",
        ["bwrap", "--dev-bind", "/dev/snd", "/dev/snd"],
    )
except SystemExit as exc:
    assert exc.code == 1
else:
    raise AssertionError("managed bubblewrap accepted direct ALSA device access")
general_usr_command = []
add_system_usr_mount(general_usr_command)
assert general_usr_command == ["--ro-bind", "/usr", "/usr"]
private_tmpfs_command = []
add_private_tmpfs_mounts(private_tmpfs_command)
assert private_tmpfs_command == [
    "--tmpfs",
    "/tmp",
    "--chmod",
    "01777",
    "/tmp",
    "--tmpfs",
    "/var/tmp",
    "--chmod",
    "01777",
    "/var/tmp",
    "--tmpfs",
    "/dev/shm",
    "--chmod",
    "01777",
    "/dev/shm",
]
for app_name in apps:
    managed_environment = build_environment(app_name, "launch")
    expected_path = (
        expected_chatgpt_sandbox_path
        if app_name == "chatgpt"
        else managed_path
    )
    assert managed_environment["PATH"] == expected_path
    for forbidden_name in (
        *forbidden_x11_environment,
        "DISPLAY",
        "WLR_BACKENDS",
        "WLR_WL_OUTPUTS",
        "WLR_XWAYLAND",
        wayland_compat_runtime.OUTER_WAYLAND_DISPLAY_ENVIRONMENT,
    ):
        assert forbidden_name not in managed_environment
    assert "/opt/xwayland" not in managed_library_path(app_name).split(os.pathsep)
for app_name, sandbox_config in module["PERSISTENT_SANDBOX_CONFIG"].items():
    if app_name in module["WAYLAND_COMPAT_APPS"]:
        assert module["PRIVATE_RUNTIME_ROOT"] in sandbox_config["ro_bind_paths"]
    else:
        assert module["PRIVATE_RUNTIME_ROOT"] not in sandbox_config["ro_bind_paths"]

for removed_runtime_name in (
    "BoundedDiagnostics",
    "require_active_startup",
    "require_private_x11_listener",
    "wait_for_private_x11_ready",
    "xwayland_arguments",
):
    assert not hasattr(wayland_compat_runtime, removed_runtime_name)
assert wayland_compat_runtime.parse_arguments(
    ["zoom", "launch", "--", "/usr/bin/zoom"]
) == ("zoom", "launch", ["/usr/bin/zoom"])
assert wayland_compat_runtime.parse_arguments(
    ["discord", "intel", "--", "/opt/discord/Discord", "--version"]
) == (
    "discord",
    "intel",
    ["/opt/discord/Discord", "--version"],
)
for invalid_arguments in (
    ["spotify", "launch", "--", "/usr/bin/spotify"],
    ["zoom", "launch", "--", "/opt/discord/Discord"],
    ["zoom", "software", "--", "/usr/bin/zoom"],
    ["zoom", "launch", "/usr/bin/zoom"],
    ["zoom", "launch", "--"],
    [
        "zoom",
        "launch",
        "--display-number",
        "99",
        "--listen-fd",
        "9",
        "--",
        "/usr/bin/zoom",
    ],
):
    try:
        wayland_compat_runtime.parse_arguments(invalid_arguments)
    except wayland_compat_runtime.CompatibilityRuntimeError:
        pass
    else:
        raise AssertionError(
            f"accepted forbidden compatibility arguments: {invalid_arguments!r}"
        )

runtime_environment_snapshot = dict(os.environ)
try:
    runtime_directory = f"/run/user/{os.getuid()}"
    outer_wayland_display = "wayland-7"
    cage_wayland_display = "wayland-8"
    display = ":17"
    os.environ.update(
        {
            "XDG_RUNTIME_DIR": runtime_directory,
            "WAYLAND_DISPLAY": cage_wayland_display,
            "DISPLAY": display,
            "WLR_BACKENDS": "wayland",
            "WLR_WL_OUTPUTS": "1",
            "WLR_XWAYLAND": module["PRIVATE_RUNTIME_BINARY"],
            wayland_compat_runtime.OUTER_WAYLAND_DISPLAY_ENVIRONMENT: (
                outer_wayland_display
            ),
        }
    )

    original_runtime_lstat = wayland_compat_runtime.os.lstat
    expected_wayland_sockets = {
        os.path.join(runtime_directory, outer_wayland_display),
        os.path.join(runtime_directory, cage_wayland_display),
    }

    def fake_runtime_lstat(path):
        if path in expected_wayland_sockets:
            return types.SimpleNamespace(
                st_mode=stat.S_IFSOCK | 0o600,
                st_uid=os.getuid(),
            )
        return original_runtime_lstat(path)

    wayland_compat_runtime.os.lstat = fake_runtime_lstat
    try:
        wayland_compat_runtime.require_cage_wayland_socket()
        os.environ["WAYLAND_DISPLAY"] = outer_wayland_display
        try:
            wayland_compat_runtime.require_cage_wayland_socket()
        except wayland_compat_runtime.CompatibilityRuntimeError as exc:
            assert "nested Wayland socket" in str(exc)
        else:
            raise AssertionError("outer Wayland socket was accepted as Cage's socket")
        os.environ["WAYLAND_DISPLAY"] = cage_wayland_display
    finally:
        wayland_compat_runtime.os.lstat = original_runtime_lstat

    assert wayland_compat_runtime.require_cage_x11_display() == "17"
    os.environ["WLR_XWAYLAND"] = "/usr/bin/Xwayland"
    try:
        wayland_compat_runtime.require_cage_x11_display()
    except wayland_compat_runtime.CompatibilityRuntimeError as exc:
        assert "WLR_XWAYLAND" in str(exc)
    else:
        raise AssertionError("system Xwayland was accepted by the Cage runtime")
    os.environ["WLR_XWAYLAND"] = module["PRIVATE_RUNTIME_BINARY"]
    os.environ["XAUTHORITY"] = "/tmp/untrusted-Xauthority"
    try:
        wayland_compat_runtime.require_cage_x11_display()
    except wayland_compat_runtime.CompatibilityRuntimeError as exc:
        assert "XAUTHORITY" in str(exc)
    else:
        raise AssertionError("inherited X11 authority was accepted")
    os.environ.pop("XAUTHORITY")

    class FakeProcess:
        def __init__(self):
            self.returncode = None
            self.terminated = False
            self.killed = False
            self.signals = []

        def poll(self):
            return self.returncode

        def wait(self, timeout=None):
            if self.returncode is None:
                self.returncode = 23
            return self.returncode

        def terminate(self):
            self.terminated = True
            self.returncode = 0

        def kill(self):
            self.killed = True
            self.returncode = -9

        def send_signal(self, signum):
            self.signals.append(signum)

    runtime_captures = []

    def fake_runtime_popen(argv, **kwargs):
        assert argv[0] in wayland_compat_runtime.ALLOWED_APPLICATIONS.values()
        assert argv[0] != wayland_compat_runtime.XWAYLAND_BINARY
        assert "pass_fds" not in kwargs
        process = FakeProcess()
        runtime_captures.append(
            {
                "argv": list(argv),
                "environment": dict(kwargs["env"]),
                "process": process,
            }
        )
        return process

    original_runtime_popen = wayland_compat_runtime.subprocess.Popen
    original_runtime_geteuid = wayland_compat_runtime.os.geteuid
    original_wayland_validation = wayland_compat_runtime.require_cage_wayland_socket
    original_x11_directory_validation = (
        wayland_compat_runtime.require_private_x11_socket_directory
    )
    original_x11_socket_validation = (
        wayland_compat_runtime.require_private_x11_socket
    )
    original_system_owner = wayland_compat_runtime.sandbox_system_owner
    original_file_validation = wayland_compat_runtime.require_system_owned_file
    original_private_library_validation = (
        wayland_compat_runtime.require_private_runtime_library
    )
    original_signal_registration = wayland_compat_runtime.register_signal_handlers
    os.environ["LD_LIBRARY_PATH"] = "/tmp/untrusted-library-path"
    for name in wayland_compat_runtime.DYNAMIC_LOADER_ENVIRONMENT_TO_CLEAR:
        os.environ[name] = f"/tmp/untrusted-{name.lower()}"
    try:
        wayland_compat_runtime.subprocess.Popen = fake_runtime_popen
        wayland_compat_runtime.os.geteuid = lambda: 1000
        wayland_compat_runtime.require_cage_wayland_socket = lambda: None
        wayland_compat_runtime.require_private_x11_socket_directory = lambda: None
        wayland_compat_runtime.require_private_x11_socket = (
            lambda display_number: display_number == "17"
        )
        wayland_compat_runtime.sandbox_system_owner = lambda: (0, 0)
        wayland_compat_runtime.require_system_owned_file = (
            lambda *args, **kwargs: None
        )
        wayland_compat_runtime.require_private_runtime_library = (
            lambda *args, **kwargs: None
        )
        wayland_compat_runtime.register_signal_handlers = lambda: None
        wayland_compat_runtime._received_signal = None

        assert wayland_compat_runtime.run(
            ["zoom", "launch", "--", "/usr/bin/zoom"]
        ) == 23
        assert wayland_compat_runtime.run(
            ["discord", "launch", "--", "/opt/discord/Discord"]
        ) == 23
    finally:
        wayland_compat_runtime.subprocess.Popen = original_runtime_popen
        wayland_compat_runtime.os.geteuid = original_runtime_geteuid
        wayland_compat_runtime.require_cage_wayland_socket = (
            original_wayland_validation
        )
        wayland_compat_runtime.require_private_x11_socket_directory = (
            original_x11_directory_validation
        )
        wayland_compat_runtime.require_private_x11_socket = (
            original_x11_socket_validation
        )
        wayland_compat_runtime.sandbox_system_owner = original_system_owner
        wayland_compat_runtime.require_system_owned_file = (
            original_file_validation
        )
        wayland_compat_runtime.require_private_runtime_library = (
            original_private_library_validation
        )
        wayland_compat_runtime.register_signal_handlers = (
            original_signal_registration
        )
        wayland_compat_runtime._received_signal = None
        wayland_compat_runtime._active_processes.clear()

    assert len(runtime_captures) == 2
    zoom_runtime_capture, discord_runtime_capture = runtime_captures
    assert zoom_runtime_capture["argv"] == ["/usr/bin/zoom"]
    assert discord_runtime_capture["argv"] == ["/opt/discord/Discord"]
    for capture in runtime_captures:
        application_environment = capture["environment"]
        assert application_environment["DISPLAY"] == display
        assert application_environment["WAYLAND_DISPLAY"] == cage_wayland_display
        assert "WLR_BACKENDS" not in application_environment
        assert "WLR_WL_OUTPUTS" not in application_environment
        assert "WLR_XWAYLAND" not in application_environment
        assert (
            wayland_compat_runtime.OUTER_WAYLAND_DISPLAY_ENVIRONMENT
            not in application_environment
        )
        for forbidden_name in forbidden_x11_environment:
            assert forbidden_name not in application_environment
        for loader_name in wayland_compat_runtime.DYNAMIC_LOADER_ENVIRONMENT_TO_CLEAR:
            assert loader_name not in application_environment
        assert "/tmp/untrusted-library-path" not in application_environment[
            "LD_LIBRARY_PATH"
        ]
        assert capture["process"].returncode == 23
        assert capture["process"].terminated is False
    assert zoom_runtime_capture["environment"]["LD_LIBRARY_PATH"] == (
        module["PRIVATE_RUNTIME_LIBRARY_DIRECTORY"]
    )
    assert discord_runtime_capture["environment"]["LD_LIBRARY_PATH"] == (
        os.pathsep.join(
            (
                module["PRIVATE_RUNTIME_LIBRARY_DIRECTORY"],
                module["DISCORD_ROOT"],
            )
        )
    )
finally:
    os.environ.clear()
    os.environ.update(runtime_environment_snapshot)

compatibility_calls = []
original_compatibility_runner = wayland_compat._run_persistent_sandbox
original_validate_private_runtime = wayland_compat.validate_private_runtime
try:
    wayland_compat.validate_private_runtime = lambda: None

    def capture_compatibility_call(app_name, mode, extra_args, **kwargs):
        compatibility_calls.append(
            (app_name, mode, list(extra_args), dict(kwargs))
        )
        return 0

    wayland_compat._run_persistent_sandbox = capture_compatibility_call
    for app_name in module["WAYLAND_COMPAT_APPS"]:
        assert run_wayland_compat_sandbox(
            app_name,
            "launch",
            ["--test-argument"],
        ) == 0
finally:
    wayland_compat._run_persistent_sandbox = original_compatibility_runner
    wayland_compat.validate_private_runtime = original_validate_private_runtime

assert [call[0] for call in compatibility_calls] == ["discord", "zoom"]
for app_name, mode, extra_args, options in compatibility_calls:
    assert mode == "launch"
    assert extra_args == ["--test-argument"]
    assert options["private_xwayland_binary"] == module["PRIVATE_RUNTIME_BINARY"]
    assert (
        options["private_xkbcomp_overlay_directory"]
        == module["PRIVATE_RUNTIME_XKBCOMP_OVERLAY_DIRECTORY"]
    )
    assert options["payload_argv_prefix"] == (
        module["CAGE_BINARY"],
        "-d",
        "--",
        module["SANDBOX_LIFECYCLE_HELPER"],
        app_name,
        mode,
        "--",
    )

captured_zoom_launch = {}
with tempfile.TemporaryDirectory() as zoom_home, tempfile.TemporaryDirectory() as zoom_runtime:
    for relative_path in (
        *module["PERSISTENT_SANDBOX_CONFIG"]["zoom"]["persistent_paths"],
        module["ZOOM_CONFIG_SOURCE"],
        "Documents",
        "Downloads",
    ):
        pathlib.Path(zoom_home, relative_path).mkdir(parents=True, exist_ok=True)
    pathlib.Path(zoom_runtime, "doc").mkdir()
    pathlib.Path(zoom_runtime, "pulse").mkdir()

    original_environment_home = environment.current_user_home
    original_environment_name = environment.current_user_name
    original_environment_runtime = environment.current_user_runtime_dir
    original_runtime_socket = sandbox.current_user_runtime_socket
    original_require_executable = sandbox.require_root_owned_executable
    original_require_private_file = sandbox.require_root_owned_regular_file
    original_require_xkbcomp_overlay = (
        sandbox.require_private_xkbcomp_overlay
    )
    original_validate_private_runtime = wayland_compat.validate_private_runtime
    original_start_session_proxy = sandbox.start_session_bus_proxy
    original_start_system_proxy = sandbox.start_system_bus_proxy
    original_optional_bind = sandbox.add_optional_bind
    original_runtime_bind = sandbox.add_runtime_bind
    original_video_binds = sandbox.add_video_device_binds
    original_run_slirp4netns_sandbox = sandbox.run_slirp4netns_sandbox
    environment.current_user_home = lambda: zoom_home
    environment.current_user_name = lambda: "managed-user"
    environment.current_user_runtime_dir = lambda: zoom_runtime
    sandbox.current_user_runtime_socket = (
        lambda label, entry_name: os.path.join(zoom_runtime, entry_name)
    )
    sandbox.require_root_owned_executable = lambda label, path: path
    sandbox.require_root_owned_regular_file = (
        lambda label, path, executable=False: path
    )
    sandbox.require_private_xkbcomp_overlay = lambda path: path
    wayland_compat.validate_private_runtime = lambda: None
    sandbox.start_session_bus_proxy = (
        lambda *args, **kwargs: (
            None,
            os.path.join(zoom_runtime, "filtered-session-bus"),
            None,
        )
    )
    sandbox.start_system_bus_proxy = (
        lambda *args, **kwargs: (
            None,
            os.path.join(zoom_runtime, "filtered-system-bus"),
            None,
        )
    )
    sandbox.add_optional_bind = (
        lambda command, option, source, destination: command.extend(
            [option, source, destination]
        )
    )

    def add_simulated_runtime_bind(
        command,
        host_runtime_dir,
        sandbox_runtime_dir,
        relative_path,
        expected_kind,
        *,
        required=False,
    ):
        assert expected_kind in {"directory", "socket"}
        assert required is (relative_path in {"pipewire-0", "pulse/native"})
        command.extend(
            [
                "--bind",
                os.path.join(host_runtime_dir, relative_path),
                os.path.join(sandbox_runtime_dir, relative_path),
            ]
        )

    sandbox.add_runtime_bind = add_simulated_runtime_bind
    sandbox.add_video_device_binds = lambda command, enabled: None

    def capture_zoom_sandbox(command, payload_argv, _temp_root, inherited_fds):
        captured_zoom_launch["command"] = [*command, *payload_argv]
        captured_zoom_launch["kwargs"] = {"pass_fds": inherited_fds}
        return 37

    sandbox.run_slirp4netns_sandbox = capture_zoom_sandbox
    previous_wayland_display = os.environ.get("WAYLAND_DISPLAY")
    previous_session_bus = os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)
    os.environ["WAYLAND_DISPLAY"] = "wayland-7"
    try:
        assert run_wayland_compat_sandbox("zoom", "launch", []) == 37
    finally:
        if previous_wayland_display is None:
            os.environ.pop("WAYLAND_DISPLAY", None)
        else:
            os.environ["WAYLAND_DISPLAY"] = previous_wayland_display
        if previous_session_bus is not None:
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = previous_session_bus
        environment.current_user_home = original_environment_home
        environment.current_user_name = original_environment_name
        environment.current_user_runtime_dir = original_environment_runtime
        sandbox.current_user_runtime_socket = original_runtime_socket
        sandbox.require_root_owned_executable = original_require_executable
        sandbox.require_root_owned_regular_file = original_require_private_file
        sandbox.require_private_xkbcomp_overlay = (
            original_require_xkbcomp_overlay
        )
        wayland_compat.validate_private_runtime = original_validate_private_runtime
        sandbox.start_session_bus_proxy = original_start_session_proxy
        sandbox.start_system_bus_proxy = original_start_system_proxy
        sandbox.add_optional_bind = original_optional_bind
        sandbox.add_runtime_bind = original_runtime_bind
        sandbox.add_video_device_binds = original_video_binds
        sandbox.run_slirp4netns_sandbox = original_run_slirp4netns_sandbox

zoom_command = captured_zoom_launch["command"]

def contains_sequence(sequence):
    width = len(sequence)
    return any(
        zoom_command[index : index + width] == sequence
        for index in range(len(zoom_command) - width + 1)
    )

zoom_environment = {}
for index, argument in enumerate(zoom_command):
    if argument == "--setenv":
        zoom_environment[zoom_command[index + 1]] = zoom_command[index + 2]
assert zoom_environment["QT_QPA_PLATFORM"] == "xcb"
assert zoom_environment["WAYLAND_DISPLAY"] == "wayland-7"
assert (
    zoom_environment["LD_LIBRARY_PATH"]
    == module["PRIVATE_RUNTIME_LIBRARY_DIRECTORY"]
)
assert (
    zoom_environment["WLR_XWAYLAND"]
    == module["PRIVATE_RUNTIME_BINARY"]
)
assert zoom_environment["WLR_BACKENDS"] == "wayland"
assert zoom_environment["WLR_WL_OUTPUTS"] == "1"
assert (
    zoom_environment[
        wayland_compat_runtime.OUTER_WAYLAND_DISPLAY_ENVIRONMENT
    ]
    == "wayland-7"
)
assert "DISPLAY" not in zoom_environment
assert not set(zoom_environment).intersection(forbidden_x11_environment)
assert contains_sequence(
    [
        "--dir",
        "/tmp/.X11-unix",
        "--chmod",
        "01777",
        "/tmp/.X11-unix",
    ]
)
assert not any(
    argument.startswith("/tmp/.X11-unix/X")
    for argument in zoom_command
)
assert captured_zoom_launch["kwargs"]["pass_fds"] == ()
for temporary_directory in ("/tmp", "/var/tmp", "/dev/shm"):
    assert contains_sequence(
        ["--tmpfs", temporary_directory, "--chmod", "01777", temporary_directory]
    )
assert contains_sequence(["--ro-bind", "/usr", "/usr"])
assert contains_sequence(
    [
        "--overlay-src",
        "/usr/bin",
        "--overlay-src",
        module["PRIVATE_RUNTIME_XKBCOMP_OVERLAY_DIRECTORY"],
        "--ro-overlay",
        "/usr/bin",
    ]
)
usr_bind_index = next(
    index
    for index in range(len(zoom_command) - 2)
    if zoom_command[index : index + 3] == ["--ro-bind", "/usr", "/usr"]
)
xkbcomp_overlay_index = next(
    index
    for index in range(len(zoom_command) - 5)
    if zoom_command[index : index + 6]
    == [
        "--overlay-src",
        "/usr/bin",
        "--overlay-src",
        module["PRIVATE_RUNTIME_XKBCOMP_OVERLAY_DIRECTORY"],
        "--ro-overlay",
        "/usr/bin",
    ]
)
assert xkbcomp_overlay_index > usr_bind_index
assert not contains_sequence(
    [
        "--ro-bind",
        module["PRIVATE_RUNTIME_XKBCOMP"],
        wayland_compat_runtime.XKBCOMP_BINARY,
    ]
)
assert "--tmp-overlay" not in zoom_command
assert "--remount-ro" not in zoom_command

original_overlay_directory = sandbox.PRIVATE_XKBCOMP_OVERLAY_DIRECTORY
original_overlay_source = sandbox.PRIVATE_XKBCOMP_SOURCE
original_overlay_destination = sandbox.PRIVATE_XKBCOMP_DESTINATION
original_require_private_directory = sandbox.require_root_owned_directory
original_require_private_file = sandbox.require_root_owned_regular_file
try:
    with tempfile.TemporaryDirectory() as xkbcomp_test_root:
        xkbcomp_root = pathlib.Path(xkbcomp_test_root)
        xkbcomp_source = xkbcomp_root / "private-xkbcomp"
        xkbcomp_overlay = xkbcomp_root / "overlay"
        xkbcomp_overlay_entry = xkbcomp_overlay / "xkbcomp"
        xkbcomp_destination = xkbcomp_root / "system-xkbcomp"
        xkbcomp_source.write_bytes(b"private-xkbcomp")
        xkbcomp_source.chmod(0o755)
        xkbcomp_overlay.mkdir(mode=0o755)
        os.link(xkbcomp_source, xkbcomp_overlay_entry)
        xkbcomp_overlay.chmod(0o555)

        sandbox.PRIVATE_XKBCOMP_SOURCE = str(xkbcomp_source)
        sandbox.PRIVATE_XKBCOMP_OVERLAY_DIRECTORY = str(xkbcomp_overlay)
        sandbox.PRIVATE_XKBCOMP_DESTINATION = str(xkbcomp_destination)
        sandbox.require_root_owned_directory = lambda label, path: path
        sandbox.require_root_owned_regular_file = (
            lambda label, path, executable=False: path
        )

        assert (
            sandbox.require_private_xkbcomp_overlay(str(xkbcomp_overlay))
            == str(xkbcomp_overlay)
        )
        xkbcomp_overlay.chmod(0o755)
        (xkbcomp_overlay / "unexpected").write_text(
            "unexpected",
            encoding="utf-8",
        )
        xkbcomp_overlay.chmod(0o555)
        try:
            sandbox.require_private_xkbcomp_overlay(str(xkbcomp_overlay))
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("private xkbcomp overlay accepted an extra entry")
        xkbcomp_overlay.chmod(0o755)
        (xkbcomp_overlay / "unexpected").unlink()
        xkbcomp_overlay_entry.unlink()
        xkbcomp_overlay_entry.write_bytes(b"copied-xkbcomp")
        xkbcomp_overlay_entry.chmod(0o755)
        xkbcomp_overlay.chmod(0o555)
        try:
            sandbox.require_private_xkbcomp_overlay(str(xkbcomp_overlay))
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError(
                "private xkbcomp overlay accepted a copied executable"
            )
        xkbcomp_overlay.chmod(0o755)
        xkbcomp_overlay_entry.unlink()
        os.link(xkbcomp_source, xkbcomp_overlay_entry)
        xkbcomp_overlay.chmod(0o555)
        xkbcomp_destination.write_bytes(b"system-xkbcomp")
        try:
            sandbox.require_private_xkbcomp_overlay(str(xkbcomp_overlay))
        except SystemExit as exc:
            assert exc.code == 1
        else:
            raise AssertionError("system-wide xkbcomp was accepted")
        xkbcomp_destination.unlink()
        xkbcomp_overlay.chmod(0o755)
finally:
    sandbox.PRIVATE_XKBCOMP_OVERLAY_DIRECTORY = original_overlay_directory
    sandbox.PRIVATE_XKBCOMP_SOURCE = original_overlay_source
    sandbox.PRIVATE_XKBCOMP_DESTINATION = original_overlay_destination
    sandbox.require_root_owned_directory = original_require_private_directory
    sandbox.require_root_owned_regular_file = original_require_private_file
assert contains_sequence(
    [
        "--ro-bind",
        module["PRIVATE_RUNTIME_ROOT"],
        module["PRIVATE_RUNTIME_ROOT"],
    ]
)
assert "/usr/bin/Xwayland" not in zoom_command
assert contains_sequence(["--ro-bind", "/opt/zoom", "/opt/zoom"])
assert contains_sequence(
    [
        "--bind",
        os.path.join(zoom_runtime, "wayland-7"),
        os.path.join("/run/user", str(os.getuid()), "wayland-7"),
    ]
)
for relative_socket in ("pipewire-0", "pulse/native"):
    assert contains_sequence(
        [
            "--bind",
            os.path.join(zoom_runtime, relative_socket),
            os.path.join("/run/user", str(os.getuid()), relative_socket),
        ]
    )
assert contains_sequence(
    [
        "--bind",
        os.path.join(zoom_runtime, "filtered-session-bus"),
        os.path.join("/run/user", str(os.getuid()), "bus"),
    ]
)
assert contains_sequence(
    [
        "--bind",
        os.path.join(zoom_runtime, "filtered-system-bus"),
        "/run/dbus/system_bus_socket",
    ]
)
assert contains_sequence(
    [
        "--bind",
        os.path.join(zoom_home, module["ZOOM_CONFIG_SOURCE"]),
        os.path.join(zoom_home, ".config"),
    ]
)
assert zoom_command[-8:] == [
    module["CAGE_BINARY"],
    "-d",
    "--",
    module["SANDBOX_LIFECYCLE_HELPER"],
    "zoom",
    "launch",
    "--",
    "/usr/bin/zoom",
]
cage_index = zoom_command.index(module["CAGE_BINARY"])
helper_index = zoom_command.index(module["SANDBOX_LIFECYCLE_HELPER"])
assert cage_index < helper_index
assert zoom_command[cage_index:helper_index] == [
    module["CAGE_BINARY"],
    "-d",
    "--",
]
for rootful_argument in (
    "-decorate",
    "-geometry",
    "-listenfd",
    "--display-number",
    "--listen-fd",
):
    assert rootful_argument not in zoom_command
with tempfile.TemporaryDirectory() as runtime_root:
    pipewire_path = os.path.join(runtime_root, "pipewire-0")
    pathlib.Path(pipewire_path).touch()
    original_lstat = module["os"].lstat
    module["os"].lstat = lambda path: (
        types.SimpleNamespace(st_mode=stat.S_IFSOCK | 0o600, st_uid=os.getuid())
        if path == pipewire_path
        else original_lstat(path)
    )
    try:
        runtime_command = []
        add_runtime_bind(
            runtime_command,
            runtime_root,
            "/run/user/1000",
            "pipewire-0",
            "socket",
        )
        assert runtime_command[-3:] == [
            "--bind",
            pipewire_path,
            "/run/user/1000/pipewire-0",
        ]
    finally:
        module["os"].lstat = original_lstat
    regular_audio_path = os.path.join(runtime_root, "pulse-native")
    with open(regular_audio_path, "w", encoding="utf-8") as handle:
        handle.write("not a socket\n")
    try:
        add_runtime_bind(
            [],
            runtime_root,
            "/run/user/1000",
            "pulse-native",
            "socket",
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("managed bubblewrap accepted a non-socket audio bind")
PY
then
  pass "managed application profiles and Desktop Actions stay complete and policy-aligned"
else
  fail "managed application profiles and Desktop Actions stay complete and policy-aligned"
fi

if grep -q '"vivaldi-stable.desktop"' "$launcher_sync" &&
   grep -q '"com.vivaldi.Vivaldi.desktop"' "$launcher_sync" &&
   grep -q '"bitwarden.desktop"' "$launcher_sync" &&
   grep -q '"obsidian.desktop"' "$launcher_sync" &&
   grep -q '"QoreDB.desktop"' "$launcher_sync" &&
   grep -q '"Gridline.desktop"' "$launcher_sync" &&
   grep -q '"actions": ("IntelAccelerated", "NvidiaAccelerated")' "$launcher_sync" &&
   grep -q '"tuta-mail.desktop"' "$launcher_sync" &&
   grep -q '"Zoom.desktop"' "$launcher_sync" &&
   grep -q '"Filen.desktop"' "$launcher_sync" &&
   grep -q '"discord.desktop"' "$launcher_sync" &&
   grep -q '"spotify.desktop"' "$launcher_sync" &&
   grep -q '"ledger-live.desktop"' "$launcher_sync" &&
   grep -q '"actions": ()' "$launcher_sync" &&
   grep -q '"org.telegram.desktop.desktop"' "$launcher_sync" &&
   grep -q '"retroarch.desktop"' "$launcher_sync" &&
   grep -q '"IntelAccelerated": ("intel", "IntelAccelerated")' "$launcher_sync" &&
   grep -q '"NvidiaAccelerated": ("nvidia", "NvidiaAccelerated")' "$launcher_sync" &&
   grep -q '"PurePrivacy": ("pure-privacy", "PurePrivacy")' "$launcher_sync" &&
   grep -q '^def ensure_user_directory(path: str, uid: int, gid: int) -> None:$' "$launcher_sync" &&
   grep -q '^def synchronize_bitwarden_autostart($' "$launcher_sync" &&
   grep -Fq 'managed_default_exec("bitwarden", "--autostart")' "$launcher_sync" &&
   grep -q '^def remove_unmanaged_tuta_launchers(account_home: str, uid: int) -> int:$' "$launcher_sync" &&
   grep -q 'tempfile.mkstemp(' "$launcher_sync" &&
   grep -q 'os.replace(temporary_path, path)' "$launcher_sync" &&
   grep -q '^MANAGED_APP_DEFAULT_EXEC = "__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__"$' "$launcher_sync" &&
   grep -q '^def managed_default_exec($' "$launcher_sync" &&
   grep -q '^WAYLAND_COMPAT_MANAGED_APP = "/usr/local/bin/labwc-managed-wayland-compat-app"$' "$launcher_sync" &&
   grep -q '^WAYLAND_COMPAT_APPS = {"discord", "zoom"}$' "$launcher_sync" &&
   grep -q 'default_mode: str | None = None,' "$launcher_sync" &&
   grep -q 'return f"{MANAGED_APP_DEFAULT_EXEC} {app_name} {field_code}"' "$launcher_sync" &&
   grep -q 'return managed_exec(default_mode, app_name, field_code)' "$launcher_sync" &&
   grep -q 'return managed_exec("auto", app_name, field_code)' "$launcher_sync" &&
   grep -q 'if app_name in WAYLAND_COMPAT_APPS' "$launcher_sync" &&
   grep -Fqx 'ExecStart=/usr/local/bin/labwc-sync-application-launchers %u %h' "$launcher_sync_service" &&
   grep -Fqx 'WantedBy=labwc-session.target' "$launcher_sync_service" &&
   grep -Fqx 'PathChanged=%h/.config/autostart' "$launcher_sync_path" &&
   grep -Fqx 'Unit=labwc-sync-application-launchers.service' "$launcher_sync_path" &&
   grep -Fq 'etc/skel/.config/systemd/user/labwc-sync-application-launchers.service /etc/skel/.config/systemd/user/labwc-sync-application-launchers.service 0644' "$desktop_components" &&
   grep -Fq 'etc/skel/.config/systemd/user/labwc-sync-application-launchers.path /etc/skel/.config/systemd/user/labwc-sync-application-launchers.path 0644' "$desktop_components"; then
  pass "software launchers expose managed Wayland actions while Ledger keeps its hardware-capable launch path"
else
  fail "software launchers expose managed Wayland actions while Ledger keeps its hardware-capable launch path"
fi

if managed_app_source_contains '^TUTA_PERSISTENT_PATHS = ($' &&
   managed_app_source_contains '^PERSISTENT_SANDBOX_CONFIG = {$' &&
   managed_app_source_contains '^def run_persistent_sandbox(app_name: str, mode: str, extra_args: list\[str\]) -> int:$' &&
   managed_app_source_contains '^def run_wayland_compat_sandbox($' &&
   managed_app_source_contains 'must use the dedicated native-Wayland compatibility entrypoint' &&
   managed_app_source_contains 'private compatibility sandbox is not permitted' &&
   managed_app_source_contains '^def add_system_usr_mount(command: list\[str\]) -> None:$' &&
   managed_app_source_contains 'command.extend(\["--ro-bind", "/usr", "/usr"\])' &&
   managed_app_source_contains '^def require_private_xkbcomp_overlay(path: str) -> str:$' &&
   managed_app_source_contains 'os.path.lexists(PRIVATE_XKBCOMP_DESTINATION)' &&
   managed_app_source_contains 'overlay_entries != ("xkbcomp",)' &&
   managed_app_source_contains 'os.path.samefile(PRIVATE_XKBCOMP_SOURCE, overlay_entry)' &&
   managed_app_source_contains '^def add_private_xkbcomp_overlay(command: list\[str\], overlay_directory: str) -> None:$' &&
   managed_app_source_contains 'private_xwayland_binary: str \| None = None,' &&
   managed_app_source_contains 'private_xkbcomp_overlay_directory: str \| None = None,' &&
   managed_app_source_contains 'private_xwayland_binary=PRIVATE_RUNTIME_BINARY,' &&
   managed_app_source_contains 'private_xkbcomp_overlay_directory=(' &&
   managed_app_source_contains '"WLR_BACKENDS": "wayland"' &&
   managed_app_source_contains '"WLR_WL_OUTPUTS": "1"' &&
   managed_app_source_contains 'env\["LD_LIBRARY_PATH"\] = PRIVATE_XWAYLAND_LIBRARY_DIRECTORY' &&
   managed_app_source_contains 'env\["WLR_XWAYLAND"\] = private_xwayland_binary' &&
   managed_app_source_contains 'env\[OUTER_WAYLAND_DISPLAY_ENVIRONMENT\] = wayland_display' &&
   managed_app_source_contains '"--overlay-src",' &&
   managed_app_source_contains '"--ro-overlay",' &&
   managed_app_source_lacks '--tmp-overlay' &&
   managed_app_source_lacks '--remount-ro' &&
   managed_app_source_contains 'payload_argv_prefix: tuple\[str, \.\.\.\] = (),' &&
   managed_app_source_contains 'payload_argv = \[\*payload_argv_prefix, \*argv\]' &&
   managed_app_source_contains '^CAGE_BINARY = "/usr/bin/cage"$' &&
   managed_app_source_contains '^            CAGE_BINARY,$' &&
   managed_app_source_contains '^            "-d",$' &&
   managed_app_source_lacks '^            "-x",$' &&
   managed_app_source_contains '^SANDBOX_LIFECYCLE_HELPER = "/usr/local/libexec/labwc-zoom-discord-compat-runtime"$' &&
   managed_app_source_contains '^    validate_private_runtime()$' &&
   managed_app_source_contains '^def require_cage_wayland_socket() -> None:$' &&
   managed_app_source_contains '^def require_cage_x11_display() -> str:$' &&
   managed_app_source_contains 'os.environ.get("WLR_XWAYLAND") != XWAYLAND_BINARY' &&
   managed_app_source_contains '^def application_process_environment(app_name: str) -> dict\[str, str\]:$' &&
   managed_app_source_lacks 'private_x11_listener' &&
   managed_app_source_lacks 'create_private_x11_listener' &&
   managed_app_source_lacks 'xwayland_arguments' &&
   managed_app_source_lacks '--display-number' &&
   managed_app_source_lacks '--listen-fd' &&
   managed_app_source_lacks '-decorate' &&
   managed_app_source_lacks '-geometry' &&
   managed_app_source_lacks 'usr_overlay_mounts' &&
   managed_app_source_lacks 'current_user_x11_socket' &&
   managed_app_source_lacks 'validate_x11_display' &&
   managed_app_source_lacks 'host_x11_socket' &&
   managed_app_source_lacks 'env\["DISPLAY"\]' &&
   managed_app_source_contains '"--unshare-all"' &&
   managed_app_source_contains '"--clearenv"' &&
   managed_app_source_contains '"ro_bind_paths": ("/opt/tuta-mail",)' &&
   managed_app_source_contains 'command.extend(\["--tmpfs", home_dir, "--chmod", "0700", home_dir\])' &&
   managed_app_source_contains 'command.extend(\["--bind", directory, directory\])' &&
   managed_app_source_contains '"runtime_directories": ("doc",)' &&
   managed_app_source_contains '"runtime_sockets": ("pipewire-0", "pulse/native")' &&
   managed_app_source_contains '"inner_sandbox_args": ("--no-sandbox",)' &&
   managed_app_source_contains '^TUTA_ATTACHMENT_READ_ONLY_PATHS = ($' &&
   managed_app_source_contains '^TUTA_ATTACHMENT_READ_WRITE_PATHS = ("Downloads",)$' &&
   managed_app_source_contains '"ro_bind_home_directories": TUTA_ATTACHMENT_READ_ONLY_PATHS' &&
   managed_app_source_contains '"rw_bind_home_directories": TUTA_ATTACHMENT_READ_WRITE_PATHS' &&
   managed_app_source_contains '".config/user-dirs.dirs",' &&
   managed_app_source_contains '^def add_home_directory_binds($' &&
   managed_app_source_contains 'writable=option == "--bind",' &&
   managed_app_source_contains '"APPDIR": "/opt/tuta-mail"' &&
   managed_app_source_contains '^ELECTRON_PASSWORD_STORE = "--password-store=gnome-libsecret"$' &&
   managed_app_source_lacks 'ELECTRON_PASSWORD_STORE_BY_APP' &&
   managed_app_source_lacks '^TUTA_SECRET_SERVICE_UNITS = ($' &&
   managed_app_source_lacks '^BITWARDEN_SECRET_SERVICE_' &&
   managed_app_source_lacks '^def validate_bitwarden_secret_service() -> None:$' &&
   managed_app_source_lacks '^SYSTEMCTL_PATH = ' &&
   managed_app_source_lacks '^def ensure_tuta_secret_services() -> None:$' &&
   managed_app_source_lacks 'systemctl' &&
   managed_app_source_lacks '--password-store=kwallet6' &&
   managed_app_source_contains '"FONTCONFIG_FILE": "/etc/fonts/fonts.conf"' &&
   managed_app_source_contains '"FONTCONFIG_PATH": "/etc/fonts"' &&
   managed_app_source_contains '^def persistent_sandbox_argv($' &&
   managed_app_source_contains '^def add_runtime_bind($' &&
   managed_app_source_contains 'runtime bind source is not a socket' &&
   managed_app_source_contains '^def validate_no_host_audio_device_binds(app_name: str, command: list\[str\]) -> None:$' &&
   managed_app_source_contains 'bubblewrap forbids direct ALSA device access' &&
   managed_app_source_contains '^def add_gpu_device_binds(command: list\[str\], mode: str) -> None:$' &&
   managed_app_source_contains 'add_gpu_device_binds(command, mode)' &&
   managed_app_source_contains 'TUTA_DBUS_NAMES' &&
   managed_app_source_contains '"dbus_names": TUTA_DBUS_NAMES' &&
   managed_app_source_contains '"require_session_bus": True' &&
   managed_app_source_contains 'required=sandbox.get("require_session_bus", False)' &&
   managed_app_source_lacks 'privacy_system_bus_proxy' &&
   managed_app_source_contains '^def start_system_bus_proxy($' &&
   managed_app_source_contains '^def add_system_bus_proxy_bind(command: list\[str\], proxy_socket: str) -> None:$' &&
   managed_app_source_contains '"require_system_bus": True' &&
   managed_app_source_contains '"system_dbus_names": ()' &&
   managed_app_source_contains 'required=sandbox.get("require_system_bus", False)' &&
   managed_app_source_contains 'env\["DBUS_SYSTEM_BUS_ADDRESS"\] = SYSTEM_BUS_ADDRESS' &&
   managed_app_source_contains 'env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)' &&
   managed_app_source_contains '^SYSTEM_BUS_SOCKET_PATH = "/run/dbus/system_bus_socket"$' &&
   managed_app_source_contains '^def validate_discord_runtime_tree() -> None:$' &&
   managed_app_source_contains '^DISCORD_TREE_MAXIMUM_FILES = 40_000$' &&
   managed_app_source_contains '^DISCORD_TREE_MAXIMUM_BYTES = 2_147_483_648$' &&
   managed_app_source_contains '^def ensure_discord_managed_settings(home_dir: str) -> None:$' &&
   managed_app_source_contains '"SKIP_HOST_UPDATE": True' &&
   managed_app_source_contains '"SKIP_MODULE_UPDATE": True' &&
   managed_app_source_contains '^ZOOM_CONFIG_SOURCE = ".config/zoom"$' &&
   managed_app_source_contains '"persistent_directory_binds": (' &&
   managed_app_source_contains '(ZOOM_CONFIG_SOURCE, ".config"),' &&
   managed_app_source_contains '^def add_persistent_directory_binds($' &&
   managed_app_source_contains 'sandbox.get("persistent_directory_binds", ())' &&
   managed_app_source_lacks '"xdg_config_home": ".config/zoom"' &&
   managed_app_source_lacks '"org.kde.kwalletd6"' &&
   managed_app_source_lacks '"org.kde.secretservicecompat"' &&
   managed_app_source_lacks '("--bind", home_dir, home_dir)'; then
  pass "Tuta requires a filtered Secret Service session bus and exposes no system D-Bus"
else
  fail "Tuta requires a filtered Secret Service session bus and exposes no system D-Bus"
fi

if grep -Eq '(^|[[:space:]])keepassxc([[:space:]]|$)' "$desktop_class" &&
   [ -r "$keepassxc_config" ] &&
   [ -r "$keepassxc_apparmor" ] &&
   ! grep -q '^  network ' "$keepassxc_apparmor" &&
   grep -q 'owner @{HOME}/.config/keepassxc/\*\* rwkl,' "$keepassxc_apparmor" &&
   grep -q 'owner @{HOME}/Syncthing/keepassxc/\*\* rwkl,' "$keepassxc_apparmor" &&
   grep -q '^ClearClipboard=true$' "$keepassxc_config" &&
   grep -q '^ClearClipboardTimeout=15$' "$keepassxc_config" &&
   grep -q '^BackupFilePath=backups$' "$keepassxc_config" &&
   grep -q '^LockDatabaseScreenLock=true$' "$keepassxc_config" &&
   grep -q '^LockDatabaseIdleSeconds=300$' "$keepassxc_config" &&
   grep -q '^Enabled=false$' "$keepassxc_config" &&
   grep -q 'etc/skel/.config/keepassxc/keepassxc.ini /etc/skel/.config/keepassxc/keepassxc.ini 0600' "$desktop_components" &&
   grep -q '"org.keepassxc.KeePassXC.desktop"' "$launcher_sync" &&
   grep -q '"action_app": "keepassxc"' "$launcher_sync" &&
   grep -q '"field_code": "%f"' "$launcher_sync" &&
   grep -q 'etc/skel/.config/chromium/Default/Preferences /etc/skel/.config/chromium/Default/Preferences 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/microsoft-edge/Default/Preferences /etc/skel/.config/microsoft-edge/Default/Preferences 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/vivaldi/Default/Preferences /etc/skel/.config/vivaldi/Default/Preferences 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/Code/User/settings.json /etc/skel/.config/Code/User/settings.json 0600' "$desktop_components" &&
   grep -q 'etc/skel/.config/obsidian/obsidian.json /etc/skel/.config/obsidian/obsidian.json 0600' "$desktop_components" &&
   grep -q '^desktop_stage_obsidian_default_vault() {$' "$desktop_components" &&
   grep -q 'Syncthing/obsidian-md \\' "$desktop_components" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/ rw,$' "$obsidian_apparmor" &&
   grep -q '^  owner @{HOME}/Syncthing/obsidian-md/\*\* rwkl,$' "$obsidian_apparmor" &&
   [ -r "$obsidian_vault/.obsidian/app.json" ] &&
   [ -r "$obsidian_vault/.obsidian/appearance.json" ] &&
   [ -r "$obsidian_vault/.obsidian/themes/evergreen-notes/theme.css" ] &&
   grep -Fqx '(?d)obsidian-md/.obsidian/workspace*.json' "$obsidian_vault/../.stignore" &&
   python3 - "$managed_app_package_root" "$keepassxc_config" "$chromium_preferences" "$edge_preferences" "$vivaldi_preferences" "$code_settings" "$obsidian_config" "$obsidian_vault" <<'PY' >/dev/null 2>&1
import configparser
import json
import pathlib
import sys

sys.path.insert(0, sys.argv[1])
from labwc_managed_app import environment, profiles

module = {
    "APPS": profiles.APPS,
    "PERSISTENT_SANDBOX_CONFIG": profiles.PERSISTENT_SANDBOX_CONFIG,
    "OBSIDIAN_VAULT_RELATIVE_PATH": profiles.OBSIDIAN_VAULT_RELATIVE_PATH,
    "MANAGED_RUNTIME_STATE": profiles.MANAGED_RUNTIME_STATE,
    "obsidian_vault_id": environment.obsidian_vault_id,
}
assert "keepassxc" not in module["PERSISTENT_SANDBOX_CONFIG"]
assert module["APPS"]["keepassxc"].get("persistent_sandbox", False) is False

config = configparser.ConfigParser(interpolation=None)
config.read(sys.argv[2], encoding="utf-8")
assert config.getboolean("Browser", "Enabled") is False
assert config.getboolean("SSHAgent", "Enabled") is False
assert config.getboolean("AutoType", "Enabled") is False
assert config.getboolean("Security", "LockDatabaseScreenLock") is True
assert config.getint("Security", "LockDatabaseIdleSeconds") == 300

for preference_path in sys.argv[3:6]:
    with open(preference_path, encoding="utf-8") as handle:
        preference = json.load(handle)
    assert preference == {"browser": {"custom_chrome_frame": False}}

with open(sys.argv[6], encoding="utf-8") as handle:
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

with open(sys.argv[7], encoding="utf-8") as handle:
    obsidian = json.load(handle)
assert obsidian == {
    "frame": "native",
    "openSchemes": {},
    "vaults": {},
}

vault = pathlib.Path(sys.argv[8])
with (vault / ".obsidian/app.json").open(encoding="utf-8") as handle:
    obsidian_app = json.load(handle)
assert obsidian_app["newFileFolderPath"] == "inbox"
assert obsidian_app["attachmentFolderPath"] == "attachments"
assert obsidian_app["trashOption"] == "local"

with (vault / ".obsidian/appearance.json").open(encoding="utf-8") as handle:
    appearance = json.load(handle)
assert appearance["cssTheme"] == "evergreen-notes"
assert appearance["enabledCssSnippets"] == ["managed-ux"]

with (vault / ".obsidian/core-plugins.json").open(encoding="utf-8") as handle:
    core_plugins = json.load(handle)
assert core_plugins["file-recovery"] is True
assert core_plugins["sync"] is False
assert core_plugins["publish"] is False
assert core_plugins["webviewer"] is False

with (vault / ".obsidian/community-plugins.json").open(encoding="utf-8") as handle:
    assert json.load(handle) == []

assert module["OBSIDIAN_VAULT_RELATIVE_PATH"] == "Syncthing/obsidian-md"
assert "obsidian" not in module["MANAGED_RUNTIME_STATE"]
assert module["obsidian_vault_id"]("/home/test/Syncthing/obsidian-md")
PY
then
  pass "managed desktop profiles seed native frames, VS Code privacy, KeePassXC confinement, and the default Obsidian vault"
else
  fail "managed desktop profiles seed native frames, VS Code privacy, KeePassXC confinement, and the default Obsidian vault"
fi

[ "$FAIL_COUNT" -eq 0 ]
