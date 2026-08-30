package WhisperMode::Transcriber;

use strict;
use warnings;

use File::Temp qw(tempfile);
use JSON::PP qw(encode_json);
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use WhisperMode::Logger qw(log_msg);

has artifacts => ( is => 'ro', required => 1 );
has config    => ( is => 'ro', required => 1 );
has memory    => ( is => 'ro', required => 1 );
has state     => ( is => 'ro', required => 1 );

sub _fatal {
    my ($message) = @_;
    die "whisper-record-toggle: $message\n";
}

sub _normalize {
    my ($text) = @_;
    $text //= q{};
    $text =~ s/[\p{Cc}\p{Cf}]+/ /gu;
    $text =~ s/\s+/ /gu;
    $text =~ s/\A\s+|\s+\z//gu;
    return $text;
}

sub _text_from_json {
    my ($data) = @_;
    my @parts;
    for my $key (qw(transcription segments)) {
        if (ref $data->{$key} eq 'ARRAY') {
            push @parts, map { ref $_ eq 'HASH' && defined $_->{text} ? $_->{text} : () } @{ $data->{$key} };
            last;
        }
    }
    push @parts, $data->{text} if !@parts && defined $data->{text};
    push @parts, $data->{result}{text} if !@parts && ref($data->{result}) eq 'HASH' && defined $data->{result}{text};
    return _normalize(join q{ }, @parts);
}

sub transcribe_pending {
    my ($self) = @_;
    my $recording = $self->state()->read() or return;
    my $wav = $self->artifacts()->validate_wav($recording);
    -f $wav && !-l $wav && -s $wav > 44
        or _fatal('recorded WAV is missing or too small to transcribe');

    my ($fh, $json) = tempfile('.whisper-transcript.XXXXXX', DIR => $self->state()->runtime_directory(), UNLINK => 0);
    close $fh or _fatal("cannot create transient transcription output: $!");
    if ($self->config()->persistent_memory_enabled()) {
        $self->memory()->transcribe($wav, $json);
    } else {
        my $prefix = $json;
        $prefix =~ s/\.XXXXXX\z//;
        my @command = (
            $self->config()->value('WHISPER_CLI'),
            '--model', $self->config()->value('WHISPER_MODEL'),
            '--file', $wav, '--threads', $self->config()->thread_count(),
            '--output-json', '--no-timestamps', '--output-file', $prefix,
        );
        my $status = system { $command[0] } @command;
        $status == 0 or _fatal('whisper-cli transcription failed');
        unlink $json if -e $json;
        $json = "$prefix.json";
    }
    my $data = $self->artifacts()->read_json($json, 8 * 1024 * 1024, 'Whisper transcription output');
    unlink $json or _fatal("cannot remove transient Whisper output: $!");
    my $text = _text_from_json($data);
    $self->artifacts()->store_transcript($recording->{stem}, $text);
    $self->artifacts()->append_task($recording->{stem}, $text);
    my $paths = $self->artifacts()->paths();
    $self->artifacts()->prune($paths->{audio}, 'wav');
    $self->artifacts()->prune($paths->{transcribed}, 'json');
    $self->state()->clear();
    log_msg('info', "transcribed Whisper recording $recording->{stem}");
}

1;
