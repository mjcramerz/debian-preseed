use strict;
use warnings;

use Cwd qw(abs_path);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Test::More;

my $repo_root = abs_path("$Bin/..");
my $module_base = File::Spec->catdir(
    $repo_root,
    qw(d-i forky hooks role desktop target usr local lib perl5 site_perl),
);

my @expected_roots = qw(
  ai-copilots
  apparmor-managed-modes
  digital-assets
  external-managed-software
  labwc-adb
  labwc-network-control-action
  labwc-network-scan-action
  labwc-security-action
  telpoll
  whisper
);

my @module_paths;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            return if !-f $_;
            return if $_ !~ /[.]pm(?:[.]tmpl)?\z/;
            push @module_paths, $File::Find::name;
        },
    },
    $module_base,
);
@module_paths = sort @module_paths;

is(scalar(@module_paths), 102, 'desktop site_perl inventory contains 102 modules');

opendir my $module_dir, $module_base or die "opendir $module_base: $!";
my @actual_roots = sort grep {
    $_ ne q{.}
        && $_ ne q{..}
        && -d File::Spec->catdir($module_base, $_);
} readdir $module_dir;
closedir $module_dir or die "closedir $module_base: $!";
is_deeply(\@actual_roots, \@expected_roots, 'desktop site_perl roots are canonical');

my (%package_path, %package_text, %local_dependencies);
for my $path (@module_paths) {
    my $text = read_text($path);
    my @packages = $text =~ /^[ \t]*package[ \t]+([A-Za-z_][A-Za-z0-9_:]*)[ \t]*;/mg;
    is(scalar(@packages), 1, relative_path($path) . ' declares one package');
    next if @packages != 1;

    my $package = $packages[0];
    ok(!exists($package_path{$package}), "$package is declared once");
    $package_path{$package} = $path;
    $package_text{$package} = $text;

    my $root_relative = File::Spec->abs2rel(
        $path,
        File::Spec->catdir(
            $module_base,
            (File::Spec->splitdir(File::Spec->abs2rel($path, $module_base)))[0],
        ),
    );
    my $expected_relative = $package;
    $expected_relative =~ s{::}{/}g;
    $expected_relative .= $path =~ /[.]pm[.]tmpl\z/ ? '.pm.tmpl' : '.pm';
    is($root_relative, $expected_relative, "$package matches its installed path");

    my @dependencies =
      $text =~ /^[ \t]*(?:use|require)[ \t]+([A-Za-z_][A-Za-z0-9_:]*)\b/mg;
    $local_dependencies{$package} = \@dependencies;
}

my %local_prefix = map { (split /::/, $_, 2)[0] => 1 } keys %package_path;
for my $package (sort keys %local_dependencies) {
    for my $dependency (@{ $local_dependencies{$package} }) {
        next if !$local_prefix{(split /::/, $dependency, 2)[0]};
        ok(
            exists($package_path{$dependency}),
            "$package local dependency $dependency resolves",
        );
    }
}

for my $path (@module_paths) {
    my $text = read_text($path);
    while (
        $text =~
          /^[ \t]*use[ \t]+([A-Za-z_][A-Za-z0-9_:]*)[ \t]+qw[(](.*?)[)][ \t]*;/msg
      )
    {
        my ($dependency, $raw_symbols) = ($1, $2);
        next if !exists($package_text{$dependency});

        my @symbols = grep { $_ ne q{} } split /\s+/, $raw_symbols;
        next if !@symbols;

        my %exported;
        while (
            $package_text{$dependency} =~
              /our[ \t]+\@EXPORT(?:_OK)?[ \t]*=[ \t]*qw[(](.*?)[)][ \t]*;/msg
          )
        {
            $exported{$_} = 1 for grep { $_ ne q{} } split /\s+/, $1;
        }
        my @missing = grep { !$exported{$_} } @symbols;
        is_deeply(
            \@missing,
            [],
            relative_path($path) . " imports only exported symbols from $dependency",
        );
    }
}

my %manifest = (
    'ai-copilots' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_ai_copilots_perl_modules',
        [],
    ],
    'apparmor-managed-modes' => [
        'd-i/forky/scripts/late/security.sh',
        'apparmor_managed_modes_perl_modules',
        [],
    ],
    'digital-assets' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_digital_assets_perl_modules',
        [],
    ],
    'external-managed-software' => [
        'd-i/forky/scripts/late/software.sh',
        'software_perl_modules',
        [],
    ],
    'labwc-adb' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_labwc_adb_perl_modules',
        [],
    ],
    'labwc-network-control-action' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_labwc_network_control_action_perl_modules',
        [],
    ],
    'labwc-network-scan-action' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_labwc_network_scan_action_perl_modules',
        ['LabwcNetworkScanAction/Root.pm.tmpl'],
    ],
    'labwc-security-action' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_labwc_security_action_perl_modules',
        [],
    ],
    'telpoll' => [
        'd-i/forky/scripts/desktop/components.sh',
        'desktop_telpoll_perl_modules',
        [],
    ],
    'whisper' => [
        'd-i/forky/scripts/late/whisper.sh',
        'whisper_mode_perl_modules',
        [],
    ],
);

for my $root (@expected_roots) {
    my ($script_relative, $function, $extra) = @{ $manifest{$root} };
    my $script_path = File::Spec->catfile($repo_root, split m{/}, $script_relative);
    my @declared = extract_manifest(read_text($script_path), $function);
    push @declared, @{$extra};
    @declared = sort @declared;

    my @tracked = sort map {
        File::Spec->abs2rel($_, File::Spec->catdir($module_base, $root));
    } grep {
        my $relative = File::Spec->abs2rel($_, $module_base);
        (File::Spec->splitdir($relative))[0] eq $root;
    } @module_paths;

    is_deeply(\@declared, \@tracked, "$root staging manifest is exact");
}

my @required_packages = qw(
  libmoo-perl
  libmoox-options-perl
  libmoox-strictconstructor-perl
  libmoox-typetiny-perl
  libmoox-types-mooselike-perl
  libtype-tiny-perl
);
for my $policy_relative (
    'd-i/forky/fragments/apt.cfg',
    'd-i/forky/classes/class-select/role/desktop.cfg',
  )
{
    my $policy_path = File::Spec->catfile($repo_root, split m{/}, $policy_relative);
    my $policy = read_text($policy_path);
    for my $package (@required_packages) {
        like(
            $policy,
            qr/(?:\A|\s)\Q$package\E(?:\s|\z)/,
            "$policy_relative installs $package",
        );
    }
}

my %entrypoints = (
    'ai-copilots' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-ai-copilots-action',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-ai-llama-server',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-ai-model-install-root',
    ],
    'apparmor-managed-modes' => [
        'd-i/forky/hooks/shared/target/usr/local/libexec/apparmor-managed-modes-run',
    ],
    'digital-assets' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-digital-assets-action',
    ],
    'external-managed-software' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/managed-external-software-notify',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/managed-external-software-update',
    ],
    'labwc-adb' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-adb-action',
    ],
    'labwc-network-control-action' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-control-action',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-control-action-root',
    ],
    'labwc-network-scan-action' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-network-scan-action',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-network-scan-action-root.tmpl',
    ],
    'labwc-security-action' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-security-action',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/apparmor-generate-rules',
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-security-action-root',
    ],
    'telpoll' => [
        'd-i/forky/hooks/shared/target/usr/local/libexec/telpoll',
    ],
    'whisper' => [
        'd-i/forky/hooks/role/desktop/target/usr/local/libexec/whisper-record-toggle',
    ],
);

my @perl_entrypoints;
for my $root (@expected_roots) {
    my $installed_root = "/usr/local/lib/perl5/site_perl/$root";
    for my $entry_relative (@{ $entrypoints{$root} }) {
        my $entry_path = File::Spec->catfile($repo_root, split m{/}, $entry_relative);
        my $entry_text = read_text($entry_path);
        like($entry_text, qr/\Q$installed_root\E/, "$entry_relative uses $installed_root");
        push @perl_entrypoints, $entry_path if $entry_text =~ /\A#![^\n]*perl\b/;
    }
}

my %entry_modules = (
    'ai-copilots' => [
        'AICopilots::CLI',
        'AICopilots::ModelInstallRoot',
        'AICopilots::Runtime',
        'AICopilots::Session',
    ],
    'apparmor-managed-modes' => [qw(
      AppArmor::ManagedModes::CLI
      AppArmor::ManagedModes::Config
      AppArmor::ManagedModes::Tool
      AppArmor::ManagedModes::Transition
      AppArmor::ManagedModes::TrustedPath
      AppArmor::ManagedModes::Verify
      AppArmor::ManagedModes::Workspace
    )],
    'digital-assets' => ['DigitalAssets::CLI'],
    'external-managed-software' => ['ExternalSoftware::Servicing::CLI'],
    'labwc-adb' => ['AndroidADB::CLI'],
    'labwc-network-control-action' => [
        'LabwcNetworkControlAction::Client',
        'LabwcNetworkControlAction::Root',
    ],
    'labwc-network-scan-action' => [
        'LabwcNetworkScanAction::Client',
        'LabwcNetworkScanAction::Root',
    ],
    'labwc-security-action' => [
        'LabwcSecurityAction::AppArmor::RuleGenerator',
        'LabwcSecurityAction::Client',
        'LabwcSecurityAction::Root',
    ],
    'telpoll' => ['Telpoll::CLI'],
    'whisper' => ['WhisperMode::CLI'],
);

for my $root (@expected_roots) {
    my %reachable;
    my @pending = @{ $entry_modules{$root} };
    while (my $package = shift @pending) {
        next if $reachable{$package}++;
        push @pending, grep {
            exists($package_path{$_}) && !$reachable{$_}
        } @{ $local_dependencies{$package} // [] };
    }
    my @root_packages = sort grep {
        my $relative = File::Spec->abs2rel($package_path{$_}, $module_base);
        (File::Spec->splitdir($relative))[0] eq $root;
    } keys %package_path;
    my @unreachable = grep { !$reachable{$_} } @root_packages;
    is_deeply(\@unreachable, [], "$root modules are reachable from installed entrypoints");
}

like(
    $package_text{'Telpoll::Config'},
    qr/has ownership_conflict_backoff_seconds =>/,
    'telpoll configuration exposes the ownership-conflict backoff',
);
like(
    $package_text{'Telpoll::Config'},
    qr/['"]TELPOLL_OWNERSHIP_CONFLICT_BACKOFF_SECONDS['"],[\s\S]*?60,[\s\S]*?86_400,/,
    'telpoll bounds the ownership-conflict backoff from 60 through 86400 seconds',
);
like(
    $package_text{'Telpoll::Daemon'},
    qr/if \(_is_get_updates_ownership_conflict\(\$error\)\)[\s\S]*?ownership_conflict_backoff_seconds\(\)/,
    'telpoll gives the exact getUpdates ownership conflict its configured backoff',
);
like(
    $package_text{'Telpoll::Daemon'},
    qr/return defined\(\$error\) && \$error eq \$GET_UPDATES_OWNERSHIP_CONFLICT;/,
    'telpoll ownership-conflict classification is exact rather than a broad HTTP 409 match',
);
like(
    $package_text{'Telpoll::Daemon'},
    qr/2 \*\* \(\$failures > 5 \? 5 : \$failures\)/,
    'telpoll preserves generic exponential retry behavior for other failures',
);
like(
    $package_text{'Telpoll::State'},
    qr/flock\(\$fh, LOCK_EX \| LOCK_NB\)/,
    'telpoll preserves the local nonblocking singleton lock',
);

my $stub_root = create_perl_stubs();
my $rendered_root = create_rendered_modules();
my @module_roots = map { File::Spec->catdir($module_base, $_) } @expected_roots;
local $ENV{PERL5LIB} = join q{:}, $stub_root, $rendered_root, @module_roots;
local $ENV{LC_ALL} = 'C';
local $ENV{TZ} = 'UTC';

{
    local @INC = ($stub_root, $rendered_root, @module_roots, @INC);
    require Telpoll::Daemon;
    require Telpoll::State;
    install_telpoll_test_accessors();
    test_telpoll_singleton_and_offsets();
}

for my $path (@module_paths) {
    my ($ok, $diagnostic) = compile_perl($path);
    ok($ok, relative_path($path) . ' compiles')
        or diag($diagnostic);
}
for my $path (sort @perl_entrypoints) {
    my ($ok, $diagnostic) = compile_perl($path);
    ok($ok, relative_path($path) . ' entrypoint compiles')
        or diag($diagnostic);
}

done_testing();

sub read_text {
    my ($path) = @_;
    open my $handle, '<', $path or die "open $path: $!";
    local $/;
    my $text = <$handle>;
    close $handle or die "close $path: $!";
    return $text;
}

sub relative_path {
    my ($path) = @_;
    return File::Spec->abs2rel($path, $repo_root);
}

sub extract_manifest {
    my ($text, $function) = @_;
    $text =~
      /^\Q$function\E[(][)][ \t]*[{][ \t]*\n[ \t]*cat[ \t]+<<['"]?EOF['"]?[ \t]*\n(.*?)^EOF[ \t]*$/ms
      or die "cannot parse $function manifest";
    return grep { $_ ne q{} } map {
        my $line = $_;
        $line =~ s/\A\s+//;
        $line =~ s/\s+\z//;
        $line;
    } split /\n/, $1;
}

sub create_perl_stubs {
    my $root = tempdir(CLEANUP => 1);
    my %stubs = (
        'Moo.pm' => <<'MOO',
package Moo;
use strict;
use warnings;
sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::has"} = sub { return; };
    return;
}
1;
MOO
        'MooX/Options.pm' => <<'OPTIONS',
package MooX::Options;
use strict;
use warnings;
sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::option"} = sub { return; };
    *{"${caller}::new_with_options"} = sub { return bless {}, $_[0]; };
    return;
}
1;
OPTIONS
        'MooX/StrictConstructor.pm' => <<'STRICT',
package MooX::StrictConstructor;
use strict;
use warnings;
sub import { return; }
1;
STRICT
        'MooX/TypeTiny.pm' => <<'TYPETINY',
package MooX::TypeTiny;
use strict;
use warnings;
sub import { return; }
1;
TYPETINY
        'MooX/Types/MooseLike/Base.pm' => <<'MOOSELIKE',
package MooX::Types::MooseLike::Base;
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
MOOSELIKE
        'Types/Standard.pm' => <<'TYPES',
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
TYPES
    );

    for my $relative (sort keys %stubs) {
        my @parts = split m{/}, $relative;
        my $filename = pop @parts;
        my $directory = File::Spec->catdir($root, @parts);
        make_path($directory);
        my $path = File::Spec->catfile($directory, $filename);
        open my $handle, '>', $path or die "open $path: $!";
        print {$handle} $stubs{$relative} or die "write $path: $!";
        close $handle or die "close $path: $!";
    }
    return $root;
}

sub create_rendered_modules {
    my $root = tempdir(CLEANUP => 1);
    my $source = File::Spec->catfile(
        $module_base,
        qw(labwc-network-scan-action LabwcNetworkScanAction Root.pm.tmpl),
    );
    my $text = read_text($source);
    $text =~ s/__INSTALLER_ACCOUNT_USERNAME__/desktop-test-user/g;

    my $directory = File::Spec->catdir(
        $root,
        qw(LabwcNetworkScanAction),
    );
    make_path($directory);
    my $path = File::Spec->catfile($directory, 'Root.pm');
    open my $handle, '>', $path or die "open $path: $!";
    print {$handle} $text or die "write $path: $!";
    close $handle or die "close $path: $!";
    return $root;
}

sub compile_perl {
    my ($path) = @_;
    my $error = gensym;
    my $perl = '/usr/bin/perl';
    my $pid = open3(undef, my $stdout, $error, $perl, '-c', $path);
    my $output = do { local $/; <$stdout> // q{} };
    my $diagnostic = do { local $/; <$error> // q{} };
    waitpid($pid, 0);
    my $status = $?;
    return ($status == 0, $output . $diagnostic);
}

sub install_telpoll_test_accessors {
    no strict 'refs';
    no warnings 'redefine';

    *{'Telpoll::State::directory'} = sub { return $_[0]->{directory}; };
    *{'Telpoll::State::max_bytes'} = sub {
        return $_[0]->{max_bytes} // (1024 * 1024);
    };
    *{'Telpoll::State::data'} = sub {
        my ($self) = @_;
        $self->{data} //= $self->_build_data();
        return $self->{data};
    };
    *{'Telpoll::State::lock_handle'} = sub {
        my ($self, $handle) = @_;
        $self->{lock_handle} = $handle if @_ > 1;
        return $self->{lock_handle};
    };

    for my $accessor (qw(config logger state telegram processor whisper)) {
        *{"Telpoll::Daemon::${accessor}"} = sub {
            return $_[0]->{$accessor};
        };
    }
    *{'Telpoll::Daemon::stop_requested'} = sub {
        my ($self, $value) = @_;
        $self->{stop_requested} = $value ? 1 : 0 if @_ > 1;
        return $self->{stop_requested} // 0;
    };
    return;
}

sub test_telpoll_singleton_and_offsets {
    my $lock_directory = tempdir(CLEANUP => 1);
    my $lock_owner = bless {
        directory => $lock_directory,
    }, 'Telpoll::State';
    my $owner_ok = eval {
        $lock_owner->acquire_lock();
        1;
    };
    ok($owner_ok, 'telpoll first state object acquires the local daemon lock')
        or diag($@);

    my $lock_contender = bless {
        directory => $lock_directory,
    }, 'Telpoll::State';
    my $contender_ok = eval {
        $lock_contender->acquire_lock();
        1;
    };
    ok(!$contender_ok, 'telpoll second state object fails the singleton lock nonblockingly');
    is(
        $@,
        "telpoll: another daemon instance is already running\n",
        'telpoll reports the exact local singleton-owner failure',
    );

    my $ownership_conflict =
        "telpoll: Telegram getUpdates failed with HTTP 409: " .
        "Conflict: terminated by other getUpdates request; " .
        "make sure that only one bot instance is running\n";
    my $conflict_state = TelpollTest::State->new(
        offset  => 17,
        pending => {
            17 => {
                attempts        => 0,
                delete_attempts => 0,
                local_complete  => 0,
                delete_message  => 0,
            },
        },
    );
    my $conflict_daemon = bless {
        config => TelpollTest::Config->new(
            ownership_conflict_backoff_seconds => 900,
            max_update_attempts                 => 5,
        ),
        logger    => TelpollTest::Logger->new(),
        state     => $conflict_state,
        telegram  => TelpollTest::Telegram->new(error => $ownership_conflict),
        processor => TelpollTest::Processor->new(state => $conflict_state),
        whisper   => TelpollTest::Whisper->new(),
    }, 'Telpoll::Daemon';
    my $observed_delay;
    my $conflict_ok;
    {
        no warnings 'redefine';
        local *Telpoll::Daemon::_sleep_interruptibly = sub {
            my ($self, $seconds) = @_;
            $observed_delay = $seconds;
            $self->stop_requested(1);
            return;
        };
        $conflict_ok = eval {
            $conflict_daemon->run(0);
            1;
        };
    }
    ok($conflict_ok, 'telpoll exact Telegram ownership conflict remains retryable')
        or diag($@);
    is($observed_delay, 900, 'telpoll exact ownership conflict selects the configured 900-second backoff');
    is($conflict_state->offset(), 17, 'telpoll ownership conflict leaves the update offset unchanged');
    is_deeply(
        $conflict_state->mutation_events(),
        [],
        'telpoll ownership conflict neither advances nor removes pending state',
    );
    ok(
        exists($conflict_state->pending()->{17}),
        'telpoll ownership conflict preserves existing pending state',
    );

    my $success_state = TelpollTest::State->new(offset => 41);
    my $success_processor = TelpollTest::Processor->new(state => $success_state);
    my $success_daemon = bless {
        config => TelpollTest::Config->new(
            ownership_conflict_backoff_seconds => 900,
            max_update_attempts                 => 5,
        ),
        logger => TelpollTest::Logger->new(),
        state  => $success_state,
        telegram => TelpollTest::Telegram->new(
            updates => [
                {
                    update_id => 41,
                    message   => { text => 'fixture' },
                },
            ],
        ),
        processor => $success_processor,
        whisper   => TelpollTest::Whisper->new(),
    }, 'Telpoll::Daemon';
    my $success_ok = eval {
        $success_daemon->poll_once();
        1;
    };
    ok($success_ok, 'telpoll processes a successful update fixture')
        or diag($@);
    is(
        $success_processor->offset_during_process(),
        41,
        'telpoll keeps the old offset while update processing is in progress',
    );
    is(
        $success_processor->advance_calls_during_process(),
        0,
        'telpoll does not acknowledge an update before processing completes',
    );
    is($success_state->offset(), 42, 'telpoll advances a processed update to update_id plus one');
    is_deeply(
        $success_state->mutation_events(),
        [qw(advance remove_pending)],
        'telpoll advances before removing the completed pending record',
    );
    ok(
        !exists($success_state->pending()->{41}),
        'telpoll removes pending state only after successful processing',
    );
    return;
}

package TelpollTest::Config;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub ownership_conflict_backoff_seconds {
    return $_[0]->{ownership_conflict_backoff_seconds};
}

sub max_update_attempts {
    return $_[0]->{max_update_attempts};
}

package TelpollTest::Logger;

sub new {
    my ($class) = @_;
    return bless { messages => [] }, $class;
}

sub log {
    my ($self, @message) = @_;
    push @{ $self->{messages} }, \@message;
    return;
}

package TelpollTest::State;

sub new {
    my ($class, %args) = @_;
    $args{pending} //= {};
    $args{mutation_events} = [];
    return bless \%args, $class;
}

sub offset {
    return $_[0]->{offset};
}

sub pending {
    return $_[0]->{pending};
}

sub mutation_events {
    return $_[0]->{mutation_events};
}

sub pending_for {
    my ($self, $update_id) = @_;
    $self->{pending}->{$update_id} //= {
        attempts        => 0,
        delete_attempts => 0,
        local_complete  => 0,
        delete_message  => 0,
    };
    return $self->{pending}->{$update_id};
}

sub save {
    return;
}

sub advance {
    my ($self, $offset) = @_;
    push @{ $self->{mutation_events} }, 'advance';
    $self->{offset} = $offset;
    return;
}

sub remove_pending {
    my ($self, $update_id) = @_;
    push @{ $self->{mutation_events} }, 'remove_pending';
    delete $self->{pending}->{$update_id};
    return;
}

package TelpollTest::Telegram;

sub new {
    my ($class, %args) = @_;
    $args{updates} //= [];
    return bless \%args, $class;
}

sub get_updates {
    my ($self) = @_;
    die $self->{error} if defined($self->{error});
    return $self->{updates};
}

sub delete_message {
    die "telpoll test fixture unexpectedly attempted message deletion\n";
}

package TelpollTest::Processor;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub process {
    my ($self) = @_;
    my $state = $self->{state};
    $self->{offset_during_process} = $state->offset();
    $self->{advance_calls_during_process} = scalar grep {
        $_ eq 'advance'
    } @{ $state->mutation_events() };
    return {
        delete_message => 0,
        message_id     => 0,
        chat_id        => q{},
    };
}

sub offset_during_process {
    return $_[0]->{offset_during_process};
}

sub advance_calls_during_process {
    return $_[0]->{advance_calls_during_process};
}

package TelpollTest::Whisper;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub release_reservation {
    die "telpoll test fixture unexpectedly released a Whisper reservation\n";
}

package main;
