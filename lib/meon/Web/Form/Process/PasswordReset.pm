package meon::Web::Form::Process::PasswordReset;

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

use meon::Web::Form::PasswordReset;

sub get_form {
    my ($self, $c) = @_;

    my $form = meon::Web::Form::PasswordReset->new();
    $form->process(params=>$c->req->params);
    return $form;
}

sub submitted {
    my ($self, $c, $form_config, $form) = @_;

    $c->log->debug(__PACKAGE__.' '.Data::Dumper::Dumper($c->req->params))
        if $c->debug;

    my $members_folder = $c->default_auth_store->folder;

    my $xml = $c->model('ResponseXML')->dom;
    my $xpc = $c->xpc;
    my ($redirect) = map { $_->textContent } $xpc->findnodes('w:redirect',$form_config);
    die 'no redirect provided' unless $redirect;
    my ($from) = map { $_->textContent } $xpc->findnodes('w:from',$form_config);
    die 'no from provided' unless $from;
    my ($pw_change) = map { $_->textContent } $xpc->findnodes('w:pw-change',$form_config);
    die 'no pw-change provided' unless $pw_change;

    return if $form->has_errors;

    my $email = $form->field('email')->value;
    my $member = meon::Web::Member->find_by_email(
        members_folder => $members_folder,
        email          => $email,
    );

    unless ($member) {
        $form->field('email')->add_error('no such email found');
        return;
    }

    $member->send_password_reset(
        $from,
        $c->uri_for($pw_change),
    );
    $c->res->redirect($redirect);
}

1;
