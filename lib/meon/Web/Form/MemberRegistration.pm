package meon::Web::Form::MemberRegistration;

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

sub submitted {
    my ($self) = @_;

    my $c   = $self->c;
    my $xpc = $c->xpc;
    my $xml = $c->model('ResponseXML')->dom;
    $c->log->debug(__PACKAGE__.' '.Data::Dumper::Dumper($c->req->params))
        if $c->debug;

    my $members_folder = $c->default_auth_store->folder;
    my $username = meon::Web::Util->username_cleanup(
        $c->req->param('username'),
        $members_folder,
    );
    $c->req->params->{username} = $username;

    my $member_folder = dir($members_folder, $username);
    mkdir($member_folder) or die 'failed to create member folder: '.$!;

    my $rcpt_to  = $self->get_config_text('rcpt-to');
    my $subject  = $self->get_config_text('subject');
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

    # create user xml file
    my $member = meon::Web::Member->new(
        members_folder => $members_folder,
        username       => $username,
    );
    $member->create(
        name    => $c->req->param('name'),
        email   => $c->req->param('email'),
        address => $c->req->param('address'),
        lat     => $c->req->param('lat'),
        lng     => $c->req->param('lng'),
        registration_form => $email_content,
    );

    my $email = Email::MIME->create(
        header_str => [
            From    => $c->req->param('email'),
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
