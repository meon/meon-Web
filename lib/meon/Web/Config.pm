package meon::Web::Config;

use strict;
use warnings;

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
foreach my $hostname_folder (keys %{$config->{domains} || {}}) {
    my $hostname_folder_config = File::Spec->catfile(
        meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_folder, 'config.ini'
    );
    warn $hostname_folder_config;
    if (-e $hostname_folder_config) {
        $config->{$hostname_folder} = Config::INI::Reader->read_file(
            $hostname_folder_config
        );
    }
}

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
