#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

use Plack::Builder;

use meon::Web::SPc;
use meon::Web::SearchAPI;
use Path::Class qw(dir);

my $wapi = meon::Web::SearchAPI->new(
    static_dir       => dir(meon::Web::SPc->datadir, 'meon-web', 'search-api'),
    static_path      => 'oapi',
    file_placeholder => 'OAPI-SERVICE-NAME',
);
my $app = sub { $wapi->plack_handler(@_) };

builder {
    enable "Plack::Middleware::ContentLength";
    $app;
};

__END__

=head1 NAME

meon-web-search-api.psgi - PSGI file for meon::Web::SearchAPI

=head1 DESCRIPTION

See L<meon::Web::SearchAPI>.

Run using C<bin/run_meon-web-search-api>

=cut
