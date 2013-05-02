package meon::Web::Form::Process::PasswordChange;

use strict;
use warnings;
use 5.010;

use List::MoreUtils 'uniq';
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Data::Dumper;
use meon::Web::Util;
use meon::Web::Member;
use Path::Class 'dir';

use meon::Web::Form::PasswordChange;

sub get_form {
    my ($self, $c) = @_;

    my $old_pw_not_required = $c->session->{old_pw_not_required};
    my $form = meon::Web::Form::PasswordChange->new(
        member              => $c->user,
        old_pw_not_required => $old_pw_not_required,
    );
    $form->field('old_password')->inactive(1)
        if $old_pw_not_required;
    $form->process(params=>$c->req->params);
    return $form;
}

sub submitted {
    my ($self, $c, $form_config, $form) = @_;

    my $xml = $c->model('ResponseXML')->dom;
    my $xpc = $c->xpc;
    my ($redirect) = map { $_->textContent } $xpc->findnodes('w:redirect',$form_config);
    die 'no redirect provided' unless $redirect;
    my ($from) = map { $_->textContent } $xpc->findnodes('w:from',$form_config);
    die 'no from provided' unless $redirect;

    return if $form->has_errors;

    delete $c->session->{old_pw_not_required};
    my $password = $form->field('password')->value;
    $form->member->set_password($password);

    $c->res->redirect($redirect);
}

1;
