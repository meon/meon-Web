package meon::Web::Form::PasswordChange;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has '+name' => (default => 'form_password_change');
has '+widget_wrapper' => ( default => 'Bootstrap' );

has 'member' => ( is => 'ro', isa => 'Object', required => 1 );
has 'old_pw_not_required' => ( is => 'ro', isa => 'Bool', default => 0 );

has_field 'old_password' => (
    type => 'Password', required => 0, label => 'Old Password',
    element_class => 'no-hide',
    element_attr => { placeholder => 'please enter your current password' }
);
has_field 'password'     => (
    type => 'Password', required => 0, label => 'New Password',
    element_class => 'no-hide',
    element_attr => { placeholder => 'please enter minimum 8 characters' }
);
has_field 'password_conf'=> (
    type => 'Password', required => 0, label => 'Confirm Password Change',
    element_class => 'no-hide',
    element_attr => { placeholder => 'please retype your new password' }
);

has_field 'submit' => ( type => 'Submit', value => 'Update', element_class => 'btn btn-primary', );

sub validate {
    my $self = shift;

    my $usr     = $self->member;
    my $old_pw  = $self->values->{old_password};
    my $new_pw  = $self->values->{password};
    my $new_pw2 = $self->values->{password_conf};

    return if (length($old_pw.$new_pw.$new_pw2) == 0);

    unless ($self->old_pw_not_required) {
        if (length($old_pw)) {
            $self->field('old_password')->add_error('Incorrect password')
                unless ($usr->check_password($old_pw));
        }
        else {
            $self->field('old_password')->add_error('Required');
        }
    }

    if (length($new_pw)) {
        $self->field('password')->add_error('Password too short. Please enter at least 8 characters.')
            if (length($new_pw) < 8);
    }
    else {
        $self->field('password')->add_error('Required');
    }

    if (length($new_pw2)) {
        $self->field('password_conf')->add_error('Confirmation password does not match')
            unless ($new_pw eq $new_pw2);
    }
    else {
        $self->field('password_conf')->add_error('Required');
    }
}

no HTML::FormHandler::Moose;

1;
