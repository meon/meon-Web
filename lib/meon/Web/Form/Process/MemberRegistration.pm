package meon::Web::Form::Process::MemberRegistration;

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

sub get_form {
    my ($self, $c) = @_;
    return;
}

sub submitted {
    my ($self, $c, $form_config) = @_;

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


    my $xml = $c->model('ResponseXML')->dom;
    my $xpc = $c->xpc;
    my ($rcpt_to) = map { $_->textContent } $xpc->findnodes('w:rcpt-to',$form_config);
    die 'no email provided' unless $rcpt_to;
    my ($subject) = map { $_->textContent } $xpc->findnodes('w:subject',$form_config);
    die 'no subject provided' unless $subject;
    my ($redirect) = map { $_->textContent } $xpc->findnodes('w:redirect',$form_config);
    die 'no redirect provided' unless $redirect;
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

    $c->log->debug(__PACKAGE__.' '.Data::Dumper::Dumper($c->req->params))
        if $c->debug;

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

    unless ($redirect =~ m{^https?://}) {
        $redirect =~ s{^/}{};
        $redirect = $c->req->base.$redirect;
    }

    $c->res->redirect($redirect);
}

1;
