package meon::Web::Form::PasswordReset;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has '+name' => (default => 'form_password_reset');
has '+widget_wrapper' => ( default => 'Bootstrap' );

has_field 'email' => ( type => 'Email', required => 1, label => 'Email' );
has_field 'submit'   => ( type => 'Submit', value => 'Submit', );

no HTML::FormHandler::Moose;

1;
