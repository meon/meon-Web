package meon::Web::Form::TimelineUpdate;

use meon::Web::Util;
use meon::Web::TimelineEntry;
use meon::Web::XML2Comment;
use Path::Class 'dir';

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
    my $category = 'news';
    my $comment_to_uri = $c->stash->{comment_to};
    my $comment_to;
    if ($comment_to_uri) {
        $category = 'comment';
        $comment_to = meon::Web::XML2Comment->new(
            path => $comment_to_uri.'.xml',
            c    => $c,
        );
    }

    my $timeline_path = $self->get_config_text('timeline');
    my $timeline_full_path = dir(meon::Web::Util->full_path_fixup($c, $timeline_path));
    my $entry = meon::Web::TimelineEntry->new(
        timeline_dir => $timeline_full_path,
        title        => $title,
        author       => $c->user->username,
        category     => $category,
        (defined($intro) ? (intro => $intro) : ()),
        (defined($body)  ? (body  => $body)  : ()),
        (defined($comment_to) ? (comment_to => $comment_to)  : ()),
    );
    $entry->create;

    $self->redirect($comment_to_uri // $timeline_path);
}

no HTML::FormHandler::Moose;

1;
