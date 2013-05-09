package meon::Web::Role::Form;

use Moose::Role;
use Carp 'croak';
use meon::Web::Util 'path_fixup';

has 'c'      => ( is => 'ro', isa => 'Object', required => 1 );
has 'config' => ( is => 'ro', isa => 'Object', lazy_build => 1 );

sub _build_config {
    my ($self) = @_;

    my $c = $self->c;
    my $dom = $c->model('ResponseXML')->dom;
    my $xpc = $c->xpc;
    my ($form_config) = $xpc->findnodes('/w:page/w:meta/w:form',$dom);
    return $form_config;
}

around 'submitted' => sub {
    my ($orig,$self) = @_;
    return unless $self->is_valid;
    $self->$orig(@_);
};

sub get_config_text {
    my ($self, $el_name) = @_;
    croak 'need element name argument'
        unless defined $el_name && length($el_name);

    my $xpc = $self->c->xpc;
    my $form_config = $self->config;
    my ($text) = map { $_->textContent } $xpc->findnodes('w:'.$el_name,$form_config);
    die 'config element '.$el_name.' not found'
        unless defined $text;

    return $text;
}

sub get_config_folder {
    my ($self, $el_name) = @_;
    my $c = $self->c;
    my $path = $self->get_config_text($el_name);
    $path = meon::Web::Util->path_fixup($c,$path);
    $path = $c->stash->{xml_file}->dir->subdir($path);
    $path->resolve;
    return $path;
}

sub _traverse_uri {
    my ($self,$path) = @_;

    my $c = $self->c;
    $path = meon::Web::Util->path_fixup($c,$path);

    # redirect absolute urls
    if ($path =~ m{^https?://}) {
        return URI->new($path);
    }

    my $new_uri = $c->req->uri->clone;
    my @segments = $new_uri->path_segments;
    pop(@segments);
    $new_uri->path_segments(
        @segments,
        URI->new($path)->path_segments
    );
    return $new_uri;
}

sub detach {
    my ($self,$detach_path) = @_;

    my $c = $self->c;
    my $detach_uri = (
        $detach_path
        ? $self->_traverse_uri($detach_path)
        : $c->req->uri->absolute
    );

    $c->session->{post_redirect_path} = $detach_uri;
    $c->res->redirect($c->req->uri->absolute);
}

sub redirect {
    my ($self,$redirect) = @_;

    my $c = $self->c;
    my $redirect_uri = $self->_traverse_uri($redirect);
    $c->res->redirect($redirect_uri->absolute);
    $c->detach;
}

1;
