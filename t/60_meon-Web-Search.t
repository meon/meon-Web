#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;
use Test::Dirs;

use FindBin qw($Bin);
use lib "$Bin/lib";

use File::Temp            qw(tempdir);
use Path::Class           qw(file dir);
use Monkey::Patch::Action qw(patch_package);
use List::Util            qw(first);
use JSON::XS;
use Test::MockTime       qw(set_fixed_time);

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
use_ok('meon::Web::SearchIndex') or exit;

set_fixed_time('2026-05-01T13:38:00');

meon::Web::env->clear;
meon::Web::env->hostname('search-test.local');

my $t_data_dir = dir($Bin, 'tdata');
my $json = JSON::XS->new->utf8(1)->pretty(1)->canonical(1);

subtest 'check env' => sub {
    ok( -d meon::Web::env->hostname_dir,
        'hostname_dir() exists: ' . meon::Web::env->hostname_dir )
        or exit;
    meon::Web::env->xml_file(
        meon::Web::env->hostname_dir->file( 'content', 'index.xml' ) );
    ok( meon::Web::env->apply_includes(), 'apply_includes()' );
};

subtest 'derived teaser truncation' => sub {
    my $mws = meon::Web::Search->new(
        hostname       => 'search-test.local',
        teaser_max_len => 12,
    );
    my $long_content = 'alpha beta gamma delta';

    is(
        $mws->_teaser_from_content( undef, $long_content ),
        'alpha beta…',
        'derived teaser is truncated at word boundary with ellipsis'
    );
};

subtest 'opensearch-records' => sub {
    my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
    $mws->index_ts;    # force index_ts to be built before records
    my @osearch_records = $mws->all_osearch_records;
    cmp_ok( scalar(@osearch_records), '>', 5, 'osearch_records count' ) or return;

    my $home_page = first { $_->url eq '/' && $_->search_type eq 'page' }
        @osearch_records;
    is(
        $home_page->teaser,
        'there is no place like home category1 category2',
        'page teaser is generated from content text'
    );

    my $product = first { $_->url eq '/c/cat1/prod-1-1' } @osearch_records;
    is( $product->teaser, 'Very first test product.',
        'existing category-product teaser is preserved' );
    is(
        $product->as_opensearch_record->{search_content},
        'home category 1 product 1-1 very first test description of 1st product from category',
        'category-product search_content includes explicit teaser text only'
    );

    my @osearch_records_json =
        map { $_->as_opensearch_record }
        sort { $a->url cmp $b->url } @osearch_records;

    my $tmp_dir = tempdir( CLEANUP => 1 );
    file( $tmp_dir, 'osearch_records.json' )
        ->spew( $json->encode( \@osearch_records_json ) );

    is_dir(
        $tmp_dir,
        $t_data_dir->subdir('meon-Web-Search'),
        'generated data match',
        [], 'verbose'
    );
};

subtest 'dry-run indexing' => sub {
    my %calls = (
        init   => 0,
        index  => 0,
        switch => 0,
    );

    my $patch_init = patch_package(
        'meon::Web::SearchIndex',
        'init_index',
        'replace',
        sub {
            $calls{init}++;
            return;
        }
    );
    my $patch_index_docs = patch_package(
        'meon::Web::SearchIndex',
        'index_docs',
        'replace',
        sub {
            my ( $self, $docs ) = @_;
            $calls{index}++;
            ok( ref($docs) eq 'ARRAY', 'index_docs gets a batch array' );
            return;
        }
    );
    my $patch_switch = patch_package(
        'meon::Web::SearchIndex',
        'switch_active_index',
        'replace',
        sub {
            $calls{switch}++;
            return;
        }
    );

    my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
    $mws->do_indexing( dry_run => 1 );

    is( $calls{init},   1, 'init_index called once' );
    cmp_ok( $calls{index}, '>', 0, 'index_docs called' );
    is( $calls{switch}, 0, 'switch_active_index skipped in dry run' );
};

subtest 'update schema' => sub {
    my %calls = (
        update_schema => 0,
    );

    my $patch_update_schema = patch_package(
        'meon::Web::SearchIndex',
        'update_schema',
        'replace',
        sub {
            $calls{update_schema}++;
            return;
        }
    );

    my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
    $mws->update_schema;

    is( $calls{update_schema}, 1, 'search_index->update_schema called once' );
};

done_testing();
