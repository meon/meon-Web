package meon::Web::Form::Process::SendEmail;

use strict;
use warnings;
use 5.010;

use List::MoreUtils 'uniq';
use Email::MIME;
use Email::Sender::Simple qw(sendmail);

sub submitted {
    my ($self, $c, $form) = @_;

    my $xml = $c->stash->{'xml'};
    my $xpc = $c->xpc;
    my ($rcpt_to) = map { $_->textContent } $xpc->findnodes('w:rcpt-to',$form);
    die 'no email provided' unless $rcpt_to;
    my ($subject) = map { $_->textContent } $xpc->findnodes('w:subject',$form);
    die 'no subject provided' unless $subject;
    my ($redirect) = map { $_->textContent } $xpc->findnodes('w:redirect',$form);
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
        return unless length $input_value;
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

    unless ($redirect =~ m{^https?://}) {
        $redirect =~ s{^/}{};
        $redirect = $c->req->base.$redirect;
    }

    $c->res->redirect($redirect);
}

1;
