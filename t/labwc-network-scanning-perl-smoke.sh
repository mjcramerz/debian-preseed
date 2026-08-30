#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-network-scanning-perl.XXXXXX")
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

network_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-scan-action"
network_root_entrypoint="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-scan-action-root.tmpl"
module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/labwc-network-scan-action"
client_module="$module_root/LabwcNetworkScanAction/Client.pm"
command_module="$module_root/LabwcNetworkScanAction/Command.pm"
root_template="$module_root/LabwcNetworkScanAction/Root.pm.tmpl"
validation_module="$module_root/LabwcNetworkScanAction/Validation.pm"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"

if grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-network-scan-action';" "$network_action" &&
   grep -Fq 'use LabwcNetworkScanAction::Client;' "$network_action" &&
   grep -Fq "use lib '/usr/local/lib/perl5/site_perl/labwc-network-scan-action';" "$network_root_entrypoint" &&
   grep -Fq 'use LabwcNetworkScanAction::Root;' "$network_root_entrypoint" &&
   grep -Fq "default => sub { '/usr/local/libexec/labwc-network-scan-action-root' }," "$client_module" &&
   grep -Fq "default => sub { '__INSTALLER_ACCOUNT_USERNAME__' }," "$root_template" &&
   grep -Fq 'system { $argv[0] } @argv;' "$command_module" &&
   grep -Fq 'CORE::exec { $argv[0] } @argv;' "$command_module" &&
   grep -Fq 'desktop_stage_labwc_network_scan_action_perl_modules' "$components" &&
   grep -Fq 'LabwcNetworkScanAction/Client.pm' "$components" &&
   grep -Fq 'LabwcNetworkScanAction/Command.pm' "$components" &&
   grep -Fq 'LabwcNetworkScanAction/Validation.pm' "$components" &&
   grep -Fq 'usr/local/lib/perl5/site_perl/labwc-network-scan-action/LabwcNetworkScanAction/Root.pm.tmpl' "$components" &&
   grep -q 'usr/local/bin/labwc-network-scan-action /usr/local/bin/labwc-network-scan-action 0755' "$components" &&
   grep -q 'usr/local/libexec/labwc-network-scan-action-root.tmpl' "$components" &&
   grep -q '/usr/local/bin/labwc-network-scan-action' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-network-scan-action-root' "$desktop_verify"; then
  pass "network scanning stages the complete Perl client, validator, command, and rendered root boundary"
else
  fail "network scanning stages the complete Perl client, validator, command, and rendered root boundary"
fi

compat_root="$TMP_DIR/perl-compat"
rendered_root="$TMP_DIR/rendered-modules"
mkdir -p "$compat_root/MooX" "$compat_root/Types" "$rendered_root/LabwcNetworkScanAction"
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
            if (@_ > 1) {
                $self->{$name} = $_[1];
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
sed 's/__INSTALLER_ACCOUNT_USERNAME__/desktopuser/g' \
  "$root_template" >"$rendered_root/LabwcNetworkScanAction/Root.pm"

perl5lib="$compat_root:$rendered_root:$module_root"
compile_ok=true
for perl_file in \
  "$network_action" \
  "$network_root_entrypoint" \
  "$client_module" \
  "$command_module" \
  "$root_template" \
  "$validation_module" \
  "$rendered_root/LabwcNetworkScanAction/Root.pm"
do
  env PERL5LIB="$perl5lib" LC_ALL=C TZ=UTC /usr/bin/perl -c "$perl_file" >/dev/null 2>&1 ||
    compile_ok=false
done
if [ "$compile_ok" = true ] && ! grep -q '__INSTALLER_' "$rendered_root/LabwcNetworkScanAction/Root.pm"; then
  pass "network scanning Perl entrypoints, modules, and rendered root module compile"
else
  fail "network scanning Perl entrypoints, modules, and rendered root module compile"
fi

behavior_harness="$TMP_DIR/network-scanning-behavior.pl"
cat >"$behavior_harness" <<'PERL'
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use LabwcNetworkScanAction::Client;
use LabwcNetworkScanAction::Root;
use LabwcNetworkScanAction::Validation;

package Local::FakeCommand;
sub new {
    my ($class, %arguments) = @_;
    $arguments{calls} //= [];
    $arguments{executables} //= {};
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
    if (@argv == 2 && $argv[1] eq '-D') {
        return (0, "1. eth0\n2. any\n");
    }
    die "unexpected capture request: @argv\n";
}
sub run_to_new_file {
    my ($self, $path, @argv) = @_;
    push @{$self->{calls}}, ['write', $path, @argv];
    open my $handle, '>', $path or die "open $path: $!\n";
    print {$handle} "pcap\n" or die "write $path: $!\n";
    close $handle or die "close $path: $!\n";
    return 0;
}

package Local::Client;
our @ISA = ('LabwcNetworkScanAction::Client');
sub _require_capture_group { return; }

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
sub matching_call {
    my ($calls, $pattern) = @_;
    return scalar grep { join(q{ }, @{$_}) =~ $pattern } @{$calls};
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
my $tmp = $ENV{NETWORK_SCAN_TEST_TMP} // die "NETWORK_SCAN_TEST_TMP is unset\n";
my $validator = LabwcNetworkScanAction::Validation->new();

if ($case eq 'target-validation') {
    require_true($validator->nmap_target('192.168.50.0/24', 'private-scan') eq '192.168.50.0/24', 'private target changed');
    require_true($validator->nmap_target('8.8.8.8', 'authorized-wan-scan') eq '8.8.8.8', 'WAN target changed');
    expect_failure(qr/private network scans are bounded/, sub { $validator->nmap_target('192.168.0.0/16', 'private-scan') });
    expect_failure(qr/private scan scope requires/, sub { $validator->nmap_target('8.8.8.8', 'private-scan') });
    expect_failure(qr/WAN scan scope cannot target private/, sub { $validator->nmap_target('10.0.0.1', 'authorized-wan-scan') });
    expect_failure(qr/WAN scans reject protocol-assignment/, sub { $validator->nmap_target('203.0.113.10', 'authorized-wan-scan') });
    expect_failure(qr/WAN scans accept one public IPv4 host/, sub { $validator->nmap_target('8.8.8.0/24', 'authorized-wan-scan') });
}
elsif ($case eq 'capture-validation') {
    my $home = File::Spec->catdir($tmp, 'home');
    make_path($home, { mode => 0700 });
    my $path = $validator->new_capture_path($home, 'dumpcap', 'dns', 'pcapng');
    require_true(index($path, File::Spec->catdir($home, 'Captures', 'network-scanning') . '/') == 0, 'capture path escaped root');
    open my $handle, '>', $path or die "open $path: $!\n";
    print {$handle} "capture\n" or die "write $path: $!\n";
    close $handle or die "close $path: $!\n";
    require_true($validator->capture_file($home, $path) eq $path, 'managed capture path changed');

    my $outside = File::Spec->catfile($tmp, 'outside.pcap');
    open $handle, '>', $outside or die "open $outside: $!\n";
    print {$handle} "capture\n" or die "write $outside: $!\n";
    close $handle or die "close $outside: $!\n";
    expect_failure(qr/outside the managed capture directory/, sub { $validator->capture_file($home, $outside) });
    expect_failure(qr/must be an absolute path/, sub { $validator->capture_file($home, 'capture.pcap') });

    my $symlink = File::Spec->catfile($home, 'Captures', 'network-scanning', 'link.pcap');
    symlink $path, $symlink or die "symlink $symlink: $!\n";
    expect_failure(qr/symlinks are not allowed/, sub { $validator->capture_file($home, $symlink) });
}
elsif ($case eq 'request-shape') {
    my $client = LabwcNetworkScanAction::Client->new(validator => $validator);
    $client->_validate_request_shape('nmap-approved-services', '192.168.50.0/24', 'private-scan');
    $client->_validate_request_shape('nmap-tls-settings', '8.8.8.8', 'authorized-wan-scan');
    $client->_validate_request_shape('tcpdump-capture-dns', 'eth0');
    $client->_validate_request_shape('wireshark-launch');
    expect_failure(qr/unsupported characters/, sub {
        $client->_validate_request_shape('nmap-discovery', '8.8.8.8;id', 'authorized-wan-scan');
    });
    expect_failure(qr/scope authorization is invalid/, sub {
        $client->_validate_request_shape('nmap-discovery', '8.8.8.8', 'missing-confirmation');
    });
    expect_failure(qr/invalid capture interface/, sub {
        $client->_validate_request_shape('tcpdump-capture-dns', '../eth0');
    });
}
elsif ($case eq 'wireshark-argv') {
    my $home = File::Spec->catdir($tmp, 'wireshark-home');
    make_path(File::Spec->catdir($home, 'Captures', 'network-scanning'), { mode => 0700 });
    my $capture = File::Spec->catfile($home, 'Captures', 'network-scanning', 'managed.pcapng');
    open my $handle, '>', $capture or die "open $capture: $!\n";
    print {$handle} "capture\n" or die "write $capture: $!\n";
    close $handle or die "close $capture: $!\n";

    my $command = Local::FakeCommand->new(
        executables => { setsid => 1, wireshark => 1 },
    );
    my $client = LabwcNetworkScanAction::Client->new(
        command => $command,
        validator => $validator,
    );
    bless $client, 'Local::Client';
    local $ENV{HOME} = $home;
    $client->_run_wireshark_action('wireshark-launch');
    $client->_run_wireshark_action('wireshark-open-capture', $capture);
    require_true(has_call($command->calls(), '/mock/setsid', '-f', '/mock/wireshark'), 'Wireshark launch argv missing');
    require_true(has_call($command->calls(), '/mock/setsid', '-f', '/mock/wireshark', '-r', $capture), 'Wireshark capture argv missing');
}
elsif ($case eq 'root-argv') {
    my $script_root = File::Spec->catdir($tmp, 'nmap-scripts');
    make_path($script_root, { mode => 0700 });
    for my $name ('managed-approved-services.nse') {
        my $path = File::Spec->catfile($script_root, $name);
        open my $handle, '>', $path or die "open $path: $!\n";
        print {$handle} "description = 'test'\n" or die "write $path: $!\n";
        close $handle or die "close $path: $!\n";
    }
    my $command = Local::FakeCommand->new(
        executables => { ip => 1, nmap => 1, ss => 1, tcpdump => 1, timeout => 1 },
    );
    my $root = LabwcNetworkScanAction::Root->new(
        command => $command,
        nmap_script_root => $script_root,
    );
    dispatch_allow_exec($root, 'nmap-approved-services', '192.168.50.0/24', 'private-scan');
    dispatch_allow_exec($root, 'tcpdump-capture-dns', 'any');
    dispatch_allow_exec($root, 'show-listening-ports');

    require_true(
        matching_call(
            $command->calls(),
            qr{\A/mock/timeout --signal=INT --kill-after=10s 25m /mock/nmap -n --max-rate 250 .* --script .*managed-approved-services[.]nse .* 192[.]168[.]50[.]0/24\z},
        ) == 1,
        'bounded approved-services Nmap argv missing',
    );
    require_true(
        has_call(
            $command->calls(),
            '/mock/timeout', '--preserve-status', '--signal=INT', '--kill-after=5s', '60s',
            '/mock/tcpdump', '-i', 'any', '-nn', '-s', '256', '-c', '20000', '-w', '-', 'port', '53',
        ),
        'bounded tcpdump DNS argv missing',
    );
    require_true(has_call($command->calls(), '/mock/ss', '-tulpen'), 'listening-port argv missing');
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
    NETWORK_SCAN_TEST_TMP="$TMP_DIR" \
    LC_ALL=C \
    TZ=UTC \
    /usr/bin/perl "$behavior_harness" "$case_name"
}

if run_behavior_case target-validation; then
  pass "network scan validation separates bounded private targets from explicitly authorized public hosts"
else
  fail "network scan validation separates bounded private targets from explicitly authorized public hosts"
fi

if run_behavior_case capture-validation; then
  pass "network scan validation confines owned capture files to the managed capture directory"
else
  fail "network scan validation confines owned capture files to the managed capture directory"
fi

if run_behavior_case request-shape; then
  pass "network scan client rejects malformed interfaces, targets, and missing scope authorization"
else
  fail "network scan client rejects malformed interfaces, targets, and missing scope authorization"
fi

if run_behavior_case wireshark-argv; then
  pass "network scan client launches Wireshark unprivileged with fixed managed-capture argv"
else
  fail "network scan client launches Wireshark unprivileged with fixed managed-capture argv"
fi

if run_behavior_case root-argv; then
  pass "network scan root module maps approved Nmap, tcpdump, and listening-port actions to bounded fixed argv"
else
  fail "network scan root module maps approved Nmap, tcpdump, and listening-port actions to bounded fixed argv"
fi

if grep -Fq '$> != 0' "$client_module" &&
   grep -Fq 'labwc-network-scan-action must run as the logged-in desktop user' "$client_module" &&
   grep -Fq 'Wireshark GUI actions must be launched directly from the desktop session' "$client_module"; then
  pass "network scan client preserves the non-root desktop and internal-mode GUI boundaries"
else
  fail "network scan client preserves the non-root desktop and internal-mode GUI boundaries"
fi

[ "$FAIL_COUNT" -eq 0 ]
