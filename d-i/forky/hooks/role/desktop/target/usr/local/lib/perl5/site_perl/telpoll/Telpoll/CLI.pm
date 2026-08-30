package Telpoll::CLI;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Telpoll::Config;
use Telpoll::Daemon;
use Telpoll::Logger;
use Telpoll::Processor;
use Telpoll::State;
use Telpoll::Storage;
use Telpoll::Telegram;
use Telpoll::Whisper;

sub run {
    my ($class, @arguments) = @_;

    my $once = 0;
    my $help = 0;
    GetOptionsFromArray(
        \@arguments,
        'once' => \$once,
        'help' => \$help,
    ) or return _usage(2);
    return _usage(0) if $help;
    return _usage(2) if @arguments;

    binmode STDERR, ':encoding(UTF-8)';
    binmode STDOUT, ':encoding(UTF-8)';
    umask 0077;
    delete @ENV{
        qw(
            ALL_PROXY HTTPS_PROXY HTTP_PROXY NO_PROXY
            all_proxy https_proxy http_proxy no_proxy
        )
    };

    my $logger;
    my $ok = eval {
        my $config = Telpoll::Config->from_managed_files();
        return 0 if !$config->enabled();
        $logger = Telpoll::Logger->new(secret => $config->api_key());
        my $state = Telpoll::State->new(directory => $config->state_dir());
        $state->acquire_lock();
        my $storage = Telpoll::Storage->new(
            home         => $config->home(),
            download_dir => $config->download_dir(),
        );
        my $telegram = Telpoll::Telegram->new(
            config => $config,
            logger => $logger,
        );
        my $whisper = Telpoll::Whisper->new(
            home   => $config->home(),
            logger => $logger,
        );
        my $processor = Telpoll::Processor->new(
            config   => $config,
            logger   => $logger,
            state    => $state,
            storage  => $storage,
            telegram => $telegram,
            whisper  => $whisper,
        );
        my $daemon = Telpoll::Daemon->new(
            config    => $config,
            logger    => $logger,
            state     => $state,
            telegram  => $telegram,
            processor => $processor,
            whisper   => $whisper,
        );
        $logger->log('info', 'daemon started');
        $daemon->run($once);
        1;
    };
    return 0 if $ok;

    my $error = $@ || 'unknown daemon failure';
    if (defined($logger)) {
        $logger->log('error', $error);
    }
    else {
        $error =~ s/[\r\n\t]+/ /g;
        $error =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/?/g;
        $error = substr($error, 0, 1_024) if length($error) > 1_024;
        print STDERR "$error\n";
    }
    return 1;
}

sub _usage {
    my ($status) = @_;

    print STDERR "Usage: telpoll [--once]\n";
    return $status;
}

1;
