use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../d-i/forky/hooks/shared/target/usr/local/lib/perl5/site_perl/zram-writeback";
use lib "$Bin/lib";
use Test::More;
use Zram::Metrics qw(
  add_page_index_range block_state_line_limit capture_zram_state
  finish_page_index_ranges new_range_builder
);
use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use Zram::Config qw(load_config);
use ZramTestConfig qw(required_tuning_ini);

my $capped = new_range_builder(
    max_pages => 5,
    chunk_page_limit => 3,
    max_spec_bytes => 3900,
    max_chunks => 64,
);
for my $page (1 .. 8) {
    add_page_index_range($capped, $page);
}
is_deeply(
    [finish_page_index_ranges($capped)],
    ['page_indexes=1-3', 'page_indexes=4-5'],
    'page-index builder enforces class max pages and pages-per-spec chunks',
);
is($capped->{pages}, 8, 'builder keeps candidate count separate from emitted cap');
is($capped->{emitted_pages}, 5, 'builder emits only the capped page count');
is($capped->{capped}, 1, 'builder reports intentional cap truncation');

my $chunked = new_range_builder(
    chunk_page_limit => 3,
    max_spec_bytes => 3900,
    max_chunks => 64,
);
for my $page (1, 2, 10, 11, 12, 20) {
    add_page_index_range($chunked, $page);
}
is_deeply(
    [finish_page_index_ranges($chunked)],
    ['page_indexes=1-2', 'page_indexes=10-12', 'page_index=20'],
    'page-index builder keeps each sysfs writeback spec under the page limit',
);
is($chunked->{emitted_pages}, 6, 'uncapped builder emits every candidate page');

my $chunk_limited = new_range_builder(
    max_spec_bytes => 20,
    max_chunks => 1,
);
for my $page (1, 3) {
    add_page_index_range($chunk_limited, $page);
}
is_deeply(
    [finish_page_index_ranges($chunk_limited)],
    ['page_index=1'],
    'page-index builder drops work that would exceed the chunk-count ceiling',
);
is($chunk_limited->{emitted_pages}, 1, 'dropped chunks are not counted as emitted pages');
is($chunk_limited->{truncated}, 1, 'chunk-count exhaustion is reported as truncation');

is(
    block_state_line_limit(
        4_294_967_296,
        4096,
        maximum => 4_194_304,
        fallback => 1_000_000,
        logical_block_size_fallback => 4096,
    ),
    1_048_577,
    'block-state scan covers every page of the maximum configured 4 GiB zram device',
);
is(
    block_state_line_limit(
        34_359_738_368,
        4096,
        maximum => 4_194_304,
        fallback => 1_000_000,
        logical_block_size_fallback => 4096,
    ),
    4_194_304,
    'block-state scan keeps an absolute upper bound for unexpectedly large devices',
);
is(
    block_state_line_limit(
        undef,
        undef,
        maximum => 4_194_304,
        fallback => 1_000_000,
        logical_block_size_fallback => 4096,
    ),
    1_000_000,
    'block-state scan keeps the bounded fallback when device geometry is unavailable',
);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

my $runtime_root = $ENV{XDG_RUNTIME_DIR} || '/run/user/1000';
my $root = tempdir(DIR => $runtime_root, CLEANUP => 1);
my $sysfs = "$root/sys";
my $debugfs = "$root/debug";
my $procfs = "$root/proc";
my $runtime_dir = "$root/run/zram";
make_path("$sysfs/block/zram0", "$debugfs/zram/zram0", $procfs, $runtime_dir);
write_file("$procfs/uptime", "10000.00 0.00\n");
write_file("$sysfs/block/zram0/disksize", "409600\n");
write_file("$sysfs/block/zram0/mm_stat", "40960 1024 2048 0 0 0 0 0 0\n");
write_file("$sysfs/block/zram0/io_stat", "0 0 0 0\n");
write_file("$sysfs/block/zram0/bd_stat", "0 0 0\n");
write_file("$sysfs/block/zram0/debug_stat", "1\n");
write_file(
    "$debugfs/zram/zram0/block_state",
    "1 1000 ih\n" .
    "2 1000 ihn\n" .
    "3 1000 ih\n" .
    "4 1000 n\n" .
    "5 1000 n\n",
);

my ($fh, $config_path) = tempfile();
print {$fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
idle_age_seconds = 300
pressure_idle_age_seconds = 300
emergency_idle_age_seconds = 300

[paths]
sysfs_root = $sysfs
debugfs_root = $debugfs
procfs_root = $procfs
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
print {$fh} required_tuning_ini();
close $fh or die "close $config_path: $!";
load_config($config_path);

my $no_writeback = capture_zram_state(
    'test-no-writeback',
    idle_age_sec => 300,
    writeback_class_caps => {},
);
is_deeply($no_writeback->{incompressible_writeback_specs}, [], 'capture skips writeback specs when no classes are requested');
is($no_writeback->{targeted_incompressible_pages}, 0, 'disabled class avoids targeted range construction');

my $capped_capture = capture_zram_state(
    'test-capped-writeback',
    idle_age_sec => 300,
    writeback_class_caps => {
        incompressible => 2,
        huge_idle => 8,
    },
);
is_deeply(
    $capped_capture->{incompressible_writeback_specs},
    ['page_index=2 page_index=4'],
    'incompressible targets include idle and non-idle incompressible pages first',
);
is($capped_capture->{emitted_incompressible_pages}, 2, 'incompressible target emission is capped by pass budget');
is_deeply(
    $capped_capture->{huge_idle_writeback_specs},
    ['page_index=1 page_index=3'],
    'huge-idle targets skip pages already covered by incompressible writeback',
);

unlink $config_path;
done_testing;
