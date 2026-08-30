package Telpoll::Whisper;

use strict;
use warnings;

use Errno qw(EEXIST);
use Fcntl qw(:flock O_APPEND O_CREAT O_EXCL O_NOFOLLOW O_RDONLY O_RDWR O_WRONLY);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON::PP;
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use POSIX qw(strftime sysconf);
use Types::Standard qw(Str);

has home => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has logger => (
    is       => 'ro',
    required => 1,
);

has ffmpeg_binary => (
    is      => 'ro',
    isa     => Str,
    default => sub { '/usr/bin/ffmpeg' },
);

has config_path => (
    is      => 'ro',
    isa     => Str,
    default => sub { '/etc/whisper/whisper.conf' },
);

sub reserve_stem {
    my ($self, $epoch) = @_;

    defined($epoch) && "$epoch" =~ /\A[0-9]{1,12}\z/
        or die "telpoll: Whisper message timestamp is invalid\n";
    my $paths = $self->_paths();
    for my $offset (0 .. 120) {
        my $stem = strftime('%Y-%m-%d-%H-%M-%S', localtime($epoch + $offset));
        my $wav = "$paths->{audio}/$stem.wav";
        if (sysopen my $fh, $wav, O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY, 0600) {
            close $fh
                or die "telpoll: cannot close Whisper audio reservation: $!\n";
            return $stem;
        }
        next if $! == EEXIST;
        die "telpoll: cannot reserve a Whisper artifact name: $!\n";
    }
    die "telpoll: cannot allocate a collision-free Whisper artifact name\n";
}

sub release_reservation {
    my ($self, $stem) = @_;

    _validate_stem($stem);
    my $wav = $self->_paths()->{audio} . "/$stem.wav";
    return if !-e $wav;
    my $size = _user_file_size($wav, 'Whisper audio reservation');
    unlink $wav
        or die "telpoll: cannot release Whisper audio reservation: $!\n"
        if $size == 0;
    return;
}

sub process_ogg {
    my ($self, $source, $stem) = @_;

    defined($source) && $source =~ /\.(?:oga|ogg)\z/i
        or die "telpoll: Whisper source must be an .oga or .ogg file\n";
    -f $source && !-l $source && (lstat $source)[4] == $< && -s $source > 0
        or die "telpoll: Whisper source file is unsafe or empty\n";
    _validate_stem($stem);

    my $wav = $self->_convert_to_wav($source, $stem);
    my $text = $self->_transcribe($wav, $stem);
    $self->_append_task($stem, $text);
    return $text;
}

sub _convert_to_wav {
    my ($self, $source, $stem) = @_;

    my $paths = $self->_paths();
    my $destination = "$paths->{audio}/$stem.wav";
    if (!-e $destination) {
        sysopen my $reservation,
            $destination,
            O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY,
            0600
            or die "telpoll: cannot restore Whisper audio reservation: $!\n";
        close $reservation
            or die "telpoll: cannot close Whisper audio reservation: $!\n";
    }
    my $destination_size =
        _user_file_size($destination, 'Whisper audio reservation');
    return $destination if $destination_size > 44;
    $destination_size == 0
        or die "telpoll: Whisper audio reservation is not empty\n";
    _safe_absolute_file('ffmpeg', $self->ffmpeg_binary(), 1);

    my ($fh, $temporary) = tempfile(".$stem.XXXXXX", DIR => $paths->{audio}, SUFFIX => '.wav', UNLINK => 0);
    close $fh
        or die "telpoll: cannot create temporary Whisper WAV: $!\n";
    my @command = (
        $self->ffmpeg_binary(),
        '-nostdin',
        '-hide_banner',
        '-loglevel', 'error',
        '-y',
        '-i', $source,
        '-vn',
        '-ac', '1',
        '-ar', '16000',
        '-c:a', 'pcm_s16le',
        $temporary,
    );
    my $status = system { $command[0] } @command;
    if ($status != 0) {
        unlink $temporary if -e $temporary;
        die "telpoll: ffmpeg conversion failed\n";
    }
    -f $temporary && !-l $temporary && (lstat $temporary)[4] == $< && -s $temporary > 44
        or do {
            unlink $temporary if -e $temporary;
            die "telpoll: ffmpeg did not create a valid Whisper WAV\n";
        };
    chmod 0600, $temporary
        or die "telpoll: cannot secure temporary Whisper WAV: $!\n";
    _user_file_size($destination, 'Whisper audio reservation') == 0
        or die "telpoll: Whisper audio reservation changed during conversion\n";
    rename $temporary, $destination
        or die "telpoll: cannot publish converted Whisper WAV: $!\n";
    return $destination;
}

sub _transcribe {
    my ($self, $wav, $stem) = @_;

    my $paths = $self->_paths();
    my $transcript = "$paths->{transcribed}/$stem.json";
    if (-e $transcript) {
        my $data = $self->_read_json($transcript, 8 * 1024 * 1024, 'stored Whisper transcript');
        return _text_from_json($data);
    }

    my $config = $self->_read_whisper_config();
    my ($fh, $prefix) = tempfile(".$stem.XXXXXX", DIR => $paths->{transcribed}, UNLINK => 0);
    close $fh
        or die "telpoll: cannot create temporary Whisper output prefix: $!\n";
    unlink $prefix
        or die "telpoll: cannot prepare temporary Whisper output prefix: $!\n";
    my @command = (
        $config->{WHISPER_CLI},
        '--model', $config->{WHISPER_MODEL},
        '--file', $wav,
        '--threads', $self->_thread_count($config->{WHISPER_RUNTIME_THREADS}),
        '--output-json',
        '--no-timestamps',
        '--output-file', $prefix,
    );
    my $status = system { $command[0] } @command;
    my $generated = "$prefix.json";
    if ($status != 0) {
        unlink $generated if -e $generated;
        die "telpoll: whisper-cli transcription failed\n";
    }
    my $data = $self->_read_json($generated, 8 * 1024 * 1024, 'Whisper transcription output');
    my $text = _text_from_json($data);
    $self->_atomic_json($paths->{transcribed}, "$stem.json", { text => $text });
    unlink $generated
        or die "telpoll: cannot remove temporary Whisper transcription output: $!\n";
    return $text;
}

sub _append_task {
    my ($self, $stem, $text) = @_;

    $text = _normalize_text($text);
    return if !length($text);
    my $paths = $self->_paths();
    my $directory = $paths->{sleek};
    my $task_file = "$directory/whisper.txt";
    if (!-e $task_file) {
        if (sysopen my $new,
            $task_file,
            O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY,
            0600
        ) {
            close $new
                or die "telpoll: cannot close Sleek task file: $!\n";
        }
        elsif ($! != EEXIST) {
            die "telpoll: cannot create Sleek task file: $!\n";
        }
    }
    _user_file_size($task_file, 'Sleek task file');
    chmod 0600, $task_file
        or die "telpoll: cannot secure Sleek task file: $!\n";

    sysopen my $lock, "$directory/.whisper.txt.lock", O_CREAT | O_NOFOLLOW | O_RDWR, 0600
        or die "telpoll: cannot open Sleek task lock: $!\n";
    my @lock_stat = stat $lock;
    @lock_stat && -f $lock && $lock_stat[4] == $<
        or die "telpoll: Sleek task lock is unsafe\n";
    chmod 0600, "$directory/.whisper.txt.lock"
        or die "telpoll: cannot secure Sleek task lock: $!\n";
    flock($lock, LOCK_EX)
        or die "telpoll: cannot lock Sleek task file: $!\n";

    _user_file_size($task_file, 'Sleek task file') <= 16 * 1024 * 1024
        or die "telpoll: Sleek task file exceeds the size limit\n";
    sysopen my $read, $task_file, O_RDONLY | O_NOFOLLOW
        or die "telpoll: cannot read Sleek task file: $!\n";
    my @read_stat = stat $read;
    @read_stat && -f $read && $read_stat[4] == $< &&
        ($read_stat[2] & 0077) == 0
        or die "telpoll: Sleek task file is unsafe\n";
    binmode $read, ':encoding(UTF-8)'
        or die "telpoll: cannot configure Sleek task encoding: $!\n";
    while (my $line = <$read>) {
        if ($line =~ /(?:\A|\s)source:\Q$stem\E(?:\s|\z)/) {
            close $read
                or die "telpoll: cannot close Sleek task file: $!\n";
            close $lock
                or die "telpoll: cannot close Sleek task lock: $!\n";
            return;
        }
    }
    close $read
        or die "telpoll: cannot close Sleek task file: $!\n";

    sysopen my $append, $task_file, O_APPEND | O_NOFOLLOW | O_WRONLY
        or die "telpoll: cannot append Sleek task: $!\n";
    my @append_stat = stat $append;
    @append_stat && -f $append && $append_stat[4] == $< &&
        ($append_stat[2] & 0077) == 0
        or die "telpoll: Sleek task file is unsafe\n";
    binmode $append, ':encoding(UTF-8)'
        or die "telpoll: cannot configure Sleek task encoding: $!\n";
    print {$append} substr($stem, 0, 10), " $text +whisper \@voice source:$stem\n"
        or die "telpoll: cannot write Sleek task: $!\n";
    $append->sync()
        or die "telpoll: cannot synchronize Sleek task file: $!\n";
    close $append
        or die "telpoll: cannot close Sleek task file: $!\n";
    close $lock
        or die "telpoll: cannot close Sleek task lock: $!\n";
    return;
}

sub _paths {
    my ($self) = @_;

    my $home = $self->home();
    -d $home && !-l $home && (lstat $home)[4] == $<
        or die "telpoll: HOME must remain a user-owned real directory\n";
    my $music = _parent_directory("$home/Music");
    my $root = _managed_directory("$music/Whisper", 0700);
    my $audio = _managed_directory("$root/audio", 0700);
    my $transcribed = _managed_directory("$root/transcribed", 0700);
    my $syncthing = _parent_directory("$home/Syncthing");
    my $sleek = _managed_directory("$syncthing/sleek", 0700);
    return {
        audio       => $audio,
        transcribed => $transcribed,
        sleek       => $sleek,
    };
}

sub _read_whisper_config {
    my ($self) = @_;

    my $path = $self->config_path();
    sysopen my $fh, $path, O_RDONLY | O_NOFOLLOW
        or die "telpoll: Whisper configuration is unavailable\n";
    my @stat = stat $fh;
    @stat && -f $fh && $stat[4] == 0 && ($stat[2] & 0022) == 0 &&
        $stat[7] > 0 && $stat[7] <= 16 * 1024
        or die "telpoll: Whisper configuration is unsafe\n";
    my %values;
    while (my $line = <$fh>) {
        $line =~ s/\r?\n\z//;
        next if $line eq q{} || $line =~ /\A#/;
        $line =~ /\A([A-Z_]+)=([^\r\n]*)\z/
            or die "telpoll: Whisper configuration contains an invalid line\n";
        exists($values{$1})
            and die "telpoll: Whisper configuration contains duplicate $1\n";
        $values{$1} = $2;
    }
    close $fh
        or die "telpoll: cannot close Whisper configuration: $!\n";
    for my $key (qw(WHISPER_CLI WHISPER_MODEL WHISPER_RUNTIME_THREADS)) {
        defined($values{$key}) && length($values{$key})
            or die "telpoll: Whisper configuration is missing $key\n";
    }
    _safe_absolute_file('WHISPER_CLI', $values{WHISPER_CLI}, 1);
    _safe_absolute_file('WHISPER_MODEL', $values{WHISPER_MODEL}, 0);
    $values{WHISPER_RUNTIME_THREADS} =~ /\A(?:auto|[1-9][0-9]{0,2})\z/
        or die "telpoll: WHISPER_RUNTIME_THREADS is invalid\n";
    $values{WHISPER_RUNTIME_THREADS} eq 'auto' ||
        $values{WHISPER_RUNTIME_THREADS} <= 256
        or die "telpoll: WHISPER_RUNTIME_THREADS exceeds the supported limit\n";
    return \%values;
}

sub _read_json {
    my ($self, $path, $limit, $label) = @_;

    sysopen my $fh, $path, O_RDONLY | O_NOFOLLOW
        or die "telpoll: cannot read $label: $!\n";
    my @stat = stat $fh;
    @stat && -f $fh && $stat[4] == $< && ($stat[2] & 0077) == 0 &&
        $stat[7] > 0 && $stat[7] <= $limit
        or die "telpoll: $label is missing, unsafe, or too large\n";
    binmode $fh, ':raw';
    local $/;
    my $raw = <$fh> // q{};
    close $fh
        or die "telpoll: cannot close $label: $!\n";
    my $data = eval { JSON::PP->new()->utf8(1)->decode($raw) };
    !$@ && ref($data) eq 'HASH'
        or die "telpoll: $label is not valid JSON\n";
    return $data;
}

sub _atomic_json {
    my ($self, $directory, $name, $data) = @_;

    $name =~ /\A[0-9A-Za-z._-]+\z/
        or die "telpoll: Whisper artifact name is invalid\n";
    my $content = JSON::PP->new()->canonical(1)->utf8(1)->encode($data) . "\n";
    my ($fh, $temporary) = tempfile(".$name.XXXXXX", DIR => $directory, UNLINK => 0);
    my $ok = eval {
        binmode $fh, ':raw';
        print {$fh} $content
            or die "telpoll: cannot write temporary Whisper artifact: $!\n";
        $fh->sync()
            or die "telpoll: cannot synchronize temporary Whisper artifact: $!\n";
        close $fh
            or die "telpoll: cannot close temporary Whisper artifact: $!\n";
        chmod 0600, $temporary
            or die "telpoll: cannot secure temporary Whisper artifact: $!\n";
        rename $temporary, "$directory/$name"
            or die "telpoll: cannot publish Whisper artifact: $!\n";
        1;
    };
    if (!$ok) {
        my $error = $@ || "telpoll: unknown Whisper artifact write failure\n";
        close $fh if defined(fileno($fh));
        unlink $temporary if defined($temporary) && -e $temporary;
        die $error;
    }
    return;
}

sub _thread_count {
    my ($self, $configured) = @_;

    return $configured if $configured ne 'auto';
    my $count = eval { sysconf(POSIX::_SC_NPROCESSORS_ONLN()) };
    if (defined($count) && "$count" =~ /\A[1-9][0-9]*\z/) {
        return $count > 256 ? 256 : $count;
    }
    return 1;
}

sub _parent_directory {
    my ($path) = @_;

    if (!-e $path) {
        make_path($path, { mode => 0700 });
    }
    -d $path && !-l $path && (lstat $path)[4] == $<
        or die "telpoll: required parent directory is unsafe: $path\n";
    return $path;
}

sub _managed_directory {
    my ($path, $mode) = @_;

    if (!-e $path) {
        make_path($path, { mode => $mode });
    }
    -d $path && !-l $path && (lstat $path)[4] == $<
        or die "telpoll: managed Whisper directory is unsafe: $path\n";
    chmod $mode, $path
        or die "telpoll: cannot secure managed Whisper directory: $!\n";
    return $path;
}

sub _user_file_size {
    my ($path, $label) = @_;

    my @stat = lstat $path;
    @stat && -f _ && !-l _ && $stat[4] == $< && ($stat[2] & 0077) == 0
        or die "telpoll: $label is unsafe\n";
    return $stat[7];
}

sub _safe_absolute_file {
    my ($label, $path, $executable) = @_;

    defined($path) && $path =~ m{\A/} &&
        $path !~ m{\0|(?:\A|/)\.\.(?:/|\z)|//}
        or die "telpoll: $label path is invalid\n";
    my @stat = lstat $path;
    @stat && -f _ && !-l _ && $stat[4] == 0 && ($stat[2] & 0022) == 0
        or die "telpoll: $label is unavailable\n";
    $executable ? -x $path : -r $path
        or die "telpoll: $label is not accessible\n";
    return;
}

sub _validate_stem {
    my ($stem) = @_;
    defined($stem) && $stem =~ /\A[0-9]{4}(?:-[0-9]{2}){5}\z/
        or die "telpoll: Whisper artifact stem is invalid\n";
    return;
}

sub _text_from_json {
    my ($data) = @_;

    my @parts;
    for my $key (qw(transcription segments)) {
        if (ref($data->{$key}) eq 'ARRAY') {
            push @parts, map {
                ref($_) eq 'HASH' && defined($_->{text}) && !ref($_->{text})
                    ? $_->{text}
                    : ()
            } @{$data->{$key}};
            last;
        }
    }
    push @parts, $data->{text}
        if !@parts && defined($data->{text}) && !ref($data->{text});
    push @parts, $data->{result}->{text}
        if !@parts && ref($data->{result}) eq 'HASH' &&
            defined($data->{result}->{text}) && !ref($data->{result}->{text});
    return _normalize_text(join q{ }, @parts);
}

sub _normalize_text {
    my ($text) = @_;

    $text //= q{};
    $text =~ s/[\p{Cc}\p{Cf}]+/ /gu;
    $text =~ s/\s+/ /gu;
    $text =~ s/\A\s+|\s+\z//gu;
    $text = substr($text, 0, 8_192) if length($text) > 8_192;
    return $text;
}

1;
