#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-adb-perl.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=8
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

adb_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-adb-action"
module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-adb"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_packages="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
validation_module="$module_root/AndroidADB/Validation.pm"
server_module="$module_root/AndroidADB/ADB/Server.pm"
backup_module="$module_root/AndroidADB/ADB/Backup.pm"
notification_module="$module_root/AndroidADB/Notification.pm"
logger_module="$module_root/AndroidADB/Logger.pm"
samsung_module="$module_root/AndroidADB/Vendor/Samsung.pm"
cli_module="$module_root/AndroidADB/CLI.pm"
config_module="$module_root/AndroidADB/Config.pm"

module_count=$(find "$module_root" -type f -name '*.pm' | wc -l | tr -d '[:space:]')
manifest_count=$(sed -n '/^desktop_labwc_adb_perl_modules() {$/,/^}$/p' "$components" | grep -c '^AndroidADB/.*[.]pm$')
if [ "$module_count" -eq 20 ] &&
   [ "$manifest_count" -eq 20 ] &&
   grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-adb';" "$adb_action" &&
   grep -Fq 'use AndroidADB::CLI;' "$adb_action" &&
   grep -Fq 'desktop_stage_labwc_adb_perl_modules' "$components" &&
   grep -q 'usr/local/bin/labwc-adb-action /usr/local/bin/labwc-adb-action 0755' "$components" &&
   grep -Eq '(^|[[:space:]])libmoo-perl([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libmoox-strictconstructor-perl([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libmoox-typetiny-perl([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libtype-tiny-perl([[:space:]]|$)' "$desktop_packages"; then
  pass "ADB stages exactly 20 Perl modules, the installed entrypoint, and required Moo providers"
else
  fail "ADB stages exactly 20 Perl modules, the installed entrypoint, and required Moo providers"
fi

compat_root="$TMP_DIR/perl-compat"
mkdir -p "$compat_root/MooX" "$compat_root/Sys" "$compat_root/Types"
cat >"$compat_root/Moo.pm" <<'PERL'
package Moo;
use strict;
use warnings;
our %ATTRIBUTES;
sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::has"} = sub {
        my ($name, %specification) = @_;
        $ATTRIBUTES{$caller}{$name} = \%specification;
        *{"${caller}::${name}"} = sub {
            my ($self) = @_;
            if (@_ > 1) {
                $self->{$name} = $_[1];
                return $self->{$name};
            }
            if (!exists $self->{$name}) {
                if (exists $specification{default}) {
                    my $default = $specification{default};
                    $self->{$name} = ref($default) eq 'CODE' ? $default->($self) : $default;
                }
                elsif (($specification{is} // q{}) eq 'lazy' && defined $specification{builder}) {
                    my $builder = $specification{builder};
                    $self->{$name} = $self->$builder();
                }
            }
            return $self->{$name};
        };
        return;
    };
    *{"${caller}::new"} = sub {
        my ($class, @arguments) = @_;
        @arguments % 2 == 0 or die "odd constructor arguments for $class\n";
        my %arguments = @arguments;
        my $attributes = $ATTRIBUTES{$class} // {};
        for my $name (keys %arguments) {
            exists $attributes->{$name} or die "unknown constructor argument $name for $class\n";
        }
        my $self = bless {}, $class;
        for my $name (keys %{$attributes}) {
            if (exists $arguments{$name}) {
                $self->{$name} = $arguments{$name};
            }
            elsif ($attributes->{$name}{required}) {
                die "missing required constructor argument $name for $class\n";
            }
        }
        return $self;
    };
    return;
}
1;
PERL
cat >"$compat_root/MooX/StrictConstructor.pm" <<'PERL'
package MooX::StrictConstructor;
use strict;
use warnings;
sub import { return; }
1;
PERL
cat >"$compat_root/MooX/TypeTiny.pm" <<'PERL'
package MooX::TypeTiny;
use strict;
use warnings;
sub import { return; }
1;
PERL
cat >"$compat_root/Types/Standard.pm" <<'PERL'
package Types::Standard;
use strict;
use warnings;
sub import {
    my ($class, @symbols) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $symbol (@symbols) {
        *{"${caller}::${symbol}"} = sub { return sub { 1 }; };
    }
    return;
}
1;
PERL
cat >"$compat_root/Sys/Syslog.pm" <<'PERL'
package Sys::Syslog;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(
    openlog syslog closelog
    LOG_DEBUG LOG_INFO LOG_WARNING LOG_ERR LOG_USER
);
our %EXPORT_TAGS = (
    standard => [qw(openlog syslog closelog)],
    macros   => [qw(LOG_DEBUG LOG_INFO LOG_WARNING LOG_ERR LOG_USER)],
);
sub LOG_DEBUG () { 7 }
sub LOG_INFO () { 6 }
sub LOG_WARNING () { 4 }
sub LOG_ERR () { 3 }
sub LOG_USER () { 8 }
sub _append {
    return 1 if !defined($ENV{ADB_LOG_CAPTURE});
    open my $handle, '>>', $ENV{ADB_LOG_CAPTURE}
        or die "open ADB log capture: $!\n";
    print {$handle} $_[0], "\n"
        or die "write ADB log capture: $!\n";
    close $handle
        or die "close ADB log capture: $!\n";
    return 1;
}
sub openlog { return _append("openlog $_[0]"); }
sub syslog { return _append("syslog $_[2]"); }
sub closelog { return 1; }
1;
PERL

perl5lib="$compat_root:$module_root"
compile_ok=true
for perl_file in "$adb_action" $(find "$module_root" -type f -name '*.pm' | sort); do
  env PERL5LIB="$perl5lib" LC_ALL=C TZ=UTC /usr/bin/perl -c "$perl_file" >/dev/null 2>&1 ||
    compile_ok=false
done
if [ "$compile_ok" = true ]; then
  pass "ADB entrypoint and all 20 Perl modules compile through deterministic compatibility providers"
else
  fail "ADB entrypoint and all 20 Perl modules compile through deterministic compatibility providers"
fi

behavior_harness="$TMP_DIR/adb-behavior.pl"
cat >"$behavior_harness" <<'PERL'
use strict;
use warnings;

use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use AndroidADB::ADB::Backup;
use AndroidADB::ADB::Server;
use AndroidADB::Notification;
use AndroidADB::Validation qw(validate_action);

package Local::Config;
sub new { my ($class, %args) = @_; return bless \%args, $class; }
sub runtime_dir { return $_[0]{runtime_dir}; }
sub home { return $_[0]{home}; }
sub server_marker { return $_[0]{server_marker}; }
sub output_root { return $_[0]{output_root}; }
sub adb_server_port { return 5037; }
sub adb_probe_seconds { return 6; }
sub adb_start_seconds { return 20; }
sub adb_command_seconds { return 120; }
sub adb_backup_seconds { return 14_400; }
sub adb_backup_headroom_kib { return 1_048_576; }
sub tool {
    my ($self, $name) = @_;
    return "/mock/$name";
}
sub require_tool { return $_[0]->tool($_[1]); }

package Local::ServerCommand;
sub new { my ($class, %args) = @_; $args{calls} //= []; return bless \%args, $class; }
sub calls { return $_[0]{calls}; }
sub capture {
    my ($self, $timeout, @argv) = @_;
    push @{$self->{calls}}, ['capture', @argv];
    return {
        status => 0,
        stdout => $self->{port_in_use} ? "LISTEN 0 4096 127.0.0.1:5037\n" : q{},
        stderr => q{},
    };
}
sub run_quiet {
    my ($self, $timeout, @argv) = @_;
    push @{$self->{calls}}, ['run_quiet', @argv];
    return $self->{service_status} // 1
        if grep { $_ eq 'is-active' } @argv;
    return $self->{failed_status} // 1
        if grep { $_ eq 'is-failed' } @argv;
    return $self->{probe_status} // 1;
}
sub run {
    my ($self, $timeout, @argv) = @_;
    push @{$self->{calls}}, ['run', @argv];
    if (grep { $_ eq 'start' || $_ eq 'restart' } @argv) {
        $self->{service_status} = 0;
    }
    if (grep { $_ eq 'stop' } @argv) {
        $self->{service_status} = 1;
    }
    if (grep { $_ eq 'reset-failed' } @argv) {
        $self->{failed_status} = 1;
    }
    return 0;
}
sub run_signal {
    my ($self, @argv) = @_;
    push @{$self->{calls}}, ['run_signal', @argv];
    return 0;
}

package Local::BackupStorage;
sub new { my ($class, %args) = @_; return bless \%args, $class; }
sub output_timestamp { return '20260807T120000Z'; }
sub prepare_output_directory {
    my ($self, $name) = @_;
    my $path = File::Spec->catdir($self->{output_root}, $name);
    File::Path::make_path($path, { mode => 0700 });
    return $path;
}
sub create_partial_directory {
    my ($self, $parent, $label) = @_;
    my $path = File::Spec->catdir($parent, ".$label.partial.test");
    mkdir $path, 0700 or die "mkdir $path: $!\n";
    return $path;
}
sub create_directory {
    my ($self, $path) = @_;
    File::Path::make_path($path, { mode => 0700 });
    return $path;
}
sub write_text {
    my ($self, $path, $content) = @_;
    open my $handle, '>', $path or die "open $path: $!\n";
    print {$handle} $content or die "write $path: $!\n";
    close $handle or die "close $path: $!\n";
    return $path;
}
sub available_kib { return 10_000_000; }
sub file_sha256 { return 'a' x 64; }
sub secure_tree { return; }
sub finalize_directory {
    my ($self, $partial, $final) = @_;
    rename $partial, $final or die "rename $partial to $final: $!\n";
    return $final;
}

package Local::BackupLock;
sub new { return bless { completed => 0 }, $_[0]; }
sub acquire { return; }
sub register_partial_directory { $_[0]{partial} = $_[1]; return; }
sub complete_partial_directory { $_[0]{completed} = 1; delete $_[0]{partial}; return; }

package Local::BackupDevice;
sub new { my ($class, %args) = @_; return bless \%args, $class; }
sub wait_for_serial { $_[0]{waited}{$_[1]}++; return; }
sub device_summary { print "serial=$_[1]\nmodel=Test Device\n"; return 0; }
sub capture_serial {
    my ($self, $timeout, $serial, @argv) = @_;
    my $command = join q{ }, @argv;
    return "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/fuse 1000000 1024 998976 1% /storage/emulated\n"
        if $command eq 'shell df -k /sdcard';
    return "[ro.product.model]: [Test Device]\n" if $command eq 'shell getprop';
    return "package:/data/app/example.apk=com.example\n" if $command eq 'shell pm list packages -f -U -u';
    return "Users:\nUserInfo{0:Owner:13}\n" if $command eq 'shell pm list users';
    return "/dev/fuse 1000000 1024 998976 1% /storage/emulated\n" if $command eq 'shell df -k';
    die "unexpected capture_serial request: $command\n";
}
sub run_serial {
    my ($self, $timeout, $serial, @argv) = @_;
    if ($argv[0] eq 'pull') {
        my $destination = $argv[-1];
        File::Path::make_path($destination, { mode => 0700 });
        open my $handle, '>', File::Spec->catfile($destination, 'example.txt')
            or die "create shared-storage fixture: $!\n";
        print {$handle} "backup\n" or die "write shared-storage fixture: $!\n";
        close $handle or die "close shared-storage fixture: $!\n";
        return 0;
    }
    if ($argv[0] eq 'bugreport') {
        open my $handle, '>', $argv[1] or die "create bugreport fixture: $!\n";
        print {$handle} "bugreport\n" or die "write bugreport fixture: $!\n";
        close $handle or die "close bugreport fixture: $!\n";
        return 0;
    }
    die "unexpected run_serial request: @argv\n";
}

package Local::BackupCommand;
sub new { return bless {}, $_[0]; }
sub run_to_file {
    my ($self, $timeout, $stdout, $stderr, @argv) = @_;
    open my $handle, '>', $stdout or die "open $stdout: $!\n";
    print {$handle} "setting=value\n" or die "write $stdout: $!\n";
    close $handle or die "close $stdout: $!\n";
    open $handle, '>', $stderr or die "open $stderr: $!\n";
    close $handle or die "close $stderr: $!\n";
    return 0;
}
sub capture {
    return { status => 0, stdout => "Android Debug Bridge\n", stderr => q{} };
}

package Local::NotifyCommand;
sub new { return bless { calls => [] }, $_[0]; }
sub calls { return $_[0]{calls}; }
sub run_quiet {
    my ($self, $timeout, @argv) = @_;
    push @{$self->{calls}}, [@argv];
    return 0;
}

package main;
sub require_true {
    my ($condition, $message) = @_;
    $condition or die "$message\n";
    return;
}
sub expect_failure {
    my ($pattern, $code) = @_;
    my $ok = eval { $code->(); 1 };
    my $error = $@;
    !$ok or die "expected failure matching $pattern\n";
    $error =~ $pattern or die "unexpected failure: $error";
    return;
}
sub read_text {
    my ($path) = @_;
    open my $handle, '<', $path or die "open $path: $!\n";
    local $/;
    my $content = <$handle>;
    close $handle or die "close $path: $!\n";
    return $content;
}
sub has_fragment {
    my ($calls, $fragment) = @_;
    return scalar grep { index(join(q{ }, @{$_}), $fragment) >= 0 } @{$calls};
}

my $case = shift @ARGV // q{};
my $tmp = $ENV{ADB_TEST_TMP} // die "ADB_TEST_TMP is unset\n";

if ($case eq 'validation') {
    my $firmware = File::Spec->catdir($tmp, 'firmware');
    File::Path::make_path($firmware, { mode => 0700 });
    require_true(validate_action('start-server'), 'server start validation failed');
    require_true(validate_action('repair-server'), 'server repair validation failed');
    require_true(validate_action('stop-server'), 'server stop validation failed');
    require_true(validate_action('backup-device', 'ABC123', 'confirmed-adb-action'), 'backup validation failed');
    require_true(validate_action('pair-wireless', '192.168.1.10:37123', '123456'), 'pair validation failed');
    require_true(validate_action('samsung-download-firmware', 'ABC123', 'SM-S931U1', 'EUX', 'confirmed-samsung-download'), 'Samsung download validation failed');
    require_true(validate_action('samsung-flash-keep-data', 'ABC123', $firmware, 'confirmed-samsung-keep-data-flash'), 'Samsung keep-data validation failed');
    require_true(validate_action('samsung-flash-factory-reset', 'ABC123', $firmware, 'confirmed-samsung-factory-reset'), 'Samsung factory-reset validation failed');
    expect_failure(qr/invalid Android device serial/, sub { validate_action('device-summary', '../device') });
    expect_failure(qr/requires the managed confirmation/, sub { validate_action('backup-device', 'ABC123', 'missing') });
    expect_failure(qr/pairing code must contain six digits/, sub { validate_action('pair-wireless', '192.168.1.10:37123', '123') });
    expect_failure(qr/managed HOME_CSC confirmation/, sub { validate_action('samsung-flash-keep-data', 'ABC123', $firmware, 'missing') });
    expect_failure(qr/managed factory-reset confirmation/, sub { validate_action('samsung-flash-factory-reset', 'ABC123', $firmware, 'missing') });
}
elsif ($case eq 'server') {
    my $runtime = File::Spec->catdir($tmp, 'runtime');
    File::Path::make_path($runtime, { mode => 0700 });
    my $marker = File::Spec->catfile($runtime, 'labwc-adb-server.managed');
    open my $handle, '>', $marker or die "open $marker: $!\n";
    close $handle or die "close $marker: $!\n";
    my $config = Local::Config->new(runtime_dir => $runtime, server_marker => $marker);

    my $unresponsive_command = Local::ServerCommand->new(port_in_use => 1, probe_status => 1);
    my $unresponsive = AndroidADB::ADB::Server->new(config => $config, command => $unresponsive_command);
    expect_failure(qr/refusing process-table discovery or name-wide termination/, sub { $unresponsive->ensure_responsive });
    require_true(!has_fragment($unresponsive_command->calls(), 'kill-server'), 'unresponsive probe invoked kill-server');
    require_true(!has_fragment($unresponsive_command->calls(), 'start-server'), 'unresponsive probe invoked start-server');

    my $stopped_command = Local::ServerCommand->new(port_in_use => 0, probe_status => 1);
    my $stopped = AndroidADB::ADB::Server->new(config => $config, command => $stopped_command);
    my $output = q{};
    my $status;
    {
        local *STDOUT;
        open STDOUT, '>', \$output or die "capture server status: $!\n";
        $status = $stopped->show_status;
    }
    require_true($status == 3, 'stopped server status changed');
    require_true(index($output, 'ADB server status: stopped') >= 0, 'stopped server message missing');
    require_true(!has_fragment($stopped_command->calls(), 'server-status'), 'stopped status contacted adb');

    open $handle, '>', $marker or die "reopen $marker: $!\n";
    close $handle or die "reclose $marker: $!\n";
    my $service_start_command = Local::ServerCommand->new(
        port_in_use    => 1,
        probe_status   => 0,
        service_status => 1,
    );
    my $service_start = AndroidADB::ADB::Server->new(
        config  => $config,
        command => $service_start_command,
    );
    require_true($service_start->start_via_service == 0, 'managed service start failed');
    require_true(
        !has_fragment(
            $service_start_command->calls(),
            '--user reset-failed labwc-adb-server.service',
        ),
        'never-loaded managed service attempted reset-failed before first start',
    );
    require_true(
        has_fragment(
            $service_start_command->calls(),
            '--user is-failed --quiet labwc-adb-server.service',
        ),
        'managed service start did not query failed state quietly',
    );
    require_true(
        has_fragment(
            $service_start_command->calls(),
            '--user start labwc-adb-server.service',
        ),
        'managed service start did not use the user unit',
    );

    my $service_failed_command = Local::ServerCommand->new(
        port_in_use    => 1,
        probe_status   => 0,
        service_status => 1,
        failed_status  => 0,
    );
    my $service_failed = AndroidADB::ADB::Server->new(
        config  => $config,
        command => $service_failed_command,
    );
    require_true(
        $service_failed->start_via_service == 0,
        'failed managed service did not recover',
    );
    require_true(
        has_fragment(
            $service_failed_command->calls(),
            '--user reset-failed labwc-adb-server.service',
        ),
        'failed managed service was not reset before recovery',
    );
    require_true(
        has_fragment(
            $service_failed_command->calls(),
            '--user start labwc-adb-server.service',
        ),
        'failed managed service did not start after reset',
    );

    my $service_repair_command = Local::ServerCommand->new(
        port_in_use    => 1,
        probe_status   => 0,
        service_status => 0,
    );
    my $service_repair = AndroidADB::ADB::Server->new(
        config  => $config,
        command => $service_repair_command,
    );
    require_true($service_repair->repair_via_service == 0, 'managed service repair failed');
    require_true(
        has_fragment(
            $service_repair_command->calls(),
            '--user restart labwc-adb-server.service',
        ),
        'managed service repair did not restart the user unit',
    );

    my $service_stop_command = Local::ServerCommand->new(
        port_in_use    => 0,
        probe_status   => 0,
        service_status => 0,
    );
    my $service_stop = AndroidADB::ADB::Server->new(
        config  => $config,
        command => $service_stop_command,
    );
    require_true($service_stop->stop_via_service == 0, 'managed service stop failed');
    require_true(
        has_fragment(
            $service_stop_command->calls(),
            '--user stop labwc-adb-server.service',
        ),
        'managed service stop did not use the user unit',
    );
}
elsif ($case eq 'backup') {
    my $home = File::Spec->catdir($tmp, 'backup-home');
    File::Path::make_path($home, { mode => 0700 });
    my $output_root = File::Spec->catdir($home, 'Android', 'adb');
    my $config = Local::Config->new(home => $home, output_root => $output_root);
    my $storage = Local::BackupStorage->new(output_root => $output_root);
    my $lock = Local::BackupLock->new();
    my $device = Local::BackupDevice->new();
    my $command = Local::BackupCommand->new();
    my $backup = AndroidADB::ADB::Backup->new(
        config => $config,
        command => $command,
        device => $device,
        lock => $lock,
        storage => $storage,
    );
    my $output = q{};
    my $status;
    {
        local *STDOUT;
        open STDOUT, '>', \$output or die "capture backup output: $!\n";
        $status = $backup->backup('ABC123');
    }
    my $final = File::Spec->catdir($output_root, 'backups', '20260807T120000Z-ABC123');
    require_true($status == 0, 'backup returned nonzero');
    require_true(-f File::Spec->catfile($final, 'shared-storage', 'example.txt'), 'shared-storage backup missing');
    my $status_text = read_text(File::Spec->catfile($final, 'backup-status.txt'));
    require_true(index($status_text, "format=managed-adb-backup-v1\n") >= 0, 'backup format missing');
    require_true(index($status_text, "legacy_android_backup=unsupported\n") >= 0, 'legacy status missing');
    require_true(index($status_text, "bugreport=created\n") >= 0, 'bugreport status missing');
    require_true(-f File::Spec->catfile($final, 'SHA256SUMS'), 'backup checksum manifest missing');
    require_true($lock->{completed}, 'backup partial directory was not completed');
    require_true(index($output, 'Completed best-effort device backup') >= 0, 'backup completion message missing');
}
elsif ($case eq 'notification') {
    my $config = Local::Config->new();
    my $command = Local::NotifyCommand->new();
    my $notification = AndroidADB::Notification->new(config => $config, command => $command);
    local $ENV{DBUS_SESSION_BUS_ADDRESS} = 'unix:path=/tmp/test-bus';
    $notification->notify_result(0, 'backup-device');
    $notification->notify_result(1, 'backup-device');
    require_true(@{$command->calls()} == 2, 'notification call count changed');
    require_true(has_fragment($command->calls(), '-a Android Device'), 'notification application name missing');
    require_true(has_fragment($command->calls(), '-c x-labwc.maintenance'), 'notification category missing');
    require_true(has_fragment($command->calls(), '-u normal'), 'success notification urgency missing');
    require_true(has_fragment($command->calls(), '-u critical'), 'failure notification urgency missing');
}
else {
    die "unsupported behavior case: $case\n";
}

exit 0;
PERL

run_behavior_case() {
  case_name=$1
  env \
    PERL5LIB="$perl5lib" \
    ADB_TEST_TMP="$TMP_DIR" \
    LC_ALL=C \
    TZ=UTC \
    /usr/bin/perl "$behavior_harness" "$case_name"
}

if run_behavior_case validation; then
  pass "ADB validation enforces serial, endpoint, backup, and Samsung confirmation contracts"
else
  fail "ADB validation enforces serial, endpoint, backup, and Samsung confirmation contracts"
fi

if run_behavior_case server; then
  pass "ADB server control fails closed for stopped or unresponsive managed servers without process-wide termination"
else
  fail "ADB server control fails closed for stopped or unresponsive managed servers without process-wide termination"
fi

if run_behavior_case backup; then
  pass "ADB backup atomically stores shared data, metadata, status, and integrity hashes"
else
  fail "ADB backup atomically stores shared data, metadata, status, and integrity hashes"
fi

if run_behavior_case notification; then
  pass "ADB action results use bounded Mako notification argv"
else
  fail "ADB action results use bounded Mako notification argv"
fi

if grep -Fq '$> != 0' "$config_module" &&
   grep -Fq 'for my $override (qw(ADB_SERVER_SOCKET ANDROID_ADB_SERVER_PORT))' "$config_module" &&
   grep -Fq '"$override overrides are not supported by the managed launcher"' "$config_module" &&
   grep -Fq 'require_value(scalar(@account), "desktop account is unavailable for UID $<");' "$config_module" &&
   grep -Fq "? (\$firmware->{home_csc}, 'HOME_CSC')" "$samsung_module" &&
   grep -Fq ": (\$firmware->{csc}, 'CSC');" "$samsung_module" &&
   grep -q 'exactly one supported Samsung Download Mode device is required' "$samsung_module" &&
   grep -Fq 'use AndroidADB::Logger qw(log_event);' "$cli_module" &&
   grep -Fq 'exec { $terminal } $terminal' "$cli_module" &&
   grep -Fq 'exit AndroidADB::CLI->new()->run(@ARGV);' "$adb_action"; then
  pass "ADB CLI validates passwd lookup as one predicate and preserves terminal, HOME_CSC, CSC, and single-device boundaries"
else
  fail "ADB CLI validates passwd lookup as one predicate and preserves terminal, HOME_CSC, CSC, and single-device boundaries"
fi

logger_capture="$TMP_DIR/adb-logger.capture"
if env \
     PERL5LIB="$perl5lib" \
     ADB_LOG_CAPTURE="$logger_capture" \
     LC_ALL=C \
     TZ=UTC \
     /usr/bin/perl -MAndroidADB::Logger=log_event -e \
       'log_event("error", "failed", action => "start-server", detail => "bad record\n", status => 1) or die "log failed\n";' &&
   grep -Fqx 'openlog labwc-adb' "$logger_capture" &&
   grep -Fqx 'syslog event=failed action=start-server detail=bad_record_ status=1' "$logger_capture" &&
   grep -Fq "openlog('labwc-adb'" "$logger_module"; then
  pass "ADB logging emits bounded deterministic events through the dedicated syslog identifier"
else
  fail "ADB logging emits bounded deterministic events through the dedicated syslog identifier"
fi

[ "$FAIL_COUNT" -eq 0 ]
