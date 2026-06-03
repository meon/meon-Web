#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use JSON::XS;
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
    $mech->post( $service_url . 'autocomplete',
        content => $json->encode( { todo_autocomplete => 1 } ), );
    ok( $mech->success, 'post to autocomplete' );
    my $dt_data;
    lives_ok( sub { $dt_data = $json->decode( $mech->content ) },
        'json content' );
    eq_or_diff_data(
        $dt_data,
        { todo_autocomplete => 1 },
        'autocomplete response content'
    );
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

done_testing();
