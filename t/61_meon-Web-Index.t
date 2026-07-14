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
use_ok('meon::Web::SearchIndex') or exit;

meon::Web::env->clear;
meon::Web::env->hostname('search-test.local');

unless ($ENV{TEST_WITH_OPENSEARCH}) {
    ok(1, "skipping opensearch tests, enable with TEST_WITH_OPENSEARCH=1");
    done_testing();
    exit;
}

my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
my $search_index = $mws->search_index;

subtest 'clean-up first' => sub {
    $search_index->_delete_index($search_index->index_a);
    $search_index->_delete_index($search_index->index_b);

    # Recreate the schema at test start and verify it is applied.
    $search_index->init_index;
    my $mapping = $search_index->ose->indices->get_mapping(
        index => $search_index->work_index,
    )->sync;
    is(
        $mapping->{ $search_index->work_index }->{mappings}->{properties}
            ->{weight}->{type},
        'float',
        'schema mapping is recreated at test start',
    );

    $search_index->_delete_index($search_index->work_index);
    $search_index->_clear__indices_info;
    $search_index->_clear_active_index;
    $search_index->_clear_work_index;

    eq_or_diff(
        $search_index->_indices_info,
        {   index_a => undef,
            index_b => undef,
            alias   => undef,
        },
        'initial indices info',
    );

    is($search_index->active_index, 'meon-search_search_t_idx_b', 'active index');
    is($search_index->work_index, 'meon-search_search_t_idx_a', 'work index');
};

subtest 'dry run indexing' => sub {
    $mws->do_indexing( dry_run => 1 );
    $search_index->ose->indices->refresh( index => $search_index->work_index )->sync;

    ok($search_index->_indices_info->{index_a}, 'work index exists after dry run');
    is($search_index->_indices_info->{index_b}, undef, 'active index untouched after dry run');
    is($search_index->_indices_info->{alias}, undef, 'alias not switched during dry run');

    my $search_result = $search_index->ose->count(
        index => $search_index->work_index,
    )->sync;
    cmp_ok( $search_result->{count}, '>', 5, 'documents indexed into work index' );
};

subtest 'init and switch' => sub {
    $search_index->init_index;

    ok($search_index->_indices_info->{index_a}, 'index a exists after init');
    is($search_index->_indices_info->{index_b}, undef, 'index b does not exist after init');
    is($search_index->_indices_info->{alias}, undef, 'no alias after first init');

    is($search_index->active_index, 'meon-search_search_t_idx_b', 'active index after init');
    is($search_index->work_index, 'meon-search_search_t_idx_a', 'work index after init');

    $search_index->switch_active_index;
    is($search_index->_indices_info->{alias}, 'index_a', 'index a with alias after switch');
    is($search_index->active_index, 'meon-search_search_t_idx_a', 'active index after second init');
    is($search_index->work_index, 'meon-search_search_t_idx_b', 'work index after second init');
    is($search_index->_indices_info->{index_b}, undef, 'index b gone after switch');

    $search_index->init_index;
    ok($search_index->_indices_info->{index_a}, 'index a exists after second init');
    ok($search_index->_indices_info->{index_b}, 'index b exists after second init');
    is($search_index->_indices_info->{alias}, 'index_a', 'alias still to same index');
    $search_index->switch_active_index;
    is($search_index->_indices_info->{index_a}, undef, 'index_a gone after second switch');
    ok($search_index->_indices_info->{index_b}, 'index b exists after second switch');
    is($search_index->_indices_info->{alias}, 'index_b', 'alias to index_b after second switch');
};

subtest 'indexing' => sub {
    $mws->do_indexing;
    my $search_result = $search_index->ose->count(
        index => $search_index->index_alias,
    )->sync;
    cmp_ok( $search_result->{count}, '>', 5, 'indexed records present' );
};

done_testing();
