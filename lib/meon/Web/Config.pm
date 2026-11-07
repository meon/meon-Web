package meon::Web::Config;

use strict;
use warnings;

use meon::Web::SPc;
use Config::INI::Reader;
use File::Basename 'basename';
use Log::Log4perl;
use Path::Class 'file', 'dir';
use Run::Env;
use File::is;
use File::Temp qw(tempfile);
use Time::Duration::Parse::More qw(parse_duration);

Log::Log4perl::init(
    File::Spec->catfile(
        meon::Web::SPc->sysconfdir, 'meon', 'web-log4perl.conf'
    )
);

my $config = Config::INI::Reader->read_file(
    File::Spec->catfile(
        meon::Web::SPc->sysconfdir, 'meon', 'web-config.ini'
    )
);
foreach my $hostname_dir_name (keys %{$config->{domains} || {}}) {
    my $hostname_dir = File::Spec->catfile(
        meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_dir_name
    );
    my $hostname_dir_config = File::Spec->catfile(
        $hostname_dir, 'config.ini'
    );
    if (Run::Env->dev) {
        my $hostname_dir_config_dev = File::Spec->catfile(
            $hostname_dir, 'config_dev.ini'
        );
        $hostname_dir_config = $hostname_dir_config_dev
            if -e $hostname_dir_config_dev;
    }

    if (-e $hostname_dir_config) {
        $config->{$hostname_dir_name} = Config::INI::Reader->read_file(
            $hostname_dir_config
        );
        __PACKAGE__->process_site_assets(
            $hostname_dir,
            $config->{$hostname_dir_name}
        );
    }
}

sub use_minified_assets {
    my ($class) = @_;
    return (!Run::Env->dev || $ENV{USE_MINIFIED_ASSETS}) ? 1 : 0;
}

sub process_site_assets {
    my ($class, $hostname_dir, $site_config) = @_;

    if ($class->use_minified_assets) {
        $class->minify_assets(
            $hostname_dir,
            $site_config
        );
    }
    return;
}

sub minify_assets {
    my ($class, $hostname_dir, $site_config) = @_;

    if (my $js_dir = $site_config->{main}->{'js-dir'}) {
        $js_dir = dir($hostname_dir, $js_dir);
        my $merged_js = '';
        my @merge_js_files;
        foreach my $js_file (sort $js_dir->children(no_hidden => 1)) {
            next unless -f $js_file;
            push(@merge_js_files, $js_file.'');
            $merged_js .= '/* '.$js_file." */\n\n".$js_file->slurp.";\n\n";
        }
        my $js_merged_file = file($hostname_dir, 'www','static','meon-Web-merged.js');

        if (@merge_js_files && ((! -f $js_merged_file) || !File::is->newest($js_merged_file, @merge_js_files))) {
            my ($tmp_fh, $tmp_filename) = tempfile(undef, UNLINK => 1);
            print $tmp_fh $merged_js;
            close($tmp_fh);
            if (system(
                    "esbuild --log-level=error --minify --loader=js --charset=utf8 < $tmp_filename > $js_merged_file.tmp && mv $js_merged_file.tmp $js_merged_file"
                ) != 0
            ) {
                my $status_text = ($? & 127) ? "signal " . ($? & 127) : "exit " . ($? >> 8);
                warn "failed to minify js ($status_text)";
                system(
                    "cp $tmp_filename $js_merged_file.tmp && mv $js_merged_file.tmp $js_merged_file"
                );
            }
        }
    }
    if (my $css_dir = $site_config->{main}->{'css-dir'}) {
        $css_dir = dir($hostname_dir, $css_dir);
        my $merged_css = '';
        my @merge_css_files;
        foreach my $css_file (sort $css_dir->children(no_hidden => 1)) {
            next unless -f $css_file;
            push(@merge_css_files, $css_file);
            $merged_css .= '/* '.$css_file." */\n\n".$css_file->slurp."\n\n";
        }
        my $css_merged_file = file($hostname_dir, 'www','static','meon-Web-merged.css');

        if (@merge_css_files && ((! -f $css_merged_file) || !File::is->newest($css_merged_file, @merge_css_files))) {
            my ($tmp_fh, $tmp_filename) = tempfile(undef, UNLINK => 1);
            print $tmp_fh $merged_css;
            close($tmp_fh);
            if (system(
                    "esbuild --log-level=error --minify --loader=css --charset=utf8 < $tmp_filename > $css_merged_file.tmp && mv $css_merged_file.tmp $css_merged_file"
                ) != 0
            ) {
                my $status_text = ($? & 127) ? "signal " . ($? & 127) : "exit " . ($? >> 8);
                warn "failed to minify css ($status_text)";
                system(
                    "cp $tmp_filename $css_merged_file.tmp && mv $css_merged_file.tmp $css_merged_file"
                );
            }
        }
    }

    return;
}

sub get {
    return $config;
}

sub expand_inplace {
    my ( $class, $value ) = @_;
    return $value unless defined $value;
    $value =~ s{\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}}{
        exists $ENV{$1} ? $ENV{$1}
            : die "Environment variable $1 is not set\n"
    }ge;
    return $value;
}

sub session_expires {
    my $duration = $config->{main}{'session-expires'};
    $duration = '4 hours'
        unless defined $duration;
    my $seconds = parse_duration($duration);
    die "session-expires must be greater than zero\n"
        unless $seconds > 0;
    return $seconds;
}

my %h2f;
sub hostname_to_folder {
    my ($class, $hostname) = @_;

    unless (%h2f) {
        foreach my $folder (keys %{$config->{domains} || {}}) {
            my @domains = map { $_ =~s/^\s+//;$_ =~s/\s+$//; $_ }  split(/\s*,\s*/, $config->{domains}{$folder});
            foreach my $domain (@domains) {
                $h2f{$domain} = $folder;
            }
        }
    }

    return $h2f{$hostname};
}

1;

__END__

=head1 NAME

meon::Web::Config - website configuration

=head1 METHODS

=head2 use_minified_assets

    my $use_minified = meon::Web::Config->use_minified_assets;

Returns true (1) if the application should use minified assets, either because
it is running outside the development environment (C<!Run::Env->dev>) or because
the C<USE_MINIFIED_ASSETS> environment variable is set to a true value. Returns
false (0) otherwise.

=head2 process_site_assets

    meon::Web::Config->process_site_assets($hostname_dir, $site_config);

Inspects the website configuration for asset directories (C<js-dir> and
C<css-dir>) and delegates to C<minify_assets> if C<use_minified_assets> returns
true.

=head2 minify_assets

    meon::Web::Config->minify_assets($hostname_dir, $site_config);

Concatenates and minifies JavaScript files from C<main.js-dir> into
F<www/static/meon-Web-merged.js> and CSS files from C<main.css-dir> into
F<www/static/meon-Web-merged.css> within the given site directory using
C<esbuild --minify>.

If merged files already exist and are newer than their source files, rebuilding
is skipped. If minification fails, a warning with the exit status is emitted
and unminified concatenated content is written as fallback.

=head2 expand_inplace

    my $nodes = meon::Web::Config->expand_inplace($configured_nodes);

Returns a copy of the string with each C<${env:SOME_ENV_KEY}> placeholder
replaced by its environment value. Undefined input is returned unchanged.
Replacement values are inserted literally without recursive expansion.
An unset variable raises an error naming its key; an empty value is valid.

The global C<[search]> settings C<opensearch_nodes> and
C<opensearch_basic_auth> use this expansion when a client is created.
Stored configuration remains unchanged.

=cut
