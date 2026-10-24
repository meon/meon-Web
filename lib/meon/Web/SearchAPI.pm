package meon::Web::SearchAPI;

use 5.010;
use utf8;
use Moose;

our $VERSION = '0.01';

use Async::Microservice;
with qw(Async::Microservice);
use meon::Web::SearchIndex;
use meon::Web::Util;

use namespace::autoclean;

use Future::AsyncAwait;
use JSON::PP ();
use Carp qw(croak);

has '+api_prefix' => ( default => '/_mws_1' );

my %RANKING_PROFILE = (
    search       => [qw(title_all content_search title_partial content_autocomplete)],
    autocomplete => [qw(title_all title_partial content_autocomplete content_search)],
);
my $SCORE_SCRIPT =
    q{params.base + (params.use_weight ? doc['weight'].value : 0.0) + (_score / (1.0 + _score))};

has 'ose' => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_opensearch',
);

sub _build_opensearch {
    my ($self) = @_;
    return meon::Web::SearchIndex->_build_opensearch();
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

sub _parse_search_types {
    my ( $self, $req_args ) = @_;

    my $search_types = [];
    return $search_types
        if !exists $req_args->{search_type};

    return undef
        unless ref( $req_args->{search_type} ) eq 'ARRAY';

    my %allowed_type = map { $_ => 1 } qw(page product category);
    for my $stype ( @{ $req_args->{search_type} } ) {
        return undef
            if !defined($stype) || ref($stype) || !$allowed_type{$stype};
        push( @$search_types, $stype );
    }

    return $search_types;
}

sub _map_autocomplete_items {
    my ( $self, $hits ) = @_;

    return [
        map {
            my $src = $_->{_source} || {};
            +{
                title       => $src->{title},
                url         => $src->{url},
                search_type => $src->{search_type},
                breadcrumb  => $src->{breadcrumb},
                teaser      => $src->{teaser},
                thumbnail   => $src->{thumbnail},
                weight      => $src->{weight},
                score       => 0 + ( $_->{_score} // 0 ),
            };
        } @$hits
    ];
}

sub _map_search_items {
    my ( $self, $hits ) = @_;

    return [
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
    ];
}

sub _build_ranked_query {
    my ( $self, %args ) = @_;

    my $normalized_query = $args{normalized_query};
    my $title_query      = $args{title_query};
    my $profile          = $RANKING_PROFILE{ $args{profile} }
        or croak "unknown query profile '$args{profile}'";

    my $content_predicate = {
        match => {
            search_content => {
                query    => $normalized_query,
                operator => 'and',
            },
        },
    };
    my %predicate = (
        title_all => {
            match => {
                title_ngram => {
                    query    => $title_query,
                    operator => 'and',
                },
            },
        },
        title_partial => {
            match => {
                title_ngram => {
                    query                 => $title_query,
                    operator              => 'or',
                    minimum_should_match => '85%',
                },
            },
        },
        content_search       => $content_predicate,
        content_autocomplete => $content_predicate,
    );

    my @ranked_queries;
    for my $position ( 0 .. $#$profile ) {
        my $role = $profile->[$position];
        push(
            @ranked_queries,
            {   script_score => {
                    query => $predicate{$role},
                    script => {
                        source => $SCORE_SCRIPT,
                        params => {
                            base       => 40 - 10 * $position,
                            use_weight => $role eq 'content_search'
                                ? JSON::PP::false
                                : JSON::PP::true,
                        },
                    },
                },
            },
        );
    }

    return {
        bool => {
            must => [
                {   dis_max => {
                        tie_breaker => 0,
                        queries     => \@ranked_queries,
                    },
                },
            ],
            ( @{ $args{filter} } ? ( filter => $args{filter} ) : () ),
        },
    };
}

async sub POST_autocomplete {
    my ( $self, $this_req, $match ) = @_;

    my $ac_args = eval { $this_req->json_content };
    return [ 400, [], 'invalid json body' ]
        if $@ || ( ref($ac_args) ne 'HASH' );

    my $query = $ac_args->{query};
    return [ 400, [], 'query is required' ]
        if !defined($query) || ref($query);
    $query =~ s/^\s+|\s+$//g;
    return [ 400, [], 'query is required' ]
        if $query eq '';
    my $norm_query = meon::Web::Util->norm_tokens($query);

    my $limit = defined $ac_args->{limit} ? $ac_args->{limit} : 10;
    return [ 400, [], 'limit must be integer in range 1..100' ]
        unless $limit =~ m/^\d+$/ && $limit >= 1 && $limit <= 100;

    my $search_types = $self->_parse_search_types($ac_args);
    return [ 400, [], 'search_type must be an array with valid values' ]
        unless defined($search_types);

    my $host = $this_req->http_host;
    my $search_index = eval { meon::Web::SearchIndex->new( hostname => $host ) };
    return [ 400, [], 'invalid Host header' ]
        if $@ || !$search_index;

    my @filter;
    if (@$search_types) {
        push( @filter, { terms => { search_type => $search_types } } );
    }

    my $ac_terms = meon::Web::Util->explode_for_autocomplete($query);
    my $ac_query_txt = join( ' ', @$ac_terms );
    my $ac_query = $self->_build_ranked_query(
        profile          => 'autocomplete',
        normalized_query => $norm_query,
        title_query      => $ac_query_txt,
        filter           => \@filter,
    );

    my $ac_ose_result = eval {
        await $self->ose->search(
            index => $search_index->index_alias,
            body  => {
                query => $ac_query,

                size => $limit,

                sort => [ { _score => { order => 'desc' } }, ],
            },
        )->ft;
    };

    if ( $@ || ref($ac_ose_result) ne 'HASH' ) {
        warn "autocomplete backend query for host '$host' failed: $@";
        return [ 500, [], 'search backend query failed' ];
    }

    my $ac_hits = $ac_ose_result->{hits}->{hits} || [];
    return {
        query => $norm_query,
        total => scalar(@$ac_hits),
        items => $self->_map_autocomplete_items($ac_hits),
    };
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

    my $search_types = $self->_parse_search_types($srch_args);
    return [ 400, [], 'search_type must be an array with valid values' ]
        unless defined($search_types);

    my $host = $this_req->http_host;
    my $search_index = eval { meon::Web::SearchIndex->new( hostname => $host ) };
    return [ 400, [], 'invalid Host header' ]
        if $@ || !$search_index;

    my @filter;
    if (@$search_types) {
        push( @filter, { terms => { search_type => $search_types } } );
    }

    my $title_terms = meon::Web::Util->explode_for_autocomplete($query);
    my $search_query = $self->_build_ranked_query(
        profile          => 'search',
        normalized_query => $norm_query,
        title_query      => join( ' ', @$title_terms ),
        filter           => \@filter,
    );

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

    if ( $@ || ref($ose_result) ne 'HASH' ) {
        warn "search backend query for host '$host' failed: $@";
        return [ 500, [], 'search backend query failed' ];
    }

    my $hits = $ose_result->{hits}->{hits} || [];
    my $total = $ose_result->{hits}->{total};
    $total = ref($total) eq 'HASH' ? ( $total->{value} // 0 ) : ( $total // 0 );

    return {
        query   => $norm_query,
        total   => $total,
        page    => 0 + $page,
        size    => 0 + $size,
        took_ms => 0 + ( $ose_result->{took} // 0 ),
        items   => $self->_map_search_items($hits),
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

    curl "http://localhost:5001/_mws_1/hcheck" -H "accept: application/json"

=head1 DESCRIPTION

The standalone API uses C</_mws_1> as its default root. Search and autocomplete
accept POST JSON at C</_mws_1/search> and C</_mws_1/autocomplete>.

=head2 Search form backend

The Search form creates a default L<meon::Web::SearchAPI::Client>. The client
lazily parses the website's C<[search] searchapi_url> into the service origin
and API prefix, then appends C</search>.

Configured requests supply the website hostname for index selection. Run the
standalone service with C<USING_FRONTEND_PROXY=1> so it uses that hostname.

When the setting is missing or empty, the form uses the current request's
base URL with the client's default C</_mws_1/search> endpoint.

=head2 Authenticated autocomplete

To proxy autocomplete through meon::Web, configure the standalone search
service base URL in the website's F<config.ini>:

    [search]
    searchapi_url = http://127.0.0.1:5001/_mws_1

The controller appends C</autocomplete> to this base URL. A trailing slash
is optional; the configured path must match the standalone service's API root.

Run that service with C<USING_FRONTEND_PROXY=1>. The autocomplete proxy supplies
the website hostname for index selection; without proxy mode the service can
select its listener hostname instead. The configured URL must reach the
standalone service directly.

On restricted sites, route C</_mws_1/autocomplete> to meon::Web. Public sites
can route the same path directly to the standalone service. The frontend URL
is C</_mws_1/autocomplete> in either case. POST a JSON body with C<query> and
optional C<limit> and C<search_type>. The proxy forwards C<Accept>, including
its absence. Proxied responses use the backend status, content type,
encoding, and body bytes, including validation errors.

The controller requires authentication when C<[main] restricted_web> is true.
When the setting is false or absent, it permits anonymous requests.

=head1 SEARCH PRIORITY

C<POST_search> ranks branches in this order: all analyzed title n-grams,
normalized content, partial title matches at the 85% threshold, then the
weighted content role. C<POST_autocomplete> keeps its all-title, partial-title,
and weighted-content priorities, followed by the unweighted content role.
Both endpoints use the same match predicates and scoring script.

Each branch receives a base score of 40, 30, 20, or 10 according to its
position in the endpoint profile. The script adds bounded relevance and the
indexed weight for the C<title_all>, C<title_partial>, and
C<content_autocomplete> roles. Generated weights are between zero and 0.001.
The absolute scores therefore differ from earlier API responses. Finite score
precision can create ties between close relevance scores within a priority
tier.

A document matching multiple branches appears once, scored by its best branch.
Search includes title-only matches, so autocomplete matches are eligible for
search with the same query, host, filters, and index state. Pagination limits
and the different priorities can change their page and order.

=cut
