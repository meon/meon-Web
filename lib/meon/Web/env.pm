package meon::Web::env;

use strict;
use warnings;
use 5.010;

my $env = {};
sub get { return $env; }
sub clear { $env = {}; return $env; }

sub content_base {
    my $self = shift;
    $env->{content_base} = shift
        if @_;
    return $env->{content_base} // confess('unset');
}

1;
