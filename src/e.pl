#!/usr/bin/perl -T

# File: e.pl
#
# Handles editing pages

use 5.018;
use strict;
use warnings;
use diagnostics;
use lib '.';

use M::Const;
use M::DB;
use M::Render;

use CGI;
use Digest::MD5 qw(md5_hex);
use HTML::Template;

if (defined $ENV{DOCUMENT_ROOT}) {
    eval "use CGI::Carp 'fatalsToBrowser'";
}

# load configuration
my %conf = do 'conf.pl';

my $db = M::DB->new($conf{DATABASE});
my $r = M::Render->new(
    database => $db,
    site_root => $conf{SITE_ROOT},
    language => $conf{LANGUAGE},
    timezone => $conf{TIMEZONE});

# check the edit blacklist
if ($conf{BLACKLIST} and open(my $h, '<:encoding(UTF-8)', $conf{BLACKLIST})) {
    my %blacklist = map { chomp($_); $_ => 1 } <$h>;
    close $h;

    if (exists($blacklist{$r->q->remote_addr})) {
        $r->four_oh_three(
            "Your IP address has been blocked from editing.");
        exit;
    }
}

my $slug = substr($r->q->path_info(), 1);
if ($slug !~ TITLE_PATTERN) {
    # this page can't actually get created
    print $r->four_oh_four("Invalid entry name '$slug'.");
    exit;
}

my $title = $slug;
my $content = '';
my $username = $r->q->cookie('username');
my $base;
my $id;
my @errors;
if (my $entry = $db->get_entry($slug)) {
    $id = $entry->{pageid};
    $title = $entry->{title};
    $content = $entry->{content};
    $base = $entry->{revisionid};
}

if ($r->q->request_method eq 'POST') {
    my $oldcontent = $content;
    my $oldtitle = $title;
    my $oldbase = $base;
    $base = $r->q->param('base');
    $username = $r->q->param('username');
    $content = $r->q->param('content');
    $title = $r->q->param('title');

    if ($title !~ TITLE_PATTERN) {
        # validate title format
        push @errors, { message => 
            "title must be made of letters and numbers and must begin " .
            "with a letter" };
    } elsif ($oldtitle ne $title and $db->get_id($title)) {
        # validate duplicates
        push @errors, { message =>
            "a page with named '$title' already exists" };
    } elsif ($username !~ USERNAME_PATTERN) {
        # validate username format
        push @errors, { message =>
            "a username must be made of one or more letters and numbers " .
            "and must begin with a letter" };
    } elsif ($base != $oldbase) {
        # validate no conflicting edit
        push @errors, { message =>
            "another user edited this page while you were typing. Please " .
            "make a copy of your changes and " .
            qq(<a href=") . $conf{SITE_ROOT} .
            qq(/e/$slug">click here to start over</a>.) }
    } else {
        # validation passed, save and redirect
        $username =~ USERNAME_PATTERN;
        my $name = $1;
        my $ip = $r->q->remote_addr;

        my $tripname;
        if (defined $2) {
            $tripname = $name . "!" . md5_hex($2);
        } else {
            $tripname = $name;
        }

        my $fullname = $tripname . "@" . $r->q->remote_addr;
        my $cookie = CGI->cookie(
            -name => 'username',
            -value => $username);
        my ($pcontent, $links) = $r->preprocess_entry($content, $tripname);

        $db->put_entry($id, $title, $fullname, $pcontent, $links, $base);

        my $template = HTML::Template->new(
            filename => 'templates/editok.html',
            die_on_bad_params => 0);
        $template->param(TITLE => $title);
        $template->param(SITE_ROOT => $conf{SITE_ROOT});
        $template->param(LANGUAGE => $conf{LANGUAGE});

        print $r->q->header("text/html; charset=utf-8", "200 OK"
            -cookie => $cookie);
        print $template->output;
        exit;
    }
}

my $template = HTML::Template->new(
    filename => 'templates/edit.html',
    die_on_bad_params => 0);

$template->param(ID => $id);
$template->param(SITE_ROOT => $conf{SITE_ROOT});
$template->param(LANGUAGE => $conf{LANGUAGE});
$template->param(SLUG => $slug);
$template->param(ERRORS => \@errors);
$template->param(TITLE => $title);
$template->param(BASE => $base);
$template->param(USERNAME => $username);
$template->param(IP => $r->q->remote_addr);
$template->param(CONTENT => $content);
$r->show_page("200 OK", "Editing $slug", $template->output);

