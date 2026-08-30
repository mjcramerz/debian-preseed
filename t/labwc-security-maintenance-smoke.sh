#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-security-maintenance.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=24
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

desktop_cfg="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
maintenance_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-maintenance-menu"
users_groups_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-users-groups-menu"
external_drive_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-external-drives"
security_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-security-action"
root_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-security-action-root"
apparmor_rule_generator="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/apparmor-generate-rules"
system_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-system-action"
system_root_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-system-action-root"
recovery_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-recovery-action"
recovery_root_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-recovery-action-root"
update_helper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/managed-clamav-signature-update"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
polkit_rule="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d/10-pkexec.rules"
desktop_polkit_dir="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/polkit-1/rules.d"
shared_target="$ROOT_DIR/d-i/forky/hooks/shared/target"
shared_polkit_dir="${shared_target}/etc/polkit-1/rules.d"
desktop_policy_dir="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/polkit-1/actions"
fangfrisch_config="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/fangfrisch.conf"
update_service="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-clamav-signature-update.service"
update_timer="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/systemd/system/managed-clamav-signature-update.timer"
labwc_security_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-security-action"
labwc_security_client_module="$labwc_security_module_root/LabwcSecurityAction/Client.pm"
labwc_security_command_module="$labwc_security_module_root/LabwcSecurityAction/Command.pm"
labwc_security_root_module="$labwc_security_module_root/LabwcSecurityAction/Root.pm"
labwc_security_apparmor_module="$labwc_security_module_root/LabwcSecurityAction/AppArmor.pm"
labwc_security_apparmor_audit_log_module="$labwc_security_module_root/LabwcSecurityAction/AppArmor/AuditLog.pm"
labwc_security_apparmor_profile_index_module="$labwc_security_module_root/LabwcSecurityAction/AppArmor/ProfileIndex.pm"
labwc_security_apparmor_rule_generator_module="$labwc_security_module_root/LabwcSecurityAction/AppArmor/RuleGenerator.pm"
labwc_security_apparmor_rule_renderer_module="$labwc_security_module_root/LabwcSecurityAction/AppArmor/RuleRenderer.pm"
labwc_security_scanner_log_module="$labwc_security_module_root/LabwcSecurityAction/ScannerLog.pm"
apparmor_managed_modes_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/apparmor-managed-modes"
perl_stub_root="$TMP_DIR/perl-stubs"
perl_client_runner="$TMP_DIR/labwc-security-client-runner.pl"
perl_apparmor_runner="$TMP_DIR/labwc-security-apparmor-runner.pl"
perl_rule_generator_runner="$TMP_DIR/labwc-security-rule-generator-runner.pl"

mkdir -p "$perl_stub_root/MooX" "$perl_stub_root/Types"
cat >"$perl_stub_root/Moo.pm" <<'EOF'
package Moo;

use strict;
use warnings;

my (%ATTRIBUTE_SPEC, %ATTRIBUTE_ORDER);

sub import {
    my ($class) = @_;
    my $target = caller;

    no strict 'refs';
    *{"${target}::has"} = sub {
        my ($name, @arguments) = @_;
        defined($name) && $name ne q{} or die "Moo stub attribute name is required\n";
        @arguments % 2 == 0 or die "Moo stub attribute specification is malformed\n";
        my %specification = @arguments;
        $ATTRIBUTE_SPEC{$target}{$name} = \%specification;
        push @{ $ATTRIBUTE_ORDER{$target} }, $name
            if !grep { $_ eq $name } @{ $ATTRIBUTE_ORDER{$target} // [] };
        *{"${target}::${name}"} = sub { return $_[0]->{$name}; };
        return;
    };
    *{"${target}::new"} = sub {
        my ($package, @arguments) = @_;
        @arguments % 2 == 0 or die "Moo stub constructor arguments are malformed\n";
        my %arguments = @arguments;
        my $self = bless {}, $package;
        for my $name (@{ $ATTRIBUTE_ORDER{$package} // [] }) {
            my $specification = $ATTRIBUTE_SPEC{$package}{$name};
            if (exists $arguments{$name}) {
                $self->{$name} = delete $arguments{$name};
                next;
            }
            if (exists $specification->{default}) {
                my $default = $specification->{default};
                $self->{$name} = ref($default) eq 'CODE'
                    ? $default->($self)
                    : $default;
                next;
            }
            $specification->{required}
                and die "Moo stub missing required attribute: $name\n";
        }
        keys(%arguments) == 0
            or die "Moo stub received unknown constructor attributes\n";
        return $self;
    };
    return;
}

1;
EOF
cat >"$perl_stub_root/MooX/Options.pm" <<'EOF'
package MooX::Options;

use strict;
use warnings;

sub import { return; }

1;
EOF
cat >"$perl_stub_root/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;

use strict;
use warnings;

sub import { return; }

1;
EOF
cat >"$perl_stub_root/MooX/TypeTiny.pm" <<'EOF'
package MooX::TypeTiny;

use strict;
use warnings;

sub import { return; }

1;
EOF
cat >"$perl_stub_root/Types/Standard.pm" <<'EOF'
package Types::Standard;

use strict;
use warnings;

sub import {
    my ($class, @symbols) = @_;
    my $target = caller;

    no strict 'refs';
    for my $symbol (@symbols) {
        *{"${target}::${symbol}"} = sub { return sub { 1 }; };
    }
    return;
}

1;
EOF
cat >"$perl_client_runner" <<'EOF'
#!/usr/bin/perl

use strict;
use warnings;

use LabwcSecurityAction::Client;
use LabwcSecurityAction::ScannerLog;

my %arguments;
for my $mapping (
    ['apparmor_easyprof_draft_dir', 'LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR'],
    ['apparmor_profile_draft_dir',  'LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR'],
    ['clamav_database_dir',         'LABWC_TEST_CLAMAV_DATABASE_DIR'],
) {
    my ($attribute, $environment) = @{$mapping};
    $arguments{$attribute} = $ENV{$environment}
        if defined($ENV{$environment}) && $ENV{$environment} ne q{};
}
if (defined($ENV{LABWC_TEST_SCANNER_SOCKET}) && $ENV{LABWC_TEST_SCANNER_SOCKET} ne q{}) {
    my $test_root = $ENV{LABWC_TEST_SCANNER_ROOT} // q{};
    $test_root =~ m{\A/tmp/[A-Za-z0-9._/-]+\z}
        or die "test scanner root is invalid\n";
    no warnings 'redefine';
    *LabwcSecurityAction::ScannerLog::_validate_socket_path = sub {
        my ($self) = @_;

        index($self->socket_path(), "$test_root/") == 0
            or die "test scanner socket is outside the test root\n";
        $self->socket_path() =~ m{[.]sock\z}
            or die "test scanner socket suffix is invalid\n";
        return;
    };
    $arguments{scanner_log} = LabwcSecurityAction::ScannerLog->new(
        socket_path => $ENV{LABWC_TEST_SCANNER_SOCKET},
    );
}

exit LabwcSecurityAction::Client->new(%arguments)->run(@ARGV);
EOF
cat >"$perl_apparmor_runner" <<'EOF'
#!/usr/bin/perl

use strict;
use warnings;

use File::Path qw(make_path);
use LabwcSecurityAction::AppArmor;
use LabwcSecurityAction::Command;

{
    package LabwcSecurityAction::TestAppArmor;

    use strict;
    use warnings;
    use File::Path qw(make_path);

    our @ISA = ('LabwcSecurityAction::AppArmor');

    sub _validate_mode_config {
        my ($self) = @_;

        -f $self->mode_config() && !-l $self->mode_config()
            or die "managed AppArmor mode configuration must be a regular non-symlink file\n";
        my @stat = stat $self->mode_config();
        @stat or die "cannot inspect managed AppArmor mode configuration\n";
        ($stat[2] & 0022) == 0
            or die "managed AppArmor mode configuration must not be group- or world-writable\n";
        $stat[7] <= $self->maximum_config_bytes()
            or die "managed AppArmor mode configuration exceeds " . $self->maximum_config_bytes() . " bytes\n";
        return;
    }

    sub _ensure_root_directory {
        my ($self, $directory, $mode, $label) = @_;

        !-l $directory
            or die "$label cannot be a symbolic link\n";
        make_path($directory, { mode => $mode }) if !-d $directory;
        my @stat = stat $directory;
        @stat && -d _
            or die "$label is unavailable: $directory\n";
        ($stat[2] & 0022) == 0
            or die "$label must not be group- or world-writable\n";
        chmod $mode, $directory
            or die "cannot set $label mode: $!\n";
        return;
    }

    sub _validate_root_owned_file {
        my ($self, $label, $path) = @_;

        -f $path && !-l $path
            or die "$label must be a regular non-symlink file: $path\n";
        my @stat = stat $path;
        @stat or die "cannot inspect $label: $path\n";
        ($stat[2] & 0022) == 0
            or die "$label must not be group- or world-writable: $path\n";
        $stat[7] <= $self->maximum_draft_bytes()
            or die "$label exceeds " . $self->maximum_draft_bytes() . " bytes: $path\n";
        return;
    }
}

my $command_path = $ENV{LABWC_TEST_COMMAND_PATH}
    // die "LABWC_TEST_COMMAND_PATH is required\n";
my %arguments = (
    command            => LabwcSecurityAction::Command->new(path => $command_path),
    easyprof_draft_dir => $ENV{LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR},
    event_log          => $ENV{LABWC_TEST_APPARMOR_EVENT_LOG} // '/dev/null',
    mode_config        => $ENV{LABWC_TEST_APPARMOR_MODE_CONFIG},
    mode_helper        => $ENV{LABWC_TEST_APPARMOR_MODE_HELPER},
    profile_backup_dir => $ENV{LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR},
    profile_dir        => $ENV{LABWC_TEST_APPARMOR_PROFILE_DIR},
    profile_draft_dir  => $ENV{LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR},
);
for my $name (keys %arguments) {
    defined($arguments{$name}) && $arguments{$name} ne q{}
        or die "missing AppArmor test argument: $name\n";
}
my $apparmor = LabwcSecurityAction::AppArmor->new(%arguments);
bless $apparmor, 'LabwcSecurityAction::TestAppArmor';

my $operation = shift @ARGV // die "AppArmor test operation is required\n";
if ($operation eq 'activate-draft') {
    exit $apparmor->activate_draft(@ARGV);
}
if ($operation eq 'set-application-mode') {
    exit $apparmor->set_application_mode(@ARGV);
}
if ($operation eq 'set-desktop-state') {
    exit $apparmor->set_desktop_state(@ARGV);
}
if ($operation eq 'print-application-modes') {
    exit $apparmor->print_application_modes();
}
die "unsupported AppArmor test operation: $operation\n";
EOF
cat >"$perl_rule_generator_runner" <<'EOF'
#!/usr/bin/perl

use strict;
use warnings;

use LabwcSecurityAction::AppArmor::AuditLog;
use LabwcSecurityAction::AppArmor::ProfileIndex;
use LabwcSecurityAction::AppArmor::RuleGenerator;
use LabwcSecurityAction::AppArmor::RuleRenderer;
use LabwcSecurityAction::Command;

my $command_path = $ENV{LABWC_TEST_COMMAND_PATH}
    // die "LABWC_TEST_COMMAND_PATH is required\n";
my $backup_dir = $ENV{LABWC_TEST_APPARMOR_RULE_BACKUP_DIR}
    // die "LABWC_TEST_APPARMOR_RULE_BACKUP_DIR is required\n";
my $event_log = $ENV{LABWC_TEST_APPARMOR_EVENT_LOG}
    // die "LABWC_TEST_APPARMOR_EVENT_LOG is required\n";
my $parser_config = $ENV{LABWC_TEST_APPARMOR_PARSER_CONFIG}
    // die "LABWC_TEST_APPARMOR_PARSER_CONFIG is required\n";
my $profile_dir = $ENV{LABWC_TEST_APPARMOR_PROFILE_DIR}
    // die "LABWC_TEST_APPARMOR_PROFILE_DIR is required\n";
my $command = LabwcSecurityAction::Command->new(
    path => $command_path,
);
my $trusted_uid = $<;
my $generator = LabwcSecurityAction::AppArmor::RuleGenerator->new(
    audit_log => LabwcSecurityAction::AppArmor::AuditLog->new(
        trusted_uid => $trusted_uid,
    ),
    backup_dir => $backup_dir,
    command => $command,
    event_log => $event_log,
    parser_config => $parser_config,
    profile_dir => $profile_dir,
    profile_index => LabwcSecurityAction::AppArmor::ProfileIndex->new(
        command       => $command,
        parser_config => $parser_config,
        profile_dir   => $profile_dir,
        trusted_uid   => $trusted_uid,
    ),
    reload_profiles => 1,
    renderer => LabwcSecurityAction::AppArmor::RuleRenderer->new(),
    trusted_uid => $trusted_uid,
);

exit $generator->run(
    shift @ARGV // die "AppArmor rule-generator confirmation is required\n",
);
EOF
chmod 0755 \
  "$perl_client_runner" \
  "$perl_apparmor_runner" \
  "$perl_rule_generator_runner"

run_security_action() {
  PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
    /usr/bin/perl "$security_action" "$@"
}

run_security_client() {
  PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
    /usr/bin/perl "$perl_client_runner" "$@"
}

run_security_apparmor() {
  PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
    /usr/bin/perl "$perl_apparmor_runner" "$@"
}

run_apparmor_rule_generator() {
  PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
    /usr/bin/perl "$perl_rule_generator_runner" "$@"
}

printf '1..%s\n' "$TEST_COUNT"

packages_ok=true
for package in \
  sudo iproute2 util-linux nmap debsums debsecan chkrootkit rkhunter lynis \
  clamav clamav-freshclam fangfrisch spectre-meltdown-checker fwupd
do
  if ! grep -Eq "(^|[[:space:]])${package}([[:space:]]|$)" "$desktop_cfg"; then
    packages_ok=false
  fi
done
if [ "$packages_ok" = true ] &&
   ! grep -Eq '(^|[[:space:]])systemd-resolved([[:space:]]|$)' "$desktop_cfg" &&
   grep -q '^d-i clamav-freshclam/autoupdate_freshclam select manual$' "$desktop_cfg" &&
   grep -q '^d-i clamav-freshclam/NotifyClamd boolean false$' "$desktop_cfg" &&
   ! grep -Eq '(^|[[:space:]])clamav-daemon([[:space:]]|$)' "$desktop_cfg"; then
  pass "desktop packages provide the security toolkit without enabling a ClamAV scan daemon"
else
  fail "desktop packages provide the security toolkit without enabling a ClamAV scan daemon"
fi

if grep -q '<keybind key="W-m">' "$labwc_rc" &&
   grep -q '<keybind key="C-A-m">' "$labwc_rc" &&
   grep -q 'command="labwc-computer-management"' "$labwc_rc" &&
   ! grep -Eq '<keybind key="C-W-[anpr]">' "$labwc_rc" &&
   grep -q '" Container Management"' "$computer_management" &&
   grep -q '" Remote Desktop"' "$computer_management" &&
   grep -q '" Endpoint Security"' "$computer_management" &&
   ! grep -q '" Firewall Security"' "$computer_management" &&
   grep -q '" Network Management"' "$computer_management" &&
   grep -q '" System Configuration"' "$computer_management" &&
   grep -q '" Phone Management"' "$computer_management" &&
   grep -q '" Backup & Recovery"' "$computer_management" &&
   grep -q '" Hardware & Peripherals"' "$computer_management" &&
   grep -q 'run_command labwc-maintenance-menu security' "$computer_management" &&
   grep -q "category=' Endpoint Security'" "$maintenance_menu" &&
   grep -q '^endpoint_security_menu() {$' "$maintenance_menu" &&
   grep -q "' Security Auditing'" "$maintenance_menu" &&
   grep -q "' Malware & Rootkit Scanning'" "$maintenance_menu" &&
   grep -q "' Vulnerability & Integrity'" "$maintenance_menu" &&
   grep -q "' AppArmor'" "$maintenance_menu" &&
   grep -q "' Firewall Security'" "$maintenance_menu" &&
   grep -q '^run_firewall_menu() ($' "$maintenance_menu" &&
   grep -q "' System'" "$maintenance_menu" &&
   grep -q "' Troubleshooting'" "$maintenance_menu" &&
   grep -q "''|security|system|recovery" "$maintenance_menu"; then
  pass "Super-M and Ctrl-Alt-M open the unified folder-style Computer Management launcher"
else
  fail "Super-M and Ctrl-Alt-M open the unified folder-style Computer Management launcher"
fi

security_actions_ok=true
for label in \
  'Audit Security Posture (lynis)' \
  'Run Rootkit Scan (rkhunter)' \
  'Run Rootkit Scan (chkrootkit)' \
  'Service Security Analysis' \
  'Inspect Specific Service' \
  'Check Firmware Security' \
  'Check CPU Mitigations' \
  'Check Known Vulnerabilities' \
  'Check Package Integrity' \
  'Show ClamAV Signature Status' \
  'Scan File with ClamAV' \
  'Scan Folder Recursively with ClamAV' \
  'Retrieve File Hashsums (SHA-256/SHA-512)' \
  'Create Folder Tree SHA-256 Manifest' \
  'Verify File Against SHA-256' \
  'Update ClamAV Signatures'
do
  grep -Fq "'${label}'" "$maintenance_menu" || security_actions_ok=false
done
account_actions_ok=true
for label in \
  'List User Accounts' \
  'List Non-Sudo Users' \
  'List Groups' \
  'List Sudo Administrators' \
  'List Accounts Without Password' \
  'Audit Sudo Access'
do
  grep -Fq "'${label}'" "$users_groups_menu" || account_actions_ok=false
  grep -Fq "'${label}'" "$maintenance_menu" && account_actions_ok=false
done
moved_network_actions_absent=true
for label in \
  'Show Listening TCP/UDP Ports' \
  'Scan Localhost TCP Ports' \
  'Scan LAN TCP Ports' \
  'Scan Specific LAN IP' \
  'Scan Specific WAN IP'
do
  grep -Fq "'${label}'" "$maintenance_menu" &&
    moved_network_actions_absent=false
done
if [ "$security_actions_ok" = true ] &&
   [ "$account_actions_ok" = true ] &&
   [ "$moved_network_actions_absent" = true ]; then
  pass "Endpoint Security excludes network and account actions moved to dedicated menus"
else
  fail "Endpoint Security excludes network and account actions moved to dedicated menus"
fi

apparmor_actions_ok=true
for label in \
  ' Status & Events' \
  ' Profile Drafts' \
  ' App Modes' \
  ' Policy Tools' \
  'AppArmor Status' \
  'Kernel Enablement' \
  'Unconfined Network Processes' \
  'Features ABI' \
  'Show App Modes' \
  'Complain Events (24h)' \
  'Denied Events (24h)' \
  'Easyprof Draft' \
  'Autodep Base Draft' \
  'Logprof Draft Update' \
  'Genprof Interactive Draft' \
  'List Drafts' \
  'Validate Drafts' \
  'Activate Selected Draft' \
  'Generate New Rules' \
  'Enforce All' \
  'Complain All' \
  'Disable All' \
  'Set App Mode' \
  'Set App Audit Logging' \
  'Reload Modes & Clear Audit' \
  'Disabled Profiles' \
  'Preview Unknown Cleanup' \
  'Reload AppArmor Service'
do
  grep -Fq "'${label}'" "$maintenance_menu" || apparmor_actions_ok=false
done
if [ "$apparmor_actions_ok" = true ] &&
   grep -q '^choose_apparmor_application() {$' "$maintenance_menu" &&
   grep -q '^choose_apparmor_executable() {$' "$maintenance_menu" &&
   grep -q '^run_confirmed_apparmor_profile_tool() {$' "$maintenance_menu" &&
   grep -q '^generate_apparmor_rules() {$' "$maintenance_menu" &&
   grep -q '^set_all_apparmor_desktop_profiles_mode() {$' "$maintenance_menu" &&
   grep -q 'generate-apparmor-rules' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-rule-generation' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-profile-tool' "$maintenance_menu" &&
   grep -q 'set-apparmor-desktop-state' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-desktop-state-change' "$maintenance_menu" &&
   grep -q 'set-apparmor-application-mode' "$maintenance_menu" &&
   grep -q 'set-apparmor-application-audit' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-mode-change' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-audit-change' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-reload' "$maintenance_menu" &&
   grep -q 'confirmed-apparmor-service-reload' "$maintenance_menu"; then
  pass "Endpoint Security exposes categorized AppArmor status, generation, modes, and policy maintenance"
else
  fail "Endpoint Security exposes categorized AppArmor status, generation, modes, and policy maintenance"
fi

system_actions_ok=true
for label in \
  'Show System Overview' \
  'Show Failed Services' \
  'Show Boot Performance' \
  'Show Recent System Errors' \
  'Show Kernel Warnings' \
  'Show Storage Overview' \
  'Manage External Drives' \
  'Show Memory and Swap' \
  'Show Network Overview' \
  'Check Package Health' \
  'List Pending Upgrades' \
  'Inspect Service and Logs' \
  'List Firmware-Capable Devices' \
  'Refresh Firmware Metadata' \
  'Check Firmware Updates' \
  'Apply Firmware Updates' \
  'Show Upgradeable Packages' \
  'Run Unattended Upgrades Now' \
  'Show NVMe SMART Health' \
  'Show NVMe Firmware Slots' \
  'Show NVMe Identify Data' \
  'Show NVMe SMART via smartctl' \
  'Show Btrfs Usage' \
  'Show Btrfs DF Summary' \
  'Show Last Btrfs Scrub Status' \
  'Show Journal Disk Usage' \
  'Rotate and Vacuum Journals by Time' \
  'Rotate and Vacuum Journals by Size' \
  'Top Disk Usage in Root' \
  'Top Disk Usage in Home' \
  'Show Failed System Units' \
  'Show Failed User Units' \
  'Show Timers' \
  'Show PipeWire Status' \
  'Show WirePlumber Status' \
  'Restart PipeWire' \
  'Restart WirePlumber' \
  'Flush DNS Cache' \
  'Reset Resolver Server Features' \
  'Show Resolver Statistics' \
  'Test Mako Notification' \
  'Refresh Waybar Custom Module'
do
  grep -Fq "'${label}'" "$maintenance_menu" || system_actions_ok=false
done
if [ "$system_actions_ok" = true ] &&
   grep -q 'Continue with authorized system action' "$maintenance_menu" &&
   ! grep -Eq -- '--(width|lines)=' "$maintenance_menu"; then
  pass "System exposes the complete requested inspection and maintenance catalog"
else
  fail "System exposes the complete requested inspection and maintenance catalog"
fi

recovery_actions_ok=true
for label in \
  'Restart Waybar' \
  'Restart Audio Services' \
  'Restart Desktop Portals' \
  'Refresh Display Configuration' \
  'Reset Failed System Units' \
  'Restart NetworkManager' \
  'Restart Bluetooth Service' \
  'Restart UDisks Service' \
  'Restart Polkit Service' \
  'Refresh Package Index' \
  'Complete Interrupted Package Configuration' \
  'Repair Package Dependencies' \
  'Rebuild Initramfs' \
  'Refresh GRUB Configuration' \
  'Create Timeshift Recovery Snapshot' \
  'Drop Page Cache Only' \
  'Drop Dentries and Inodes' \
  'Drop All Clean Caches' \
  'Reset zram Swap' \
  'Aggressive Journal Vacuum' \
  'Emergency Btrfs Unused-Chunk Reclaim'
do
  grep -Fq "'${label}'" "$maintenance_menu" || recovery_actions_ok=false
done
if [ "$recovery_actions_ok" = true ] &&
   grep -q 'Continue with authorized recovery action' "$maintenance_menu"; then
  pass "Troubleshooting separates session restarts from explicitly confirmed root repairs"
else
  fail "Troubleshooting separates session restarts from explicitly confirmed root repairs"
fi

pkexec_rejection_output="$TMP_DIR/pkexec-rejection.out"
if PKEXEC_UID=0 \
   PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
   /usr/bin/perl \
     -MLabwcSecurityAction::Command \
     -MLabwcSecurityAction::Root \
     -e 'LabwcSecurityAction::Root->new(command => LabwcSecurityAction::Command->new(path => q{/usr/bin:/bin}))->_require_pkexec_invoker();' \
     >"$pkexec_rejection_output" 2>&1
then
  pkexec_rejection_ok=false
else
  pkexec_rejection_ok=true
fi

apparmor_default_command_ok=false
if PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
   /usr/bin/perl \
     -MLabwcSecurityAction::Root \
     -e 'my $command = LabwcSecurityAction::Root->new()->apparmor()->command(); exit(!$command || !$command->can(q{run}));' \
     >"$TMP_DIR/apparmor-default-command.out" 2>&1
then
  apparmor_default_command_ok=true
fi

if [ "$(sed -n '1p' "$security_action")" = '#!/usr/bin/perl' ] &&
   [ "$(sed -n '1p' "$root_helper")" = '#!/usr/bin/perl' ] &&
   [ "$(sed -n '1p' "$apparmor_rule_generator")" = '#!/usr/bin/perl' ] &&
   grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-security-action';" "$security_action" &&
   grep -Fq 'use LabwcSecurityAction::Client;' "$security_action" &&
   grep -Fq 'exit LabwcSecurityAction::Client->new()->run(@ARGV);' "$security_action" &&
   grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-security-action';" "$root_helper" &&
   grep -Fq 'use LabwcSecurityAction::Root;' "$root_helper" &&
   grep -Fq 'exit LabwcSecurityAction::Root->new()->run(@ARGV);' "$root_helper" &&
   grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-security-action';" "$apparmor_rule_generator" &&
   grep -Fq 'use LabwcSecurityAction::AppArmor::RuleGenerator;' "$apparmor_rule_generator" &&
   grep -Fq 'confirmed-apparmor-rule-generation' "$apparmor_rule_generator" &&
   grep -Fq 'requires a non-root pkexec invoker' "$apparmor_rule_generator" &&
   ! grep -Eq 'show-listening-ports|scan-localhost|scan-lan-network|scan-lan-host|scan-wan-host' "$labwc_security_client_module" &&
   grep -Fq 'default => sub { 536_870_912 }' "$labwc_security_client_module" &&
   grep -Fq 'default => sub { 50_000 }' "$labwc_security_client_module" &&
   grep -Fq 'default => sub { 107_374_182_400 }' "$labwc_security_client_module" &&
   grep -Fq 'sub _run_clamav_scan {' "$labwc_security_client_module" &&
   grep -Fq 'sub _run_folder_hash_manifest {' "$labwc_security_client_module" &&
   grep -Fq 'sub _run_verify_file_sha256 {' "$labwc_security_client_module" &&
   grep -Fq "'Security Maintenance'" "$labwc_security_client_module" &&
   grep -Fq "'x-labwc.maintenance'" "$labwc_security_client_module" &&
   grep -Fq "'--max-filesize=512M'" "$labwc_security_client_module" &&
   grep -Fq "'--max-scansize=2G'" "$labwc_security_client_module" &&
   grep -Fq "tag   => 'managed-clamav-scan'," "$labwc_security_client_module" &&
   grep -Fq 'Mode: report only; infected files are never moved or deleted' "$labwc_security_client_module" &&
   grep -Fq "path => '/usr/sbin:/usr/bin:/sbin:/bin'," "$labwc_security_root_module" &&
   grep -Fq 'sub _require_pkexec_invoker {' "$labwc_security_root_module" &&
   grep -Fq 'my $uid = $ENV{PKEXEC_UID} // q{};' "$labwc_security_root_module" &&
   grep -Fq '$uid =~ /\A[1-9][0-9]*\z/' "$labwc_security_root_module" &&
   grep -Fq "return \$self->_run_scanner('managed-debsecan-scan', 'debsecan');" "$labwc_security_root_module" &&
   grep -Fq "return \$self->_run_scanner('managed-debsums-scan', 'debsums', '-s');" "$labwc_security_root_module" &&
   grep -Fq "'/var/log/managed/lynis/lynis.log'," "$labwc_security_root_module" &&
   grep -Fq "'/var/log/managed/lynis/lynis-report.dat'," "$labwc_security_root_module" &&
   grep -Fq "'/var/log/managed/rkhunter/rkhunter.log'," "$labwc_security_root_module" &&
   grep -Fq "return \$self->_exec('systemctl', 'start', '--wait', 'managed-clamav-signature-update.service');" "$labwc_security_root_module" &&
   grep -Fq "return \$self->_fatal('privileged security helper must run as root') if \$> != 0;" "$labwc_security_root_module" &&
   ! grep -Eq 'validate_ipv4|scan-lan-network|scan-folder|clamscan' "$labwc_security_root_module" &&
   grep -Fq "default => sub { '/etc/apparmor/managed-modes.conf' }" "$labwc_security_apparmor_module" &&
   grep -Fq "default => sub { '/var/log/managed/apparmor/apparmor.log' }" "$labwc_security_apparmor_module" &&
   grep -Fq "default => sub { '/var/lib/apparmor/easyprof' }" "$labwc_security_apparmor_module" &&
   grep -Fq "default => sub { '/var/lib/apparmor/drafts' }" "$labwc_security_apparmor_module" &&
   grep -Fq "default => sub { '/var/lib/apparmor/backup' }" "$labwc_security_apparmor_module" &&
   grep -Fq 'isa     => Object,' "$labwc_security_apparmor_module" &&
   [ "$apparmor_default_command_ok" = true ] &&
   grep -Fq 'sub _validate_executable {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub _publish_generated_drafts {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub _prepare_logprof_input {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub activate_draft {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub _update_modes {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub set_application_mode {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub set_desktop_state {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub set_application_audit {' "$labwc_security_apparmor_module" &&
   grep -Fq 'sub generate_rules {' "$labwc_security_apparmor_module" &&
   grep -Fq "default => sub { '/usr/local/libexec/apparmor-generate-rules' }" "$labwc_security_apparmor_module" &&
   ! grep -Fq 'sub _wrapper_profiles {' "$labwc_security_apparmor_module" &&
   grep -Fq 'return map { $_->[2] } $self->_mode_rows();' "$labwc_security_apparmor_module" &&
   grep -Fq "'all declared managed profiles'," "$labwc_security_apparmor_module" &&
   grep -Fq 'AppArmor event log contains no parseable complain-mode or enforce-mode events' "$labwc_security_apparmor_module" &&
   grep -Fq 'AppArmor draft profile labels do not match the installed target' "$labwc_security_apparmor_module" &&
   grep -Fq 'the previous profile will be restored' "$labwc_security_apparmor_module" &&
   grep -Fq '$stat[4] == 0' "$labwc_security_apparmor_module" &&
   grep -Fq '($stat[2] & 0022) == 0' "$labwc_security_apparmor_module" &&
   grep -Fq "'generate-apparmor-rules'       => 'confirmed-apparmor-rule-generation'," "$labwc_security_client_module" &&
   grep -Fq "if (\$action eq 'generate-apparmor-rules')" "$labwc_security_root_module" &&
   grep -Fq 'default => sub { 16_777_216 }' "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq 'default => sub { 20_000 }' "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq 'default => sub { 4_096 }' "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq 'O_RDONLY | O_NOFOLLOW' "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq 'managed AppArmor event log changed while it was being opened' "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq 'while being read' "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq "'requested_mask'," "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq "'denied_mask'," "$labwc_security_apparmor_audit_log_module" &&
   grep -Fq 'sub _local_include_map {' "$labwc_security_apparmor_profile_index_module" &&
   grep -Fq 'profile has no unambiguous local include for generated rules' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq '# BEGIN managed generated AppArmor rules' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq 'sub _acquire_lock {' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq 'sub _publish_atomic {' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq 'sub _rollback {' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq 'sub _source_disabled {' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq 'generated AppArmor local include is outside the approved policy root' "$labwc_security_apparmor_rule_generator_module" &&
   grep -Fq 'high-risk capability requires manual review' "$labwc_security_apparmor_rule_renderer_module" &&
   grep -Fq 'network family requires manual review' "$labwc_security_apparmor_rule_renderer_module" &&
   grep -Fq 'unsupported or unsafe file denied mask' "$labwc_security_apparmor_rule_renderer_module" &&
   grep -Fq 'link permission requires a reviewed source and target pair' "$labwc_security_apparmor_rule_renderer_module" &&
   grep -Fq 'network protocol $protocol is incompatible with socket type $socket_type' "$labwc_security_apparmor_rule_renderer_module" &&
   grep -Fq 'system { $argv[0] } @argv;' "$labwc_security_command_module" &&
   grep -Fq 'exec { $argv[0] } @argv;' "$labwc_security_command_module" &&
   ! grep -Fq '/bin/sh -c' "$labwc_security_command_module" &&
   grep -Fq "default => sub { '/run/rsyslog/managed-security-scanners/scanner.sock' }" "$labwc_security_scanner_log_module" &&
   grep -Fq "setlogsock(['native', 'unix'])" "$labwc_security_scanner_log_module" &&
   grep -Fq 'sub _wait_child {' "$labwc_security_scanner_log_module" &&
   grep -Fq 'sub _restore_default_log_socket {' "$labwc_security_scanner_log_module" &&
   [ "$pkexec_rejection_ok" = true ] &&
   grep -q 'privileged security helper must be invoked by a non-root desktop user through pkexec' "$pkexec_rejection_output"; then
  pass "Security keeps only security, ClamAV, and bounded hash actions through typed Perl modules"
else
  fail "Security keeps only security, ClamAV, and bounded hash actions through typed Perl modules"
fi

if grep -q '^require_pkexec_invoker() {$' "$system_root_helper" &&
   grep -q "journalctl --unit \"\\\$service_name\" --boot --no-pager --lines 200" "$system_root_helper" &&
   grep -q 'systemd-analyze blame --no-pager | sed -n '\''1,50p'\''' "$system_root_helper" &&
   grep -q '^validate_nvme_controller() {$' "$system_root_helper" &&
   grep -q "grep -Eq '\^/dev/nvme\\[0-9\\]+\\\$'" "$system_root_helper" &&
   grep -q 'exec fwupdmgr update --assume-yes' "$system_root_helper" &&
   grep -q 'exec systemctl start --wait apt-daily-upgrade.service' "$system_root_helper" &&
   grep -Fq "exec nvme smart-log \"\$1\"" "$system_root_helper" &&
   grep -Fq "exec smartctl --all \"\$1\"" "$system_root_helper" &&
   grep -Fq "journalctl \"--vacuum-time=\$retention\"" "$system_root_helper" &&
   grep -Fq "journalctl \"--vacuum-size=\$retention\"" "$system_root_helper" &&
   grep -q '^systemd_resolved_active() {$' "$system_root_helper" &&
   grep -q '^networkmanager_active() {$' "$system_root_helper" &&
   grep -q 'exec resolvectl reset-server-features' "$system_root_helper" &&
   grep -q 'exec nmcli general reload dns-full' "$system_root_helper" &&
   grep -q 'systemctl --user restart pipewire.service pipewire-pulse.service' "$system_action" &&
   grep -Fq '"--signal=${waybar_signal}"' "$system_action" &&
   grep -Fq 'waybar.service' "$system_action" &&
   ! grep -Eq '(^|[^[:alnum:]_])(pgrep|pkill|pidof)([^[:alnum:]_]|$)' "$system_action" &&
   grep -q '^notify_action_result() {$' "$system_action" &&
   grep -q -- '-a "System Maintenance"' "$system_action" &&
   grep -q 'notify_action_result "$action_status" "$action"' "$system_action" &&
   grep -q '^require_pkexec_invoker() {$' "$recovery_root_helper" &&
   grep -q 'confirmed-recovery-action' "$recovery_root_helper" &&
   grep -q '^    exec apt-get \\$' "$recovery_root_helper" &&
   grep -q '^      --fix-broken \\$' "$recovery_root_helper" &&
   grep -q '^      --no-remove \\$' "$recovery_root_helper" &&
   grep -q '^      --no-install-recommends \\$' "$recovery_root_helper" &&
   grep -q '^      --no-install-suggests$' "$recovery_root_helper" &&
   grep -q 'exec update-initramfs -u -k all' "$recovery_root_helper" &&
   grep -q 'findmnt --noheadings --raw --output FSTYPE --target /' "$recovery_root_helper" &&
   grep -q 'btrfs) snapshot_mode=--btrfs' "$recovery_root_helper" &&
   grep -q '\*) snapshot_mode=--rsync' "$recovery_root_helper" &&
   grep -q '^notify_action_result() {$' "$recovery_action" &&
   grep -q -- '-a "Recovery"' "$recovery_action" &&
   grep -q 'notify_action_result "$action_status" "$action"' "$recovery_action" &&
   grep -Fq "printf '%s\\n' \"\$cache_selector\" >/proc/sys/vm/drop_caches" "$recovery_root_helper" &&
   grep -q 'systemctl restart zram-setup.service' "$recovery_root_helper" &&
   grep -q 'journalctl --vacuum-time=3d' "$recovery_root_helper" &&
   grep -q 'exec btrfs balance start -dusage=0 -musage=0 /' "$recovery_root_helper" &&
   ! grep -Eq '(^|[[:space:]])eval([[:space:]]|$)|/bin/sh -c' "$system_root_helper" &&
   ! grep -Eq '(^|[[:space:]])eval([[:space:]]|$)|/bin/sh -c' "$recovery_root_helper"; then
  pass "System and Troubleshooting helpers enforce fixed, confirmed maintenance allowlists"
else
  fail "System and Troubleshooting helpers enforce fixed, confirmed maintenance allowlists"
fi

desktop_policy_files=
if [ -d "$desktop_policy_dir" ]; then
  desktop_policy_files=$(find "$desktop_policy_dir" -maxdepth 1 -type f -print)
fi
if grep -q 'org.freedesktop.policykit.exec' "$polkit_rule" &&
   grep -q 'subject.active === true && subject.local === true' "$polkit_rule" &&
   grep -q 'subject.isInGroup(ADMIN_GROUP)' "$polkit_rule" &&
   grep -q 'return polkit.Result.AUTH_ADMIN;' "$polkit_rule" &&
   [ -r "$desktop_polkit_dir/00-admin-identities.rules" ] &&
   [ -r "$desktop_polkit_dir/04-fwupd-refresh.rules" ] &&
   [ -r "$desktop_polkit_dir/70-hardware-peripherals.rules" ] &&
   [ ! -d "$shared_polkit_dir" ] &&
   [ -z "$desktop_policy_files" ]; then
  pass "security helper reuses the desktop-owned pkexec policy without custom actions"
else
  fail "security helper reuses the desktop-owned pkexec policy without custom actions"
fi

if grep -q '^User=clamav$' "$update_service" &&
   [ "$(grep -c '^ConditionFileIsExecutable=' "$update_service")" -eq 3 ] &&
   ! grep -q '^ConditionPathIsExecutable=' "$update_service" &&
   grep -q '^NoNewPrivileges=false$' "$update_service" &&
   grep -q '^ProtectSystem=strict$' "$update_service" &&
   grep -q '^OnCalendar=\*-\*-\* 03:00:00$' "$update_timer" &&
   grep -q '^Persistent=true$' "$update_timer" &&
   grep -q '^RandomizedDelaySec=2h$' "$update_timer" &&
   grep -q '^\[sanesecurity\]$' "$fangfrisch_config" &&
   grep -q '^\[urlhaus\]$' "$fangfrisch_config" &&
   grep -q 'desktop_enable_unit_if_available managed-clamav-signature-update.timer system' "$components" &&
   grep -q 'desktop_mask_unit_if_available clamav-freshclam.service system' "$components" &&
   grep -q 'desktop_mask_unit_if_available fangfrisch.timer system' "$components"; then
  pass "official and external ClamAV signatures update daily without competing vendor schedules"
else
  fail "official and external ClamAV signatures update daily without competing vendor schedules"
fi

if grep -q 'desktop_stage_role_asset usr/local/bin/labwc-maintenance-menu /usr/local/bin/labwc-maintenance-menu 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-external-drives /usr/local/bin/labwc-external-drives 0755' "$components" &&
   grep -q '^desktop_labwc_security_action_perl_modules() {$' "$components" &&
   grep -q '^LabwcSecurityAction/AppArmor.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/AppArmor/AuditLog.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/AppArmor/ProfileIndex.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/AppArmor/RuleGenerator.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/AppArmor/RuleRenderer.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/Client.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/Command.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/Logger.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/Root.pm$' "$components" &&
   grep -q '^LabwcSecurityAction/ScannerLog.pm$' "$components" &&
   grep -q 'desktop_stage_labwc_security_action_perl_modules' "$components" &&
   grep -q 'usr/local/lib/perl5/site_perl/labwc-security-action/${labwc_security_action_module}' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-security-action /usr/local/bin/labwc-security-action 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-users-groups-menu /usr/local/bin/labwc-users-groups-menu 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-system-action /usr/local/bin/labwc-system-action 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/bin/labwc-recovery-action /usr/local/bin/labwc-recovery-action 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/libexec/apparmor-generate-rules /usr/local/libexec/apparmor-generate-rules 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/libexec/labwc-security-action-root /usr/local/libexec/labwc-security-action-root 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/libexec/labwc-system-action-root /usr/local/libexec/labwc-system-action-root 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/libexec/labwc-recovery-action-root /usr/local/libexec/labwc-recovery-action-root 0755' "$components" &&
   grep -q 'desktop_stage_role_asset usr/local/libexec/managed-clamav-signature-update /usr/local/libexec/managed-clamav-signature-update 0755' "$components" &&
   grep -q 'desktop_enable_unit_if_available systemd-resolved.service system' "$components" &&
   grep -q '/usr/local/bin/labwc-maintenance-menu' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-users-groups-menu' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-external-drives' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-system-action' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-recovery-action' "$desktop_verify" &&
   grep -q '/usr/local/libexec/apparmor-generate-rules' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-security-action-root' "$desktop_verify" &&
   grep -q '/usr/local/libexec/rsyslog-managed-security-socket' "$desktop_verify" &&
   grep -q '^  labwc-security-action \\$' "$desktop_verify"; then
  pass "desktop staging and target verification cover the maintenance launcher boundary"
else
  fail "desktop staging and target verification cover the maintenance launcher boundary"
fi

apparmor_mode_root="$TMP_DIR/apparmor-modes"
apparmor_mode_config="$apparmor_mode_root/managed-modes.conf"
apparmor_mode_duplicate="$apparmor_mode_root/managed-modes-duplicate.conf"
apparmor_mode_helper="$apparmor_mode_root/apparmor-managed-modes"
apparmor_mode_log="$apparmor_mode_root/mode-helper.log"
apparmor_mode_profile_dir="$apparmor_mode_root/profiles"
apparmor_mode_draft_dir="$apparmor_mode_root/drafts"
apparmor_mode_easyprof_dir="$apparmor_mode_root/easyprof"
apparmor_mode_backup_dir="$apparmor_mode_root/backups"
apparmor_mode_output="$apparmor_mode_root/application-modes.out"
apparmor_mode_expected="$apparmor_mode_root/application-modes.expected"
apparmor_mode_actual="$apparmor_mode_root/application-modes.actual"
apparmor_mode_command_path="$apparmor_mode_root/bin:/usr/bin:/bin"
mkdir -p \
  "$apparmor_mode_profile_dir" \
  "$apparmor_mode_draft_dir" \
  "$apparmor_mode_easyprof_dir" \
  "$apparmor_mode_backup_dir"
cp "$shared_target/etc/apparmor/managed-modes.conf.tmpl" "$apparmor_mode_config"
sed -i \
  's/^__DESKTOP_APPARMOR_STATE__ /complain /' \
  "$apparmor_mode_config"
chmod 0644 "$apparmor_mode_config"
cat >"$apparmor_mode_helper" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' invoked >>"${APPARMOR_MODE_LOG:?}"
EOF
chmod 0755 "$apparmor_mode_helper"
if LABWC_TEST_COMMAND_PATH="$apparmor_mode_command_path" \
   LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_mode_easyprof_dir" \
   LABWC_TEST_APPARMOR_MODE_CONFIG="$apparmor_mode_config" \
   LABWC_TEST_APPARMOR_MODE_HELPER="$apparmor_mode_helper" \
   LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR="$apparmor_mode_backup_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_mode_profile_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_mode_draft_dir" \
   APPARMOR_MODE_LOG="$apparmor_mode_log" \
   run_security_apparmor \
     set-application-mode \
     totem \
     enforce \
     confirmed-apparmor-mode-change >/dev/null 2>&1 &&
   grep -qx 'enforce required usr.bin.totem -' "$apparmor_mode_config" &&
   grep -qx 'complain required managed-desktop-wrappers -' "$apparmor_mode_config" &&
   grep -qx 'complain required managed-system-wrappers -' "$apparmor_mode_config" &&
   grep -qx 'complain required usr.sbin.aa-status -' "$apparmor_mode_config" &&
   grep -qx 'complain required usr.bin.qoredb -' "$apparmor_mode_config" &&
   grep -qx 'complain required usr.bin.gridline -' "$apparmor_mode_config" &&
   [ "$(cat "$apparmor_mode_log")" = invoked ] &&
   LABWC_TEST_COMMAND_PATH="$apparmor_mode_command_path" \
   LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_mode_easyprof_dir" \
   LABWC_TEST_APPARMOR_MODE_CONFIG="$apparmor_mode_config" \
   LABWC_TEST_APPARMOR_MODE_HELPER="$apparmor_mode_helper" \
   LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR="$apparmor_mode_backup_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_mode_profile_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_mode_draft_dir" \
   run_security_apparmor \
     print-application-modes >"$apparmor_mode_output" 2>/dev/null &&
   grep -Eq 'managed-desktop-wrappers[[:space:]]+complain$' "$apparmor_mode_output" &&
   grep -Eq 'managed-system-wrappers[[:space:]]+complain$' "$apparmor_mode_output" &&
   grep -Eq 'usr.sbin.aa-status[[:space:]]+complain$' "$apparmor_mode_output" &&
   awk 'NR > 2 { print $(NF - 1), $NF }' "$apparmor_mode_output" |
     LC_ALL=C sort >"$apparmor_mode_actual" &&
   awk '$0 !~ /^[[:space:]]*(#|$)/ { print $3, $1 }' "$apparmor_mode_config" |
     LC_ALL=C sort >"$apparmor_mode_expected" &&
   cmp -s "$apparmor_mode_expected" "$apparmor_mode_actual" &&
   {
     cat "$apparmor_mode_config"
     printf '%s\n' 'enforce required usr.bin.totem -'
   } >"$apparmor_mode_duplicate" &&
   ! LABWC_TEST_COMMAND_PATH="$apparmor_mode_command_path" \
     LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_mode_easyprof_dir" \
     LABWC_TEST_APPARMOR_MODE_CONFIG="$apparmor_mode_duplicate" \
     LABWC_TEST_APPARMOR_MODE_HELPER="$apparmor_mode_helper" \
     LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR="$apparmor_mode_backup_dir" \
     LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_mode_profile_dir" \
     LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_mode_draft_dir" \
     APPARMOR_MODE_LOG="$apparmor_mode_log" \
     run_security_apparmor \
       set-application-mode \
       totem \
       enforce \
       confirmed-apparmor-mode-change >/dev/null 2>&1 &&
   : >"$apparmor_mode_log" &&
   LABWC_TEST_COMMAND_PATH="$apparmor_mode_command_path" \
   LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_mode_easyprof_dir" \
   LABWC_TEST_APPARMOR_MODE_CONFIG="$apparmor_mode_config" \
   LABWC_TEST_APPARMOR_MODE_HELPER="$apparmor_mode_helper" \
   LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR="$apparmor_mode_backup_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_mode_profile_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_mode_draft_dir" \
   APPARMOR_MODE_LOG="$apparmor_mode_log" \
   run_security_apparmor \
     set-desktop-state \
     complain \
     confirmed-apparmor-desktop-state-change >/dev/null 2>&1 &&
   awk '
     $0 !~ /^[[:space:]]*(#|$)/ {
       rows++
       if ($1 != "complain") {
         exit 1
       }
     }
     END { exit(rows == 71 ? 0 : 1) }
   ' "$apparmor_mode_config" &&
   grep -qx 'complain required managed-desktop-wrappers -' "$apparmor_mode_config" &&
   grep -qx 'complain required managed-system-wrappers -' "$apparmor_mode_config" &&
   grep -qx 'complain required usr.sbin.aa-status -' "$apparmor_mode_config" &&
   grep -qx 'complain required whisper-local-transcription -' "$apparmor_mode_config" &&
   grep -qx 'complain required usr.bin.totem -' "$apparmor_mode_config" &&
   grep -qx 'complain if-executable chromium /usr/bin/chromium' "$apparmor_mode_config" &&
   grep -qx 'complain if-executable vivaldi-bin /usr/bin/vivaldi-stable' "$apparmor_mode_config" &&
   grep -qx 'complain required usr.bin.pwsh -' "$apparmor_mode_config" &&
   [ "$(cat "$apparmor_mode_log")" = invoked ] &&
   : >"$apparmor_mode_log" &&
   LABWC_TEST_COMMAND_PATH="$apparmor_mode_command_path" \
   LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_mode_easyprof_dir" \
   LABWC_TEST_APPARMOR_MODE_CONFIG="$apparmor_mode_config" \
   LABWC_TEST_APPARMOR_MODE_HELPER="$apparmor_mode_helper" \
   LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR="$apparmor_mode_backup_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_mode_profile_dir" \
   LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_mode_draft_dir" \
   APPARMOR_MODE_LOG="$apparmor_mode_log" \
   run_security_apparmor \
     set-desktop-state \
     disable \
     confirmed-apparmor-desktop-state-change >/dev/null 2>&1 &&
   awk '
     $0 !~ /^[[:space:]]*(#|$)/ {
       rows++
       if ($1 != "disable") {
         exit 1
       }
     }
     END { exit(rows == 71 ? 0 : 1) }
   ' "$apparmor_mode_config" &&
   grep -qx 'disable required managed-desktop-wrappers -' "$apparmor_mode_config" &&
   grep -qx 'disable required managed-system-wrappers -' "$apparmor_mode_config" &&
   grep -qx 'disable required usr.sbin.aa-status -' "$apparmor_mode_config" &&
   grep -qx 'disable required whisper-local-transcription -' "$apparmor_mode_config" &&
   grep -qx 'disable required usr.bin.totem -' "$apparmor_mode_config" &&
   grep -qx 'disable if-executable chromium /usr/bin/chromium' "$apparmor_mode_config" &&
   grep -qx 'disable required usr.bin.pwsh -' "$apparmor_mode_config" &&
   [ "$(cat "$apparmor_mode_log")" = invoked ] &&
   ! grep -REq 'waybar[.]service|labwc-session[.]target|systemctl[[:space:]]+--user' \
     "$labwc_security_apparmor_module" \
     "$apparmor_managed_modes_module_root" &&
   ! grep -REq 'pkill[[:space:]].*(waybar|labwc)|killall[[:space:]].*(waybar|labwc)' \
     "$labwc_security_apparmor_module" \
     "$apparmor_managed_modes_module_root"; then
  pass "installer-rendered AppArmor modes support isolated application changes and administrative global disable"
else
  fail "installer-rendered AppArmor modes support isolated application changes and administrative global disable"
fi

bin_dir="$TMP_DIR/bin"
responses="$TMP_DIR/responses"
fuzzel_log="$TMP_DIR/fuzzel.log"
action_log="$TMP_DIR/action.log"
hash_fixture="$TMP_DIR/home/hash fixture.bin"
hash_folder="$TMP_DIR/home/hash folder"
hash_nested_folder="$hash_folder/nested"
hash_folder_file="$hash_folder/root file.txt"
hash_nested_file="$hash_nested_folder/nested file.txt"
mkdir -p "$bin_dir" "$TMP_DIR/home" "$hash_nested_folder"
printf '%s\n' 'maintenance hash fixture' >"$hash_fixture"
printf '%s\n' 'root folder hash fixture' >"$hash_folder_file"
printf '%s\n' 'nested maintenance hash fixture' >"$hash_nested_file"
expected_hash=$(sha256sum <"$hash_fixture" | awk '{print $1}')
expected_sha512=$(sha512sum <"$hash_fixture" | awk '{print $1}')
folder_expected_hash=$(sha256sum <"$hash_folder_file" | awk '{print $1}')
nested_expected_hash=$(sha256sum <"$hash_nested_file" | awk '{print $1}')
cat >"$responses" <<EOF
 Endpoint Security
 Malware & Rootkit Scanning
Show ClamAV Signature Status
Scan File with ClamAV
$hash_fixture
Scan Folder Recursively with ClamAV
$hash_folder
← Back
 Vulnerability & Integrity
Retrieve File Hashsums (SHA-256/SHA-512)
$hash_fixture
Create Folder Tree SHA-256 Manifest
$hash_folder
Verify File Against SHA-256
$hash_fixture
$expected_hash
← Back
 AppArmor
 Status & Events
AppArmor Status
Kernel Enablement
Unconfined Network Processes
Features ABI
Complain Events (24h)
Denied Events (24h)
← Back
 Profile Drafts
Easyprof Draft
/usr/bin/true
Continue with AppArmor profile tool
Autodep Base Draft
/usr/bin/true
Continue with AppArmor profile tool
Logprof Draft Update
Continue with AppArmor profile tool
Genprof Interactive Draft
/usr/bin/true
Continue with AppArmor profile tool
List Drafts
Validate Drafts
Activate Selected Draft
drafts/valid-profile
Continue with AppArmor draft activation
← Back
 App Modes
Show App Modes
Generate New Rules
Continue with AppArmor rule generation
Complain All
Continue with all-profile AppArmor mode change
Set App Mode
Bitwarden
Complain
Continue with AppArmor mode change
Set App Audit Logging
Bitwarden
Enable Audit Mode
Continue with AppArmor audit change
Reload Modes & Clear Audit
Continue with AppArmor reload
← Back
 Policy Tools
Disabled Profiles
Preview Unknown Cleanup
Reload AppArmor Service
Continue with AppArmor service reload
← Back
← Back
 Firewall Security
← Back
EOF
cat >"$bin_dir/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '%s\n' 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$bin_dir/systemctl" <<'EOF'
#!/bin/sh
if [ "${1:-}" = list-unit-files ]; then
  printf '%s\n' 'greetd.service enabled'
fi
EOF
cat >"$bin_dir/ip" <<'EOF'
#!/bin/sh
printf '%s\n' '192.168.50.0/24 dev eth0 proto kernel scope link src 192.168.50.10'
EOF
cat >"$bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >>"${FUZZEL_LOG:?}"
response=$(sed -n '1p' "${FUZZEL_RESPONSES:?}")
sed '1d' "$FUZZEL_RESPONSES" >"${FUZZEL_RESPONSES}.next"
mv "${FUZZEL_RESPONSES}.next" "$FUZZEL_RESPONSES"
printf '%s\n' "$response"
EOF
cat >"$bin_dir/labwc-security-action" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = --list-apparmor-draft-candidates ]; then
  printf '%s\n' drafts/valid-profile
  exit 0
fi
printf '%s\n' "$*" >>"${SECURITY_ACTION_LOG:?}"
EOF
cat >"$bin_dir/labwc-firewall-menu" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' opened >>"${FIREWALL_MENU_LOG:?}"
EOF
chmod 0755 "$bin_dir"/*

if PATH="$bin_dir:/usr/bin:/bin" \
   HOME="$TMP_DIR/home" \
   FUZZEL_LOG="$fuzzel_log" \
   FUZZEL_RESPONSES="$responses" \
   SECURITY_ACTION_LOG="$action_log" \
   FIREWALL_MENU_LOG="$TMP_DIR/firewall-menu.log" \
   /bin/sh "$maintenance_menu" &&
   [ "$(cat "$action_log")" = "show-clamav-signature-status
scan-file-clamav $hash_fixture
scan-folder-clamav $hash_folder
retrieve-file-hashes $hash_fixture
create-folder-hash-manifest $hash_folder
verify-file-sha256 $hash_fixture $expected_hash
apparmor-status
apparmor-enabled
apparmor-unconfined
apparmor-features-abi
audit-apparmor-complain
audit-apparmor-denied
aa-easyprof /usr/bin/true confirmed-apparmor-profile-tool
aa-autodep /usr/bin/true confirmed-apparmor-profile-tool
aa-logprof confirmed-apparmor-profile-tool
aa-genprof /usr/bin/true confirmed-apparmor-profile-tool
apparmor-list-drafts
apparmor-validate-drafts
apparmor-activate-draft drafts valid-profile confirmed-apparmor-draft-activation
apparmor-managed-application-modes
generate-apparmor-rules confirmed-apparmor-rule-generation
set-apparmor-desktop-state complain confirmed-apparmor-desktop-state-change
set-apparmor-application-mode bitwarden complain confirmed-apparmor-mode-change
set-apparmor-application-audit bitwarden enable confirmed-apparmor-audit-change
reload-apparmor-managed-modes confirmed-apparmor-reload
apparmor-list-disabled-profiles
aa-remove-unknown-dry-run
reload-apparmor-service confirmed-apparmor-service-reload" ] &&
   [ "$(cat "$TMP_DIR/firewall-menu.log")" = opened ] &&
   grep -q ' Endpoint Security' "$fuzzel_log" &&
   grep -q ' Malware & Rootkit Scanning' "$fuzzel_log" &&
   grep -q ' Vulnerability & Integrity' "$fuzzel_log" &&
   grep -q ' AppArmor' "$fuzzel_log" &&
   grep -q ' Status & Events' "$fuzzel_log" &&
   grep -q ' Profile Drafts' "$fuzzel_log" &&
   grep -q ' App Modes' "$fuzzel_log" &&
   grep -q 'Generate New Rules' "$fuzzel_log" &&
   grep -q 'Continue with AppArmor rule generation' "$fuzzel_log" &&
   grep -q ' Policy Tools' "$fuzzel_log" &&
   grep -q ' Firewall Security' "$fuzzel_log" &&
   grep -q ' System' "$fuzzel_log" &&
   grep -q ' Troubleshooting' "$fuzzel_log" &&
   ! grep -q 'exec labwc-security-action' "$maintenance_menu"; then
  pass "nested Endpoint Security dispatches scanning, categorized AppArmor, and Firewall Security"
else
  fail "nested Endpoint Security dispatches scanning, categorized AppArmor, and Firewall Security"
fi

hash_output="$TMP_DIR/hash-output.log"
invalid_hash_output="$TMP_DIR/invalid-hash-output.log"
cat >"$bin_dir/pkexec" <<'EOF'
#!/bin/sh
printf '%s\n' invoked >"${PKEXEC_LOG:?}"
exit 99
EOF
chmod 0755 "$bin_dir/pkexec"
if PATH="$bin_dir:/usr/bin:/bin" \
   PKEXEC_LOG="$TMP_DIR/pkexec.log" \
   run_security_action --run retrieve-file-hashes "$hash_fixture" >"$hash_output" 2>&1 &&
   grep -Fq "File: $hash_fixture" "$hash_output" &&
   grep -Fq "SHA-256: $expected_hash" "$hash_output" &&
   grep -Fq "SHA-512: $expected_sha512" "$hash_output" &&
   grep -q 'Action finished with status 0' "$hash_output" &&
   [ ! -e "$TMP_DIR/pkexec.log" ] &&
   ! PATH="$bin_dir:/usr/bin:/bin" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     run_security_action --run retrieve-file-hashes "$TMP_DIR/home" >"$invalid_hash_output" 2>&1 &&
   grep -q 'file hash path is not a regular file' "$invalid_hash_output"; then
  pass "file hash retrieval validates a regular file and computes bounded SHA-256 and SHA-512 without pkexec"
else
  fail "file hash retrieval validates a regular file and computes bounded SHA-256 and SHA-512 without pkexec"
fi

manifest_output="$TMP_DIR/manifest-output.log"
if PATH="$bin_dir:/usr/bin:/bin" \
   XDG_STATE_HOME="$TMP_DIR/state" \
   PKEXEC_LOG="$TMP_DIR/pkexec.log" \
   run_security_action --run create-folder-hash-manifest "$hash_folder" >"$manifest_output" 2>&1; then
  manifest_file=$(
    find "$TMP_DIR/state/labwc/security-reports" -maxdepth 1 -type f -print -quit
  )
else
  manifest_file=
fi
if [ -n "$manifest_file" ] &&
   [ "$(stat --format=%a -- "$manifest_file")" = 600 ] &&
   grep -Fq "# Root: $hash_folder" "$manifest_file" &&
   grep -Fq "$folder_expected_hash" "$manifest_file" &&
   grep -Fq "$nested_expected_hash" "$manifest_file" &&
   grep -Fq "Report: $manifest_file" "$manifest_output" &&
   grep -q 'Action finished with status 0' "$manifest_output" &&
   [ ! -e "$TMP_DIR/pkexec.log" ]; then
  pass "folder hashing writes a private bounded recursive SHA-256 manifest without following other filesystems"
else
  fail "folder hashing writes a private bounded recursive SHA-256 manifest without following other filesystems"
fi

verify_output="$TMP_DIR/verify-output.log"
verify_mismatch_output="$TMP_DIR/verify-mismatch-output.log"
invalid_digest_output="$TMP_DIR/invalid-digest-output.log"
wrong_hash=0000000000000000000000000000000000000000000000000000000000000000
if PATH="$bin_dir:/usr/bin:/bin" \
   PKEXEC_LOG="$TMP_DIR/pkexec.log" \
   run_security_action --run verify-file-sha256 "$hash_fixture" "$expected_hash" >"$verify_output" 2>&1 &&
   grep -q 'Result: MATCH' "$verify_output" &&
   ! PATH="$bin_dir:/usr/bin:/bin" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     run_security_action --run verify-file-sha256 "$hash_fixture" "$wrong_hash" >"$verify_mismatch_output" 2>&1 &&
   grep -q 'Result: MISMATCH' "$verify_mismatch_output" &&
   ! PATH="$bin_dir:/usr/bin:/bin" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     run_security_action --run verify-file-sha256 "$hash_fixture" invalid >"$invalid_digest_output" 2>&1 &&
   grep -q 'exactly 64 hexadecimal characters' "$invalid_digest_output" &&
   [ ! -e "$TMP_DIR/pkexec.log" ]; then
  pass "SHA-256 verification distinguishes matches, mismatches, and malformed expected digests"
else
  fail "SHA-256 verification distinguishes matches, mismatches, and malformed expected digests"
fi

apparmor_draft_test_root="$TMP_DIR/apparmor-draft-review"
apparmor_easyprof_dir="$apparmor_draft_test_root/easyprof"
apparmor_profile_dir="$apparmor_draft_test_root/drafts"
apparmor_list_output="$apparmor_draft_test_root/list.out"
apparmor_validate_output="$apparmor_draft_test_root/validate.out"
apparmor_invalid_output="$apparmor_draft_test_root/invalid.out"
apparmor_candidates_output="$apparmor_draft_test_root/candidates.out"
apparmor_parser_log="$apparmor_draft_test_root/parser.log"
mkdir -p "$apparmor_easyprof_dir" "$apparmor_profile_dir"
cat >"$apparmor_easyprof_dir/valid-profile" <<'EOF'
profile valid-profile /usr/bin/true {
  /usr/bin/true rix,
}
EOF
ln -s valid-profile "$apparmor_easyprof_dir/ignored-symlink"
cat >"$bin_dir/apparmor_parser" <<'EOF'
#!/bin/sh
set -eu
last_argument=
for argument in "$@"; do
  last_argument=$argument
done
printf '%s\n' "$last_argument" >>"${APPARMOR_PARSER_LOG:?}"
if grep -q '^invalid$' "$last_argument"; then
  exit 1
fi
EOF
chmod 0755 "$bin_dir/apparmor_parser"
rm -f -- "$TMP_DIR/pkexec.log"

if grep -Fq 'default => sub { 64 }' "$labwc_security_client_module" &&
   grep -Fq 'default => sub { 1_048_576 }' "$labwc_security_client_module" &&
   grep -Fq 'sub _list_drafts {' "$labwc_security_client_module" &&
   grep -Fq 'sub _run_apparmor_list_drafts {' "$labwc_security_client_module" &&
   grep -Fq 'sub _run_apparmor_validate_drafts {' "$labwc_security_client_module" &&
   grep -Fq 'more than " . $self->apparmor_max_draft_files() . " AppArmor drafts were found' "$labwc_security_client_module" &&
   grep -Fq 'AppArmor draft exceeds " . $self->apparmor_max_draft_bytes() . " bytes' "$labwc_security_client_module" &&
   grep -Fq 'apparmor-validate-drafts' "$labwc_security_client_module" &&
   grep -Fq 'apparmor-activate-draft' "$labwc_security_client_module" &&
   grep -Fq "require_executable('apparmor_parser')" "$labwc_security_client_module" &&
   ! grep -q 'apparmor-apply-drafts' "$maintenance_menu" &&
   ! grep -Fq 'sub apply_apparmor_profile_drafts {' "$labwc_security_apparmor_module" &&
   PATH="$bin_dir:/usr/bin:/bin" \
     LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_easyprof_dir" \
     LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_profile_dir" \
     run_security_client \
       --list-apparmor-draft-candidates >"$apparmor_candidates_output" 2>&1 &&
   [ "$(cat "$apparmor_candidates_output")" = "easyprof/valid-profile" ] &&
   PATH="$bin_dir:/usr/bin:/bin" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     APPARMOR_PARSER_LOG="$apparmor_parser_log" \
     LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_easyprof_dir" \
     LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_profile_dir" \
     run_security_client --run apparmor-list-drafts >"$apparmor_list_output" 2>&1 &&
   grep -Fq "$apparmor_easyprof_dir/valid-profile" "$apparmor_list_output" &&
   ! grep -q 'ignored-symlink' "$apparmor_list_output" &&
   PATH="$bin_dir:/usr/bin:/bin" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     APPARMOR_PARSER_LOG="$apparmor_parser_log" \
     LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_easyprof_dir" \
     LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_profile_dir" \
     run_security_client --run apparmor-validate-drafts >"$apparmor_validate_output" 2>&1 &&
   grep -Fq "valid   $apparmor_easyprof_dir/valid-profile" "$apparmor_validate_output" &&
   [ "$(cat "$apparmor_parser_log")" = "$apparmor_easyprof_dir/valid-profile" ] &&
   printf '%s\n' invalid >"$apparmor_profile_dir/invalid-profile" &&
   ! PATH="$bin_dir:/usr/bin:/bin" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     APPARMOR_PARSER_LOG="$apparmor_parser_log" \
     LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_easyprof_dir" \
     LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_profile_dir" \
     run_security_client --run apparmor-validate-drafts >"$apparmor_invalid_output" 2>&1 &&
   grep -Fq "invalid $apparmor_profile_dir/invalid-profile" "$apparmor_invalid_output" &&
   [ ! -e "$TMP_DIR/pkexec.log" ]; then
  pass "AppArmor draft maintenance stays bounded, selectable, and locally reviewable"
else
  fail "AppArmor draft maintenance stays bounded, selectable, and locally reviewable"
fi

apparmor_activation_root="$TMP_DIR/apparmor-activation"
apparmor_activation_profile_dir="$apparmor_activation_root/profiles"
apparmor_activation_easyprof_dir="$apparmor_activation_root/easyprof"
apparmor_activation_draft_dir="$apparmor_activation_root/drafts"
apparmor_activation_backup_dir="$apparmor_activation_root/backups"
apparmor_activation_bin="$apparmor_activation_root/bin"
apparmor_activation_mode_config="$apparmor_activation_root/managed-modes.conf"
apparmor_activation_mode_helper="$apparmor_activation_root/apparmor-managed-modes"
apparmor_activation_command_path="$apparmor_activation_bin:/usr/bin:/bin"
apparmor_activation_mode_log="$apparmor_activation_root/mode-helper.log"
apparmor_activation_parser_log="$apparmor_activation_root/parser.log"
apparmor_activation_output="$apparmor_activation_root/activate.out"
apparmor_activation_error="$apparmor_activation_root/activate.err"
mkdir -p \
  "$apparmor_activation_profile_dir" \
  "$apparmor_activation_easyprof_dir" \
  "$apparmor_activation_draft_dir" \
  "$apparmor_activation_backup_dir" \
  "$apparmor_activation_bin"
chmod 0700 "$apparmor_activation_backup_dir"
cat >"$apparmor_activation_mode_config" <<'EOF'
enforce required existing-profile -
enforce required rollback-profile -
enforce required canonical-profile -
EOF
chmod 0644 "$apparmor_activation_mode_config"
cat >"$apparmor_activation_mode_helper" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' invoked >>"${APPARMOR_MODE_LOG:?}"
[ "${FAIL_MODE_HELPER:-0}" -ne 1 ]
EOF
chmod 0755 "$apparmor_activation_mode_helper"
cat >"$apparmor_activation_bin/id" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -u ]; then
  printf '%s\n' 0
  exit 0
fi
exec /usr/bin/id "$@"
EOF
cat >"$apparmor_activation_bin/getent" <<'EOF'
#!/bin/sh
if [ "${1:-}" = passwd ] && [ "${2:-}" = 1000 ]; then
  printf '%s\n' 'tester:x:1000:1000:Tester:/home/tester:/bin/sh'
  exit 0
fi
exec /usr/bin/getent "$@"
EOF
cat >"$apparmor_activation_bin/stat" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = -c ]; then
  format=$2
  shift 2
  [ "${1:-}" = -- ] && shift
  path=$1
  mode=$(/usr/bin/stat -c %a -- "$path")
  size=$(/usr/bin/stat -c %s -- "$path")
  case "$format" in
    '%u %a %s') printf '0 %s %s\n' "$mode" "$size" ;;
    '%u %a') printf '0 %s\n' "$mode" ;;
    '%s') printf '%s\n' "$size" ;;
    *) exec /usr/bin/stat -c "$format" -- "$path" ;;
  esac
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
cat >"$apparmor_activation_bin/install" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  -d)
    exec /usr/bin/install -d -m "$7" "$8"
    ;;
  -o)
    exec /usr/bin/install -m "$6" "$7" "$8"
    ;;
  *)
    exec /usr/bin/install "$@"
    ;;
esac
EOF
cat >"$apparmor_activation_bin/apparmor_parser" <<'EOF'
#!/bin/sh
set -eu
last_argument=
list_names=false
load_profile=false
remove_profile=false
for argument in "$@"; do
  case "$argument" in
    -N) list_names=true ;;
    -r) load_profile=true ;;
    -R) remove_profile=true ;;
  esac
  last_argument=$argument
done
if [ "$list_names" = true ]; then
  /usr/bin/awk '$1 == "profile" { print $2 }' "$last_argument"
  exit 0
fi
if [ "$remove_profile" = true ]; then
  printf 'remove %s\n' "$last_argument" >>"${APPARMOR_PARSER_LOG:?}"
  exit 0
fi
if [ "$load_profile" = true ]; then
  printf 'load %s\n' "$last_argument" >>"${APPARMOR_PARSER_LOG:?}"
  /usr/bin/grep -q 'FAIL_LOAD' "$last_argument" && exit 9
  exit 0
fi
exit 0
EOF
chmod 0755 "$apparmor_activation_bin"/*
export APPARMOR_MODE_LOG="$apparmor_activation_mode_log"
export APPARMOR_PARSER_LOG="$apparmor_activation_parser_log"
run_activation() {
  LABWC_TEST_COMMAND_PATH="$apparmor_activation_command_path" \
    LABWC_TEST_APPARMOR_EASYPROF_DRAFT_DIR="$apparmor_activation_easyprof_dir" \
    LABWC_TEST_APPARMOR_MODE_CONFIG="$apparmor_activation_mode_config" \
    LABWC_TEST_APPARMOR_MODE_HELPER="$apparmor_activation_mode_helper" \
    LABWC_TEST_APPARMOR_PROFILE_BACKUP_DIR="$apparmor_activation_backup_dir" \
    LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_activation_profile_dir" \
    LABWC_TEST_APPARMOR_PROFILE_DRAFT_DIR="$apparmor_activation_draft_dir" \
    run_security_apparmor activate-draft "$@"
}
cat >"$apparmor_activation_profile_dir/existing-profile" <<'EOF'
profile existing-profile /usr/bin/true {
  # ORIGINAL_EXISTING
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_profile_dir/existing-profile"
cat >"$apparmor_activation_draft_dir/existing-profile" <<'EOF'
profile existing-profile /usr/bin/true {
  # UPDATED_EXISTING
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_draft_dir/existing-profile"
cat >"$apparmor_activation_draft_dir/new-profile" <<'EOF'
profile new-profile /usr/bin/true {
  # NEW_PROFILE
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_draft_dir/new-profile"
cat >"$apparmor_activation_profile_dir/rollback-profile" <<'EOF'
profile rollback-profile /usr/bin/true {
  # ORIGINAL_ROLLBACK
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_profile_dir/rollback-profile"
cat >"$apparmor_activation_draft_dir/rollback-profile" <<'EOF'
profile rollback-profile /usr/bin/true {
  # UPDATED_ROLLBACK
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_draft_dir/rollback-profile"
cat >"$apparmor_activation_draft_dir/new-fail-profile" <<'EOF'
profile new-fail-profile /usr/bin/true {
  # FAIL_LOAD
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_draft_dir/new-fail-profile"
cat >"$apparmor_activation_profile_dir/canonical-profile" <<'EOF'
profile canonical-label /usr/bin/true {
  # ORIGINAL_CANONICAL
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_profile_dir/canonical-profile"
cat >"$apparmor_activation_draft_dir/wrong-profile-name" <<'EOF'
profile canonical-label /usr/bin/true {
  # UPDATED_CANONICAL
  /usr/bin/true rix,
}
EOF
chmod 0644 "$apparmor_activation_draft_dir/wrong-profile-name"

apparmor_activation_ok=true

if ! run_activation \
       drafts \
       existing-profile \
       confirmed-apparmor-draft-activation >"$apparmor_activation_output" 2>&1; then
  apparmor_activation_ok=false
fi
grep -q 'UPDATED_EXISTING' "$apparmor_activation_profile_dir/existing-profile" ||
  apparmor_activation_ok=false
existing_backup=$(
  find "$apparmor_activation_backup_dir" \
    -mindepth 2 \
    -maxdepth 2 \
    -type f \
    -name previous-profile \
    -print \
    -quit
) || existing_backup=
[ -n "$existing_backup" ] || apparmor_activation_ok=false
[ -z "$existing_backup" ] ||
  grep -q 'ORIGINAL_EXISTING' "$existing_backup" ||
  apparmor_activation_ok=false
grep -q 'The repository-managed AppArmor mode policy was reapplied' \
  "$apparmor_activation_output" || apparmor_activation_ok=false

if ! run_activation \
       drafts \
       new-profile \
       confirmed-apparmor-draft-activation >>"$apparmor_activation_output" 2>&1; then
  apparmor_activation_ok=false
fi
grep -q 'NEW_PROFILE' "$apparmor_activation_profile_dir/new-profile" ||
  apparmor_activation_ok=false
grep -Fq "load $apparmor_activation_profile_dir/new-profile" \
  "$apparmor_activation_parser_log" || apparmor_activation_ok=false

FAIL_MODE_HELPER=1
export FAIL_MODE_HELPER
if run_activation \
     drafts \
     rollback-profile \
     confirmed-apparmor-draft-activation >"$apparmor_activation_error" 2>&1; then
  apparmor_activation_ok=false
fi
unset FAIL_MODE_HELPER
grep -q 'ORIGINAL_ROLLBACK' "$apparmor_activation_profile_dir/rollback-profile" ||
  apparmor_activation_ok=false
if grep -q 'UPDATED_ROLLBACK' "$apparmor_activation_profile_dir/rollback-profile"; then
  apparmor_activation_ok=false
fi
grep -q 'previous profile will be restored' "$apparmor_activation_error" ||
  apparmor_activation_ok=false

if run_activation \
     drafts \
     new-fail-profile \
     confirmed-apparmor-draft-activation >>"$apparmor_activation_error" 2>&1; then
  apparmor_activation_ok=false
fi
[ ! -e "$apparmor_activation_profile_dir/new-fail-profile" ] ||
  apparmor_activation_ok=false
[ "$(
    find "$apparmor_activation_backup_dir" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d |
      wc -l
  )" -eq 1 ] || apparmor_activation_ok=false

if ! run_activation \
       drafts \
       wrong-profile-name \
       confirmed-apparmor-draft-activation >>"$apparmor_activation_output" 2>&1; then
  apparmor_activation_ok=false
fi
grep -q 'UPDATED_CANONICAL' "$apparmor_activation_profile_dir/canonical-profile" ||
  apparmor_activation_ok=false
[ ! -e "$apparmor_activation_profile_dir/wrong-profile-name" ] ||
  apparmor_activation_ok=false
[ -f "$apparmor_activation_draft_dir/canonical-profile" ] ||
  apparmor_activation_ok=false
[ ! -e "$apparmor_activation_draft_dir/wrong-profile-name" ] ||
  apparmor_activation_ok=false
grep -q 'Resolved AppArmor draft filename: wrong-profile-name -> canonical-profile' \
  "$apparmor_activation_output" || apparmor_activation_ok=false

if [ "$apparmor_activation_ok" = true ]; then
  pass "selected AppArmor draft activation resolves canonical filenames, backs up replacements, loads new profiles, and rolls back failures"
else
  fail "selected AppArmor draft activation resolves canonical filenames, backs up replacements, loads new profiles, and rolls back failures"
fi

clamav_log="$TMP_DIR/clamav.log"
clamav_status_output="$TMP_DIR/clamav-status-output.log"
clamav_file_output="$TMP_DIR/clamav-file-output.log"
clamav_folder_output="$TMP_DIR/clamav-folder-output.log"
clamav_oversized_output="$TMP_DIR/clamav-oversized-output.log"
clamav_oversized_folder="$TMP_DIR/home/clamav oversized folder"
clamav_database_dir="$TMP_DIR/clamav-database"
clamav_scanner_socket="$TMP_DIR/managed-security-scanners.sock"
clamav_scanner_ready="$TMP_DIR/managed-security-scanners.ready"
clamav_scanner_messages="$TMP_DIR/managed-security-scanners.log"
mkdir -p "$clamav_oversized_folder" "$clamav_database_dir"
printf '%s\n' 'test-signature-database' >"$clamav_database_dir/daily.cvd"
truncate --size=536870913 "$clamav_oversized_folder/oversized.bin"
cat >"$bin_dir/clamscan" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = --version ]; then
  printf '%s\n' 'ClamAV 1.4.3/27800/Wed Jul 22 03:00:00 2026'
  exit 0
fi
printf '%s\n' "$*" >>"${CLAMAV_LOG:?}"
printf '%s\n' '----------- SCAN SUMMARY -----------' 'Infected files: 0'
EOF
chmod 0755 "$bin_dir/clamscan"
rm -f -- "$TMP_DIR/pkexec.log"
python3 - "$clamav_scanner_socket" "$clamav_scanner_ready" "$clamav_scanner_messages" <<'PY' &
from pathlib import Path
import socket
import sys

socket_path = Path(sys.argv[1])
ready_path = Path(sys.argv[2])
messages_path = Path(sys.argv[3])
server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
server.bind(str(socket_path))
server.settimeout(15)
ready_path.write_text("ready\n", encoding="utf-8")
completed = 0
try:
    with messages_path.open("w", encoding="utf-8") as messages:
        while completed < 3:
            payload = server.recv(65535).decode("utf-8", errors="replace").rstrip("\x00")
            messages.write(payload + "\n")
            messages.flush()
            if "event=completed status=" in payload:
                completed += 1
finally:
    server.close()
    socket_path.unlink(missing_ok=True)
raise SystemExit(0 if completed == 3 else 1)
PY
clamav_scanner_pid=$!
clamav_scanner_attempt=1
while [ ! -r "$clamav_scanner_ready" ] && [ "$clamav_scanner_attempt" -le 50 ]; do
  sleep 0.1
  clamav_scanner_attempt=$((clamav_scanner_attempt + 1))
done

clamav_runs_ok=true
if [ ! -S "$clamav_scanner_socket" ] ||
   ! PATH="$bin_dir:/usr/bin:/bin" \
     CLAMAV_LOG="$clamav_log" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     LABWC_TEST_CLAMAV_DATABASE_DIR="$clamav_database_dir" \
     LABWC_TEST_SCANNER_ROOT="$TMP_DIR" \
     LABWC_TEST_SCANNER_SOCKET="$clamav_scanner_socket" \
     run_security_client --run show-clamav-signature-status >"$clamav_status_output" 2>&1 ||
   ! PATH="$bin_dir:/usr/bin:/bin" \
     CLAMAV_LOG="$clamav_log" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     LABWC_TEST_CLAMAV_DATABASE_DIR="$clamav_database_dir" \
     LABWC_TEST_SCANNER_ROOT="$TMP_DIR" \
     LABWC_TEST_SCANNER_SOCKET="$clamav_scanner_socket" \
     run_security_client --run scan-file-clamav "$hash_fixture" >"$clamav_file_output" 2>&1 ||
   ! PATH="$bin_dir:/usr/bin:/bin" \
     CLAMAV_LOG="$clamav_log" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     LABWC_TEST_CLAMAV_DATABASE_DIR="$clamav_database_dir" \
     LABWC_TEST_SCANNER_ROOT="$TMP_DIR" \
     LABWC_TEST_SCANNER_SOCKET="$clamav_scanner_socket" \
     run_security_client --run scan-folder-clamav "$hash_folder" >"$clamav_folder_output" 2>&1
then
  clamav_runs_ok=false
fi
if ! wait "$clamav_scanner_pid"; then
  clamav_runs_ok=false
fi

if [ "$clamav_runs_ok" = true ] &&
   ! PATH="$bin_dir:/usr/bin:/bin" \
     CLAMAV_LOG="$clamav_log" \
     PKEXEC_LOG="$TMP_DIR/pkexec.log" \
     LABWC_TEST_CLAMAV_DATABASE_DIR="$clamav_database_dir" \
     LABWC_TEST_SCANNER_ROOT="$TMP_DIR" \
     LABWC_TEST_SCANNER_SOCKET="$clamav_scanner_socket" \
     run_security_client --run scan-folder-clamav "$clamav_oversized_folder" >"$clamav_oversized_output" 2>&1 &&
   grep -q 'ClamAV 1.4.3/27800' "$clamav_status_output" &&
   grep -Fq -- "--recursive=no --infected --cross-fs=no" "$clamav_log" &&
   grep -Fq -- "$hash_fixture" "$clamav_log" &&
   grep -Fq -- "--recursive=yes --infected --cross-fs=no" "$clamav_log" &&
   grep -Fq -- "$hash_folder" "$clamav_log" &&
   ! grep -Fq -- "$clamav_oversized_folder" "$clamav_log" &&
   grep -q 'contains a regular file above the managed 536870912-byte limit' "$clamav_oversized_output" &&
   grep -q 'infected files are never moved or deleted' "$clamav_file_output" &&
   grep -q 'infected files are never moved or deleted' "$clamav_folder_output" &&
   [ "$(grep -c 'managed-clamav-scan' "$clamav_scanner_messages")" -ge 9 ] &&
   [ "$(grep -c 'event=started' "$clamav_scanner_messages")" -eq 3 ] &&
   [ "$(grep -c 'event=completed status=0' "$clamav_scanner_messages")" -eq 3 ] &&
   grep -q 'stream=stdout message=ClamAV 1.4.3/27800' "$clamav_scanner_messages" &&
   grep -q 'stream=stdout message=Infected files: 0' "$clamav_scanner_messages" &&
   [ ! -e "$TMP_DIR/pkexec.log" ]; then
  pass "ClamAV status plus bounded file and recursive folder scans run unprivileged, report-only, and through the managed rsyslog socket"
else
  fail "ClamAV status plus bounded file and recursive folder scans run unprivileged, report-only, and through the managed rsyslog socket"
fi

system_recovery_responses="$TMP_DIR/system-recovery-responses"
system_action_log="$TMP_DIR/system-action.log"
recovery_action_log="$TMP_DIR/recovery-action.log"
cat >"$system_recovery_responses" <<'EOF'
 System
Restart PipeWire
Continue with authorized system action
Refresh Waybar Custom Module
Manage External Drives
← Back
 Troubleshooting
Drop Page Cache Only
Continue with authorized recovery action
← Back
EOF
cat >"$bin_dir/labwc-system-action" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${SYSTEM_ACTION_LOG:?}"
EOF
cat >"$bin_dir/labwc-recovery-action" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${RECOVERY_ACTION_LOG:?}"
EOF
cat >"$bin_dir/labwc-external-drives" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' opened >>"${EXTERNAL_DRIVE_LOG:?}"
EOF
chmod 0755 \
  "$bin_dir/labwc-system-action" \
  "$bin_dir/labwc-recovery-action" \
  "$bin_dir/labwc-external-drives"

if PATH="$bin_dir:/usr/bin:/bin" \
   HOME="$TMP_DIR/home" \
   FUZZEL_LOG="$fuzzel_log" \
   FUZZEL_RESPONSES="$system_recovery_responses" \
   SECURITY_ACTION_LOG="$action_log" \
   SYSTEM_ACTION_LOG="$system_action_log" \
   RECOVERY_ACTION_LOG="$recovery_action_log" \
   EXTERNAL_DRIVE_LOG="$TMP_DIR/external-drive.log" \
   /bin/sh "$maintenance_menu" &&
   [ "$(cat "$system_action_log")" = "restart-pipewire confirmed-system-action
refresh-waybar-custom-module" ] &&
   [ "$(cat "$TMP_DIR/external-drive.log")" = opened ] &&
   [ "$(cat "$recovery_action_log")" = "drop-page-cache confirmed-recovery-action" ]; then
  pass "System and Troubleshooting launchers dispatch confirmed and user-session actions"
else
  fail "System and Troubleshooting launchers dispatch confirmed and user-session actions"
fi

apparmor_generation_root="$TMP_DIR/apparmor-rule-generation"
apparmor_generation_profile_dir="$apparmor_generation_root/profiles"
apparmor_generation_local_dir="$apparmor_generation_profile_dir/local"
apparmor_generation_backup_dir="$apparmor_generation_root/transactions"
apparmor_generation_bin_dir="$apparmor_generation_root/bin"
apparmor_generation_event_log="$apparmor_generation_root/apparmor.log"
apparmor_generation_parser_config="$apparmor_generation_root/parser.conf"
apparmor_generation_parser_log="$apparmor_generation_root/parser.log"
apparmor_generation_output="$apparmor_generation_root/generate.out"
apparmor_generation_idempotent_output="$apparmor_generation_root/idempotent.out"
apparmor_generation_disabled_output="$apparmor_generation_root/disabled.out"
apparmor_generation_rollback_output="$apparmor_generation_root/rollback.out"
apparmor_generation_local_include="$apparmor_generation_local_dir/test-profile"
apparmor_generation_snapshot="$apparmor_generation_root/test-profile.snapshot"
apparmor_generation_rollback_snapshot="$apparmor_generation_root/test-profile.rollback-snapshot"
apparmor_generation_fail_marker="$apparmor_generation_root/fail-next-reload"
mkdir -p \
  "$apparmor_generation_local_dir" \
  "$apparmor_generation_profile_dir/disable" \
  "$apparmor_generation_backup_dir" \
  "$apparmor_generation_bin_dir"
chmod 0755 \
  "$apparmor_generation_profile_dir" \
  "$apparmor_generation_local_dir" \
  "$apparmor_generation_profile_dir/disable"
chmod 0700 "$apparmor_generation_backup_dir"
cat >"$apparmor_generation_parser_config" <<'EOF'
# Test-only parser configuration.
EOF
cat >"$apparmor_generation_profile_dir/test-profile" <<'EOF'
profile test-profile /usr/bin/test-profile flags=(attach_disconnected) {
  /usr/bin/test-profile rix,

  include if exists <local/test-profile>
}
EOF
cat >"$apparmor_generation_local_include" <<'EOF'
# Manual policy must remain byte-for-byte outside the managed block.
"/etc/hostname" r,
EOF
chmod 0644 \
  "$apparmor_generation_parser_config" \
  "$apparmor_generation_profile_dir/test-profile" \
  "$apparmor_generation_local_include"
cat >"$apparmor_generation_event_log" <<'EOF'
type=AVC apparmor="DENIED" operation="open" class="file" profile="test-profile" name="/home/tester/.config/example/state.db" requested_mask="rw" denied_mask="rw" fsuid=1000 ouid=1000
type=AVC apparmor="DENIED" operation="open" class="file" profile="test-profile" name="/home/tester/.config/example/state.db" requested_mask="rw" denied_mask="rw" fsuid=1000 ouid=1000
type=AVC apparmor="DENIED" operation="create" class="file" profile="test-profile" name="/home/tester/.cache/example/new.cache" requested_mask="c" denied_mask="c" FSUID=1000 OUID=1000
type=AVC apparmor="DENIED" operation="capable" class="cap" profile="test-profile" capname="net_bind_service"
type=AVC apparmor="DENIED" operation="connect" class="net" profile="test-profile" family=2 sock_type=1 protocol=6 requested="send receive connect" denied="send connect"
type=AVC apparmor="DENIED" operation="create" class="net" profile="test-profile" family=16 sock_type=3 protocol=0 requested="create" denied="create"
type=AVC apparmor="DENIED" operation="capable" class="cap" profile="test-profile" capname="sys_admin"
type=AVC apparmor="DENIED" operation="capable" class="cap" profile="test-profile" capname="setuid"
type=AVC apparmor="DENIED" operation="exec" class="file" profile="test-profile" name="/usr/bin/unreviewed" requested_mask="x" denied_mask="x" fsuid=1000 ouid=0
type=AVC apparmor="DENIED" operation="mount" class="mount" profile="test-profile" name="/mnt/unreviewed" requested_mask="mount" denied_mask="mount" fsuid=0 ouid=0
type=AVC apparmor="DENIED" operation="open" class="file" profile="test-profile" name="/home/tester/.ssh/id_ed25519" requested_mask="r" denied_mask="r" fsuid=1000 ouid=1000
type=AVC apparmor="DENIED" operation="open" class="file" profile="test-profile" name="/tmp/work/../../etc/shadow" requested_mask="r" denied_mask="r" fsuid=1000 ouid=0
type=AVC apparmor="DENIED" operation="open" class="file" profile="unknown-profile" name="/tmp/unknown-profile" requested_mask="r" denied_mask="r" fsuid=1000 ouid=1000
EOF
chmod 0600 "$apparmor_generation_event_log"
cat >"$apparmor_generation_bin_dir/apparmor_parser" <<'EOF'
#!/bin/sh
set -eu

last_argument=
previous_argument=
base_dir=
list_names=false
reload_profile=false
for argument in "$@"; do
  if [ "$previous_argument" = --base ]; then
    base_dir=$argument
  fi
  case "$argument" in
    -N) list_names=true ;;
    -r) reload_profile=true ;;
  esac
  previous_argument=$argument
  last_argument=$argument
done

if [ "$list_names" = true ]; then
  /usr/bin/awk '$1 == "profile" { print $2 }' "$last_argument"
  exit 0
fi

if [ "$reload_profile" = true ]; then
  if [ -n "${APPARMOR_TEST_FAIL_NEXT_RELOAD:-}" ] &&
     [ -e "$APPARMOR_TEST_FAIL_NEXT_RELOAD" ]; then
    /bin/rm -f -- "$APPARMOR_TEST_FAIL_NEXT_RELOAD"
    printf 'reload-failed %s\n' "$last_argument" >>"${APPARMOR_PARSER_LOG:?}"
    exit 9
  fi
  printf 'reload-ok %s\n' "$last_argument" >>"${APPARMOR_PARSER_LOG:?}"
  exit 0
fi

[ -n "$base_dir" ]
candidate="$base_dir/local/${APPARMOR_TEST_LOCAL_NAME:?}"
[ -r "$candidate" ]
/bin/grep -Fq '# BEGIN managed generated AppArmor rules' "$candidate"
/bin/grep -Fq '# END managed generated AppArmor rules' "$candidate"
printf 'validate %s\n' "$candidate" >>"${APPARMOR_PARSER_LOG:?}"
EOF
chmod 0755 "$apparmor_generation_bin_dir/apparmor_parser"

run_generated_apparmor_policy() {
  APPARMOR_PARSER_LOG="$apparmor_generation_parser_log" \
  APPARMOR_TEST_LOCAL_NAME=test-profile \
  LABWC_TEST_APPARMOR_EVENT_LOG="$apparmor_generation_event_log" \
  LABWC_TEST_APPARMOR_PARSER_CONFIG="$apparmor_generation_parser_config" \
  LABWC_TEST_APPARMOR_PROFILE_DIR="$apparmor_generation_profile_dir" \
  LABWC_TEST_APPARMOR_RULE_BACKUP_DIR="$apparmor_generation_backup_dir" \
  LABWC_TEST_COMMAND_PATH="$apparmor_generation_bin_dir:/usr/bin:/bin" \
    run_apparmor_rule_generator confirmed-apparmor-rule-generation
}

apparmor_generation_ok=true
if ! run_generated_apparmor_policy >"$apparmor_generation_output" 2>&1; then
  apparmor_generation_ok=false
fi
if [ "$apparmor_generation_ok" = true ]; then
  cp "$apparmor_generation_local_include" "$apparmor_generation_snapshot"
  parser_events_before=$(wc -l <"$apparmor_generation_parser_log")
  if ! run_generated_apparmor_policy >"$apparmor_generation_idempotent_output" 2>&1 ||
     ! cmp -s "$apparmor_generation_snapshot" "$apparmor_generation_local_include" ||
     [ "$(wc -l <"$apparmor_generation_parser_log")" -ne "$parser_events_before" ]
  then
    apparmor_generation_ok=false
  fi
fi
if [ "$apparmor_generation_ok" = true ]; then
  cat >"$apparmor_generation_event_log" <<'EOF'
type=AVC apparmor="DENIED" operation="open" class="file" profile="test-profile" name="/home/tester/.cache/example/disabled.cache" requested_mask="w" denied_mask="w" fsuid=1000 ouid=1000
EOF
  chmod 0600 "$apparmor_generation_event_log"
  ln -s ../test-profile \
    "$apparmor_generation_profile_dir/disable/test-profile"
  if ! run_generated_apparmor_policy >"$apparmor_generation_disabled_output" 2>&1; then
    apparmor_generation_ok=false
  fi
  rm -f -- "$apparmor_generation_profile_dir/disable/test-profile"
fi
if [ "$apparmor_generation_ok" = true ]; then
  cp "$apparmor_generation_local_include" "$apparmor_generation_rollback_snapshot"
  cat >"$apparmor_generation_event_log" <<'EOF'
type=AVC apparmor="DENIED" operation="open" class="file" profile="test-profile" name="/home/tester/.cache/example/rollback.cache" requested_mask="w" denied_mask="w" fsuid=1000 ouid=1000
EOF
  chmod 0600 "$apparmor_generation_event_log"
  : >"$apparmor_generation_fail_marker"
  if APPARMOR_TEST_FAIL_NEXT_RELOAD="$apparmor_generation_fail_marker" \
       run_generated_apparmor_policy >"$apparmor_generation_rollback_output" 2>&1
  then
    apparmor_generation_ok=false
  fi
fi

if [ "$apparmor_generation_ok" = true ] &&
   grep -Fqx '# Manual policy must remain byte-for-byte outside the managed block.' "$apparmor_generation_local_include" &&
   grep -Fqx '"/etc/hostname" r,' "$apparmor_generation_local_include" &&
   [ "$(grep -Fc '# BEGIN managed generated AppArmor rules' "$apparmor_generation_local_include")" -eq 1 ] &&
   [ "$(grep -Fc '# END managed generated AppArmor rules' "$apparmor_generation_local_include")" -eq 1 ] &&
   grep -Fqx '  owner @{HOME}/.config/example/state.db rw,' "$apparmor_generation_local_include" &&
   grep -Fqx '  owner @{HOME}/.cache/example/new.cache w,' "$apparmor_generation_local_include" &&
   grep -Fqx '  capability net_bind_service,' "$apparmor_generation_local_include" &&
   grep -Fqx '  network (connect, send) inet tcp,' "$apparmor_generation_local_include" &&
   grep -Fqx '  owner @{HOME}/.cache/example/disabled.cache w,' "$apparmor_generation_local_include" &&
   ! grep -Fq 'network create netlink raw' "$apparmor_generation_local_include" &&
   ! grep -Fq 'sys_admin' "$apparmor_generation_local_include" &&
   ! grep -Fq 'setuid' "$apparmor_generation_local_include" &&
   ! grep -Fq '/usr/bin/unreviewed' "$apparmor_generation_local_include" &&
   ! grep -Fq '/mnt/unreviewed' "$apparmor_generation_local_include" &&
   ! grep -Fq '/.ssh/' "$apparmor_generation_local_include" &&
   ! grep -Fq '../../etc/shadow' "$apparmor_generation_local_include" &&
   ! grep -Fq 'unknown-profile' "$apparmor_generation_local_include" &&
   grep -Fq 'Applied 4 unique AppArmor rules across 1 local include.' "$apparmor_generation_output" &&
   grep -Fq 'high-risk capability requires manual review: sys_admin' "$apparmor_generation_output" &&
   grep -Fq 'high-risk capability requires manual review: setuid' "$apparmor_generation_output" &&
   grep -Fq 'network family requires manual review: netlink' "$apparmor_generation_output" &&
   grep -Fq 'unsupported or unsafe file operation: exec' "$apparmor_generation_output" &&
   grep -Fq 'unsupported AppArmor class: mount' "$apparmor_generation_output" &&
   grep -Fq 'file denial does not contain a safe absolute path' "$apparmor_generation_output" &&
   grep -Fq 'file path or permission requires manual security review' "$apparmor_generation_output" &&
   grep -Fq 'profile label cannot be mapped to an installed AppArmor source' "$apparmor_generation_output" &&
   grep -Fq 'Every safe generated AppArmor rule was already present or subsumed.' "$apparmor_generation_idempotent_output" &&
   grep -Fq 'Updated disabled AppArmor source without loading it: test-profile' "$apparmor_generation_disabled_output" &&
   cmp -s "$apparmor_generation_rollback_snapshot" "$apparmor_generation_local_include" &&
   ! grep -Fq 'rollback.cache' "$apparmor_generation_local_include" &&
   grep -Fq 'cannot reload AppArmor source after generated rule update: test-profile' "$apparmor_generation_rollback_output" &&
   [ "$(grep -c '^validate ' "$apparmor_generation_parser_log")" -eq 3 ] &&
   [ "$(grep -c '^reload-ok ' "$apparmor_generation_parser_log")" -eq 2 ] &&
   [ "$(grep -c '^reload-failed ' "$apparmor_generation_parser_log")" -eq 1 ]; then
  pass "AppArmor rule generation is bounded, least-privilege, idempotent, parser-validated, and rollback-safe"
else
  fail "AppArmor rule generation is bounded, least-privilege, idempotent, parser-validated, and rollback-safe"
fi

labwc_security_perl_syntax_ok=true
for labwc_security_perl_source in \
  "$labwc_security_client_module" \
  "$labwc_security_command_module" \
  "$labwc_security_root_module" \
  "$labwc_security_apparmor_module" \
  "$labwc_security_apparmor_audit_log_module" \
  "$labwc_security_apparmor_profile_index_module" \
  "$labwc_security_apparmor_rule_generator_module" \
  "$labwc_security_apparmor_rule_renderer_module" \
  "$labwc_security_scanner_log_module" \
  "$security_action" \
  "$root_helper" \
  "$apparmor_rule_generator"
do
  if ! PERL5LIB="$perl_stub_root:$labwc_security_module_root" \
      /usr/bin/perl -c "$labwc_security_perl_source" >/dev/null 2>&1
  then
    labwc_security_perl_syntax_ok=false
  fi
done

if /bin/sh -n "$maintenance_menu" &&
   /bin/sh -n "$external_drive_helper" &&
   [ "$labwc_security_perl_syntax_ok" = true ] &&
   /bin/sh -n "$system_action" &&
   /bin/sh -n "$system_root_helper" &&
   /bin/sh -n "$recovery_action" &&
   /bin/sh -n "$recovery_root_helper" &&
   /bin/sh -n "$update_helper"; then
  pass "maintenance launchers are valid POSIX shell and security helpers are valid Perl"
else
  fail "maintenance launchers are valid POSIX shell and security helpers are valid Perl"
fi

invalid_system_log="$TMP_DIR/invalid-system.log"
invalid_recovery_log="$TMP_DIR/invalid-recovery.log"
if /bin/sh "$system_action" journal-vacuum-time 365d confirmed-system-action >"$invalid_system_log" 2>&1; then
  fail "maintenance wrappers reject unbounded retention and missing recovery confirmation"
elif /bin/sh "$recovery_action" drop-all-clean-caches >"$invalid_recovery_log" 2>&1; then
  fail "maintenance wrappers reject unbounded retention and missing recovery confirmation"
elif grep -q 'unsupported journal time retention' "$invalid_system_log" &&
     grep -q 'requires confirmation' "$invalid_recovery_log"; then
  pass "maintenance wrappers reject unbounded retention and missing recovery confirmation"
else
  fail "maintenance wrappers reject unbounded retention and missing recovery confirmation"
fi

run_step_test="$TMP_DIR/run-step-test.sh"
sed -n '/^run_step() {$/,/^}$/p' "$update_helper" >"$run_step_test"
cat >>"$run_step_test" <<'EOF'
overall_status=0
if run_step expected-failure /bin/sh -c 'exit 7'; then
  exit 1
fi
[ "$overall_status" -eq 7 ]
EOF
if /bin/sh "$run_step_test" >/dev/null 2>&1; then
  pass "signature updater preserves failing step exit statuses"
else
  fail "signature updater preserves failing step exit statuses"
fi
