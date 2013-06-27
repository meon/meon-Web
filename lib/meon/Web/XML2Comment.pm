package meon::Web::XML2Comment;

use Moose;
use MooseX::Types::Path::Class;
use 5.010;

use meon::Web::Util;
use Path::Class 'dir';
use Carp 'croak';

has 'c'    => ( is => 'ro', isa => 'Object', required => 1 );
has 'path' => (is=>'rw',isa=>'Path::Class::File',required=>1,coerce=>1);
has '_full_path' => (is=>'ro',isa=>'Path::Class::File',lazy=>1,builder=>'_build_full_path');
has 'xml'  => (is=>'ro', isa=>'XML::LibXML::Document', lazy => 1, builder => '_build_xml');

sub _build_xml {
    my ($self) = @_;

    return XML::LibXML->load_xml(
        location => $self->_full_path,
    );
}

sub _build_full_path {
    my ($self) = @_;
    return meon::Web::Util->full_path_fixup($self->c, $self->path);
}

sub web_uri {
    my ($self) = @_;

    my $c = $self->c;
    my $base_dir = dir($c->stash->{hostname_folder}, 'content');
    my $path = $self->_full_path;
    $path = '/'.$path->relative($base_dir);
    $path =~ s/\.xml$//;
    return $path;
}

sub add_comment {
    my ($self, $comment_path) = @_;
    croak 'missing comment_path argument'
        unless $comment_path;

    my $xml = $self->xml;
    my $xpc = meon::Web::Util->xpc;
    my ($comments_el) = $xpc->findnodes('/w:page/w:content//w:timeline[@class="comments"]',$xml);
    croak 'comments not allowed'
        unless $comments_el;

    my $entry_node = $comments_el->addNewChild( undef, 'w:entry' );
    $entry_node->setAttribute('href' => $comment_path);
    $comments_el->appendText("\n");

    IO::Any->spew($self->_full_path, $xml->toString, { atomic => 1 });
}

__PACKAGE__->meta->make_immutable;

1;
