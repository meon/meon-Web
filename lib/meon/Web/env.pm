package meon::Web::env;

use strict;
use warnings;
use 5.010;

use Carp 'confess';
use XML::LibXML;

my $env = {};
sub get { return $env; }
sub clear { $env = {}; return $env; }

sub content_base {
    my $self = shift;
    $env->{content_base} = shift
        if @_;
    return $env->{content_base} // confess('unset');
}

sub xml_file {
    my $self = shift;
    $env->{xml_file} = shift
        if @_;
    return $env->{xml_file} // confess('unset');
}

sub xml {
    my $self = shift;
    $env->{xml} //= XML::LibXML->load_xml(location => $self->xml_file);
    return $env->{xml};
}

1;
