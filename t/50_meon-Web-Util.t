#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Most;

use FindBin qw($Bin);
use lib "$Bin/lib";

use File::Temp qw(tempdir);
use Path::Class qw(file dir);

use_ok ( 'meon::Web::Util' ) or exit;

subtest 'username_cleanup' => sub {
    my $tmp_dir = tempdir( CLEANUP => 1 );
    dir($tmp_dir, 'username')->mkpath;
    dir($tmp_dir, 'username02')->mkpath;
    dir($tmp_dir, 'a000')->mkpath;

    is(
        meon::Web::Util->username_cleanup('username', $tmp_dir),
        'username03',
        'finding username'
    );

    is(
        meon::Web::Util->username_cleanup('Štefan Bučič', $tmp_dir),
        'StefanBucic',
        'finding username'
    );

    is(
        meon::Web::Util->username_cleanup('a', $tmp_dir),
        'axxx',
        'finding username'
    );
};

subtest 'explode_to_4ths' => sub {
    eq_or_diff(meon::Web::Util->explode_to_4ths('a'),    [],                'too short');
    eq_or_diff(meon::Web::Util->explode_to_4ths('ab'),   [qw(ab)],          'len 2');
    eq_or_diff(meon::Web::Util->explode_to_4ths('abc'),  [qw(ab abc)],      'len 3');
    eq_or_diff(meon::Web::Util->explode_to_4ths('abcd'), [qw(ab abc abcd)], 'len 4');
    eq_or_diff(
        meon::Web::Util->explode_to_4ths('abcdefghi'),
        [qw(ab abc abcd bcde cdef defg efgh fghi)],
        'long word'
    );
};

subtest 'explode_for_autocomplete' => sub {
    eq_or_diff(
        meon::Web::Util->explode_for_autocomplete('Quick brown Fox, where are you fox?'),
        [   qw(qu qui quic uick br bro brow rown fo fox wh whe wher here ar are yo you),
            qw(ickb ckbr kbro ownf wnfo nfox foxw oxwh xwhe erea rear eare arey reyo eyou youf oufo ufox),
        ],
        'sentence'
    );
};

done_testing();
