package Telpoll::Logger;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use POSIX qw(strftime);
use Types::Standard qw(Str);

has secret => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

sub log {
    my ($self, $level, $message) = @_;

    $level = 'info' if !defined($level) || $level !~ /\A(?:debug|info|warning|error)\z/;
    $message //= q{};
    my $secret = $self->secret();
    $message =~ s/\Q$secret\E/[redacted]/g if length($secret);
    $message =~ s/[\r\n\t]+/ /g;
    $message =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/?/g;
    $message = substr($message, 0, 2_048) if length($message) > 2_048;
    my $timestamp = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime());
    print STDERR "$timestamp telpoll level=$level message=$message\n";
    return;
}

1;
