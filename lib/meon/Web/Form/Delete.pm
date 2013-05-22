package meon::Web::Form::Delete;

use Digest::SHA qw(sha1_hex);

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';

has '+name' => (default => 'form-delete');
#has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_form_element_class { ['form-horizontal'] };

has_field 'yes_delete' => ( type => 'Checkbox', required => 1, label => 'Yes delete' );
has_field 'submit'   => ( type => 'Submit', value => 'Delete', );

sub submitted {
    my $self = shift;

    my $redirect = $self->get_config_text('redirect');
    $self->c->stash->{'xml_file'}->remove();
    $self->redirect($redirect);
}

no HTML::FormHandler::Moose;

1;
