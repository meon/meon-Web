package meon::Web::SearchAPI;

use 5.010;
use utf8;
use Moose;

our $VERSION = '0.01';

use Async::Microservice;
with qw(Async::Microservice);
use Search::Elasticsearch::Async;

use namespace::autoclean;

use Future::AsyncAwait;
use Carp qw(croak);

has 'ose' => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_opensearch',
);

sub _build_opensearch {
    my ($self) = @_;
    my @ose_nodes =
        split( ',', meon::Web::Config->get->{opensearch}->{nodes} );
    return Search::Elasticsearch::Async->new(
        nodes           => \@ose_nodes,
        request_timeout => 300,
        cxn_pool        => 'Async::Sniff',
    );
}
sub service_name {
    return 'meon-web-search-api';
}

sub get_routes {
    return (
        'autocomplete' => { defaults => { POST => 'POST_autocomplete', } },
        'search'       => { defaults => { POST => 'POST_search', }, },
    );
}

async sub POST_autocomplete {
    my ( $self, $this_req, $match ) = @_;

    my $ac_args = eval { $this_req->json_content };
    return [ 400, [], 'invalid json body' ]
        if $@ || ( ref($ac_args) ne 'HASH' );

    return $ac_args; # for testing
}

async sub POST_search {
    my ( $self, $this_req, $match ) = @_;

    my $srch_args = eval { $this_req->json_content };
    return [ 400, [], 'invalid json body' ]
        if $@ || ( ref($srch_args) ne 'HASH' );

    return $srch_args; # for testing
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

meon::Web::SearchAPI - meon::Web Search API

=head1 SYNOPSYS

    bin/run_meon-web-search-api

    curl "http://localhost:5001/v1/hcheck" -H "accept: application/json"

=head1 DESCRIPTION

meon::Web Search API

=cut
