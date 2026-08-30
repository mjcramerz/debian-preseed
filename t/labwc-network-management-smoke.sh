#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-network-management.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=11
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

network_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-menu"
network_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-action"
network_root_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-control-action-root"
module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-network-control-action"
client_module="$module_root/LabwcNetworkControlAction/Client.pm"
command_module="$module_root/LabwcNetworkControlAction/Command.pm"
root_module="$module_root/LabwcNetworkControlAction/Root.pm"
validation_module="$module_root/LabwcNetworkControlAction/Validation.pm"
desktop_packages="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
network_tmpfiles="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/tmpfiles.d/40-network-profiles.conf"

if grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-network-control-action';" "$network_action" &&
   grep -Fq 'use LabwcNetworkControlAction::Client;' "$network_action" &&
   grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-network-control-action';" "$network_root_action" &&
   grep -Fq 'use LabwcNetworkControlAction::Root;' "$network_root_action" &&
   grep -Fq 'has max_import_bytes =>' "$validation_module" &&
   grep -Fq 'default => sub { 1_048_576 },' "$validation_module" &&
   grep -Fq 'sub connection_uuid {' "$validation_module" &&
   grep -Fq 'sub import_file {' "$validation_module" &&
   grep -Fq 'sub wireguard_import_file {' "$validation_module" &&
   grep -Fq "default => sub { '/data/config/network/wireguard' }," "$validation_module" &&
   grep -Fq 'sub normalize_dns_servers {' "$validation_module" &&
   grep -Fq 'sub normalize_dns_families {' "$validation_module" &&
   grep -Fq 'system { $argv[0] } @argv;' "$command_module" &&
   grep -Fq 'CORE::exec { $argv[0] } @argv;' "$command_module" &&
   grep -q 'network-manager-openvpn' "$desktop_packages" &&
   grep -q 'wireguard-tools' "$desktop_packages" &&
   grep -Fq 'desktop_stage_labwc_network_control_action_perl_modules' "$desktop_components" &&
   grep -Fq 'LabwcNetworkControlAction/Client.pm' "$desktop_components" &&
   grep -Fq 'LabwcNetworkControlAction/Command.pm' "$desktop_components" &&
   grep -Fq 'LabwcNetworkControlAction/Root.pm' "$desktop_components" &&
   grep -Fq 'LabwcNetworkControlAction/Validation.pm' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-network-control-action /usr/local/bin/labwc-network-control-action 0755' "$desktop_components" &&
   grep -q 'usr/local/libexec/labwc-network-control-action-root /usr/local/libexec/labwc-network-control-action-root 0755' "$desktop_components" &&
   grep -Fq 'desktop_stage_network_profile_storage_policy' "$desktop_components" &&
   grep -Fq 'etc/tmpfiles.d/40-network-profiles.conf' "$desktop_components" &&
   grep -Fqx 'd /data/config 0755 root root -' "$network_tmpfiles" &&
   grep -Fqx 'd /data/config/network 0755 root root -' "$network_tmpfiles" &&
   grep -Fqx 'd /data/config/network/wireguard 0750 root devops -' "$network_tmpfiles" &&
   grep -Fq 'find /data/config/network/wireguard \' "$network_menu" &&
   grep -Fq -- '-maxdepth 1 \' "$network_menu" &&
   grep -q '/usr/local/bin/labwc-network-control-action' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-network-control-action-root' "$desktop_verify"; then
  pass "network management stages bounded Perl validation and fixed-argv command helpers"
else
  fail "network management stages bounded Perl validation and fixed-argv command helpers"
fi

compat_root="$TMP_DIR/perl-compat"
mkdir -p "$compat_root/MooX" "$compat_root/Types"
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
            if (!exists $self->{$name} && exists $specification{default}) {
                my $default = $specification{default};
                $self->{$name} = ref($default) eq 'CODE' ? $default->($self) : $default;
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

perl5lib="$compat_root:$module_root"
syntax_ok=true
/bin/sh -n "$network_menu" || syntax_ok=false
for perl_file in \
  "$network_action" \
  "$network_root_action" \
  "$client_module" \
  "$command_module" \
  "$root_module" \
  "$validation_module"
do
  env PERL5LIB="$perl5lib" LC_ALL=C TZ=UTC /usr/bin/perl -c "$perl_file" >/dev/null 2>&1 ||
    syntax_ok=false
done
if [ "$syntax_ok" = true ]; then
  pass "network management menu is valid POSIX shell and Perl entrypoints and modules compile"
else
  fail "network management menu is valid POSIX shell and Perl entrypoints and modules compile"
fi

behavior_harness="$TMP_DIR/network-management-behavior.pl"
cat >"$behavior_harness" <<'PERL'
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use LabwcNetworkControlAction::Client;
use LabwcNetworkControlAction::Root;
use LabwcNetworkControlAction::Validation;

package Local::FakeCommand;

sub new {
    my ($class, %arguments) = @_;
    $arguments{calls} //= [];
    $arguments{active_uuids} //= [];
    $arguments{connection_types} //= {};
    $arguments{device_uuids} //= {};
    $arguments{executables} //= {
        nmcli      => 1,
        pkexec     => 1,
        resolvectl => 1,
    };
    return bless \%arguments, $class;
}

sub calls { return $_[0]{calls}; }

sub executable {
    my ($self, $name) = @_;
    return "/mock/$name" if $self->{executables}{$name};
    return undef;
}

sub require_executable {
    my ($self, $name) = @_;
    my $path = $self->executable($name);
    defined($path) or die "unexpected executable request: $name\n";
    return $path;
}

sub run {
    my ($self, @argv) = @_;
    push @{$self->{calls}}, [@argv];
    return 0;
}

sub run_or_die {
    my ($self, $label, @argv) = @_;
    push @{$self->{calls}}, [@argv];
    return;
}

sub exec {
    my ($self, @argv) = @_;
    push @{$self->{calls}}, [@argv];
    die bless {}, 'Local::ExecCalled';
}

sub capture {
    my ($self, %arguments) = @_;
    my @argv = @{$arguments{argv} // []};
    @argv or die "unexpected empty capture request\n";

    if (@argv == 5 && $argv[1] eq '--terse' && $argv[2] eq '--fields' && $argv[3] eq 'RUNNING') {
        return (0, "running\n");
    }
    if (@argv == 7 && $argv[1] eq '--get-values' && $argv[2] eq 'connection.type') {
        my $uuid = $argv[-1];
        exists $self->{connection_types}{$uuid}
            or return (10, q{});
        return (0, $self->{connection_types}{$uuid} . "\n");
    }
    if (@argv == 6 && $argv[1] eq '--get-values' && $argv[2] eq 'GENERAL.NM-MANAGED') {
        return (0, "yes\n");
    }
    if (@argv == 6 && $argv[1] eq '--terse' && $argv[2] eq '--fields' && $argv[3] eq 'UUID') {
        return (0, join(q{}, map { "$_\n" } sort keys %{$self->{connection_types}}));
    }
    if (@argv == 7 && $argv[1] eq '--terse' && $argv[2] eq '--fields' && $argv[3] eq 'UUID') {
        return (0, join(q{}, map { "$_\n" } @{$self->{active_uuids}}));
    }
    if (@argv == 9 && $argv[1] eq '--terse' && $argv[2] eq '--escape' && $argv[4] eq '--fields' && $argv[5] eq 'DEVICE,UUID') {
        return (
            0,
            join(
                q{},
                map { "$_:$self->{device_uuids}{$_}\n" }
                  sort keys %{$self->{device_uuids}},
            ),
        );
    }
    if ($argv[0] eq '/mock/ifquery') {
        return (0, q{});
    }
    die "unexpected capture request: @argv\n";
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

sub has_call {
    my ($calls, @expected) = @_;
    for my $call (@{$calls}) {
        next if @{$call} != @expected;
        my $matches = 1;
        for my $index (0 .. $#expected) {
            if ($call->[$index] ne $expected[$index]) {
                $matches = 0;
                last;
            }
        }
        return 1 if $matches;
    }
    return 0;
}

sub call_count {
    my ($calls, @expected) = @_;
    my $count = 0;
    for my $call (@{$calls}) {
        next if @{$call} != @expected;
        my $matches = 1;
        for my $index (0 .. $#expected) {
            if ($call->[$index] ne $expected[$index]) {
                $matches = 0;
                last;
            }
        }
        ++$count if $matches;
    }
    return $count;
}

sub matching_call_count {
    my ($calls, $pattern) = @_;
    return scalar grep { join(q{ }, @{$_}) =~ $pattern } @{$calls};
}

sub client_validate_and_run {
    my ($client, $action, @arguments) = @_;
    my ($root_action, $root_arguments) = $client->_validate_request($action, @arguments);
    return $client->_run_root_action($root_action, @{$root_arguments});
}

sub dispatch_allow_exec {
    my ($root, @arguments) = @_;
    my $ok = eval {
        $root->_dispatch(@arguments);
        1;
    };
    return if !$ok && ref($@) eq 'Local::ExecCalled';
    return if $ok;
    die $@;
}

my $case = shift @ARGV // q{};
my $tmp = $ENV{NETWORK_TEST_TMP} // die "NETWORK_TEST_TMP is unset\n";
my $uuid = '12345678-1234-1234-1234-123456789abc';
my $openvpn = File::Spec->catfile($tmp, 'profile.ovpn');
my $wireguard_root = File::Spec->catdir($tmp, 'wireguard-import');
my $wireguard = File::Spec->catfile($wireguard_root, 'wg0.conf');
my $wireguard_nested_dir = File::Spec->catdir($wireguard_root, 'nested');
my $wireguard_nested = File::Spec->catfile($wireguard_nested_dir, 'nested.conf');
my $wireguard_symlink = File::Spec->catfile($wireguard_root, 'symlink.conf');
my $wireguard_sibling = File::Spec->catfile($tmp, 'sibling.conf');
my $wireguard_bad_mode = File::Spec->catfile($wireguard_root, 'bad-mode.conf');
my $wireguard_home_dir = File::Spec->catdir($tmp, 'home', '.config', 'wireguard');
my $wireguard_home = File::Spec->catfile($wireguard_home_dir, 'home.conf');
my $wrong_suffix = File::Spec->catfile($tmp, 'profile.txt');
my $symlink = File::Spec->catfile($tmp, 'profile-link.ovpn');
my $oversized_profile = File::Spec->catfile($wireguard_root, 'oversized.conf');
my $root_helper = File::Spec->catfile($tmp, 'labwc-network-control-action-root');

if (!-e $openvpn) {
    make_path($wireguard_root, $wireguard_nested_dir, $wireguard_home_dir);
    chmod 0750, $wireguard_root or die "chmod $wireguard_root: $!\n";

    open my $handle, '>', $openvpn or die "open $openvpn: $!\n";
    print {$handle} "client\n" or die "write $openvpn: $!\n";
    close $handle or die "close $openvpn: $!\n";
    chmod 0600, $openvpn or die "chmod $openvpn: $!\n";

    open $handle, '>', $wireguard or die "open $wireguard: $!\n";
    print {$handle} "[Interface]\n" or die "write $wireguard: $!\n";
    close $handle or die "close $wireguard: $!\n";
    chmod 0640, $wireguard or die "chmod $wireguard: $!\n";

    for my $path ($wireguard_nested, $wireguard_sibling, $wireguard_home) {
        open $handle, '>', $path or die "open $path: $!\n";
        print {$handle} "[Interface]\n" or die "write $path: $!\n";
        close $handle or die "close $path: $!\n";
        chmod 0640, $path or die "chmod $path: $!\n";
    }

    symlink $wireguard, $wireguard_symlink or die "symlink $wireguard_symlink: $!\n";

    open $handle, '>', $wireguard_bad_mode or die "open $wireguard_bad_mode: $!\n";
    print {$handle} "[Interface]\n" or die "write $wireguard_bad_mode: $!\n";
    close $handle or die "close $wireguard_bad_mode: $!\n";
    chmod 0660, $wireguard_bad_mode or die "chmod $wireguard_bad_mode: $!\n";

    open $handle, '>', $wrong_suffix or die "open $wrong_suffix: $!\n";
    print {$handle} "client\n" or die "write $wrong_suffix: $!\n";
    close $handle or die "close $wrong_suffix: $!\n";
    chmod 0600, $wrong_suffix or die "chmod $wrong_suffix: $!\n";

    symlink $openvpn, $symlink or die "symlink $symlink: $!\n";

    open $handle, '>', $oversized_profile or die "open $oversized_profile: $!\n";
    seek $handle, 1_048_576, 0 or die "seek $oversized_profile: $!\n";
    print {$handle} 'x' or die "write $oversized_profile: $!\n";
    close $handle or die "close $oversized_profile: $!\n";
    chmod 0640, $oversized_profile or die "chmod $oversized_profile: $!\n";

    open $handle, '>', $root_helper or die "open $root_helper: $!\n";
    print {$handle} "#!/bin/sh\nexit 99\n" or die "write $root_helper: $!\n";
    close $handle or die "close $root_helper: $!\n";
    chmod 0755, $root_helper or die "chmod $root_helper: $!\n";
}

sub wireguard_validator {
    my (%overrides) = @_;
    my @root_metadata = stat $wireguard_root;
    my @file_metadata = stat $wireguard;
    return LabwcNetworkControlAction::Validation->new(
        wireguard_import_root    => $wireguard_root,
        wireguard_root_owner_uid => $root_metadata[4],
        wireguard_file_owner_uid => $file_metadata[4],
        wireguard_root_group_gid => $root_metadata[5],
        wireguard_file_group_gid => $file_metadata[5],
        %overrides,
    );
}

if ($case eq 'invalid-uuid') {
    my $command = Local::FakeCommand->new();
    my $client = LabwcNetworkControlAction::Client->new(
        command => $command,
        root_helper => $root_helper,
    );
    my $before = scalar @{$command->calls()};
    expect_failure(qr/invalid NetworkManager connection UUID/, sub {
        client_validate_and_run($client, 'activate-vpn', 'not-a-uuid');
    });
    require_true(scalar(@{$command->calls()}) == $before, 'invalid UUID reached pkexec');
}
elsif ($case eq 'invalid-imports') {
    my $command = Local::FakeCommand->new();
    my $validator = wireguard_validator();
    my $client = LabwcNetworkControlAction::Client->new(
        command => $command,
        root_helper => $root_helper,
        validator => $validator,
    );
    my @checks = (
        [qr/path must be absolute/, sub { client_validate_and_run($client, 'import-openvpn', 'profile.ovpn', 'confirmed-network-action') }],
        [qr/cannot be a symbolic link/, sub { client_validate_and_run($client, 'import-openvpn', $symlink, 'confirmed-network-action') }],
        [qr/path must end in [.]ovpn/, sub { client_validate_and_run($client, 'import-openvpn', $wrong_suffix, 'confirmed-network-action') }],
        [qr/confirmation is missing/, sub { client_validate_and_run($client, 'import-openvpn', $openvpn, 'missing-confirmation') }],
        [qr/must be below/, sub { client_validate_and_run($client, 'import-wireguard', $wireguard_home, 'confirmed-network-action') }],
        [qr/must be below/, sub { client_validate_and_run($client, 'import-wireguard', $wireguard_sibling, 'confirmed-network-action') }],
        [qr/must be a direct child/, sub { client_validate_and_run($client, 'import-wireguard', $wireguard_nested, 'confirmed-network-action') }],
        [qr/cannot be a symbolic link/, sub { client_validate_and_run($client, 'import-wireguard', $wireguard_symlink, 'confirmed-network-action') }],
        [qr/confirmation is missing/, sub { client_validate_and_run($client, 'import-wireguard', $wireguard, 'missing-confirmation') }],
        [qr/must be owned by the invoking desktop user/, sub {
            $validator->import_file(
                label => 'OpenVPN profile', path => $openvpn, suffix => '.ovpn', owner_uid => $< + 1,
            );
        }],
        [qr/must not allow group or other writes/, sub {
            chmod 0666, $openvpn or die "chmod $openvpn: $!\n";
            my $ok = eval {
                $validator->import_file(
                    label => 'OpenVPN profile', path => $openvpn, suffix => '.ovpn', owner_uid => $<,
                );
                1;
            };
            my $error = $@;
            chmod 0600, $openvpn or die "chmod $openvpn: $!\n";
            die $error if !$ok;
        }],
        [qr/exceeds the managed 1048576-byte limit/, sub {
            $validator->import_file(
                label => 'OpenVPN profile', path => $oversized_profile, suffix => '.conf', owner_uid => $<,
            );
        }],
        [qr/file must be owned by root/, sub {
            wireguard_validator(wireguard_file_owner_uid => $< + 1)
                ->wireguard_import_file(path => $wireguard);
        }],
        [qr/file permissions must be one of/, sub {
            $validator->wireguard_import_file(path => $wireguard_bad_mode);
        }],
        [qr/group-readable file must use the devops group/, sub {
            my @metadata = stat $wireguard;
            wireguard_validator(wireguard_file_group_gid => $metadata[5] + 1)
                ->wireguard_import_file(path => $wireguard);
        }],
        [qr/file must contain between 1 and 1048576 bytes/, sub {
            $validator->wireguard_import_file(path => $oversized_profile);
        }],
    );
    for my $check (@checks) {
        my $before = scalar @{$command->calls()};
        expect_failure($check->[0], $check->[1]);
        require_true(scalar(@{$command->calls()}) == $before, 'unsafe import reached pkexec');
    }
}
elsif ($case eq 'invalid-dns') {
    my $command = Local::FakeCommand->new();
    my $client = LabwcNetworkControlAction::Client->new(
        command => $command,
        root_helper => $root_helper,
    );
    my $oversized_dns = '1' x 257;
    my @checks = (
        [qr/invalid DNS server IP address/, 'example.com', 'confirmed-network-action'],
        [qr/invalid DNS server IP address/, 'https://1.1.1.1', 'confirmed-network-action'],
        [qr/invalid DNS server IP address/, '999.1.1.1', 'confirmed-network-action'],
        [qr/provide between one and four DNS server IP addresses/, '1.1.1.1,8.8.8.8,9.9.9.9,208.67.222.222,208.67.220.220', 'confirmed-network-action'],
        [qr/DNS server list exceeds 256 characters/, $oversized_dns, 'confirmed-network-action'],
        [qr/custom DNS confirmation is missing/, '1.1.1.1', 'missing-confirmation'],
    );
    for my $check (@checks) {
        my $before = scalar @{$command->calls()};
        expect_failure($check->[0], sub {
            client_validate_and_run($client, 'set-custom-dns', $uuid, $check->[1], $check->[2]);
        });
        require_true(scalar(@{$command->calls()}) == $before, 'invalid DNS input reached pkexec');
    }
}
elsif ($case eq 'client-argv') {
    my $command = Local::FakeCommand->new();
    my $client = LabwcNetworkControlAction::Client->new(
        command => $command,
        root_helper => $root_helper,
        validator => wireguard_validator(),
    );
    client_validate_and_run($client, 'activate-connection', $uuid);
    client_validate_and_run($client, 'deactivate-connection', $uuid);
    client_validate_and_run($client, 'import-openvpn', $openvpn, 'confirmed-network-action');
    client_validate_and_run($client, 'import-wireguard', $wireguard, 'confirmed-network-action');
    client_validate_and_run($client, 'restore-automatic-dns', $uuid, 'confirmed-network-action');
    client_validate_and_run($client, 'set-custom-dns', $uuid, '1.1.1.1 2606:4700:4700::1111', 'confirmed-network-action');
    client_validate_and_run($client, 'flush-dns-cache', 'confirmed-network-action');

    my $calls = $command->calls();
    my $pkexec = '/mock/pkexec';
    require_true(has_call($calls, $pkexec, $root_helper, 'activate-connection', $uuid), 'activate connection argv missing');
    require_true(has_call($calls, $pkexec, $root_helper, 'deactivate-connection', $uuid), 'deactivate connection argv missing');
    require_true(has_call($calls, $pkexec, $root_helper, 'import-openvpn', $openvpn, 'confirmed-network-action'), 'OpenVPN import argv missing');
    require_true(has_call($calls, $pkexec, $root_helper, 'import-wireguard', $wireguard, 'confirmed-network-action'), 'WireGuard import argv missing');
    require_true(has_call($calls, $pkexec, $root_helper, 'restore-automatic-dns', $uuid, 'confirmed-network-action'), 'automatic DNS argv missing');
    require_true(has_call($calls, $pkexec, $root_helper, 'set-custom-dns', $uuid, '1.1.1.1,2606:4700:4700::1111', 'confirmed-network-action'), 'normalized custom DNS argv missing');
    require_true(has_call($calls, $pkexec, $root_helper, 'flush-dns-cache', 'confirmed-network-action'), 'DNS cache argv missing');
}
elsif ($case eq 'invalid-interface') {
    my $command = Local::FakeCommand->new();
    my $client = LabwcNetworkControlAction::Client->new(
        command => $command,
        root_helper => $root_helper,
    );
    my @checks = (
        [qr/invalid network interface name/, 'enable-ethernet', '../eth0'],
        [qr/confirmation is missing/, 'randomize-macs', 'wrong-token'],
    );
    for my $check (@checks) {
        my $before = scalar @{$command->calls()};
        expect_failure($check->[0], sub {
            client_validate_and_run($client, $check->[1], $check->[2]);
        });
        require_true(scalar(@{$command->calls()}) == $before, 'invalid interface request reached pkexec');
    }
}
elsif ($case eq 'root-argv' || $case eq 'root-type-mismatch') {
    my $vpn_uuid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    my $wireguard_uuid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    my $ethernet_uuid = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    my $command = Local::FakeCommand->new(
        connection_types => {
            $vpn_uuid => 'vpn',
            $wireguard_uuid => 'wireguard',
            $ethernet_uuid => '802-3-ethernet',
        },
        active_uuids => [$vpn_uuid, $wireguard_uuid, $ethernet_uuid],
    );
    my $root = LabwcNetworkControlAction::Root->new(
        command => $command,
        validator => wireguard_validator(),
    );

    if ($case eq 'root-type-mismatch') {
        my $before = scalar @{$command->calls()};
        expect_failure(qr/expected vpn/, sub {
            $root->_dispatch($<, 'activate-vpn', $wireguard_uuid);
        });
        require_true(scalar(@{$command->calls()}) == $before, 'mismatched connection type reached nmcli mutation');
    }
    else {
        dispatch_allow_exec($root, $<, 'activate-vpn', $vpn_uuid);
        dispatch_allow_exec($root, $<, 'activate-wireguard', $wireguard_uuid);
        dispatch_allow_exec($root, $<, 'import-openvpn', $openvpn, 'confirmed-network-action');
        dispatch_allow_exec($root, $<, 'import-wireguard', $wireguard, 'confirmed-network-action');
        $root->_dispatch($<, 'restore-automatic-dns', $ethernet_uuid, 'confirmed-network-action');
        $root->_dispatch($<, 'set-custom-dns', $ethernet_uuid, '1.1.1.1,2606:4700:4700::1111', 'confirmed-network-action');
        $root->_dispatch($<, 'flush-dns-cache', 'confirmed-network-action');

        my $calls = $command->calls();
        my $nmcli = '/mock/nmcli';
        require_true(has_call($calls, $nmcli, '--wait', '60', 'connection', 'up', 'uuid', $vpn_uuid), 'VPN activation argv missing');
        require_true(has_call($calls, $nmcli, '--wait', '60', 'connection', 'up', 'uuid', $wireguard_uuid), 'WireGuard activation argv missing');
        require_true(has_call($calls, $nmcli, '--wait', '30', 'connection', 'import', 'type', 'openvpn', 'file', $openvpn), 'OpenVPN import argv missing');
        require_true(has_call($calls, $nmcli, '--wait', '30', 'connection', 'import', 'type', 'wireguard', 'file', $wireguard), 'WireGuard import argv missing');
        require_true(has_call(
            $calls, $nmcli, '--wait', '30', 'connection', 'modify', 'uuid', $ethernet_uuid,
            'ipv4.ignore-auto-dns', 'no', 'ipv6.ignore-auto-dns', 'no', 'ipv4.dns', q{}, 'ipv6.dns', q{},
        ), 'automatic DNS argv missing');
        require_true(has_call(
            $calls, $nmcli, '--wait', '30', 'connection', 'modify', 'uuid', $ethernet_uuid,
            'ipv4.ignore-auto-dns', 'yes', 'ipv6.ignore-auto-dns', 'yes',
            'ipv4.dns', '1.1.1.1', 'ipv6.dns', '2606:4700:4700::1111',
        ), 'custom DNS argv missing');
        require_true(has_call($calls, $nmcli, 'general', 'reload', 'dns-rc'), 'NetworkManager DNS reload argv missing');
        require_true(has_call($calls, '/mock/resolvectl', 'flush-caches'), 'systemd-resolved cache flush argv missing');
    }
}
elsif ($case eq 'root-ifupdown') {
    my $sys_class_net = File::Spec->catdir($tmp, 'ifupdown-sys-class-net');
    for my $interface ('managed-eth0', 'managed-wifi0') {
        my $path = File::Spec->catdir($sys_class_net, $interface);
        mkdir $sys_class_net if !-d $sys_class_net;
        mkdir $path or die "mkdir $path: $!\n";
        mkdir File::Spec->catdir($path, 'device')
            or die "mkdir $path/device: $!\n";
        if ($interface eq 'managed-wifi0') {
            mkdir File::Spec->catdir($path, 'wireless')
                or die "mkdir $path/wireless: $!\n";
        }
        for my $file (['type', "1\n"], ['flags', "0x1003\n"]) {
            my $target = File::Spec->catfile($path, $file->[0]);
            open my $handle, '>', $target or die "open $target: $!\n";
            print {$handle} $file->[1] or die "write $target: $!\n";
            close $handle or die "close $target: $!\n";
        }
    }

    my $command = Local::FakeCommand->new(
        executables => {
            ifdown => 1,
            ifquery => 1,
            ifup => 1,
            ip => 1,
            rfkill => 1,
        },
    );
    my $root = LabwcNetworkControlAction::Root->new(
        command => $command,
        sys_class_net => $sys_class_net,
    );
    dispatch_allow_exec($root, $<, 'enable-ethernet', 'managed-eth0');
    dispatch_allow_exec($root, $<, 'disable-ethernet', 'managed-eth0');
    dispatch_allow_exec($root, $<, 'enable-wifi', 'managed-wifi0');
    dispatch_allow_exec($root, $<, 'disable-wifi', 'managed-wifi0');
    $root->_dispatch($<, 'randomize-macs', 'confirmed-network-action');

    my $calls = $command->calls();
    require_true(call_count($calls, '/mock/ifup', 'managed-eth0') == 2, 'ifupdown Ethernet restore count is wrong');
    require_true(call_count($calls, '/mock/ifdown', 'managed-eth0') == 2, 'ifupdown Ethernet down count is wrong');
    require_true(call_count($calls, '/mock/ifup', 'managed-wifi0') == 2, 'ifupdown WiFi restore count is wrong');
    require_true(call_count($calls, '/mock/ifdown', 'managed-wifi0') == 2, 'ifupdown WiFi down count is wrong');
    require_true(call_count($calls, '/mock/rfkill', 'unblock', 'wlan') == 1, 'WiFi rfkill unblock count is wrong');
    require_true(
        matching_call_count(
            $calls,
            qr{\A/mock/ip link set dev managed-eth0 address (?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z},
        ) == 1,
        'ifupdown Ethernet randomized MAC argv missing',
    );
    require_true(
        matching_call_count(
            $calls,
            qr{\A/mock/ip link set dev managed-wifi0 address (?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z},
        ) == 1,
        'ifupdown WiFi randomized MAC argv missing',
    );
}
elsif ($case eq 'root-networkmanager') {
    my $connection_uuid = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
    my $sys_class_net = File::Spec->catdir($tmp, 'nm-sys-class-net');
    my $interface_path = File::Spec->catdir($sys_class_net, 'nmether0');
    mkdir $sys_class_net if !-d $sys_class_net;
    mkdir $interface_path or die "mkdir $interface_path: $!\n";
    mkdir File::Spec->catdir($interface_path, 'device')
        or die "mkdir $interface_path/device: $!\n";
    for my $file (['type', "1\n"], ['flags', "0x1003\n"]) {
        my $target = File::Spec->catfile($interface_path, $file->[0]);
        open my $handle, '>', $target or die "open $target: $!\n";
        print {$handle} $file->[1] or die "write $target: $!\n";
        close $handle or die "close $target: $!\n";
    }

    my $command = Local::FakeCommand->new(
        executables => {
            ip => 1,
            nmcli => 1,
        },
        connection_types => {
            $connection_uuid => '802-3-ethernet',
        },
        active_uuids => [$connection_uuid],
        device_uuids => {
            nmether0 => $connection_uuid,
        },
    );
    my $root = LabwcNetworkControlAction::Root->new(
        command => $command,
        sys_class_net => $sys_class_net,
    );
    dispatch_allow_exec($root, $<, 'enable-ethernet', 'nmether0');
    $root->_dispatch($<, 'randomize-macs', 'confirmed-network-action');

    my $calls = $command->calls();
    require_true(
        has_call($calls, '/mock/nmcli', '--wait', '60', 'device', 'connect', 'nmether0'),
        'NetworkManager device connect argv missing',
    );
    require_true(
        has_call(
            $calls,
            '/mock/nmcli', '--wait', '30', 'connection', 'modify', 'uuid',
            $connection_uuid, '802-3-ethernet.cloned-mac-address', 'random',
        ),
        'NetworkManager randomized profile argv missing',
    );
    require_true(
        has_call($calls, '/mock/nmcli', '--wait', '30', 'connection', 'down', 'uuid', $connection_uuid),
        'NetworkManager profile down argv missing',
    );
    require_true(
        has_call($calls, '/mock/nmcli', '--wait', '60', 'connection', 'up', 'uuid', $connection_uuid),
        'NetworkManager profile up argv missing',
    );
    require_true(
        matching_call_count($calls, qr{\A/mock/ip link set dev nmether0 address }) == 0,
        'active NetworkManager interface was randomized directly',
    );
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
    NETWORK_TEST_TMP="$TMP_DIR" \
    LC_ALL=C \
    TZ=UTC \
    /usr/bin/perl "$behavior_harness" "$case_name"
}

if run_behavior_case invalid-uuid; then
  pass "network client rejects malformed connection UUIDs before pkexec"
else
  fail "network client rejects malformed connection UUIDs before pkexec"
fi

if run_behavior_case invalid-imports; then
  pass "network client rejects unsafe OpenVPN and WireGuard imports before pkexec"
else
  fail "network client rejects unsafe OpenVPN and WireGuard imports before pkexec"
fi

if run_behavior_case invalid-dns; then
  pass "network client rejects malformed, oversized, and unconfirmed DNS input before pkexec"
else
  fail "network client rejects malformed, oversized, and unconfirmed DNS input before pkexec"
fi

if run_behavior_case client-argv; then
  pass "validated network requests reach pkexec with fixed normalized arguments"
else
  fail "validated network requests reach pkexec with fixed normalized arguments"
fi

if run_behavior_case root-argv; then
  pass "privileged network module maps VPN, WireGuard, import, and DNS actions to fixed nmcli argv"
else
  fail "privileged network module maps VPN, WireGuard, import, and DNS actions to fixed nmcli argv"
fi

if run_behavior_case root-type-mismatch; then
  pass "privileged network module rejects mismatched VPN and WireGuard connection types"
else
  fail "privileged network module rejects mismatched VPN and WireGuard connection types"
fi

if run_behavior_case invalid-interface; then
  pass "network client rejects unsafe interfaces and missing confirmations before pkexec"
else
  fail "network client rejects unsafe interfaces and missing confirmations before pkexec"
fi

if run_behavior_case root-ifupdown; then
  pass "privileged network module controls and randomizes installer-owned ifupdown adapters"
else
  fail "privileged network module controls and randomizes installer-owned ifupdown adapters"
fi

if run_behavior_case root-networkmanager; then
  pass "privileged network module controls and randomizes NetworkManager-owned adapters"
else
  fail "privileged network module controls and randomizes NetworkManager-owned adapters"
fi

[ "$FAIL_COUNT" -eq 0 ]
