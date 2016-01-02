#!/usr/bin/perl -T

# File: w.pl
#
# Handles displaying content pages

use 5.018;
use strict;
use warnings;
use diagnostics;
use lib '.';

use M::Const;
use M::DB;
use M::Render;

use CGI;
use Data::Dump qw(dump);
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
    timezone => $conf{TIMEZONE});


### request handling ###

sub ref_list {
    my ($slug) = @_;

    if (my $title = $db->get_title($slug)) {
        my @links = map { {
            ID => $_->{pageid},
            TITLE => $_->{title}, 
            SITE_ROOT => $conf{SITE_ROOT},
        } } $db->get_links($slug);
        my $template = HTML::Template->new(
            filename => 'templates/links.html',
            die_on_bad_params => 0);
        $template->param(TITLE => $title);
        $template->param(SITE_ROOT => $conf{SITE_ROOT});
        $template->param(LINKS => \@links);
        $r->show_page("200 OK", "Links to $title", $template->output);
    } else {
        $r->four_oh_four("No such entry '$slug'.");
    }
}

sub show_entry {
    my ($slug) = @_;
    
    my $on = $r->q->param('on');
    if (my $page = $db->get_entry($slug, $on)) {

        if ($page->{title} ne $slug) {
            # if the title is different from the slug, redirect and try again
            my $url = $conf{SITE_ROOT} . "/w/" . $page->{title} . ".html";
            if (defined $on and $on ne "") {
                $url .= "?on=$on";
            }

            print $r->q->redirect($url);
            return;
        }

        my $template = HTML::Template->new(
            filename => 'templates/entry.html',
            die_on_bad_params => 0);
        $template->param(TITLE => $page->{title});
        $template->param(SITE_ROOT => $conf{SITE_ROOT});
        $template->param(CONTENT => $r->render_entry($page->{content}));
        $template->param(USERLINK => $r->render_username($page->{editor}));
        $template->param(EDITED => $r->render_time($page->{edited}));
        $template->param(ID => $page->{pageid});
        $r->show_page("200 OK", $page->{title}, $template->output);
    } elsif ($slug =~ /^\d+$/) {
        # digit identifiers just 404
        $r->four_oh_four("Invalid permalink '$slug'.");
    } elsif ($slug !~ TITLE_PATTERN) {
        # so do invalid titles
        $r->four_oh_four("Invalid entry name '$slug'.");
    } else {
        # it's a valid page that doesn't exist yet, so go to edit
        print $r->q->redirect($conf{SITE_ROOT} . "/e/" . $slug);
    }
}

sub show_all {
    print $r->q->header("text/plain; charset=utf-8");
    for ($db->get_all_pages) {
        print $_->{pageid} . " " . $_->{title} . "\n";
    }
}

sub dump_entry {
    my ($slug) = @_;

    if (my $page = $db->get_entry($slug)) {
        print $r->q->header("text/plain; charset=utf-8");
        print $page->{content};
    } elsif ($slug =~ /^\d+$/) {
        $r->four_oh_four("Invalid permalink '$slug'.");
    } elsif ($slug !~ TITLE_PATTERN) {
        $r->four_oh_four("Invalid entry name '$slug'.");
    } else {
        $r->four_oh_four(
            "No such entry '$slug'. " .
            "<a href='" . $conf{SITE_ROOT} .
            qq(/e/$slug'>Create it?</a>));
    }
}

$_ = (substr($r->q->path_info(), 1) or '1.html');
if (/^_([^\s.]*)$/) {
    if ($1 eq "all") {
        show_all;
    } else {
        $r->four_oh_four("Unknown special page '$1'");
    }
} elsif (/^([^\s.]*)\.([^\s.]*)$/) {
    if ($2 eq "links") {
        ref_list $1;
    } elsif ($2 eq "html") {
        show_entry $1;
    } elsif ($2 eq "txt") {
        dump_entry $1;
    } else {
        $r->four_oh_four("Unknown mode '$2'");
    }
} elsif ($_ =~ TITLE_PATTERN) {

    my $on = $r->q->param('on');
    my $url = $conf{SITE_ROOT} . "/w/$_.html";
    if (defined $on and $on ne "") {
        $url .= "?on=$on";
    }
    print $r->q->redirect($url);

} elsif (/^(\d+)$/) {

    my $on = $r->q->param('on');
    my $url = $conf{SITE_ROOT} . "/w/$_.html";
    if (defined $on and $on ne "") {
        $url .= "?on=$on";
    }
    print $r->q->redirect($url);

} else {
    $r->four_oh_four("Unknown page '$_'");
}

