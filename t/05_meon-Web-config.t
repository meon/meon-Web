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

subtest 'session expiration' => sub {
    my $main = meon::Web::Config->get->{main};
    local $main->{'session-expires'};
    is(meon::Web::Config->session_expires, 14_400,
        'session expiration defaults to four hours');

    for my $case (
        [14_400, 14_400, '14,400 numeric seconds'],
        ['30s', 30, 'seconds suffix'],
        ['5m', 300, 'minutes suffix'],
        ['4h', 14_400, 'hours suffix'],
        ['3d', 259_200, 'days suffix'],
    ) {
        my ($value, $expected, $name) = @$case;
        $main->{'session-expires'} = $value;
        my $seconds = eval { meon::Web::Config->session_expires };
        is($seconds, $expected, "$name is parsed to seconds");
    }

    $main->{'session-expires'} = 'nonsense';
    throws_ok { meon::Web::Config->session_expires }
        qr/Could not parse 'nonsense'/,
        'duration parser exception propagates for malformed input';

    for my $invalid (0, '-1h') {
        $main->{'session-expires'} = $invalid;
        throws_ok { meon::Web::Config->session_expires }
            qr/session-expires must be greater than zero/,
            "non-positive session expiration '$invalid' is rejected";
    }
};

done_testing();
