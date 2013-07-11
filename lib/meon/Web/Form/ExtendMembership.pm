package meon::Web::Form::ExtendMembership;

use meon::Web::Util;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';

has '+name' => (default => 'form-member-update');
has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_form_element_class { ['form-horizontal'] };

sub submitted {
    my $self = shift;

    my $c = $self->c;
    my $profiles_dir = meon::Web::env->profiles_dir;
    my $username     = $c->req->body_params->{username};
    my $member = meon::Web::Member->new(
        members_folder => $profiles_dir,
        username       => $username,
    );

    $c->detach('/status_not_found', ['failed to load user'])
        unless eval { $member->xml };

    $member->extend_expiration_by_1y;
    $self->redirect('');
}

no HTML::FormHandler::Moose;

1;
