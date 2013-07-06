package meon::Web::env;

use strict;
use warnings;
use 5.010;

use Carp 'confess';
use XML::LibXML;
use XML::LibXML::XPathContext;
use Scalar::Util 'weaken';

my $env = {};
sub get { return $env; }
sub clear { $env = {}; return $env; }

sub xpc {
    my $self = shift;
    my $xpc = XML::LibXML::XPathContext->new($self->xml);
    $xpc->registerNs('x', 'http://www.w3.org/1999/xhtml');
    $xpc->registerNs('w', 'http://web.meon.eu/');
    return $xpc;
}

sub current_dir {
    my $self = shift;
    return $self->xml_file->dir;
}

sub current_path {
    my $self = shift;
    $env->{current_path} = shift
        if @_;
    return $env->{current_path} // confess('unset');
}

sub content_dir {
    my $self = shift;
    $env->{content_dir} = shift
        if @_;
    return $env->{content_dir} // confess('unset');
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

sub stash {
    my $self = shift;
    if (@_) {
        $env->{stash} = shift @_;
        weaken($env->{stash});
    }

    return $env->{stash} // confess('unset');
}

sub user {
    my $self = shift;
    if (@_) {
        $env->{user} = shift @_;
        weaken($env->{user});
    }
    return $env->{user};
}

1;
