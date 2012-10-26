package meon::Web::Config;

use meon::Web::SPc;
use Config::INI::Reader;
use File::Basename 'basename';
use Log::Log4perl;

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

sub get {
    return $config;
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
