package meon::Web::SearchAPI;

use 5.010;
use utf8;
use Moose;

our $VERSION = '0.01';

use Async::Microservice;
with qw(Async::Microservice);
use Search::Elasticsearch::Async;
use meon::Web::SearchIndex;
use meon::Web::Util;

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
    my $cfg = meon::Web::Config->get->{opensearch};
    my @ose_nodes = split( ',', $cfg->{nodes} );
    my %osearch_args = (
        nodes           => \@ose_nodes,
        request_timeout => 300,
        cxn_pool        => (
            $cfg->{cxn_pool} // 'Async::Static'
        ),
    );
    $osearch_args{userinfo} = $cfg->{basic_auth}
        if $cfg->{basic_auth};
    return Search::Elasticsearch::Async->new(%osearch_args);
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

    my $query = $srch_args->{query};
    return [ 400, [], 'query is required' ]
        if !defined($query) || ref($query);
    $query =~ s/^\s+|\s+$//g;
    return [ 400, [], 'query is required' ]
        if $query eq '';
    my $norm_query = meon::Web::Util->norm_tokens($query);

    my $page = defined $srch_args->{page} ? $srch_args->{page} : 1;
    my $size = defined $srch_args->{size} ? $srch_args->{size} : 20;

    return [ 400, [], 'page must be integer >= 1' ]
        unless $page =~ m/^\d+$/ && $page >= 1;
    return [ 400, [], 'size must be integer in range 1..200' ]
        unless $size =~ m/^\d+$/ && $size >= 1 && $size <= 200;

    my $search_types = [];
    if ( exists $srch_args->{search_type} ) {
        return [ 400, [], 'search_type must be an array' ]
            unless ref( $srch_args->{search_type} ) eq 'ARRAY';

        my %allowed_type = map { $_ => 1 } qw(page product category);
        for my $stype ( @{ $srch_args->{search_type} } ) {
            return [ 400, [], 'invalid search_type value' ]
                if !defined($stype) || ref($stype) || !$allowed_type{$stype};
            push( @$search_types, $stype );
        }
    }

    my $host = $this_req->http_host;
    my $search_index = eval { meon::Web::SearchIndex->new( hostname => $host ) };
    return [ 400, [], 'invalid Host header' ]
        if $@ || !$search_index;

    my @filter;
    if (@$search_types) {
        push( @filter, { terms => { search_type => $search_types } } );
    }

    my $search_query = {
        bool => {
            must => [
                {
                    match => {
                        search_content => {
                            query    => $norm_query,
                            operator => 'and',
                        },
                    },
                },
            ],
            ( @filter ? ( filter => \@filter ) : () ),
        },
    };

    my $ose_result = eval {
        await $self->ose->search(
            index => $search_index->index_alias,
            body  => {
                query => $search_query,
                from  => ( $page - 1 ) * $size,
                size  => $size,
                sort  => [
                    { _score => { order => 'desc' } },
                ],
            },
        )->ft;
    };

    return [ 500, [], 'search backend query failed' ]
        if $@ || ref($ose_result) ne 'HASH';

    my $hits = $ose_result->{hits}->{hits} || [];
    my $total = $ose_result->{hits}->{total};
    $total = ref($total) eq 'HASH' ? ( $total->{value} // 0 ) : ( $total // 0 );

    return {
        query   => $norm_query,
        total   => $total,
        page    => 0 + $page,
        size    => 0 + $size,
        took_ms => 0 + ( $ose_result->{took} // 0 ),
        items   => [
            map {
                my $src = $_->{_source} || {};
                +{
                    title          => $src->{title},
                    url            => $src->{url},
                    search_type    => $src->{search_type},
                    breadcrumb     => $src->{breadcrumb},
                    teaser         => $src->{teaser},
                    thumbnail      => $src->{thumbnail},
                    weight         => $src->{weight},
                    score          => 0 + ( $_->{_score} // 0 ),
                    index_ts       => $src->{index_ts},
                    search_content => $src->{search_content},
                };
            } @$hits
        ],
    };
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
