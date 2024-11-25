#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use FindBin qw($Bin);
use lib "$Bin/tlib";

use Path::Class qw(file dir);
use Monkey::Patch::Action qw(patch_package);

use_ok ( 'meon::Web::SPc' ) or exit;

my $patch_prefix = patch_package('meon::Web::SPc', 'prefix', 'replace',
    sub {dir(Sys::Path->find_distribution_root('meon::Web::SPc'), 't', 'tsp')});

use_ok ( 'meon::Web::Config' ) or exit;


subtest 'basic' => sub {
    ok(meon::Web::Config->get, 'get()');
    is(meon::Web::Config->hostname_to_folder('includes'), 'includes_t', 'hostname_to_folder()');
};

done_testing();
