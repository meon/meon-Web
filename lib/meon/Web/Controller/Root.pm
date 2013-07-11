package meon::Web::Controller::Root;
use Moose;
use namespace::autoclean;
use 5.010;

use Path::Class 'file', 'dir';
use meon::Web::SPc;
use meon::Web::Config;
use meon::Web::Util;
use meon::Web::env;
use XML::LibXML 1.70;
use URI::Escape 'uri_escape';
use IO::Any;
use Class::Load 'load_class';
use File::MimeInfo 'mimetype';
use Scalar::Util 'blessed';
use DateTime::Format::HTTP;
use Imager;
use URI::Escape 'uri_escape';
use List::MoreUtils 'none';

use meon::Web::Form::Login;
use meon::Web::Form::Delete;
use meon::Web::Member;
use meon::Web::TimelineEntry;


BEGIN { extends 'Catalyst::Controller' }

__PACKAGE__->config(namespace => '');

sub auto : Private {
    my ( $self, $c ) = @_;

    meon::Web::env->clear;
    meon::Web::env->stash($c->stash);

    my $uri      = $c->req->uri;
    my $hostname = $uri->host;
    meon::Web::env->hostname($hostname);
    my $hostname_dir_name = meon::Web::Config->hostname_to_folder($hostname);

    $c->detach('/status_not_found', ['no such domain '.$hostname.' configured'])
        unless $hostname_dir_name;

    my $hostname_dir = $c->stash->{hostname_dir} = meon::Web::env->hostname_dir;

    my $template_file = file($hostname_dir, 'template', 'xsl', 'default.xsl')->stringify;
    $c->stash->{template} = XML::LibXML->load_xml(location => $template_file);

    $c->default_auth_store->folder(meon::Web::env->profiles_dir);
    meon::Web::env->user($c->user);

    # set cookie domain
    my $cookie_domain = $hostname;
    my $config_cookie_domain = meon::Web::Config->get->{$hostname_dir_name}{'main'}{'cookie-domain'};

    if ($config_cookie_domain && (substr($hostname,0-length($config_cookie_domain)) eq $config_cookie_domain)) {
        $cookie_domain = $config_cookie_domain;
    }

    $c->_session_plugin_config->{cookie_domain} = $cookie_domain;

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

    my $hostname_dir = $c->stash->{hostname_dir};
    my $path            =
        delete($c->session->{post_redirect_path})
        || $c->stash->{path}
        || $c->req->uri;
    $path = URI->new($path)
        unless blessed($path);

    meon::Web::env->current_path(file($path->path));
    my $xml_file = file($hostname_dir, 'content', $path->path_segments);
    $xml_file .= '.xml';
    if ((! -f $xml_file) && (-d substr($xml_file,0,-4))) {
        $xml_file = file(substr($xml_file,0,-4), 'index.xml');
    }
    if ((! -f $xml_file) && (-f substr($xml_file,0,-4))) {
        my $static_file = file(substr($xml_file,0,-4));
        my $mtime = $static_file->stat->mtime;
        if (!$c->req->param('t')) {
            $c->res->redirect($c->req->uri_with({t => $mtime})->absolute);
            $c->detach;
        }

        my $max_age = 365*24*60*60;
        $c->res->header('Cache-Control' => 'max-age='.$max_age.', private');
        $c->res->header(
            'Expires' => DateTime::Format::HTTP->format_datetime(
                DateTime->now->add(seconds => $max_age)
            )
        );
        $c->res->header(
            'Last-Modified' => DateTime::Format::HTTP->format_datetime(
                DateTime->from_epoch(epoch => $mtime)
            )
        );

        my $mime_type = mimetype($static_file->basename);
        $c->res->content_type($mime_type);
        $c->res->body($static_file->open('r'));
        $c->detach;
    }

    $c->detach('/status_not_found', [($c->debug ? $path.' '.$xml_file : $path)])
        unless -e $xml_file;

    $xml_file = file($xml_file);
    $c->stash->{xml_file} = $xml_file;
    meon::Web::env->xml_file($xml_file);

    my $dom = meon::Web::env->xml;
    my $xpc = meon::Web::Util->xpc;

    $c->model('ResponseXML')->dom($dom);

    $c->model('ResponseXML')->push_new_element('current-path')->appendText($c->req->uri->path);

    # user
    if ($c->user_exists) {
        my $user_el = $c->model('ResponseXML')->create_element('user');

        my $user_el_username = $c->model('ResponseXML')->create_element('username');
        $user_el_username->appendText($c->user->username);
        $user_el->appendChild($user_el_username);

        my @user_roles = $c->user->roles;
        my $roles_el = $c->model('ResponseXML')->create_element('roles');
        foreach my $role (@user_roles) {
            $roles_el->appendChild(
                $c->model('ResponseXML')->create_element($role)
            );
        }
        $user_el->appendChild($roles_el);

        my $member = $c->member;
        my $full_name_el = $c->model('ResponseXML')->create_element('full-name');
        $full_name_el->appendText($member->get_member_meta('full-name'));
        $user_el->appendChild($full_name_el);

        $c->model('ResponseXML')->append_xml($user_el);

        my @access_roles = map { $_->textContent } $xpc->findnodes('/w:page/w:meta/w:access/w:role',$dom);
        if (@access_roles && (none { $_ ~~ \@user_roles } @access_roles)) {
            $c->session->{post_redirect_path} = '/forbidden';
            $c->res->redirect($c->req->uri->absolute);
            $c->detach;
        }
    }
    else {
        if ($xpc->findnodes('/w:page/w:meta/w:members-only',$dom)) {
            $c->detach('/login', []);
        }
    }

    # redirect
    my ($redirect) = $xpc->findnodes('/w:page/w:meta/w:redirect', $dom);
    if ($redirect) {
        $redirect = $redirect->textContent;
        my $redirect_uri = $c->traverse_uri($redirect);
        $c->res->redirect($redirect_uri->absolute);
        $c->detach;
    }

    # forms
    if (my ($form_el) = $xpc->findnodes('/w:page/w:meta/w:form',$dom)) {
        my $skip_form = 0;
        if ($xpc->findnodes('w:owner-only',$form_el)) {
            my $member = $c->member;
            my $member_folder = $member->dir;

            $skip_form = 1
                unless $member_folder->contains($xml_file);
        }

        unless ($skip_form) {
            my $back_link = delete $c->req->params->{_back_link};
            if (defined($back_link)) {
                $c->model('ResponseXML')->push_new_element('back-link')->appendText($back_link);
                $c->stash->{back_link} = $back_link;
            }
            my ($form_class) = 'meon::Web::Form::'.$xpc->findnodes('/w:page/w:meta/w:form/w:process', $dom);
            load_class($form_class);
            my $form = $form_class->new(c => $c);
            my $params = $c->req->body_parameters;
            foreach my $field ($form->fields) {
                next if $field->type ne 'Upload';
                my $field_name = $field->name;
                $params->{$field_name} = $c->req->upload($field_name)
                    if $params->{$field_name};
            }
            $form->process(params=>$params);
            $form->submitted
                if $form->is_valid && $form->can('submitted') && ($c->req->method eq 'POST');
            $c->model('ResponseXML')->add_xhtml_form(
                $form->render
            );
        }
    }

    # folder listing
    my (@folders) =
        map { $_->textContent }
        $xpc->findnodes('/w:page/w:meta/w:dir-listing',$dom);
    foreach my $folder_name (@folders) {
        my $folder_rel = dir(meon::Web::Util->path_fixup($folder_name));
        my $folder = dir($xml_file->dir, $folder_rel)->absolute;
        next unless -d $folder;
        $folder = $folder->resolve;
        $c->detach('/status_forbidden', [])
            unless $hostname_dir->contains($folder);

        my @files = sort(grep { not $_->is_dir } $folder->children(no_hidden => 1));

        my $folder_el = $c->model('ResponseXML')->create_element('folder');
        $folder_el->setAttribute('name' => $folder_name);
        $c->model('ResponseXML')->append_xml($folder_el);

        foreach my $file (@files) {
            $file = $file->basename;
            my $file_el = $c->model('ResponseXML')->create_element('file');
            $file_el->setAttribute('href' => join('/', map { uri_escape($_) } $folder_rel->dir_list, $file));
            $file_el->appendText($file);
            $folder_el->appendChild($file_el);
        }
    }

    # gallery listing
    my (@galleries) = $xpc->findnodes('/w:page/w:content//w:gallery',$dom);
    foreach my $gallery (@galleries) {
        my $gallery_path = $gallery->getAttribute('href');
        my $max_width  = $gallery->getAttribute('thumb-width');
        my $max_height = $gallery->getAttribute('thumb-height');

        my $folder_rel = dir(meon::Web::Util->path_fixup($gallery_path));
        my $folder = dir($xml_file->dir, $folder_rel)->absolute;
        die 'no pictures in '.$folder unless -d $folder;
        $folder = $folder->resolve;
        $c->detach('/status_forbidden', [])
            unless $hostname_dir->contains($folder);

        my @files = sort(grep { not $_->is_dir } $folder->children(no_hidden => 1));

        foreach my $file (@files) {
            $file = $file->basename;
            next if $file =~ m/\.xml$/;
            my $thumb_file = file(map { uri_escape($_) } $folder_rel->dir_list, 'thumb', $file);
            my $img_file   = file(map { uri_escape($_) } $folder_rel->dir_list, $file);
            my $file_el = $c->model('ResponseXML')->create_element('img');
            $file_el->setAttribute('src' => $img_file);
            $file_el->setAttribute('src-thumb' => $thumb_file);
            $file_el->setAttribute('title' => $file);
            $file_el->setAttribute('alt' => $file);
            $gallery->appendChild($file_el);

            # create thumbnail image
            $thumb_file = file($xml_file->dir, $thumb_file);
            unless (-e $thumb_file) {
                $thumb_file->dir->mkpath
                    unless -e $thumb_file->dir;

                my $img = Imager->new(file => file($xml_file->dir, $img_file))
                    or die Imager->errstr();
                if ($img->getwidth > $max_width) {
                    $img = $img->scale(xpixels => $max_width)
                        || die 'failed to scale image - '.$img->errstr;
                }
                if ($img->getheight > $max_height) {
                    $img = $img->scale(ypixels => $max_height)
                        || die 'failed to scale image - '.$img->errstr;
                }
                $img->write(file => $thumb_file->stringify) || die 'failed to save image - '.$img->errstr;
            }
        }
    }

    # generate timeline
    my ($timeline_el) = $xpc->findnodes('/w:page/w:content//w:timeline', $dom);
    if ($timeline_el) {
        my $timeline_class = $timeline_el->getAttribute('class') // 'folder';
        my @entries_files;
        foreach my $href_entry ($xpc->findnodes('w:timeline-entry[@href]', $timeline_el)) {
            my $href = $href_entry->getAttribute('href');
            $timeline_el->removeChild($href_entry);
            my $path = file(meon::Web::Util->full_path_fixup($href).'.xml');
            push(@entries_files,$path)
                if -e $path;
        }
        @entries_files = $xml_file->dir->children(no_hidden => 1)
            if $timeline_class eq 'folder';

        my @entries =
            sort { $b->created <=> $a->created }
            grep { eval { $_->element } }
            map  { meon::Web::TimelineEntry->new(file => $_) }
            grep { $_->basename ne $xml_file->basename }
            grep { !$_->is_dir }
            @entries_files
        ;

        foreach my $entry (@entries) {
            my $entry_el = $entry->element;
            my $intro = $entry->intro;
            my $href = $entry->file->resolve;
            return unless $href;
            $href = substr($href,0,-4);
            $href = substr($href,length($c->stash->{hostname_dir}.'/content'));
            $entry_el->setAttribute('href' => $href);
            if (defined($intro)) {
                my $intro_snipped_el = $c->model('ResponseXML')->create_element('intro-snipped');
                $entry_el->appendChild($intro_snipped_el);
                $intro_snipped_el->appendText(length($intro) > 78 ? substr($intro,0,78).'…' : $intro);
            }

            $timeline_el->appendChild($entry_el);
        }

        if (my $older = $self->_older_entries($c)) {
            my $older_el = $c->model('ResponseXML')->create_element('older');
            $timeline_el->appendChild($older_el);
            $older_el->setAttribute('href' => $older);
        }
        if (my $newer = $self->_newer_entries($c)) {
            my $newer_el = $c->model('ResponseXML')->create_element('newer');
            $timeline_el->appendChild($newer_el);
            $newer_el->setAttribute('href' => $newer);
        }
    }

    # generate exists
    my (@exists) = (
        $xpc->findnodes('//w:exists', $dom),
        $xpc->findnodes('//w:exists', $c->stash->{template}),
    );
    foreach my $exist_el (@exists) {
        my $href = $exist_el->getAttribute('href');
        my $path = meon::Web::Util->full_path_fixup($href);
        $exist_el->appendText(-e $path ? 1 : 0);
    }
}

sub _older_entries {
    my ( $self, $c ) = @_;
    my $dir = $c->stash->{xml_file}->dir;
    my $cur_dir = $dir->basename;
    $dir = $dir->parent;
    while ($cur_dir =~ m/^\d+$/) {
        my @min_folders =
            sort
            grep { $_ < $cur_dir }
            grep { m/^\d+$/ }
            map  { $_->basename }
            grep { $_->is_dir }
            $dir->children(no_hidden => 1)
        ;

        if (@min_folders) {
            # find the last folder of this folder
            while (@min_folders) {
                $dir = $dir->subdir(pop(@min_folders));
                @min_folders =
                    sort
                    grep { m/^\d+$/ }
                    map { $_->basename }
                    grep { $_->is_dir }
                    $dir->children(no_hidden => 1)
                ;
            }
            return $dir->relative($c->stash->{xml_file}->dir).'/';
        }

        $cur_dir = $dir->basename;
        $dir = $dir->parent;
    }
}

sub _newer_entries {
    my ( $self, $c ) = @_;
    my $dir = $c->stash->{xml_file}->dir;
    my $cur_dir = $dir->basename;
    $dir = $dir->parent;
    while ($cur_dir =~ m/^\d+$/) {
        my @max_folders =
            sort
            grep { $_ > $cur_dir }
            grep { m/^\d+$/ }
            map  { $_->basename }
            grep { $_->is_dir }
            $dir->children(no_hidden => 1)
        ;

        if (@max_folders) {
            # find the first folder of this folder
            while (@max_folders) {
                $dir = $dir->subdir(shift(@max_folders));
                @max_folders =
                    sort
                    grep { m/^\d+$/ }
                    map { $_->basename }
                    grep { $_->is_dir }
                    $dir->children(no_hidden => 1)
                ;
            }
            return $dir->relative($c->stash->{xml_file}->dir).'/';
        }

        $cur_dir = $dir->basename;
        $dir = $dir->parent;
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

    my $username = eval { $c->user->username };
    $c->delete_session;
    $c->log->info('logout user '.$username)
        if $username;
    return $c->res->redirect($c->uri_for('/'));
}

sub login : Local {
    my ( $self, $c ) = @_;

    my $token    = $c->req->param('auth-token');
    my $username = $c->req->param('username');
    my $password = $c->req->param('password');
    my $back_to  = $c->req->param('back-to');

    if ($c->action eq 'logout') {
        return $c->res->redirect($c->uri_for('/'));
    }
    if ($c->user_exists && !$token) {
        $back_to ||= '/';
        return $c->res->redirect($c->uri_for($back_to));
    }

    my $login_form = meon::Web::Form::Login->new(
        action => $c->req->uri,
    );

    # token authentication
    if ($token) {
        my $members_folder = $c->default_auth_store->folder;
        my $member;
        if (($token eq 'admin') && $c->user_exists) {
            my @roles = $c->user->roles;
            if ('admin' ~~ \@roles) {
                $member = meon::Web::Member->new(
                    members_folder => $members_folder,
                    username       => $username,
                );
            }
        }
        else {
            $member = meon::Web::Member->find_by_token(
                members_folder => $members_folder,
                token          => $token,
            );
        }

        if ($member) {
            my $username = $member->username;
            $c->set_authenticated($c->find_user({ username => $username }));
            $c->log->info('user '.$username.' authenticated via token');
            $c->change_session_id;
            $c->session->{old_pw_not_required} = 1;
            return $c->res->redirect(
                $c->req->uri_with({
                    'auth-token' => undef,
                    'username'   => undef,
                })->absolute
            );
        }
        else {
            $login_form->add_form_error('Invalid authentication token.');
        }
    }
    else {
        $login_form->process(params=>$c->req->params);
        if ($username && $password && $login_form->is_valid) {
            if (
                $c->authenticate({
                    username => $username,
                    password => $password,
                })
            ) {
                $c->log->info('user '.$username.' authenticated');
                $c->change_session_id;
                return $c->res->redirect($c->req->uri);
            }
            else {
                $c->log->info('login of user '.$username.' fail');
                $login_form->field('password')->add_error('authentication failed');
            }
        }
    }

    $c->stash->{path} = URI->new('/login');
    $c->forward('resolve_xml', []);
    $c->model('ResponseXML')->add_xhtml_form(
        $login_form->render
    );
}

sub end : ActionClass('RenderView') {}

__PACKAGE__->meta->make_immutable;

1;
