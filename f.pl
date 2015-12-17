#!/usr/bin/env perl

# File: f.pl
#
# Handles displaying feeds and history.

use 5.018;
use strict;
use warnings;
use diagnostics;

use M::Const;
use M::DB;
use M::Render;

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


$_ = substr($r->q->path_info, 1);
if (/^\.html$/) {
    my @edits = map { {
        TITLE => $_->{title},
        USERLINK => $r->render_username($_->{editor}),
        EDITED => $_->{edited},
        FORMATTEDTIME => $r->render_time($_->{edited}),
        SITE_ROOT => $conf{SITE_ROOT},
    } } $db->get_edits;

    my $template = HTML::Template->new(
        filename => 'templates/recent.html',
        die_on_bad_params => 0);
    $template->param(SITE_ROOT => $conf{SITE_ROOT});
    $template->param(EDITS => \@edits);
    $r->show_page("200 OK", "Recently edited pages", $template->output);
} else {
    $r->four_oh_four("Unknown page '$_'");
}
