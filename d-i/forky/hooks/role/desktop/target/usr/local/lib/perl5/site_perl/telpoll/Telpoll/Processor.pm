package Telpoll::Processor;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;

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

has storage => (
    is       => 'ro',
    required => 1,
);

has telegram => (
    is       => 'ro',
    required => 1,
);

has whisper => (
    is       => 'ro',
    required => 1,
);

sub process {
    my ($self, $update, $pending) = @_;

    ref($update) eq 'HASH' && ref($pending) eq 'HASH'
        or die "telpoll: update processing input is invalid\n";
    my $update_id = _integer($update->{update_id}, 'update ID');
    my $message = $update->{message};
    ref($message) eq 'HASH'
        or return {
            delete_message => 0,
            message_id     => 0,
            chat_id        => q{},
        };
    my $message_id = _integer($message->{message_id}, 'message ID');
    ref($message->{chat}) eq 'HASH'
        or die "telpoll: Telegram message chat is invalid\n";
    my $chat_id = _chat_id($message->{chat}->{id});
    if ($chat_id ne $self->config()->chat_id()) {
        $self->logger()->log(
            'warning',
            "ignored Telegram update from unauthorized chat update_id=$update_id",
        );
        return {
            delete_message => 0,
            message_id     => $message_id,
            chat_id        => $chat_id,
        };
    }

    my $prefix = $self->storage()->store_message($update);
    my $attachment = _attachment($message);
    if (defined($attachment)) {
        my $declared_size = _optional_size($attachment->{file_size});
        if ($declared_size > $self->config()->max_file_bytes()) {
            $self->storage()->store_error(
                $prefix,
                'Telegram attachment exceeds the Bot API download limit and was left in Telegram.',
            );
            return {
                delete_message => 0,
                message_id     => $message_id,
                chat_id        => $chat_id,
            };
        }

        my $remote = $self->telegram()->get_file($attachment->{file_id});
        my $remote_size = _optional_size($remote->{file_size});
        my $expected_size = $remote_size || $declared_size;
        if ($expected_size > $self->config()->max_file_bytes()) {
            $self->storage()->store_error(
                $prefix,
                'Telegram attachment exceeds the Bot API download limit and was left in Telegram.',
            );
            return {
                delete_message => 0,
                message_id     => $message_id,
                chat_id        => $chat_id,
            };
        }

        my $name = $self->storage()->attachment_name(
            $prefix,
            $attachment->{kind},
            $attachment->{file_name},
            $remote->{file_path},
        );
        my $path = $self->storage()->store_download(
            $name,
            $expected_size,
            $self->config()->max_file_bytes(),
            sub {
                my ($fh) = @_;
                return $self->telegram()->download(
                    $remote->{file_path},
                    $fh,
                    $self->config()->max_file_bytes(),
                );
            },
        );

        if ($path =~ /\.(?:oga|ogg)\z/i) {
            if (!defined($pending->{stem})) {
                my $epoch = _message_epoch($message->{date});
                $pending->{stem} = $self->whisper()->reserve_stem($epoch);
                $self->state()->save();
            }
            $self->whisper()->process_ogg($path, $pending->{stem});
        }
    }

    return {
        delete_message => 1,
        message_id     => $message_id,
        chat_id        => $chat_id,
    };
}

sub _attachment {
    my ($message) = @_;

    for my $kind (qw(voice audio document animation video video_note sticker)) {
        next if ref($message->{$kind}) ne 'HASH';
        my $item = $message->{$kind};
        _file_id($item->{file_id});
        return {
            kind      => $kind,
            file_id   => $item->{file_id},
            file_name => _optional_file_name($item->{file_name}),
            file_size => $item->{file_size},
        };
    }
    if (ref($message->{photo}) eq 'ARRAY' && @{$message->{photo}}) {
        my @photos = grep { ref($_) eq 'HASH' && defined($_->{file_id}) } @{$message->{photo}};
        if (@photos) {
            my ($photo) = sort {
                (_optional_size($b->{file_size}) <=> _optional_size($a->{file_size})) ||
                    (_photo_area($b) <=> _photo_area($a))
            } @photos;
            _file_id($photo->{file_id});
            return {
                kind      => 'photo',
                file_id   => $photo->{file_id},
                file_name => 'photo.jpg',
                file_size => $photo->{file_size},
            };
        }
    }
    return undef;
}

sub _file_id {
    my ($file_id) = @_;
    defined($file_id) && !ref($file_id) &&
        $file_id =~ /\A[A-Za-z0-9_-]{1,512}\z/
        or die "telpoll: Telegram attachment file ID is invalid\n";
    return "$file_id";
}

sub _optional_file_name {
    my ($value) = @_;

    return undef if !defined($value);
    !ref($value) && length($value) <= 1_024 &&
        $value !~ /[\x00-\x1f\x7f]/
        or die "telpoll: Telegram attachment file name is invalid\n";
    return "$value";
}

sub _optional_size {
    my ($value) = @_;
    return 0 if !defined($value);
    !ref($value) && "$value" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: Telegram attachment size is invalid\n";
    return 0 + $value;
}

sub _photo_area {
    my ($photo) = @_;

    my $width = _optional_dimension($photo->{width});
    my $height = _optional_dimension($photo->{height});
    return $width * $height;
}

sub _optional_dimension {
    my ($value) = @_;

    return 0 if !defined($value);
    !ref($value) && "$value" =~ /\A[0-9]{1,6}\z/
        or die "telpoll: Telegram photo dimensions are invalid\n";
    return 0 + $value;
}

sub _integer {
    my ($value, $label) = @_;
    defined($value) && !ref($value) && "$value" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: Telegram $label is invalid\n";
    return "$value";
}

sub _chat_id {
    my ($value) = @_;
    defined($value) && !ref($value) && "$value" =~ /\A-?[0-9]{1,16}\z/
        or die "telpoll: Telegram chat ID is invalid\n";
    return "$value";
}

sub _message_epoch {
    my ($value) = @_;
    my $now = time();
    return int($value)
        if defined($value) && "$value" =~ /\A[0-9]{1,12}\z/ &&
            $value >= 0 && $value <= $now + 86_400;
    return int($now);
}

1;
