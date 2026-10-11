#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use JSON::XS;
use Digest::SHA qw(sha256_base64);
use File::Temp            qw(tempfile);
use Path::Class           qw(file dir);
use Monkey::Patch::Action qw(patch_package);

use Test::Most;
use Test::WWW::Mechanize;

use FindBin     qw($Bin);
use Path::Class qw(file dir);
use lib file( $Bin, 'testlib' )->stringify;

use_ok('meon::Web::SPc') or exit;
my $patch_prefix = patch_package(
    'meon::Web::SPc',
    'prefix',
    'replace',
    sub {
        dir( Sys::Path->find_distribution_root('meon::Web::SPc'), 't',
            'tsp' );
    }
);

my $json      = JSON::XS->new();
my $tdata_dir = dir( meon::Web::SPc->datadir, 'meon-web', 'search-api' );

use_ok('meon::Web::Search')          or die;
use_ok('meon::Web::SearchAPI')       or die;
use_ok('Test::meon::Web::SearchAPI') or die;
use_ok('meon::Web::SearchIndex')     or die;
use_ok('meon::Web::Util')            or die;

# empty static dir
my $static_dir = $tdata_dir->subdir('oapi');
$static_dir->mkpath;
$ENV{STATIC_DIR} = $static_dir;
$ENV{USING_FRONTEND_PROXY} = 1;

my $meon_webapi = Test::meon::Web::SearchAPI->start;
my $service_url = $meon_webapi->url;
my $mech        = Test::WWW::Mechanize->new();
$mech->add_header( content_type => 'application/json' );
$mech->add_header( accept       => 'application/json' );
$mech->add_header( 'HTTP_X_FORWARDED_HOST' => 'search-test.local' );

$mech->get_ok( $service_url . 'hcheck' )
    or die Test::More::diag( Data::Dumper::Dumper( $mech->content ) );

unless ( $ENV{TEST_WITH_OPENSEARCH} ) {
    ok( 1, "skipping opensearch tests, enable with TEST_WITH_OPENSEARCH=1" );
    done_testing();
    exit;
}

subtest 'refresh index' => sub {
    my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
    my $search_index = $mws->search_index;
    my $search_result =
        $search_index->ose->count( index => $search_index->index_alias, )
        ->sync;
    if ( $search_result->{count} < 5 ) {
        diag(
            'indexed records not present, please run `TEST_WITH_OPENSEARCH=1 prove 61_meon-Web-Index.t` first'
        );
        exit;
    }

    ok( 1, 'search records present' );
};

subtest '/autocomplete' => sub {
    subtest 'title_ngram query' => sub {
        $mech->post( $service_url . 'autocomplete',
            content => $json->encode( { query => 'PRODUCT 2-1', limit => 3 } ), );
        ok( $mech->success, 'post to autocomplete' ) or diag( $mech->content );

        my $dt_data;
        lives_ok( sub { $dt_data = $json->decode( $mech->content ) },
            'json content' );

        is( $dt_data->{query}, 'product 2-1', 'autocomplete response query' );
        is( $dt_data->{total}, 3, 'autocomplete response total' );
        ok( ref( $dt_data->{items} ) eq 'ARRAY', 'autocomplete items array' );
        is( scalar( @{ $dt_data->{items} } ), 3, 'autocomplete items count' );
        is( $dt_data->{items}->[0]->{title}, 'Product 2-1-1', 'first title' );
        is( $dt_data->{items}->[1]->{title}, 'Product 2-1-2', 'second title' );
        is( $dt_data->{items}->[2]->{title}, 'Product 2-1-3', 'third title' );
    };

    subtest 'fallback to normal search' => sub {
        $mech->post( $service_url . 'autocomplete',
            content => $json->encode( { query => 'second product' } ), );
        ok( $mech->success, 'post to autocomplete with fallback query' )
            or diag( $mech->content );

        my $dt_data;
        lives_ok( sub { $dt_data = $json->decode( $mech->content ) },
            'json content' );

        is( $dt_data->{query}, 'second product', 'fallback response query' );
        is( $dt_data->{total}, 2, 'fallback response total' );
        ok( ref( $dt_data->{items} ) eq 'ARRAY', 'fallback items array' );
        is( scalar( @{ $dt_data->{items} } ), 2, 'fallback items count' );
        is( $dt_data->{items}->[0]->{title}, 'Product 1-2', 'fallback first title' );
        is( $dt_data->{items}->[1]->{title}, 'Product 2-1-2',
            'fallback second title' );
    };
};

subtest '/search' => sub {
    $mech->post( $service_url . 'search',
        content => $json->encode( { query => 'sEcond product' } ), );
    ok( $mech->success, 'post to search' ) or diag($mech->content);
    my $dt_data;
    lives_ok( sub { $dt_data = $json->decode( $mech->content ) },
        'json content' );

    is( $dt_data->{query}, 'second product', 'search response query' );
    is( $dt_data->{total}, 2, 'search response total' );
    is( $dt_data->{page}, 1, 'search response page' );
    is( $dt_data->{size}, 20, 'search response size' );
    ok( exists $dt_data->{took_ms}, 'search response took_ms present' );
    ok( ref( $dt_data->{items} ) eq 'ARRAY', 'search response items array' );
    is( scalar( @{ $dt_data->{items} } ), 2, 'search response has 2 items' );
};

sub ranking_doc {
    my (%args) = @_;
    my $title = $args{title};
    return {
        url            => $args{url},
        title          => $title,
        teaser         => '',
        breadcrumb     => '',
        search_type    => 'page',
        index_ts       => '2026-10-09T00:00:00Z',
        weight         => $args{weight} // 0,
        title_ngram    => join( ' ', @{ meon::Web::Util->explode_for_autocomplete($title) } ),
        search_content => $args{content} // '',
        thumbnail      => '',
    };
}

sub ranking_request {
    my ( $endpoint, $args ) = @_;
    $mech->post( $service_url . $endpoint, content => $json->encode($args) );
    die "$endpoint returned HTTP " . $mech->status . ': ' . $mech->content
        unless $mech->success;
    return $json->decode( $mech->content );
}

subtest 'ranked search fixtures' => sub {
    my $search_index = meon::Web::SearchIndex->new(
        hostname => 'search-test.local',
    );
    my $index = $search_index->index_alias;
    my $query = 'qzvexluminostragalacticmineralium';
    my $content_needle = 'frostedcontentmarker';
    my %url = map { $_ => "https://search.test/ranking/$_" }
        qw(title_prefix overlap partial content_strong content_weak weight_low weight_high);
    my @docs = (
        ranking_doc(
            url => $url{title_prefix},
            title => "$query prefix-only",
        ),
        ranking_doc(
            url => $url{overlap},
            title => $query,
            content => "$query $content_needle",
            weight => 0.001,
        ),
        ranking_doc(
            url => $url{partial},
            title => substr( $query, 0, length($query) - 1 ),
        ),
        ranking_doc(
            url => $url{content_strong},
            title => 'unrelated strong relevance document',
            content => ( ("$query ") x 80 ) . $content_needle,
        ),
        ranking_doc(
            url => $url{content_weak},
            title => 'unrelated weak relevance document',
            content => "$query $content_needle",
            weight => 0.001,
        ),
        ranking_doc(
            url => $url{weight_low},
            title => 'unrelated low weight document',
            content => "$query $content_needle",
            weight => 0,
        ),
        ranking_doc(
            url => $url{weight_high},
            title => 'unrelated high weight document',
            content => "$query $content_needle",
            weight => 0.001,
        ),
    );
    my @fixture_ids = map { sha256_base64( $_->{url} ) } @docs;
    my $test_error;
    eval {
        my @bulk;
        for my $i ( 0 .. $#docs ) {
            push @bulk, { index => { _id => $fixture_ids[$i] } }, $docs[$i];
        }
        my $bulk_result = $search_index->ose->bulk(
            index => $index,
            body  => \@bulk,
        )->sync;
        die 'OpenSearch bulk indexing reported errors'
            if $bulk_result->{errors};
        $search_index->ose->indices->refresh( index => $index )->sync;

        my $autocomplete = ranking_request( 'autocomplete', {
            query => $query,
            limit => 100,
        } );
        my $search_first = ranking_request( 'search', {
            query => $query,
            page  => 1,
            size  => 2,
        } );
        is( $autocomplete->{total}, scalar(@docs),
            'autocomplete matches every title and content fixture' );
        is( $search_first->{total}, scalar(@docs),
            'search matches every title and content fixture' );

        my @search_urls;
        my $pages = int( ( $search_first->{total} + 1 ) / 2 );
        for my $page ( 1 .. $pages ) {
            my $response = $page == 1 ? $search_first : ranking_request(
                'search', { query => $query, page => $page, size => 2 }
            );
            is( $response->{page}, $page, "search returns page $page" );
            my $expected_count = $search_first->{total} - ( $page - 1 ) * 2;
            $expected_count = 2 if $expected_count > 2;
            is( scalar( @{ $response->{items} } ), $expected_count,
                "search page $page has the requested page size" );
            push @search_urls, map { $_->{url} } @{ $response->{items} };
        }
        is( scalar(@search_urls), scalar(@docs),
            'search pagination covers all fixtures' );
        is( scalar( keys %{ { map { $_ => 1 } @search_urls } } ),
            scalar(@search_urls), 'search pages contain no duplicate fixtures' );

        my @autocomplete_urls = map { $_->{url} } @{ $autocomplete->{items} };
        is_deeply( [ sort @search_urls ], [ sort @autocomplete_urls ],
            'autocomplete membership equals the union of every search page' );
        ok( grep( { $_ eq $url{title_prefix} } @search_urls ),
            'search includes a title-prefix hit without a content match' );
        ok( grep( { $_ eq $url{partial} } @search_urls ),
            'search includes a partial-title hit without a content match' );

        my %search_position = map { $search_urls[$_] => $_ } 0 .. $#search_urls;
        cmp_ok( $search_position{ $url{overlap} } // -1, '<',
            $search_position{ $url{content_strong} } // -1,
            'all-title overlap outranks content with much higher raw relevance' );
        cmp_ok( $search_position{ $url{content_strong} } // -1, '<',
            $search_position{ $url{content_weak} } // -1,
            'search keeps stronger content relevance ahead despite lower weight' );
        cmp_ok( $search_position{ $url{content_strong} } // -1, '<',
            $search_position{ $url{partial} } // -1,
            'content-only results outrank partial-title-only results in search' );

        my %autocomplete_position = map {
            $autocomplete_urls[$_] => $_
        } 0 .. $#autocomplete_urls;
        cmp_ok( $autocomplete_position{ $url{partial} }, '<',
            $autocomplete_position{ $url{content_strong} },
            'partial-title results outrank content-only results in autocomplete' );
        cmp_ok( $autocomplete_position{ $url{weight_high} }, '<',
            $autocomplete_position{ $url{weight_low} },
            'autocomplete weight orders otherwise equivalent content matches' );

        my $search_content = ranking_request( 'search', {
            query => $content_needle,
            size  => 20,
        } );
        my $autocomplete_content = ranking_request( 'autocomplete', {
            query => $content_needle,
            limit => 100,
        } );
        my @expected_content_urls = sort @url{qw(overlap content_strong content_weak weight_low weight_high)};
        is_deeply(
            [ sort map { $_->{url} } @{ $search_content->{items} } ],
            \@expected_content_urls,
            'search content role matches every content fixture exactly once',
        );
        is_deeply(
            [ sort map { $_->{url} } @{ $autocomplete_content->{items} } ],
            \@expected_content_urls,
            'autocomplete content role has the same content-only match set',
        );
        is( scalar( grep { $_ eq $url{overlap} } @search_urls ), 1,
            'overlapping title and content branches return the document once' );
    };
    $test_error = $@;

    my @cleanup_errors;
    for my $id (@fixture_ids) {
        eval {
            $search_index->ose->delete( index => $index, id => $id )->sync;
            1;
        } or push @cleanup_errors, $@;
    }
    eval {
        $search_index->ose->indices->refresh( index => $index )->sync;
        1;
    } or push @cleanup_errors, $@;

    if ($test_error) {
        diag "ranking fixture test aborted: $test_error";
        fail('ranking fixture setup and requests complete');
    }
    if (@cleanup_errors) {
        diag 'fixture cleanup errors: ' . join( '; ', @cleanup_errors );
        fail('ranking fixture documents are cleaned up');
    }
    pass('ranking fixture documents are deleted and index refreshed');
};

done_testing();
