package meon::Web::Form::SendEmail;

use List::MoreUtils 'uniq';
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Data::Dumper;
use meon::Web::Util;
use meon::Web::Member;
use Path::Class 'dir';

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';

has_field 'submit'   => ( type => 'Submit', value => 'Submit', );

before 'validate' => sub {
    my ($self) = @_;

    $self->add_form_error('Are you real?')
        if $self->c->req->param('yreo');
};

sub submitted {
    my ($self) = @_;

    my $c   = $self->c;
    my $xpc = meon::Web::Util->xpc;
    $c->log->debug(__PACKAGE__.' '.Data::Dumper::Dumper($c->req->params))
        if $c->debug;

    my $xml = $c->model('ResponseXML')->dom;
    my $rcpt_to  = $self->get_config_text('rcpt-to');
    my $subject  = $self->get_config_text('subject');
    $subject    .= ' - '.$c->req->param('email')
        if $c->req->param('name');
    my $detach   = $self->get_config_text('detach');
    my $email_content = '';

    my (@input_names) =
        uniq
        grep { defined $_ }
        map { $_->getAttribute('name') }
        $xpc->findnodes('//x:form//x:input | //x:form//x:textarea',$xml);

    my @args;
    foreach my $input_name (@input_names) {
        my $input_value = $c->req->param($input_name) // '';
        next unless length $input_value;
        push(@args, [ $input_name => $input_value ]);
        $email_content .= $input_name.': '.$input_value."\n";    # FIXME use Data::Header::Fields
    }

    my $email = Email::MIME->create(
        header_str => [
            From    => 'no-reply@meon.eu',
            To      => $rcpt_to,
            Subject => $subject,
        ],
        parts => [
            Email::MIME->create(
                attributes => {
                content_type => "text/plain",
                charset      => "UTF-8",
                encoding     => "8bit",
            },
                body_str => $email_content,
            ),
        ],
    );

    sendmail($email->as_string);
    $self->detach($detach);
}

no HTML::FormHandler::Moose;

1;
