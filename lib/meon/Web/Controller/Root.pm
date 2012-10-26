package meon::Web::Controller::Root;
use Moose;
use namespace::autoclean;

use Path::Class 'file', 'dir';
use meon::Web::SPc;
use meon::Web::Config;
use File::MimeInfo;
use XML::LibXML 1.70;
use URI::Escape 'uri_escape';
use IO::Any;

use meon::Web::Form::Process::SendEmail;
use meon::Web::Form::Login;

BEGIN { extends 'Catalyst::Controller' }

__PACKAGE__->config(namespace => '');

sub auto : Private {
    my ( $self, $c ) = @_;

    my $uri      = $c->req->uri;
    my $hostname = $uri->host;
    my $hostname_folder = meon::Web::Config->hostname_to_folder($hostname);

    $c->detach('/status_not_found', ['no such domain '.$hostname.' configured'])
        unless $hostname_folder;

    $hostname_folder = dir(meon::Web::SPc->srvdir, 'www', 'meon-web', $hostname_folder)->absolute->resolve;
    $c->stash->{hostname_folder} = $hostname_folder;

    my $template_file = file($hostname_folder, 'template', 'xsl', 'default.xsl');
    $c->stash->{template} = $template_file;

    $c->default_auth_store->folder(
        dir($hostname_folder, 'members')
    );

    return 1;
}

sub static : Path('/static') {
    my ($self, $c) = @_;

    my $static_file = file(@{$c->static_include_path}, $c->req->path);
    $c->detach('/status_not_found', [($c->debug ? $static_file : '')])
        unless -e $static_file;

    my $mime_type = mimetype($static_file->stringify);
    $c->res->content_type($mime_type);
    $c->res->body(IO::Any->read([$static_file]));
}

sub default :Path {
    my ( $self, $c ) = @_;
    $c->forward('resolve_xml', []);
}

sub resolve_xml : Private {
    my ( $self, $c ) = @_;

    my $hostname_folder = $c->stash->{hostname_folder};
    my $path            = $c->stash->{path} || $c->req->uri->path;

    my $xml_file = file($hostname_folder, 'content', $path);
    $xml_file .= '.xml';
    if ((! -f $xml_file) && (-d substr($xml_file,0,-4))) {
        $xml_file = file(substr($xml_file,0,-4), 'index.xml');
    }

    $c->detach('/status_not_found', [($c->debug ? $path.' '.$xml_file : $path)])
        unless -e $xml_file;

    my $dom = XML::LibXML->load_xml(location => $xml_file);
    my $xpc = $c->xpc;

    $c->model('ResponseXML')->dom($dom);

    # user
    if ($c->user_exists) {
        my $user_el = $c->model('ResponseXML')->create_element('user');
        my $user_el_username = $c->model('ResponseXML')->create_element('username');
        $user_el_username->appendText($c->user->username);
        $user_el->appendChild($user_el_username);
        $c->model('ResponseXML')->append_xml($user_el);
    }
    else {
        if ($xpc->findnodes('/w:page/w:meta/w:members-only',$dom)) {
            $c->detach('/login', []);
        }
    }

    # form submit
    my ($form) = $xpc->findnodes('/w:page/w:meta/w:form',$dom);
    if ($form) {
        my ($process) = 'meon::Web::Form::Process::'.$xpc->findnodes('//w:process', $form);
        $process->submitted($c, $form)
            if $c->req->method eq 'POST';
    }

    # folder listing
    my (@folders) =
        map { $_->textContent }
        $xpc->findnodes('/w:page/w:meta/w:dir-listing',$dom);
    foreach my $folder_name (@folders) {
        my $folder_rel = dir($folder_name);
        my $folder = dir($hostname_folder, $folder_rel)->absolute->resolve;
        $c->detach('/status_forbidden', [])
            unless $hostname_folder->contains($folder);

        my @files = sort(grep { not $_->is_dir } $folder->children(no_hidden => 1));

        my $folder_el = $c->model('ResponseXML')->create_element('folder');
        $folder_el->setAttribute('name' => $folder_name);
        $c->model('ResponseXML')->append_xml($folder_el);

        foreach my $file (@files) {
            $file = $file->basename;
            my $file_el = $c->model('ResponseXML')->create_element('file');
            $file_el->setAttribute('href' => join('/', '', map { uri_escape($_) } $folder_rel->dir_list, $file));
            $file_el->appendText($file);
            $folder_el->appendChild($file_el);
        }
    }
}

sub status_forbidden : Private {
    my ( $self, $c, $message ) = @_;

    $message = '401 - Forbidden: '.$c->req->uri."\n".($message // '');

    $c->res->status(401);
    $c->res->content_type('text/plain');
    $c->res->body($message);
}

sub status_not_found : Private {
    my ( $self, $c, $message ) = @_;

    $message = '404 - Page not found: '.$c->req->uri."\n".($message // '');

    $c->res->status(404);
    $c->res->content_type('text/plain');
    $c->res->body($message);
}

sub logout : Local {
    my ( $self, $c ) = @_;

    my $username = $c->user->username;
    $c->delete_session;
    $c->log->info('logout user '.$username);
    return $c->res->redirect($c->uri_for('/'));
}

sub login : Local {
    my ( $self, $c ) = @_;

    if ($c->action eq 'logout') {
        return $c->res->redirect($c->uri_for('/'));
    }
    if ($c->user_exists) {
        return $c->res->redirect($c->uri_for('/'));
    }

    my $username = $c->req->param('username');
    my $password = $c->req->param('password');

    my $login_form = meon::Web::Form::Login->new(
        action => $c->req->uri,
    );
    $login_form->process(params=>$c->req->params);

    if ($username && $password && $login_form->is_valid) {
        if (
            $c->authenticate({
                username => $username,
                password => $password,
            })
        ) {
            $c->log->info('login of user '.$username.' authenticated');
            $c->change_session_id;
            return $c->res->redirect($c->req->uri);
        }
        else {
            $c->log->info('login of user '.$username.' fail');
            $login_form->field('password')->add_error('authentication failed');
        }
    }

    $c->stash->{path} = '/login';
    $c->forward('resolve_xml', []);
    $c->model('ResponseXML')->add_xhtml_form(
        $login_form->render
    );
}

sub end : ActionClass('RenderView') {}

__PACKAGE__->meta->make_immutable;

1;
