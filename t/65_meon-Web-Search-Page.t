#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;
use Data::asXML;
use LWP::UserAgent;

use FindBin     qw($Bin);
use Path::Class qw(file dir);
use lib file( $Bin, 'testlib' )->stringify;

use Monkey::Patch::Action qw(patch_package);

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

use_ok('meon::Web::env')                       or exit;
use_ok('meon::Web::Util')                      or exit;
use_ok('meon::Web::Search')                    or exit;
use_ok('meon::Web::SearchAPI::Client')         or exit;
use_ok('meon::Web::SearchAPI::SearchResponse') or exit;
use_ok('Test::meon::Web::SearchAPI')           or exit;

subtest 'search.xml page meta form wiring' => sub {
    meon::Web::env->clear;
    meon::Web::env->hostname('search-test.local');
    meon::Web::env->xml_file(
        meon::Web::env->hostname_dir->file( 'content', 'search.xml' ) );

    my $xpc = meon::Web::Util->xpc;
    my $dom = meon::Web::env->xml;

    my ($process) = map { $_->textContent }
        $xpc->findnodes( '/w:page/w:meta/w:form/w:process', $dom );
    is( $process, 'Search', 'search page uses Search form process' );

    ok( $xpc->findnodes(
            '/w:page/w:content/xhtml:div/xhtml:div/w:form[@copy-id="form-search"]',
            $dom
        )->size,
        'search form placeholder present in content'
    );

    ok( $xpc->findnodes( '/w:page/w:content/xhtml:div/w:search-results',
            $dom )->size,
        'search results placeholder present in content'
    );
};

subtest 'default.xsl renders Data::asXML search results' => sub {
    meon::Web::env->clear;
    meon::Web::env->hostname('search-test.local');
    meon::Web::env->xml_file(
        meon::Web::env->hostname_dir->file( 'content', 'search.xml' ) );

    my $dom = meon::Web::env->xml;
    my $search_results_el =
        $dom->createElementNS( 'http://web.meon.eu/', 'search-results' );
    my $dxml = Data::asXML->new(
        namespace => 1,
        pretty    => 0,
    );
    $search_results_el->appendChild(
        $dxml->encode(
            {   query => 'bike',
                total => 1,
                items => [
                    {   title => 'Bike 1',
                        url   => '/bike-1',
                    },
                ],
            }
        )
    );
    $dom->documentElement->appendChild($search_results_el);

    my $rendered_dom = meon::Web::env->transform_xml;
    my $rendered     = $rendered_dom->toString;

    like(
        $rendered,
        qr/Search Results/,
        'render contains search result heading'
    );
    like( $rendered, qr/Query:\s*<b>bike<\/b>/,
        'render contains query value' );
    like( $rendered, qr/Bike 1/, 'render contains first item title' );
    like( $rendered, qr/href="\/bike-1"/, 'render contains first item link' );
};

subtest 'live search with TEST_WITH_OPENSEARCH' => sub {
    unless ( $ENV{TEST_WITH_OPENSEARCH} ) {
        ok( 1,
            'skipping live search test, enable with TEST_WITH_OPENSEARCH=1' );
        return;
    }

    my $mws = meon::Web::Search->new( hostname => 'search-test.local' );
    my $search_index = $mws->search_index;
    my $count_result =
        $search_index->ose->count( index => $search_index->index_alias, )
        ->sync;

    unless ( $count_result->{count} >= 1 ) {
        ok( 1, 'skipping live search test, index is empty' );
        diag(
            'please run TEST_WITH_OPENSEARCH=1 prove -l t/61_meon-Web-Index.t first'
        );
        return;
    }

    my $static_dir =
        dir( meon::Web::SPc->datadir, 'meon-web', 'search-api', 'oapi' );
    $static_dir->mkpath;
    $ENV{STATIC_DIR}           = $static_dir;
    $ENV{USING_FRONTEND_PROXY} = 1;

    my $service  = Test::meon::Web::SearchAPI->start;
    my $base_url = $service->url;
    $base_url =~ s{/mws_1/?$}{};

    my $ua = LWP::UserAgent->new( timeout => 30 );
    $ua->default_header( 'HTTP_X_FORWARDED_HOST' => 'search-test.local' );

    my $client = meon::Web::SearchAPI::Client->new(
        base_url   => $base_url,
        user_agent => $ua,
    );

    my $res = $client->search( { query => 'product' } );
    isa_ok( $res, 'meon::Web::SearchAPI::SearchResponse' );
    cmp_ok( ( $res->total // 0 ),
        '>=', 1, 'live search returns at least one result' );
};

done_testing();
