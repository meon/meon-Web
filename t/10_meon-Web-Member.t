#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More 'no_plan';
#use Test::More tests => 10;
use Test::Differences;
use Test::Exception;

use FindBin qw($Bin);
use lib "$Bin/lib";

use File::Temp 'tempdir';
use Path::Class 'dir','file';

BEGIN {
    use_ok ( 'meon::Web::Member' ) or exit;
}

exit main();

sub main {
    register_user();
    return 0;
}

sub register_user {
    my $tmp_dir = tempdir( CLEANUP => 1 );
    dir($tmp_dir, 'usr01')->mkpath;

    my $member = meon::Web::Member->new(
        members_folder => $tmp_dir,
        username       => 'usr01',
    );
    $member->create(
        name    => 'somename',
        email   => 'name <email@email.email>',
        address => "street 12\nwien",
        lat     => '48.123',
        lng     => '16.321',
        registration_form => '<email && content>',
    );


    my $usr01_slurp = file($tmp_dir, 'usr01','index.xml')->slurp.'';
    $usr01_slurp =~ m{<created>(.+?)</created>};
    my $created = $1;
    eq_or_diff(
        $usr01_slurp,
        usr01_content($created),
        'check user xml file content',
    );
}

sub usr01_content {
    my ($created) = @_;
    return qq{<?xml version="1.0" encoding="UTF-8"?>
<page xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">

<meta>
    <title>somename</title>
    <user xmlns="http://search.cpan.org/perldoc?Catalyst%3A%3APlugin%3A%3AAuthentication%3A%3AStore%3A%3AUserXML">
        <status>registration-pending</status>
        <username>usr01</username>
        <password>***DISABLED***</password>
    </user>
    <full-name>somename</full-name>
    <email>name &lt;email\@email.email&gt;</email>
    <created>$created</created>
    <address>street 12
wien</address>
    <lat>48.123</lat>
    <lng>16.321</lng>
    <registration-form>&lt;email &amp;&amp; content&gt;</registration-form>
</meta>

<content><div xmlns="http://www.w3.org/1999/xhtml">
</div></content>

</page>
};
}
