package Telpoll::Daemon;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Time::HiRes qw(sleep);
use Types::Standard qw(Bool);

my $GET_UPDATES_OWNERSHIP_CONFLICT =
    "telpoll: Telegram getUpdates failed with HTTP 409: " .
    "Conflict: terminated by other getUpdates request; " .
    "make sure that only one bot instance is running\n";

has config => (
    is       => 'ro',
    required => 1,
);

has logger => (
    is       => 'ro',
    required => 1,
);

has state => (
    is       => 'ro',
    required => 1,
);

has telegram => (
    is       => 'ro',
    required => 1,
);

has processor => (
    is       => 'ro',
    required => 1,
);

has whisper => (
    is       => 'ro',
    required => 1,
);

has stop_requested => (
    is      => 'rw',
    isa     => Bool,
    default => sub { 0 },
);

sub run {
    my ($self, $once) = @_;

    local $SIG{INT} = sub {
        $self->stop_requested(1);
        die "telpoll: stop requested\n";
    };
    local $SIG{TERM} = sub {
        $self->stop_requested(1);
        die "telpoll: stop requested\n";
    };
    local $SIG{HUP} = sub {
        $self->logger()->log(
            'info',
            'SIGHUP received; managed configuration changes require a service restart',
        );
    };

    my $run_ok = eval {
        my $failures = 0;
        while (!$self->stop_requested()) {
            my $ok = eval {
                $self->poll_once();
                1;
            };
            if ($ok) {
                $failures = 0;
                last if $once;
                next;
            }

            my $error = $@ || 'unknown Telegram polling failure';
            last if $self->stop_requested();
            die $error if $once;
            $failures++;
            $self->logger()->log('error', $error);
            my $delay;
            if (_is_get_updates_ownership_conflict($error)) {
                $delay = $self->config()
                    ->ownership_conflict_backoff_seconds();
            }
            else {
                $delay = 2 ** ($failures > 5 ? 5 : $failures);
                $delay = 60 if $delay > 60;
            }
            $self->_sleep_interruptibly($delay);
        }
        1;
    };
    if (!$run_ok && !$self->stop_requested()) {
        die($@ || "telpoll: daemon loop failed\n");
    }
    $self->logger()->log('info', 'daemon stopped');
    return;
}

sub poll_once {
    my ($self) = @_;

    my $updates = $self->telegram()->get_updates($self->state()->offset());
    ref($updates) eq 'ARRAY'
        or die "telpoll: Telegram updates are invalid\n";
    my @ordered;
    for my $update (@{$updates}) {
        ref($update) eq 'HASH'
            or die "telpoll: Telegram update entry is invalid\n";
        push @ordered, [ _update_id($update->{update_id}), $update ];
    }

    for my $ordered (sort { $a->[0] <=> $b->[0] } @ordered) {
        last if $self->stop_requested();
        my ($update_id, $update) = @{$ordered};
        next if $update_id < $self->state()->offset();
        my $pending = $self->state()->pending_for($update_id);
        $self->state()->save();

        if (!$pending->{local_complete}) {
            my $result;
            my $processed = eval {
                $result = $self->processor()->process($update, $pending);
                1;
            };
            if (!$processed) {
                my $error = $@ || 'unknown Telegram update processing failure';
                die $error if $self->stop_requested();
                $pending->{attempts} = int($pending->{attempts} // 0) + 1;
                $self->state()->save();
                if ($pending->{attempts} >= $self->config()->max_update_attempts()) {
                    $self->logger()->log(
                        'error',
                        "abandoning Telegram update after bounded retries update_id=$update_id error=$error",
                    );
                    $self->whisper()->release_reservation($pending->{stem})
                        if defined($pending->{stem});
                    $self->_acknowledge($update_id);
                    next;
                }
                die $error;
            }
            ref($result) eq 'HASH'
                or die "telpoll: update processor returned an invalid result\n";
            $pending->{local_complete} = 1;
            $pending->{delete_message} = $result->{delete_message} ? 1 : 0;
            $pending->{message_id} = $result->{message_id} // 0;
            $pending->{chat_id} = $result->{chat_id} // q{};
            $pending->{attempts} = 0;
            $self->state()->save();
        }

        if ($pending->{delete_message}) {
            my $deleted = $self->telegram()->delete_message(
                $pending->{chat_id},
                $pending->{message_id},
            );
            ref($deleted) eq 'HASH' && exists($deleted->{ok})
                or die "telpoll: Telegram deletion result is invalid\n";
            if (!$deleted->{ok}) {
                $pending->{delete_attempts} = int($pending->{delete_attempts} // 0) + 1;
                $self->state()->save();
                if ($pending->{delete_attempts} < $self->config()->max_update_attempts()) {
                    die "telpoll: Telegram message deletion failed: $deleted->{error}\n";
                }
                $self->logger()->log(
                    'warning',
                    "retaining Telegram message after bounded deletion retries update_id=$update_id error=$deleted->{error}",
                );
            }
        }
        $self->_acknowledge($update_id);
    }
    return;
}

sub _acknowledge {
    my ($self, $update_id) = @_;

    $self->state()->advance($update_id + 1);
    $self->state()->remove_pending($update_id);
    $self->state()->save();
    return;
}

sub _sleep_interruptibly {
    my ($self, $seconds) = @_;

    while ($seconds > 0 && !$self->stop_requested()) {
        my $slice = $seconds > 1 ? 1 : $seconds;
        sleep($slice);
        $seconds -= $slice;
    }
    return;
}

sub _is_get_updates_ownership_conflict {
    my ($error) = @_;

    return defined($error) && $error eq $GET_UPDATES_OWNERSHIP_CONFLICT;
}

sub _update_id {
    my ($value) = @_;
    defined($value) && "$value" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: Telegram update ID is invalid\n";
    return 0 + $value;
}

1;
