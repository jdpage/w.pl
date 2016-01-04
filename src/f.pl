#!/usr/bin/perl -T

# File: f.pl
#
# Handles displaying feeds and history.

use 5.018;
use strict;
use warnings;
use diagnostics;
use lib '.';

use M::Const;
use M::DB;
use M::Render;

use HTML::Template;
use List::Util qw(reduce);

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

sub render_html_feed {
    my ($id, $title, $edited, $edits) = @_;

    my $template = HTML::Template->new(
        filename => 'templates/recent.html',
        die_on_bad_params => 0);
    $template->param(SITE_ROOT => $conf{SITE_ROOT});
    $template->param(EDITS => $edits);
    $r->show_page("200 OK", "Recent edits to $title", $template->output);
}

sub render_atom_feed {
    my ($id, $title, $edited, $edits) = @_;
    my $isotime = $r->render_isotime($edited);

    my $template = HTML::Template->new(
        filename => 'templates/feed.xml',
        die_on_bad_params => 0);
    $template->param(SITE_ROOT => $conf{SITE_ROOT});
    $template->param(EDITS => $edits);
    $template->param(TITLE => $title);
    $template->param(ID => $id);
    $template->param(ISO_TIME => $isotime);
    print $r->q->header("application/atom+xml; charset=utf-8");
    print $template->output;
}

if (/^([^\s.]*)\.([^\s\.]*)$/) {
    my $id = undef;
    my $title;
    my $edited;
    my @edits;

    if ($1 eq "_all") {

        $id = 0;
        $title = "site";
        @edits = map { {

            ID => $_->{pageid},
            TITLE => $_->{title},

            EDITOR_NAME => $r->name_of_editor($_->{editor}),
            USER_LINK => $r->render_username($_->{editor}),

            EDITED => $_->{edited},
            FORMATTED_TIME => $r->render_time($_->{edited}),
            ISO_TIME => $r->render_isotime($_->{edited}),

            SITE_ROOT => $conf{SITE_ROOT},

        } } $db->get_all_edits;
        $edited = reduce { $a > $b->{EDITED} ? $a : $b->{EDITED} } 0, @edits;

    } elsif (my $entry = $db->get_entry($1)) {

        $id = $entry->{pageid};
        $title = $entry->{title};
        $edited = $entry->{edited};
        @edits = map { {

            ID => $id,
            TITLE => $title,

            EDITOR_NAME => $r->name_of_editor($_->{editor}),
            USER_LINK => $r->render_username($_->{editor}),

            EDITED => $r->{edited},
            FORMATTED_TIME => $r->render_time($_->{edited}),
            ISO_TIME => $r->render_isotime($_->{edited}),

            SITE_ROOT => $conf{SITE_ROOT},

        } } $db->get_edits($id);

    } else {

        $r->four_oh_four("Unknown page '$1'.");

    }

    if (defined($id)) {

        if ($2 =~ /^html$/i) {
            render_html_feed($id, $title, $edited, \@edits);
        } elsif ($2 =~ /^xml$/i) {
            render_atom_feed($id, $title, $edited, \@edits);
        } else {
            $r->four_oh_four("Unknown format '$2'.");
        }
    }
} else {
    $r->four_oh_four("Unknown page 'f/$_'");
}
