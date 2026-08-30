package Telpoll::Telegram;

use strict;
use warnings;

use HTTP::Tiny;
use JSON::PP;
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

has api_http => (
    is      => 'lazy',
    builder => '_build_api_http',
);

has file_http => (
    is      => 'lazy',
    builder => '_build_file_http',
);

sub get_updates {
    my ($self, $offset) = @_;

    defined($offset) && "$offset" =~ /\A[0-9]{1,16}\z/
        or die "telpoll: Telegram update offset is invalid\n";
    my $result = $self->_api_request(
        'getUpdates',
        {
            allowed_updates => '["message"]',
            limit           => $self->config()->max_updates(),
            offset          => $offset,
            timeout         => $self->config()->poll_seconds(),
        },
    );
    ref($result) eq 'ARRAY'
        or die "telpoll: Telegram getUpdates returned an invalid result\n";
    @{$result} <= $self->config()->max_updates()
        or die "telpoll: Telegram getUpdates exceeded the configured result limit\n";
    return $result;
}

sub get_file {
    my ($self, $file_id) = @_;

    _validate_file_id($file_id);
    my $result = $self->_api_request('getFile', { file_id => $file_id });
    ref($result) eq 'HASH'
        or die "telpoll: Telegram getFile returned an invalid result\n";
    my $file_path = $result->{file_path};
    _validate_file_path($file_path);
    if (defined($result->{file_size})) {
        !ref($result->{file_size}) &&
            "$result->{file_size}" =~ /\A[0-9]{1,16}\z/
            or die "telpoll: Telegram getFile returned an invalid file size\n";
    }
    return $result;
}

sub download {
    my ($self, $file_path, $fh, $maximum_size) = @_;

    _validate_file_path($file_path);
    defined($maximum_size) && "$maximum_size" =~ /\A[1-9][0-9]{0,15}\z/
        or die "telpoll: Telegram download limit is invalid\n";
    my $url = $self->config()->api_base() .
        '/file/bot' . $self->config()->api_key() . '/' . $file_path;
    my $bytes = 0;
    my $response = eval {
        $self->file_http()->request(
            'GET',
            $url,
            {
                headers => {
                    accept => 'application/octet-stream',
                },
                data_callback => sub {
                    my ($chunk) = @_;
                    $bytes += length($chunk);
                    $bytes <= $maximum_size
                        or die "telpoll: Telegram file exceeds the configured size limit\n";
                    print {$fh} $chunk
                        or die "telpoll: cannot write downloaded Telegram file: $!\n";
                },
            },
        );
    };
    if (!defined($response)) {
        my $error = $@ || 'Telegram file request failed before an HTTP response';
        die "telpoll: $error";
    }
    ref($response) eq 'HASH'
        or die "telpoll: Telegram file download returned an invalid response\n";
    $response->{success}
        or die sprintf(
            "telpoll: Telegram file download returned HTTP %s\n",
            $response->{status} // 'unknown',
        );
    return $bytes;
}

sub delete_message {
    my ($self, $chat_id, $message_id) = @_;

    defined($chat_id) && "$chat_id" =~ /\A-?[0-9]{1,16}\z/
        or return { ok => 0, error => 'Telegram chat ID is invalid' };
    defined($message_id) && "$message_id" =~ /\A[0-9]{1,16}\z/
        or return { ok => 0, error => 'Telegram message ID is invalid' };
    my $ok = eval {
        my $result = $self->_api_request(
            'deleteMessage',
            {
                chat_id    => $chat_id,
                message_id => $message_id,
            },
        );
        $result
            or die "Telegram deleteMessage returned false\n";
        1;
    };
    return { ok => 1, error => q{} } if $ok;
    my $error = $@ || 'Telegram deleteMessage failed';
    return { ok => 1, error => q{} }
        if $error =~ /message to delete not found/i;
    $error =~ s/[\r\n\t]+/ /g;
    $error = substr($error, 0, 512) if length($error) > 512;
    return { ok => 0, error => $error };
}

sub _api_request {
    my ($self, $method, $fields) = @_;

    defined($method) && $method =~ /\A[A-Za-z][A-Za-z0-9]{0,63}\z/
        or die "telpoll: Telegram API method is invalid\n";
    ref($fields) eq 'HASH'
        or die "telpoll: Telegram API fields are invalid\n";
    my $url = $self->config()->api_base() .
        '/bot' . $self->config()->api_key() . '/' . $method;
    my $response = eval {
        $self->api_http()->post_form($url, $fields);
    };
    if (!defined($response)) {
        my $error = $@ || 'request failed before an HTTP response';
        die "telpoll: Telegram $method $error\n";
    }

    my $content = $response->{content} // q{};
    length($content) <= $self->config()->max_api_response_bytes()
        or die "telpoll: Telegram $method response exceeds the size limit\n";
    my $decoded = eval {
        JSON::PP->new()->utf8(1)->decode($content);
    };
    my $description = ref($decoded) eq 'HASH' &&
        defined($decoded->{description}) && !ref($decoded->{description})
        ? ($decoded->{description} // q{})
        : q{};
    $description =~ s/[\r\n\t]+/ /g;
    $description = substr($description, 0, 512) if length($description) > 512;

    if (!$response->{success} || ref($decoded) ne 'HASH' || !$decoded->{ok}) {
        die sprintf(
            "telpoll: Telegram %s failed with HTTP %s%s\n",
            $method,
            $response->{status} // 'unknown',
            length($description) ? ": $description" : q{},
        );
    }
    return $decoded->{result};
}

sub _build_api_http {
    my ($self) = @_;

    return HTTP::Tiny->new(
        agent        => 'telpoll/1.0',
        max_redirect => 0,
        max_size     => $self->config()->max_api_response_bytes(),
        timeout      => $self->config()->http_timeout_seconds(),
        verify_SSL   => 1,
    );
}

sub _build_file_http {
    my ($self) = @_;

    return HTTP::Tiny->new(
        agent        => 'telpoll/1.0',
        max_redirect => 0,
        timeout      => $self->config()->http_timeout_seconds(),
        verify_SSL   => 1,
    );
}

sub _validate_file_id {
    my ($file_id) = @_;
    defined($file_id) && $file_id =~ /\A[A-Za-z0-9_-]{1,512}\z/
        or die "telpoll: Telegram file ID is invalid\n";
    return;
}

sub _validate_file_path {
    my ($file_path) = @_;
    defined($file_path) && length($file_path) <= 1_024 &&
        $file_path =~ m{\A(?:[0-9A-Za-z._-]+/)*[0-9A-Za-z._-]+\z} &&
        $file_path !~ m{(?:\A|/)\.{1,2}(?:/|\z)}
        or die "telpoll: Telegram file path is invalid\n";
    return;
}

1;
