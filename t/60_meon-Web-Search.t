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

subtest 'opensearch-records' => sub {
    my $mws = meon::Web::Search->new( hostname => 'search-test.local', );
    $mws->index_ts;    # force index_ts to be built before records
    my @osearch_records = $mws->all_osearch_records;
    cmp_ok( scalar(@osearch_records), '>', 5, 'osearch_records count' ) or return;

    my @osearch_records_json =
        map { $_->as_opensearch_record }
        sort { $a->url cmp $b->url } @osearch_records;

    my $tmp_dir = tempdir( CLEANUP => 1 );
    file( $tmp_dir, 'osearch_records.json' )
        ->spew( $json->encode( \@osearch_records_json ) );

    is_dir($tmp_dir, $t_data_dir->subdir('meon-Web-Search'), 'generated data match');
};

done_testing();
