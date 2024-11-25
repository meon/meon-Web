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

use_ok ( 'meon::Web::env' ) or exit;

subtest 'includes' => sub {
    ok(meon::Web::env->clear, 'clear()');
    meon::Web::env->hostname('includes');
    ok(-d meon::Web::env->hostname_dir, 'hostname_dir() exists: '.meon::Web::env->hostname_dir) or exit;

    meon::Web::env->xml_file(meon::Web::env->hostname_dir->file('content', 'index.xml'));
    isa_ok(meon::Web::env->xml, 'XML::LibXML::Document', 'xml()');
    ok(meon::Web::env->apply_includes(), 'apply_includes()');

    eq_or_diff(meon::Web::env->xml->toString, includes_xml(), 'includes xml');
};

done_testing();

sub includes_xml {
    return << '__INCLUDES_XML__';
<?xml version="1.0" encoding="UTF-8"?>
<page xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">

<meta>
    <title>includes</title>
</meta>

<content><div xmlns="http://www.w3.org/1999/xhtml">

<h1>Welcome to includes!</h1>

<p>This meon::Web includes test page.</p>

</div></content>

<extras xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:w="http://web.meon.eu/">
<w:extrawurst/>
</extras>

<cars xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:w="http://web.meon.eu/">
<w:auto/>
</cars>
</page>
__INCLUDES_XML__
}
