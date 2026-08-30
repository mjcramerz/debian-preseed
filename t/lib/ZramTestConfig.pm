package ZramTestConfig;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(required_tuning_ini);

sub required_tuning_ini {
    my (%overrides) = @_;
    my @writeback_keys = qw(
      writeback_batch_size
      writeback_batch_size_adaptive
      writeback_batch_size_normal
      writeback_batch_size_pressure
      writeback_batch_size_emergency
      writeback_batch_size_rotational_max
      writeback_max_pages_pressure
      writeback_max_pages_emergency
    );
    my @limit_keys = qw(
      writeback_batch_size_max
      writeback_pass_pages_max
      block_state_max_lines
      block_state_fallback_lines
      logical_block_size_fallback
      writeback_spec_max_bytes
      writeback_chunks_per_class_max
      psi_window_min_us
      psi_window_max_us
      daemon_seconds_max
    );
    my %values = (
        writeback_batch_size => 512,
        writeback_batch_size_adaptive => 1,
        writeback_batch_size_normal => 32,
        writeback_batch_size_pressure => 64,
        writeback_batch_size_emergency => 128,
        writeback_batch_size_rotational_max => 32,
        writeback_max_pages_pressure => 8192,
        writeback_max_pages_emergency => 32768,
        writeback_batch_size_max => 4096,
        writeback_pass_pages_max => 4194304,
        block_state_max_lines => 4194304,
        block_state_fallback_lines => 1000000,
        logical_block_size_fallback => 4096,
        writeback_spec_max_bytes => 3900,
        writeback_chunks_per_class_max => 64,
        psi_window_min_us => 500000,
        psi_window_max_us => 10000000,
        daemon_seconds_max => 86400,
        %overrides,
    );
    my %known = map { $_ => 1 } (@writeback_keys, @limit_keys);
    for my $key (keys %overrides) {
        exists $known{$key} or die "unknown zram test tuning override: $key";
    }
    my $writeback = join '', map { "$_ = $values{$_}\n" } @writeback_keys;
    my $limits = join '', map { "$_ = $values{$_}\n" } @limit_keys;
    return "\n[writeback]\n$writeback\n[limits]\n$limits";
}

1;
