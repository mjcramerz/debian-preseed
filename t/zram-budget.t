use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback";
use lib "$Bin/lib";
use Test::More;
use Zram::Budget qw(budget_state_file refresh_daily_writeback_budget);
use Zram::Config qw(load_config);
use ZramTestConfig qw(required_tuning_ini);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    my $value = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $value;
}

my $runtime_root = $ENV{XDG_RUNTIME_DIR} || '/run/user/1000';
my $root = tempdir(DIR => $runtime_root, CLEANUP => 1);
my $sysfs_root = "$root/sys";
my $runtime_dir = "$root/run/zram";
make_path("$sysfs_root/block/zram0", $runtime_dir);
write_file("$sysfs_root/block/zram0/writeback_limit", "0\n");

my ($fh, $config_path) = tempfile();
print {$fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
daily_writeback_limit = 16K

[paths]
sysfs_root = $sysfs_root
debugfs_root = $root/debug
procfs_root = $root/proc
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
print {$fh} required_tuning_ini();
close $fh or die "close $config_path: $!";
load_config($config_path);

is(
    refresh_daily_writeback_budget(),
    0,
    'daily budget state is not committed when writeback_limit_enable is unavailable',
);
ok(!-e budget_state_file(), 'failed budget enable leaves no completed daily state');

write_file("$sysfs_root/block/zram0/writeback_limit_enable", "0\n");
is(refresh_daily_writeback_budget(), 1, 'daily budget refresh succeeds when both kernel attributes are writable');
like(read_file(budget_state_file()), qr/^daily_budget_pages=4$/m, 'daily budget state records the applied page count');
is(refresh_daily_writeback_budget(), 0, 'daily budget is not reset more than once per UTC day');

unlink $config_path;
done_testing;
