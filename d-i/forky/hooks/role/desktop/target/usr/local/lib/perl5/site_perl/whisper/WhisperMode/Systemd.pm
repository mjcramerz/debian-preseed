package WhisperMode::Systemd;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Time::HiRes qw(sleep);

has record_service     => ( is => 'ro', default => sub { 'whisper-record.service' } );
has transcribe_service => ( is => 'ro', default => sub { 'whisper-transcribe.service' } );
has server_service     => ( is => 'ro', default => sub { 'whisper-server.service' } );
has session_target     => ( is => 'ro', default => sub { 'labwc-session.target' } );

sub _fatal {
    my ($message) = @_;
    die "whisper-record-toggle: $message\n";
}

sub _run {
    my ($self, @arguments) = @_;
    my $systemctl = '/usr/bin/systemctl';
    -x $systemctl && -f $systemctl or _fatal('systemctl is unavailable');
    return system { $systemctl } $systemctl, '--user', @arguments;
}

sub _detail {
    my ($status) = @_;
    return "exec error: $!" if $status == -1;
    return 'terminated by signal ' . ($status & 127) if $status & 127;
    return 'exit status ' . ($status >> 8);
}

sub is_active { my ($self, $service) = @_; return $self->_run('--quiet', 'is-active', $service) == 0; }
sub is_failed { my ($self, $service) = @_; return $self->_run('--quiet', 'is-failed', $service) == 0; }

sub _reset_failed_if_needed {
    my ($self, $service) = @_;
    return if !$self->is_failed($service);
    my $status = $self->_run('reset-failed', $service);
    $status == 0
        or _fatal("cannot reset failed state for $service: " . _detail($status));
}

sub start_recording {
    my ($self) = @_;
    $self->is_active($self->session_target())
        or _fatal('cannot start recording while the Labwc session is stopping');
    $self->_reset_failed_if_needed($self->record_service());
    $self->is_active($self->session_target())
        or _fatal('cannot start recording while the Labwc session is stopping');
    my $status = $self->_run('start', $self->record_service());
    return if $status == 0 && $self->wait_active($self->record_service(), 50);
    _fatal('cannot start recording service: ' . _detail($status));
}

sub stop_recording {
    my ($self) = @_;
    return if !$self->is_active($self->record_service());
    my $status = $self->_run('stop', $self->record_service());
    $status == 0 or _fatal('cannot stop recording service: ' . _detail($status));
    $self->wait_inactive($self->record_service(), 50)
        or _fatal('recording service did not stop within 5 seconds');
}

sub start_transcription {
    my ($self) = @_;
    return if !$self->is_active($self->session_target());
    $self->_reset_failed_if_needed($self->transcribe_service());
    return if !$self->is_active($self->session_target());
    my $status = $self->_run('--no-block', 'start', $self->transcribe_service());
    $status == 0 or _fatal('cannot start transcription service: ' . _detail($status));
}

sub wait_active {
    my ($self, $service, $attempts) = @_;
    for (1 .. $attempts) {
        return 1 if $self->is_active($service);
        return 0 if $self->is_failed($service);
        sleep 0.1;
    }
    return 0;
}

sub wait_inactive {
    my ($self, $service, $attempts) = @_;
    for (1 .. $attempts) {
        return 1 if !$self->is_active($service);
        sleep 0.1;
    }
    return 0;
}

1;
