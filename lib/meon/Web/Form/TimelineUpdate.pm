package meon::Web::Form::TimelineUpdate;

use meon::Web::Util;
use meon::Web::TimelineEntry;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';

has '+name' => (default => 'form-timeline-update');
has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_form_element_class { ['form-horizontal'] };

has_field 'title'     => (
    type => 'Text', required => 1, label => 'Title',
    element_attr => { placeholder => 'title or a short message' }
);

has_field 'intro'     => (
    type => 'TextArea', required => 0, label => 'Introduction',
    element_attr => { placeholder => '(optional) short text or introduction' }
);

has_field 'body'     => (
    type => 'TextArea', required => 0, label => 'Body text',
    element_attr => { placeholder => '(optional) long text' }
);

has_field 'submit' => ( type => 'Submit', value => 'Post', element_class => 'btn btn-primary', );

sub submitted {
    my $self = shift;

    my $c = $self->c;
    my $title = $self->field('title')->value;
    my $intro = $self->field('intro')->value;
    my $body  = $self->field('body')->value;

    my $timeline_path = $self->get_config_text('timeline');
    my $timeline_full_path = $c->stash->{xml_file}->dir->subdir(meon::Web::Util->path_fixup($c, $timeline_path));
    my $entry = meon::Web::TimelineEntry->new(
        timeline_dir => $timeline_full_path,
        title        => $title,
        author       => $c->user->username,
        (defined($intro) ? (intro => $intro) : ()),
        (defined($body)  ? (body  => $body)  : ()),
    );
    $entry->create;

    $self->redirect($timeline_path);
}

no HTML::FormHandler::Moose;

1;
