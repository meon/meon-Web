package meon::Web::Role::Form;

use Moose::Role;
use Carp 'croak';

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

sub redirect {
    my ($self,$redirect) = @_;

    my $c = $self->c;
    if ($c->user_exists) {
        my $username = $c->user->username;
        $redirect =~ s/{\$USERNAME}/$username/;
    }

    # redirect absolute urls
    if ($redirect =~ m{^https?://}) {
        $c->res->redirect($redirect);
        $c->detach;
    }

    my $redirect_uri = $c->req->uri->clone;
    my @segments = $redirect_uri->path_segments;
    pop(@segments);
    $redirect_uri->path_segments(
        @segments,
        URI->new($redirect)->path_segments
    );
    $c->res->redirect($redirect_uri);
    $c->detach;
}

1;
