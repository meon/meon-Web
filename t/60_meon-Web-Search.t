#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use FindBin qw($Bin);
use lib "$Bin/lib";

use File::Temp            qw(tempdir);
use Path::Class           qw(file dir);
use Monkey::Patch::Action qw(patch_package);
use List::Util            qw(first);

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

use_ok('meon::Web::Search') or exit;

meon::Web::env->clear;
meon::Web::env->hostname('search-test.local');

subtest 'check env' => sub {
    ok( -d meon::Web::env->hostname_dir,
        'hostname_dir() exists: ' . meon::Web::env->hostname_dir )
        or exit;
    meon::Web::env->xml_file(
        meon::Web::env->hostname_dir->file( 'content', 'index.xml' ) );
    ok( meon::Web::env->apply_includes(), 'apply_includes()' );
};

subtest 'opensearch-records' => sub {
    my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
    $mws->index_ts;    # force index_ts to be built before records
    my @osearch_records = $mws->all_osearch_records;
    cmp_ok( scalar(@osearch_records), '>', 5, 'osearch_records count' );

    my ($first_page) =
        grep { $_->search_type eq 'page' } @osearch_records;
    ok( $first_page, 'found first page - home page' ) or return;
    eq_or_diff(
        $first_page->as_opensearch_record,
        {   search_type    => 'page',
            title          => 'search test home',
            breadcrumb     => undef,
            teaser         => undef,
            url            => '/',
            index_ts       => $mws->index_ts,
            weight         => 1,
            thumbnail      => undef,
            search_content =>
                'there is no place like home category1 category2',
        },
        'first page record'
    );

    my ($first_product) =
        grep { $_->ident eq 'prod-1-1' } @osearch_records;
    ok( $first_product, 'found first product' ) or return;
    eq_or_diff(
        $first_product->as_opensearch_record,
        {   search_type    => 'product',
            title          => 'Product 1-1',
            breadcrumb     => 'Home > Category 1',
            teaser         => 'Very first test product.',
            url            => '/c/cat1/prod-1-1',
            index_ts       => $mws->index_ts,
            weight         => 1,
            thumbnail      => '/static/img/products/prod-1-1-thumb-img.jpg',
            search_content => 'Description of 1st product from 1st category',
        },
        'first product record'
    );
};

done_testing();
