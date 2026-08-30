use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback";
use lib "$Bin/lib";
use Test::More;
use Zram::Config qw(load_config);
use Zram::Tuning qw(
  apply_writeback_batch_size backing_queue_depth backing_rotational
  writeback_batch_size_for_state writeback_pass_pages_for_state
);
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
my $sysfs = "$root/sys";
my $runtime_dir = "$root/run/zram";
my $queue = "$sysfs/class/block/nvme0n1p12/queue";
my $mapper_queue = "$sysfs/class/block/zram-writeback-test/queue";
make_path("$sysfs/block/zram0", $queue, $mapper_queue, $runtime_dir);
write_file("$sysfs/block/zram0/writeback_batch_size", "512\n");
write_file("$queue/nr_requests", "48\n");
write_file("$queue/rotational", "0\n");
write_file("$mapper_queue/nr_requests", "64\n");
write_file("$mapper_queue/rotational", "0\n");

my ($fh, $config_path) = tempfile();
print {$fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback-test
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback-test

[paths]
sysfs_root = $sysfs
debugfs_root = $root/debug
procfs_root = $root/proc
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 0
INI
print {$fh} required_tuning_ini();
close $fh or die "close $config_path: $!";
load_config($config_path);

is(backing_queue_depth(), 48, 'backing queue depth is detected from the raw block device');
is(backing_rotational(), 0, 'non-rotational backing media is detected');
write_file("$mapper_queue/nr_requests", "24\n");
is(backing_queue_depth(), 24, 'the smallest queue depth across raw and mapped layers wins');
write_file("$mapper_queue/nr_requests", "64\n");
is(writeback_batch_size_for_state('normal'), 32, 'normal state uses conservative kernel-default iodepth');
is(writeback_batch_size_for_state('pressure'), 48, 'pressure iodepth is capped by backing queue depth');
is(writeback_batch_size_for_state('emergency'), 48, 'emergency iodepth is capped by backing queue depth');
is(writeback_pass_pages_for_state('pressure', undef), 8192, 'pressure pass volume is independent from iodepth');
is(writeback_pass_pages_for_state('pressure', 5000), 5000, 'kernel writeback budget caps pressure pass volume');
is(writeback_pass_pages_for_state('pressure', 0), 0, 'exhausted kernel writeback budget suppresses pass volume');
is(writeback_pass_pages_for_state('emergency', undef), 32768, 'emergency pass uses its larger bounded volume');

my $applied = apply_writeback_batch_size('pressure');
is($applied->{effective_batch_size}, 48, 'adaptive pressure iodepth is reported');
is(read_file("$sysfs/block/zram0/writeback_batch_size"), "48\n", 'adaptive pressure iodepth is applied to sysfs');

write_file("$queue/rotational", "1\n");
is(writeback_batch_size_for_state('emergency'), 32, 'any rotational backing layer uses the configured conservative cap');

write_file("$queue/nr_requests", "16\n");
is(writeback_batch_size_for_state('emergency'), 16, 'backing queue depth remains the final hard iodepth cap');

unlink $config_path;
done_testing;
