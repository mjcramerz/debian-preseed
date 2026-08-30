use strict;
use warnings;

use Errno ();
use Fcntl qw(F_GETFD FD_CLOEXEC);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
my $lib = "$Bin/../d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback";
use lib "$Bin/../d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback";
use lib "$Bin/lib";
use Test::More;
use Zram::Command qw(dispatch requires_lock requires_sysfs);
use Zram::Config qw(load_config validate_config);
use Zram::Daemon qw(run_daemon);
use ZramTestConfig qw(required_tuning_ini);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

sub invalid_config_exits_nonzero {
    my ($config_path) = @_;
    open my $saved_stderr, '>&', \*STDERR or die "dup STDERR: $!";
    open STDERR, '>', File::Spec->devnull or die "redirect STDERR: $!";
    system(
        $^X,
        '-I',
        $lib,
        '-MZram::Config=load_config',
        '-e',
        'load_config($ARGV[0])',
        $config_path,
    );
    open STDERR, '>&', $saved_stderr or die "restore STDERR: $!";
    return $? != 0 ? 1 : 0;
}

ok(!requires_lock('daemon'), 'daemon does not hold the lifecycle lock for its full service lifetime');
ok(requires_sysfs('daemon'), 'daemon validates zram sysfs at startup');

my $runtime_root = $ENV{XDG_RUNTIME_DIR} || '/run/user/1000';
my $root = tempdir(DIR => $runtime_root, CLEANUP => 1);
my $sysfs_root = "$root/sys";
my $procfs_root = "$root/proc";
my $runtime_dir = "$root/run/zram";
make_path("$sysfs_root/block/zram0", "$procfs_root/pressure", $runtime_dir);
write_file("$procfs_root/pressure/memory", "some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n");

my ($disabled_fh, $disabled_path) = tempfile();
print {$disabled_fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[daemon]
enabled = 0
psi_some_stall_us = 150000
psi_full_stall_us = 50000

[paths]
sysfs_root = $sysfs_root
debugfs_root = $root/debug
procfs_root = $procfs_root
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
print {$disabled_fh} required_tuning_ini();
close $disabled_fh or die "close $disabled_path: $!";

load_config($disabled_path);
ok(eval { validate_config(require_sysfs => requires_sysfs('daemon')); 1 }, 'disabled daemon config still validates');
is(dispatch('daemon'), 0, 'disabled daemon command exits immediately');

my ($invalid_fh, $invalid_path) = tempfile();
print {$invalid_fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[daemon]
enabled = 1
psi_some_stall_us = 0
psi_full_stall_us = 0
INI
print {$invalid_fh} required_tuning_ini();
close $invalid_fh or die "close $invalid_path: $!";

ok(invalid_config_exits_nonzero($invalid_path), 'enabled daemon requires at least one positive PSI trigger threshold');

my ($unknown_key_fh, $unknown_key_path) = tempfile();
print {$unknown_key_fh} <<'INI';
[zram]
unexpected = 1
INI
close $unknown_key_fh or die "close $unknown_key_path: $!";

ok(invalid_config_exits_nonzero($unknown_key_path), 'unknown zram config keys are rejected');

my ($unknown_section_fh, $unknown_section_path) = tempfile();
print {$unknown_section_fh} <<'INI';
[unknown]
enabled = 1
INI
close $unknown_section_fh or die "close $unknown_section_path: $!";

ok(invalid_config_exits_nonzero($unknown_section_path), 'unknown zram config sections are rejected');

my ($missing_tuning_fh, $missing_tuning_path) = tempfile();
print {$missing_tuning_fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
INI
close $missing_tuning_fh or die "close $missing_tuning_path: $!";
ok(invalid_config_exits_nonzero($missing_tuning_path), 'profile-owned tuning keys have no hidden implementation fallback');

my ($invalid_batch_fh, $invalid_batch_path) = tempfile();
print {$invalid_batch_fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
INI
print {$invalid_batch_fh} required_tuning_ini(writeback_batch_size => 16);
close $invalid_batch_fh or die "close $invalid_batch_path: $!";
ok(invalid_config_exits_nonzero($invalid_batch_path), 'adaptive state targets cannot exceed the configured hard iodepth ceiling');

my ($invalid_size_percent_fh, $invalid_size_percent_path) = tempfile();
print {$invalid_size_percent_fh} <<'INI';
[zram]
size_percent = 0
INI
print {$invalid_size_percent_fh} required_tuning_ini();
close $invalid_size_percent_fh or die "close $invalid_size_percent_path: $!";
ok(invalid_config_exits_nonzero($invalid_size_percent_path), 'zram size percent must remain positive for shell sizing');

my ($invalid_size_bounds_fh, $invalid_size_bounds_path) = tempfile();
print {$invalid_size_bounds_fh} <<'INI';
[zram]
size_min_mib = 4096
size_max_mib = 2048
INI
print {$invalid_size_bounds_fh} required_tuning_ini();
close $invalid_size_bounds_fh or die "close $invalid_size_bounds_path: $!";
ok(invalid_config_exits_nonzero($invalid_size_bounds_path), 'zram size bounds must be ordered for shell sizing');

my ($invalid_mem_limit_percent_fh, $invalid_mem_limit_percent_path) = tempfile();
print {$invalid_mem_limit_percent_fh} <<'INI';
[zram]
mem_limit_percent = 0
INI
print {$invalid_mem_limit_percent_fh} required_tuning_ini();
close $invalid_mem_limit_percent_fh or die "close $invalid_mem_limit_percent_path: $!";
ok(invalid_config_exits_nonzero($invalid_mem_limit_percent_path), 'zram memory limit percent must remain positive for shell sizing');

my ($invalid_writeback_limit_percent_fh, $invalid_writeback_limit_percent_path) = tempfile();
print {$invalid_writeback_limit_percent_fh} <<'INI';
[writeback]
enabled = 1
writeback_limit_enabled = 1
writeback_limit_percent = 0
INI
print {$invalid_writeback_limit_percent_fh} required_tuning_ini();
close $invalid_writeback_limit_percent_fh or die "close $invalid_writeback_limit_percent_path: $!";
ok(
    invalid_config_exits_nonzero($invalid_writeback_limit_percent_path),
    'enabled writeback limiting requires a positive writeback percentage',
);

my ($invalid_daily_writeback_limit_fh, $invalid_daily_writeback_limit_path) = tempfile();
print {$invalid_daily_writeback_limit_fh} <<'INI';
[writeback]
daily_writeback_limit = 1K
INI
print {$invalid_daily_writeback_limit_fh} required_tuning_ini();
close $invalid_daily_writeback_limit_fh or die "close $invalid_daily_writeback_limit_path: $!";
ok(
    invalid_config_exits_nonzero($invalid_daily_writeback_limit_path),
    'nonzero daily writeback limits must contain at least one kernel writeback page',
);

my ($duplicate_recompression_priority_fh, $duplicate_recompression_priority_path) = tempfile();
print {$duplicate_recompression_priority_fh} <<'INI';
[recompression_tier1]
enabled = 1
priority = 1

[recompression_tier2]
enabled = 1
priority = 1
INI
print {$duplicate_recompression_priority_fh} required_tuning_ini();
close $duplicate_recompression_priority_fh or die "close $duplicate_recompression_priority_path: $!";
ok(
    invalid_config_exits_nonzero($duplicate_recompression_priority_path),
    'enabled recompression tiers must use distinct priorities',
);

my ($invalid_scan_limits_fh, $invalid_scan_limits_path) = tempfile();
print {$invalid_scan_limits_fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
INI
print {$invalid_scan_limits_fh} required_tuning_ini(
    block_state_max_lines => 100,
    block_state_fallback_lines => 101,
);
close $invalid_scan_limits_fh or die "close $invalid_scan_limits_path: $!";
ok(invalid_config_exits_nonzero($invalid_scan_limits_path), 'monitoring fallback cannot exceed the configured scan ceiling');

my ($invalid_window_fh, $invalid_window_path) = tempfile();
print {$invalid_window_fh} <<'INI';
[daemon]
psi_window_us = 100000
INI
print {$invalid_window_fh} required_tuning_ini();
close $invalid_window_fh or die "close $invalid_window_path: $!";
ok(invalid_config_exits_nonzero($invalid_window_path), 'PSI trigger window rejects values below the configured minimum');

my ($invalid_stall_fh, $invalid_stall_path) = tempfile();
print {$invalid_stall_fh} <<'INI';
[daemon]
psi_window_us = 500000
psi_some_stall_us = 500001
INI
print {$invalid_stall_fh} required_tuning_ini();
close $invalid_stall_fh or die "close $invalid_stall_path: $!";
ok(invalid_config_exits_nonzero($invalid_stall_path), 'PSI stall threshold cannot exceed its monitoring window');

my ($invalid_mem_threshold_fh, $invalid_mem_threshold_path) = tempfile();
print {$invalid_mem_threshold_fh} <<'INI';
[policy]
pressure_mem_available_percent = 10
emergency_mem_available_percent = 11
INI
print {$invalid_mem_threshold_fh} required_tuning_ini();
close $invalid_mem_threshold_fh or die "close $invalid_mem_threshold_path: $!";
ok(
    invalid_config_exits_nonzero($invalid_mem_threshold_path),
    'emergency MemAvailable threshold cannot be less severe than pressure',
);

my ($invalid_psi_threshold_fh, $invalid_psi_threshold_path) = tempfile();
print {$invalid_psi_threshold_fh} <<'INI';
[policy]
memory_some_avg10_min = 2.00
emergency_some_avg10_min = 1.00
INI
print {$invalid_psi_threshold_fh} required_tuning_ini();
close $invalid_psi_threshold_fh or die "close $invalid_psi_threshold_path: $!";
ok(
    invalid_config_exits_nonzero($invalid_psi_threshold_path),
    'emergency PSI threshold cannot be below pressure',
);

my ($invalid_idle_age_fh, $invalid_idle_age_path) = tempfile();
print {$invalid_idle_age_fh} <<'INI';
[writeback]
hot_age_seconds = 300
idle_age_seconds = 600
pressure_idle_age_seconds = 700
emergency_idle_age_seconds = 300
INI
print {$invalid_idle_age_fh} required_tuning_ini();
close $invalid_idle_age_fh or die "close $invalid_idle_age_path: $!";
ok(
    invalid_config_exits_nonzero($invalid_idle_age_path),
    'pressure idle age cannot be longer than normal idle age',
);

my ($invalid_cooldown_fh, $invalid_cooldown_path) = tempfile();
print {$invalid_cooldown_fh} <<'INI';
[daemon]
pressure_cooldown_seconds = 30
emergency_cooldown_seconds = 31
INI
print {$invalid_cooldown_fh} required_tuning_ini();
close $invalid_cooldown_fh or die "close $invalid_cooldown_path: $!";
ok(
    invalid_config_exits_nonzero($invalid_cooldown_path),
    'emergency cooldown cannot exceed pressure cooldown',
);

my ($psi_fh, $psi_path) = tempfile();
my $trigger = Zram::Daemon::_register_psi_trigger($psi_path, 'some', 1, 500_000);
my $descriptor_flags = fcntl($trigger->{fh}, F_GETFD, 0);
ok($descriptor_flags & FD_CLOEXEC, 'PSI trigger descriptors are close-on-exec');
close $trigger->{fh} or die "close $psi_path: $!";

{
    package ZramTestInterruptedPoll;
    sub poll {
        $! = Errno::EINTR();
        return undef;
    }
}
is(
    Zram::Daemon::_poll_triggers(bless({}, 'ZramTestInterruptedPoll'), 1),
    0,
    'interrupted PSI polling returns control for clean signal shutdown',
);

my ($enabled_fh, $enabled_path) = tempfile();
print {$enabled_fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[daemon]
enabled = 1
poll_timeout_seconds = 1
pressure_cooldown_seconds = 0
emergency_cooldown_seconds = 0
recovery_hysteresis_seconds = 0

[paths]
sysfs_root = $sysfs_root
debugfs_root = $root/debug
procfs_root = $procfs_root
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
print {$enabled_fh} required_tuning_ini();
close $enabled_fh or die "close $enabled_path: $!";
load_config($enabled_path);

my ($trigger_fh) = tempfile();
my ($poll_calls, $state_calls, $passes, $tuning_updates) = (0, 0, 0, 0);
{
    no warnings 'redefine';
    local *Zram::Daemon::_register_triggers = sub {
        return ({
            fh => $trigger_fh,
            kind => 'some',
            stall_us => 1,
            window_us => 1,
        });
    };
    local *Zram::Daemon::_poll_triggers = sub {
        $poll_calls++;
        if ($poll_calls > 1) {
            kill 'TERM', $$;
        }
        return 0;
    };
    local *Zram::Daemon::determine_pressure_state = sub {
        $state_calls++;
        return ('pressure', ['periodic test']);
    };
    local *Zram::Daemon::_run_pressure_pass = sub {
        $passes++;
        return 1;
    };
    local *Zram::Daemon::_apply_tuning_state = sub {
        $tuning_updates++;
        return 1;
    };
    is(run_daemon(), 0, 'daemon exits cleanly after the bounded test loop');
}
is($state_calls, 1, 'daemon evaluates memory pressure after a poll timeout');
is($passes, 1, 'daemon dispatches a pressure pass without requiring a fresh PSI edge');
is($tuning_updates, 1, 'daemon updates iodepth when the sampled pressure state changes');

unlink $disabled_path;
unlink $invalid_path;
unlink $unknown_key_path;
unlink $unknown_section_path;
unlink $missing_tuning_path;
unlink $invalid_batch_path;
unlink $invalid_size_percent_path;
unlink $invalid_size_bounds_path;
unlink $invalid_mem_limit_percent_path;
unlink $invalid_writeback_limit_percent_path;
unlink $invalid_daily_writeback_limit_path;
unlink $duplicate_recompression_priority_path;
unlink $invalid_scan_limits_path;
unlink $invalid_window_path;
unlink $invalid_stall_path;
unlink $invalid_mem_threshold_path;
unlink $invalid_psi_threshold_path;
unlink $invalid_idle_age_path;
unlink $invalid_cooldown_path;
unlink $enabled_path;
done_testing;
