use strict;
use warnings;

use Config ();
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use POSIX ();

BEGIN {
    require File::Path;
    require File::Temp;

    my $stub_root = File::Temp::tempdir(CLEANUP => 1);
    File::Path::make_path(
        "$stub_root/MooX/Types/MooseLike",
    );

    my %stubs = (
        'Moo.pm' => <<'MOO',
package Moo;
our %ATTRIBUTES;
sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::has"} = sub {
        my ($name, %options) = @_;
        $ATTRIBUTES{$caller}{$name} = \%options;
        *{"${caller}::$name"} = sub {
            my ($self, @values) = @_;
            $self->{$name} = $values[0] if @values;
            return $self->{$name};
        };
    };
    *{"${caller}::new"} = sub {
        my ($class, %arguments) = @_;
        my $self = bless {}, $class;
        for my $name (keys %{$ATTRIBUTES{$class} || {}}) {
            my $options = $ATTRIBUTES{$class}{$name};
            if (exists $arguments{$name}) {
                $self->{$name} = $arguments{$name};
            }
            elsif (exists $options->{default}) {
                $self->{$name} = ref($options->{default}) eq 'CODE'
                    ? $options->{default}->($self)
                    : $options->{default};
            }
        }
        return $self;
    };
}
1;
MOO
        'MooX/StrictConstructor.pm' => <<'STRICT',
package MooX::StrictConstructor;
sub import { return; }
1;
STRICT
        'MooX/Types/MooseLike/Base.pm' => <<'BASE',
package MooX::Types::MooseLike::Base;
sub import {
    my $caller = caller;
    no strict 'refs';
    for my $name (@_[1 .. $#_]) {
        *{"${caller}::$name"} = sub { return sub { 1 }; };
    }
}
1;
BASE
        'MooX/Types/MooseLike/Numeric.pm' => <<'NUMERIC',
package MooX::Types::MooseLike::Numeric;
sub import {
    my $caller = caller;
    no strict 'refs';
    for my $name (@_[1 .. $#_]) {
        *{"${caller}::$name"} = sub { return sub { 1 }; };
    }
}
1;
NUMERIC
    );

    for my $relative_path (sort keys %stubs) {
        my $path = "$stub_root/$relative_path";
        open my $fh, '>', $path or die "open $path: $!";
        print {$fh} $stubs{$relative_path} or die "write $path: $!";
        close $fh or die "close $path: $!";
    }

    unshift @INC, $stub_root;
}

use lib "$Bin/../d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback";
use Test::More;
use Zram::Config qw(load_config validate_config);
use Zram::Setup::BackingDevice;
use Zram::Setup::CLI;
use Zram::Setup::Device;

my $root = "$Bin/..";
my $template = "$root/d-i/forky/hooks/shared/target/etc/zram-writeback.conf";
open my $tfh, '<', $template or die "open $template: $!";
my $template_text = do { local $/; <$tfh> };
close $tfh or die "close $template: $!";
my $default_template = "$root/d-i/forky/hooks/shared/target/etc/default/zram-writeback.tmpl";
open my $dfh, '<', $default_template or die "open $default_template: $!";
my $default_template_text = do { local $/; <$dfh> };
close $dfh or die "close $default_template: $!";
my $setup_helper = "$root/d-i/forky/hooks/shared/target/usr/local/libexec/zram-device-setup.tmpl";
open my $shfh, '<', $setup_helper or die "open $setup_helper: $!";
my $setup_helper_text = do { local $/; <$shfh> };
close $shfh or die "close $setup_helper: $!";
my $setup_device = "$root/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback/Zram/Setup/Device.pm";
open my $sdfh, '<', $setup_device or die "open $setup_device: $!";
my $setup_device_text = do { local $/; <$sdfh> };
close $sdfh or die "close $setup_device: $!";
my $setup_backing_device = "$root/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback/Zram/Setup/BackingDevice.pm";
open my $sbdfh, '<', $setup_backing_device or die "open $setup_backing_device: $!";
my $setup_backing_device_text = do { local $/; <$sbdfh> };
close $sbdfh or die "close $sbdfh: $!";
my $tuning_module = "$root/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback/Zram/Tuning.pm";
open my $tmfh, '<', $tuning_module or die "open $tuning_module: $!";
my $tuning_module_text = do { local $/; <$tmfh> };
close $tmfh or die "close $tmfh: $!";
my $config_validator = "$root/d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback/Zram/Config/Validator.pm";
open my $cvfh, '<', $config_validator or die "open $config_validator: $!";
my $config_validator_text = do { local $/; <$cvfh> };
close $cvfh or die "close $cvfh: $!";
my @unit_templates = (
    "$root/d-i/forky/hooks/shared/target/etc/systemd/system/zram-setup.service.tmpl",
    "$root/d-i/forky/hooks/shared/target/etc/systemd/system/zram-writeback.service.tmpl",
    "$root/d-i/forky/hooks/shared/target/etc/systemd/system/zram-writebackd.service.tmpl",
    "$root/d-i/forky/hooks/shared/target/etc/systemd/system/zram-idle-writeback.timer.tmpl",
    "$root/d-i/forky/hooks/shared/target/etc/systemd/system/zram-cold-tier.timer.tmpl",
);

sub read_env_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    my %env;
    while (my $line = <$fh>) {
        next if $line =~ /\A\s*(?:#|\z)/;
        if ($line =~ /\A([A-Z0-9_]+)="([^"]*)"\s*(?:#.*)?\z/) {
            $env{$1} = $2;
        }
    }
    close $fh or die "close $path: $!";
    return %env;
}

my $shared_runtime = "$root/d-i/forky/hosts/shared/runtime.env";
my %shared_runtime = read_env_file($shared_runtime);
my $apt_fragment = "$root/d-i/forky/fragments/apt.cfg";
open my $afh, '<', $apt_fragment or die "open $apt_fragment: $!";
my $apt_fragment_text = do { local $/; <$afh> };
close $afh or die "close $apt_fragment: $!";
my ($pkgsel_include) = $apt_fragment_text =~ /^d-i\s+pkgsel\/include\s+string\s+(.+)$/m;
ok(defined $pkgsel_include, 'global apt fragment declares a pkgsel package policy');
my %pkgsel_packages = map { $_ => 1 } grep { length } split /\s+/, ($pkgsel_include // '');
my @zram_perl_runtime_packages = qw(
    liblog-any-perl
    libmoo-perl
    libmoox-handlesvia-perl
    libmoox-log-any-perl
    libmoox-options-perl
    libmoox-strictconstructor-perl
    libmoox-types-mooselike-numeric-perl
    libmoox-types-mooselike-perl
    libmoox-typetiny-perl
    libtype-tiny-perl
    libtypes-path-tiny-perl
);
is_deeply(
    [ grep { !$pkgsel_packages{$_} } @zram_perl_runtime_packages ],
    [],
    'role-neutral pkgsel policy supplies every ZRAM Perl runtime dependency',
);
my @profiles = sort glob "$root/d-i/forky/hosts/profiles/*/*.env";
ok(@profiles > 0, 'found concrete host profiles');
is_deeply(
    {
        map { $_ => $shared_runtime{$_} }
            qw(NFTABLES_LOG_LEVEL ZRAM_LOG_LEVEL SYSTEMD_LOG_LEVEL)
    },
    {
        NFTABLES_LOG_LEVEL => 'none',
        ZRAM_LOG_LEVEL     => 'error',
        SYSTEMD_LOG_LEVEL  => 'error',
    },
    'shared runtime policy owns installed-system log-level defaults',
);
like(
    $setup_helper_text,
    qr/\A#!\/usr\/bin\/perl.*?use Zram::Setup::CLI;.*?Zram::Setup::CLI->new\(\)->run\(\@ARGV\);/s,
    'zram device setup is a thin Perl entrypoint to the managed setup CLI',
);
like(
    $setup_device_text,
    qr/writeback_batch_size_for_state\('normal'\)/,
    'zram device setup starts from the bounded normal-state writeback batch size',
);
{
    pipe my $quiet_reader, my $quiet_writer
        or die "create zram quiet-command capture pipe: $!";
    my $quiet_probe_pid = fork;
    defined $quiet_probe_pid
        or die "fork zram quiet-command probe: $!";

    if ($quiet_probe_pid == 0) {
        close $quiet_reader
            or POSIX::_exit(2);
        open STDOUT, '>&', $quiet_writer
            or POSIX::_exit(2);
        open STDERR, '>&', $quiet_writer
            or POSIX::_exit(2);
        close $quiet_writer
            or POSIX::_exit(2);

        my $device = bless {}, 'Zram::Setup::Device';
        my $success = $device->_run_quiet(
            $Config::Config{perlpath},
            '-e',
            'print STDOUT "quiet-success-stdout\n"; print STDERR "quiet-success-stderr\n"; exit 0;',
        ) ? 1 : 0;
        my $failure = $device->_run_quiet(
            $Config::Config{perlpath},
            '-e',
            'print STDOUT "quiet-failure-stdout\n"; print STDERR "quiet-failure-stderr\n"; exit 7;',
        ) ? 1 : 0;
        my $marker = "success=$success failure=$failure\n";
        syswrite(STDOUT, $marker) == length($marker)
            or POSIX::_exit(2);
        POSIX::_exit(0);
    }

    close $quiet_writer
        or die "close zram quiet-command capture writer: $!";
    my $quiet_output = do {
        local $/;
        <$quiet_reader> // '';
    };
    close $quiet_reader
        or die "close zram quiet-command capture reader: $!";
    my $quiet_waited = waitpid $quiet_probe_pid, 0;
    my $quiet_status = $?;

    is(
        $quiet_waited,
        $quiet_probe_pid,
        'zram quiet-command probe waits for its child',
    );
    is(
        $quiet_status,
        0,
        'zram quiet-command probe exits successfully',
    );
    is(
        $quiet_output,
        "success=1 failure=0\n",
        'zram quiet-command execution preserves status without leaking child output',
    );
}
like(
    $setup_backing_device_text,
    qr/use Cwd qw\(abs_path\);.*?my \$canonical = abs_path\(\$device\);/s,
    'zram backing setup resolves device-mapper aliases before reading sysfs',
);
my $backing_sysfs_root = tempdir(CLEANUP => 1);
File::Path::make_path("$backing_sysfs_root/class/block/dm-0");
open my $rofh, '>', "$backing_sysfs_root/class/block/dm-0/ro"
    or die "open zram mapper ro attribute: $!";
print {$rofh} "0\n" or die "write zram mapper ro attribute: $!";
close $rofh or die "close zram mapper ro attribute: $!";
{
    no warnings 'redefine';
    local *Zram::Setup::BackingDevice::abs_path = sub { return '/dev/dm-0'; };
    local *Zram::Setup::BackingDevice::cfg = sub {
        $_[0] eq 'ZRAM_SYSFS_ROOT'
            or die "unexpected zram config key: $_[0]";
        return $backing_sysfs_root;
    };
    my $backing_device = Zram::Setup::BackingDevice->new(
        mapper => bless({}, 'Zram::Test::Mapper'),
    );
    is(
        $backing_device->_block_read_only('/dev/mapper/zram-writeback'),
        0,
        'zram backing setup reads dm-N sysfs state for a mapper alias',
    );
}
like(
    $tuning_module_text,
    qr/sub backing_queue_depth \{.*?_backing_queue_values\('nr_requests'\)/s,
    'zram writeback tuning clamps batch size to backing queue capacity',
);
like(
    $tuning_module_text,
    qr/sub _writeback_batch_size_for_state \{.*?ZRAM_WRITEBACK_BATCH_SIZE_ROTATIONAL_MAX.*?\$rotational == 1/s,
    'zram writeback tuning applies the rotational backing-media batch-size cap',
);
unlike(
    $tuning_module_text,
    qr/\b(?:return|target) 32\b/,
    'zram writeback tuning does not hardcode the initial batch size',
);
like(
    $setup_device_text,
    qr/sub _clear_runtime_state \{.*?writeback-budget[.]state/s,
    'zram device reset clears stale per-device writeback budget state',
);
like(
    $config_validator_text,
    qr/enabled recompression tiers .*?must not share priority/s,
    'zram device setup rejects duplicate enabled recompression priorities',
);
like(
    $config_validator_text,
    qr/for my \$tier \(1 \.\. 3\) \{.*?recompression_priority_tiers/s,
    'zram config validation checks every enabled recompression tier priority',
);

my @expected_default_keys = qw(
  ZRAM_ENABLE ZRAM_LOG_LEVEL
  ZRAM_SWAP_DEVICE ZRAM_SYSFS ZRAM_RUNTIME_DIR ZRAM_LOCK_FILE
  ZRAM_BACKING_RAW_DEVICE ZRAM_BACKING_MAPPER_NAME ZRAM_BACKING_DEVICE ZRAM_BACKING_RESERVE_MIB
  DMCRYPT_EPHEMERAL_CIPHER DMCRYPT_EPHEMERAL_KEY_SIZE DMCRYPT_EPHEMERAL_HASH DMCRYPT_RANDOM_KEY_FILE
  ZRAM_COMPRESSION_ALGORITHM ZRAM_ALGORITHM_PARAMS
  ZRAM_TIER1_ENABLE ZRAM_TIER1_ALGORITHM ZRAM_TIER1_PRIORITY ZRAM_TIER1_LEVEL
  ZRAM_TIER2_ENABLE ZRAM_TIER2_ALGORITHM ZRAM_TIER2_PRIORITY ZRAM_TIER2_LEVEL
  ZRAM_TIER3_ENABLE ZRAM_TIER3_ALGORITHM ZRAM_TIER3_PRIORITY ZRAM_TIER3_LEVEL
  ZRAM_SWAP_PRIORITY ZRAM_MAX_COMP_STREAMS
  ZRAM_WRITEBACK_ENABLE ZRAM_COMPRESSED_WRITEBACK ZRAM_WRITEBACK_BATCH_SIZE
  ZRAM_WRITEBACK_BATCH_SIZE_ADAPTIVE ZRAM_WRITEBACK_BATCH_SIZE_NORMAL
  ZRAM_WRITEBACK_BATCH_SIZE_ROTATIONAL_MAX ZRAM_WRITEBACK_BATCH_SIZE_MAX
  ZRAM_WRITEBACK_LIMIT_ENABLE
  ZRAM_PCT ZRAM_MIN_MIB ZRAM_MAX_MIB ZRAM_MEM_LIMIT_PCT ZRAM_WRITEBACK_LIMIT_PCT
  ZRAM_POLICY_CONFIG
);

for my $profile (@profiles) {
    my %env = (%shared_runtime, read_env_file($profile));
    my ($zram_name) = ($env{ZRAM_SWAP_DEVICE} || '/dev/zram0') =~ m{/([^/]+)\z};
    $env{ZRAM_ENABLE} = '1';
    $env{ZRAM_SWAP_DEVICE_NAME} = $zram_name || 'zram0';
    $env{ZRAM_SYSFS} = "/sys/block/$env{ZRAM_SWAP_DEVICE_NAME}";
    $env{ZRAM_RUNTIME_DIR} = '/run/zram';
    $env{ZRAM_LOCK_FILE} = '/run/zram/zram-writeback.lock';
    $env{ZRAM_BACKING_RAW_PARTUUID} = '11111111-2222-3333-4444-555555555555';
    $env{ZRAM_BACKING_RAW_DEVICE} = '/dev/nvme0n1p12';
    $env{ZRAM_BACKING_DEVICE} = '/dev/mapper/zram-writeback';
    $env{ZRAM_BACKING_MAPPER_NAME} = 'zram-writeback';
    $env{ZRAM_BACKING_RESERVE_MIB} = '128';
    $env{DMCRYPT_EPHEMERAL_CIPHER} = 'aes-xts-plain64';
    $env{DMCRYPT_EPHEMERAL_KEY_SIZE} = '512';
    $env{DMCRYPT_EPHEMERAL_HASH} = 'sha256';
    $env{DMCRYPT_RANDOM_KEY_FILE} = '/dev/urandom';
    $env{ZRAM_SETUP_UNIT} = 'zram-setup.service';
    $env{FILE_ZRAM_DEFAULT} = '/etc/default/zram-writeback';
    $env{FILE_ZRAM_CONFIG} = '/etc/zram-writeback.conf';
    $env{FILE_ZRAM_SETUP_HELPER} = '/usr/local/libexec/zram-device-setup';
    $env{FILE_ZRAM_WRITEBACK_HELPER} = '/usr/local/libexec/zram-writeback';
    $env{ZRAM_POLICY_CONFIG} = '/etc/zram-writeback.conf';
    $env{ZRAM_MAINTENANCE_IO_WRITE_BANDWIDTH_MAX} = '16M';
    $env{ZRAM_MAINTENANCE_MEMORY_HIGH} = '128M';
    $env{ZRAM_MAINTENANCE_MEMORY_MAX} = '256M';
    $env{ZRAM_IDLE_WRITEBACK_INTERVAL} = '15min';
    $env{ZRAM_IDLE_WRITEBACK_RANDOMIZED_DELAY} = '2min';
    $env{ZRAM_COLD_TIER_INTERVAL} = '1h';
    $env{ZRAM_COLD_TIER_RANDOMIZED_DELAY} = '5min';
    my $rendered = $template_text;
    $rendered =~ s/__([A-Z0-9_]+)__/
        exists $env{$1} ? $env{$1} : "__$1__"
    /gex;
    my $rendered_default = $default_template_text;
    $rendered_default =~ s/__INSTALLER_([A-Z0-9_]+)__/
        exists $env{$1} ? $env{$1} : "__INSTALLER_$1__"
    /gex;
    my $rendered_setup = $setup_helper_text;
    $rendered_setup =~ s/__INSTALLER_([A-Z0-9_]+)__/
        exists $env{$1} ? $env{$1} : "__INSTALLER_$1__"
    /gex;
    my @rendered_units;
    for my $unit_template (@unit_templates) {
        open my $ufh, '<', $unit_template or die "open $unit_template: $!";
        my $unit_text = do { local $/; <$ufh> };
        close $ufh or die "close $unit_template: $!";
        $unit_text =~ s/__INSTALLER_([A-Z0-9_]+)__/
            exists $env{$1} ? $env{$1} : "__INSTALLER_$1__"
        /gex;
        push @rendered_units, [$unit_template, $unit_text];
    }

    unlike($rendered, qr/__[A-Z0-9_]+__/, "$profile renders every zram config placeholder");
    unlike($rendered_default, qr/__INSTALLER_[A-Z0-9_]+__/, "$profile renders every zram default placeholder");
    unlike($rendered_setup, qr/__INSTALLER_[A-Z0-9_]+__/, "$profile renders every zram setup placeholder");
    my @rendered_default_keys = map { /\A([A-Z0-9_]+)=/ ? $1 : () } split /\n/, $rendered_default;
    is_deeply(\@rendered_default_keys, \@expected_default_keys, "$profile renders only shell-bootstrap zram defaults");
    like($rendered_default, qr{\A# /etc/default/zram-writeback\n# Shell-sourced bootstrap configuration[.]\n# Keep this file root-owned and not world-writable[.]\n}, "$profile keeps the requested zram default header");
    is($env{ZRAM_MAX_COMP_STREAMS}, '0', "$profile uses automatic zram compression streams");
    my $desktop_profile = $profile =~ m{/hosts/profiles/(?:btrfs|f2fs|vm)/desktop[.]env\z}
        || $profile =~ m{/hosts/profiles/override/(?:btrfs|f2fs)-de(?:-[a-z0-9]+)*[.]env\z};
    if ($desktop_profile) {
        is_deeply(
            {
                map { ("tier$_" => $env{"ZRAM_TIER${_}_ALGORITHM"}) } (1 .. 3)
            },
            {
                tier1 => 'lzo-rle',
                tier2 => 'zstd',
                tier3 => 'zstd',
            },
            "$profile uses the desktop lzo-rle, zstd, zstd recompression order",
        );
        is_deeply(
            {
                map { ("tier$_" => $env{"ZRAM_TIER${_}_LEVEL"}) } (1 .. 3)
            },
            {
                tier1 => '0',
                tier2 => '3',
                tier3 => '1',
            },
            "$profile uses the requested desktop zstd compression levels",
        );
        is_deeply(
            {
                map { ("tier$_" => $env{"ZRAM_TIER${_}_PRIORITY"}) } (1 .. 3)
            },
            {
                tier1 => '1',
                tier2 => '2',
                tier3 => '3',
            },
            "$profile assigns tier priorities in recompression order",
        );
        is_deeply(
            {
                map { ("tier$_" => $env{"ZRAM_TIER${_}_THRESHOLD_BYTES"}) } (1 .. 3)
            },
            {
                tier1 => '2048',
                tier2 => '3000',
                tier3 => '3584',
            },
            "$profile applies the requested desktop recompression thresholds",
        );
    }
    my @enabled_recompression_priorities = map {
        $env{"ZRAM_TIER${_}_PRIORITY"}
    } grep {
        $env{"ZRAM_TIER${_}_ENABLE"} eq '1'
    } 1 .. 3;
    my %enabled_recompression_priorities = map { $_ => 1 } @enabled_recompression_priorities;
    is(
        scalar @enabled_recompression_priorities,
        scalar keys %enabled_recompression_priorities,
        "$profile uses distinct enabled recompression priorities",
    );
    like($rendered, qr/^lock_file = \Q$env{ZRAM_LOCK_FILE}\E$/m, "$profile renders the shared zram lifecycle lock path");
    unlike(
        $rendered_default,
        qr/\b(?:ZRAM_PRESSURE|ZRAM_COLD_TIER|ZRAM_IDLE_WRITEBACK|ZRAM_DAEMON|ZRAM_HOT_AGE|ZRAM_DAILY_WRITEBACK_LIMIT|ZRAM_MAINTENANCE|ZRAM_MIN_FREE_MEMORY|ZRAM_WRITEBACK_MIN_REMAINING)/,
        "$profile keeps runtime policy out of shell zram defaults"
    );
    for my $unit (@rendered_units) {
        my ($unit_template, $unit_text) = @{$unit};
        unlike($unit_text, qr/__INSTALLER_[A-Z0-9_]+__/, "$unit_template renders every systemd placeholder for $profile");
        if ($unit_template =~ /zram-setup[.]service[.]tmpl\z/) {
            unlike($unit_text, qr/ZRAM_WRITEBACK_CONFIG|zram-writeback[.]tmpl|FILE_ZRAM_WRITEBACK_HELPER/, "$unit_template stays shell-only for $profile");
            like($unit_text, qr/^After=local-fs[.]target systemd-modules-load[.]service swap-fallback[.]service swap[.]target$/m, "$unit_template starts after the generic swap boundary so custom teardown runs first for $profile");
            like($unit_text, qr/^Wants=local-fs[.]target systemd-modules-load[.]service swap-fallback[.]service swap[.]target$/m, "$unit_template pulls in the generic swap boundary for deterministic reverse ordering for $profile");
            like($unit_text, qr/^Before=multi-user[.]target$/m, "$unit_template completes before multi-user for $profile");
            unlike($unit_text, qr/^ConditionPathExists=\/dev\/disk\/by-partuuid\//m, "$unit_template lets the helper wait for raw backing device for $profile");
        }
        if ($unit_template =~ /zram-writeback[.]service[.]tmpl\z/) {
            like($unit_text, qr/^After=zram-setup[.]service sys-kernel-debug[.]mount$/m, "$unit_template waits for setup for $profile");
            like($unit_text, qr/^Requires=zram-setup[.]service$/m, "$unit_template requires setup for $profile");
            like($unit_text, qr/^EnvironmentFile=\/etc\/default\/zram-writeback$/m, "$unit_template loads shell bootstrap defaults for $profile");
            like($unit_text, qr/^ExecStart=\/usr\/local\/libexec\/zram-writeback --config \$\{ZRAM_POLICY_CONFIG\} run$/m, "$unit_template uses policy config from defaults for $profile");
            like($unit_text, qr/^ReadWritePaths=\/run\/zram$/m, "$unit_template keeps runtime writes scoped for $profile");
        }
        if ($unit_template =~ /zram-writebackd[.]service[.]tmpl\z/) {
            like($unit_text, qr/^After=zram-setup[.]service sys-kernel-debug[.]mount$/m, "$unit_template waits for setup for $profile");
            like($unit_text, qr/^BindsTo=zram-setup[.]service$/m, "$unit_template is bound to setup lifecycle for $profile");
            like($unit_text, qr/^PartOf=zram-setup[.]service$/m, "$unit_template stops with setup lifecycle for $profile");
            like($unit_text, qr/^Requires=zram-setup[.]service$/m, "$unit_template requires setup for $profile");
            like($unit_text, qr/^ConditionPathExists=\/proc\/pressure\/memory$/m, "$unit_template requires PSI memory pressure support for $profile");
            like($unit_text, qr/^ExecStartPre=\/usr\/local\/libexec\/zram-writeback --config \$\{ZRAM_POLICY_CONFIG\} validate-runtime$/m, "$unit_template validates runtime before daemon start for $profile");
            like($unit_text, qr/^ExecStart=\/usr\/local\/libexec\/zram-writeback --config \$\{ZRAM_POLICY_CONFIG\} daemon$/m, "$unit_template runs the PSI daemon for $profile");
            like($unit_text, qr/^Restart=on-failure$/m, "$unit_template restarts only failed daemon exits for $profile");
            like($unit_text, qr/^TasksMax=16$/m, "$unit_template bounds daemon task fanout for $profile");
        }
        if ($unit_template =~ /zram-(?:idle-writeback|cold-tier)[.]timer[.]tmpl\z/) {
            like($unit_text, qr/^After=zram-setup[.]service$/m, "$unit_template waits for setup for $profile");
            like($unit_text, qr/^Requires=zram-setup[.]service$/m, "$unit_template requires setup for $profile");
        }
    }
    my ($fh, $path) = tempfile();
    print {$fh} $rendered;
    close $fh or die "close rendered config: $!";
    load_config($path);
    ok(eval { validate_config(require_sysfs => 0); 1 }, "$profile validates rendered zram config");
    unlink $path;
}

done_testing;
