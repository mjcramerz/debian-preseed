package WhisperMode::Audio;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use POSIX qw(_exit);
use Time::HiRes qw(sleep);

has default_source_attempts => ( is => 'ro', default => sub { 20 } );
has default_source_retry_seconds => ( is => 'ro', default => sub { 0.5 } );
has wpctl_binary => ( is => 'ro', default => sub { '/usr/bin/wpctl' } );

use constant SOURCE_LIST_MAX_BYTES => 64 * 1024;

sub _fatal {
    my ($message) = @_;
    die "whisper-record-toggle: $message\n";
}

sub _command_status {
    my (@command) = @_;
    my $status = system { $command[0] } @command;
    return if $status == 0;
    my $detail = $status == -1 ? "exec error: $!" : "exit status " . ($status >> 8);
    _fatal("command failed: $detail");
}

sub _command_output_quietly {
    my ($self, @command) = @_;
    my $pid = open my $fh, '-|';
    defined $pid or _fatal("cannot fork command: $!");
    if ($pid == 0) {
        open STDERR, '>', '/dev/null' or _exit(125);
        exec { $command[0] } @command or _exit(127);
    }

    my $output = q{};
    while (1) {
        my $remaining = SOURCE_LIST_MAX_BYTES - length $output;
        if ($remaining <= 0) {
            close $fh;
            return (0, q{});
        }
        my $read_size = $remaining < 8192 ? $remaining : 8192;
        my $read = read($fh, my $chunk, $read_size);
        if (!defined $read) {
            close $fh;
            return (0, q{});
        }
        last if $read == 0;
        $output .= $chunk;
    }

    my $closed = close $fh;
    return ($closed && $? == 0, $output);
}

sub _source_is_blocked {
    my ($name) = @_;
    my $normalized = lc($name // q{});

    return 1 if $normalized =~ /\Aalsa_output[.]/;
    return 1 if $normalized =~ /(?:\A|[.])monitor(?:[.]|\z)/;
    return 1 if $normalized =~ /hdmi/;
    return 1 if $normalized =~ /display(?:[._ -]?port)/;
    return 0;
}

sub _source_preference {
    my ($name) = @_;
    my $normalized = lc($name // q{});

    return 0 if $normalized =~ /\Aalsa_input[.](?:pci|platform|soc)-/;
    return 0 if $normalized =~ /(?:built[._ -]?in|internal)/;
    return 1 if $normalized =~ /\Aalsa_input[.]/;
    return 2;
}

sub _source_records_from_status {
    my ($self, $output) = @_;
    my @sources;
    my $in_audio = 0;
    my $in_sources = 0;
    my $order = 0;

    # Forky's WirePlumber supports `wpctl status --name`, but not the newer
    # `wpctl list` interface. Parse only the Audio Sources subtree, excluding
    # output monitors and HDMI/DisplayPort nodes even if WirePlumber has not
    # finished disabling them. Prefer internal ALSA capture over USB or
    # virtual sources; within one tier, retain the current default first.
    for my $line (split /\n/, $output) {
        $line =~ s/\r\z//;
        if (!$in_audio) {
            $in_audio = 1 if $line =~ /\AAudio\s*\z/;
            next;
        }
        if (!$in_sources) {
            last if $line =~ /\A\S/;
            $in_sources = 1 if $line =~ /\bSources:\s*\z/;
            next;
        }

        last if $line =~ /\A\S/;
        last if $line =~ /:\s*\z/ && $line !~ /[1-9][0-9]*[.]/;

        # wpctl draws the tree with UTF-8 box characters, while this pipe is a
        # byte stream. Match the numeric record independently of that prefix
        # instead of relying on the process locale to decode the tree glyphs.
        my ($prefix, $id, $name) = $line =~
            /\A(.*?)([1-9][0-9]*)[.]\s+(.+?)(?:\s+\[[^\]]*\])?\s*\z/;
        next if !defined($id) || !defined($name);
        next if _source_is_blocked($name);
        push @sources, {
            id         => $id,
            name       => $name,
            default    => index($prefix, '*') >= 0 ? 1 : 0,
            preference => _source_preference($name),
            order      => $order++,
        };
    }

    return sort {
        $a->{preference} <=> $b->{preference}
            || $b->{default} <=> $a->{default}
            || $a->{order} <=> $b->{order}
    } @sources;
}

sub _available_source_records {
    my ($self, $wpctl) = @_;
    my ($listed, $output) = $self->_command_output_quietly(
        $wpctl, 'status', '--name',
    );
    return if !$listed;

    return $self->_source_records_from_status($output);
}

sub _wait_for_source_records {
    my ($self, $wpctl) = @_;
    my $attempts = $self->default_source_attempts();
    $attempts =~ /\A[1-9][0-9]*\z/ or _fatal('invalid default source attempt count');
    my $retry_seconds = $self->default_source_retry_seconds();
    defined $retry_seconds && $retry_seconds =~ /\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/
        or _fatal('invalid default source retry interval');

    for my $attempt (1 .. $attempts) {
        my @sources = $self->_available_source_records($wpctl);
        return @sources if @sources;
        sleep $retry_seconds if $attempt < $attempts;
    }
    return;
}

sub _wait_for_sources {
    my ($self, $wpctl) = @_;
    return map { $_->{id} } $self->_wait_for_source_records($wpctl);
}

sub _wait_for_source {
    my ($self, $wpctl) = @_;
    my @sources = $self->_wait_for_source_records($wpctl);
    return $sources[0];
}

sub _select_default_source {
    my ($self, $wpctl) = @_;
    my $source = $self->_wait_for_source($wpctl);
    defined $source
        or _fatal('no usable audio capture source became available');
    _command_status($wpctl, 'set-default', $source->{id});
    return $source;
}

sub set_default_source_muted {
    my ($self, $muted) = @_;
    $muted == 0 || $muted == 1 or _fatal('invalid microphone mute state');
    my $wpctl = $self->wpctl_binary();
    -x $wpctl && -f $wpctl or _fatal('wpctl is unavailable');
    my $source = $self->_select_default_source($wpctl);
    _command_status($wpctl, 'set-mute', $source->{id}, "$muted");
    return 1;
}

sub set_available_sources_muted {
    my ($self, $muted) = @_;
    $muted == 0 || $muted == 1 or _fatal('invalid microphone mute state');
    my $wpctl = $self->wpctl_binary();
    -x $wpctl && -f $wpctl or _fatal('wpctl is unavailable');
    my @source_ids = $self->_wait_for_sources($wpctl);
    @source_ids
        or _fatal('no usable audio capture source became available');

    for my $source_id (@source_ids) {
        _command_status($wpctl, 'set-mute', $source_id, "$muted");
    }
    return scalar @source_ids;
}

sub record {
    my ($self, $destination) = @_;
    my $binary = $ENV{WHISPER_PW_RECORD_BIN} // '/usr/bin/pw-record';
    -x $binary && -f $binary && $binary =~ m{\A/}
        or _fatal('pw-record is unavailable');
    my $wpctl = $self->wpctl_binary();
    -x $wpctl && -f $wpctl or _fatal('wpctl is unavailable');
    my $source = $self->_select_default_source($wpctl);
    _command_status($wpctl, 'set-mute', $source->{id}, '0');
    # wpctl's numeric IDs are control handles. pw-record targets a node.name or
    # object.serial, so use the name requested from `wpctl status --name`.
    exec { $binary } $binary, "--target=$source->{name}",
        '--rate=16000', '--channels=1', '--format=s16', $destination
        or _fatal("cannot exec pw-record: $!");
}

1;
