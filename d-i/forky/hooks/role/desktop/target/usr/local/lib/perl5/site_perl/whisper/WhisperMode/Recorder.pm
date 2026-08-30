package WhisperMode::Recorder;

use strict;
use warnings;

use POSIX qw(strftime);
use Time::HiRes qw(sleep);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use WhisperMode::Logger qw(log_msg);

has artifacts => ( is => 'ro', required => 1 );
has audio     => ( is => 'ro', required => 1 );
has state     => ( is => 'ro', required => 1 );
has systemd   => ( is => 'ro', required => 1 );

sub _fatal {
    my ($message) = @_;
    die "whisper-record-toggle: $message\n";
}

sub _stem {
    my ($self, $directory) = @_;
    for (1 .. 3) {
        my $stem = strftime('%Y-%m-%d-%H-%M-%S', localtime);
        return $stem if !-e "$directory/$stem.wav";
        sleep 1;
    }
    _fatal('could not create a collision-free recording name');
}

sub start {
    my ($self) = @_;
    my $paths = $self->artifacts()->paths();
    my $existing = $self->state()->read();
    if ($self->systemd()->is_active($self->systemd()->record_service())) {
        $existing or _fatal('recording service is active without managed runtime state');
        $self->artifacts()->validate_wav($existing);
        $self->audio()->set_default_source_muted(0);
        return;
    }
    if ($existing) {
        my $wav = $self->artifacts()->validate_wav($existing);
        -s $wav > 44 and _fatal('a completed recording is pending transcription');
        $self->state()->clear();
    }
    my $stem = $self->_stem($paths->{audio});
    my $recording = { stem => $stem, wav => "$paths->{audio}/$stem.wav" };
    my $unmuted = 0;
    eval {
        $self->audio()->set_default_source_muted(0);
        $unmuted = 1;
        $self->state()->write($recording);
        $self->systemd()->start_recording();
        1;
    } or do {
        my $error = $@ || 'unknown recorder failure';
        eval { $self->state()->clear() };
        eval { $self->audio()->set_default_source_muted(1) } if $unmuted;
        die $error;
    };
    log_msg('info', "started Whisper recording $stem");
}

sub stop {
    my ($self) = @_;
    my ($recording, $stop_error, $finalize_error);
    eval { $self->systemd()->stop_recording(); 1 }
        or $stop_error = $@ || 'unknown recorder stop failure';
    eval {
        $recording = $self->finalize();
        1;
    } or $finalize_error = $@ || 'unknown recording finalization failure';
    if ($stop_error) {
        if ($finalize_error) {
            chomp($stop_error);
            chomp($finalize_error);
            die "$stop_error; recording finalization also failed: $finalize_error\n";
        }
        die $stop_error;
    }
    die $finalize_error if $finalize_error;
    return $recording;
}

sub finalize {
    my ($self) = @_;
    $self->audio()->set_default_source_muted(1);
    my $recording = $self->state()->read();
    return undef if !$recording;
    my $wav = $self->artifacts()->validate_wav($recording);
    if (!-f $wav || -l $wav || -s $wav <= 44) {
        $self->state()->clear();
        return undef;
    }
    log_msg('info', "stopped Whisper recording $recording->{stem}");
    return $recording;
}

sub record_worker {
    my ($self) = @_;
    my $recording = $self->state()->read()
        or _fatal('recorder service started without managed runtime state');
    my $guard = $self->state()->lock(1, 1)
        or _fatal('a Whisper recording is already active');
    my $wav = $self->artifacts()->validate_wav($recording);
    $self->audio()->record($wav);
}

1;
