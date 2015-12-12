#!/usr/bin/env perl

use 5.018;
use strict;
use warnings;
use diagnostics;

use constant TIMEZONE => 'EST';
use constant DATABASE => '/home/protected/books.sqlite3';
use constant TITLE_PATTERN => qr/^[a-z][a-z0-9]*$/i;

use CGI;
use Data::Dump qw(dump);
use Date::Format;
use DBI;
use Digest::MD5;
use List::MoreUtils qw(uniq);
use HTML::Template;

if (defined $ENV{DOCUMENT_ROOT}) {
    eval "use CGI::Carp 'fatalsToBrowser'";
}

my $q = CGI->new;
my $database = DATABASE;
my $db = DBI->connect("DBI:SQLite:dbname=$database") or die $DBI::errstr;


### database access ###

sub get_entry {
    my ($title) = @_;

    my $stmt = q(
        select pages.pageid
             , pages.title
             , pages.revision
             , revisions.edited
             , revisions.editor
             , revisions.content
        from pages join revisions
        on pages.revision = revisions.revisionid);

    if ($title =~ /^(\d+)$/) {
        $stmt .= q(
            where pages.pageid = ?);
    } else {
        $stmt .= q(
            where pages.title = ?);
    }
    my $pst = $db->prepare($stmt) or die $db->errstr;
    $pst->execute($title) or die $pst->errstr;
    return $pst->fetchrow_hashref;
}

sub put_entry {
    my ($id, $title, $username, $content, $links, $base) = @_;

    # insert new revision
    my $revp = $db->prepare(q(insert into revisions values(NULL, ?, ?, ?, ?)))
        or die $db->errstr;
    $revp->execute(time, $username, $content, $base) or die $revp->errstr;
    my $revid = $db->sqlite_last_insert_rowid;

    # update page entry to point to new revision
    my $pagep = $db->prepare(q(
        insert or replace into pages values(
            ?, ?, ?))) or die $db->errstr;
    $pagep->execute($id, $title, $revid) or die $pagep->errstr;
    my $pageid = $db->sqlite_last_insert_rowid;

    # remove all links from this page
    my $dlp = $db->prepare(q(delete from links where page = ?))
        or die $db->errstr;
    $dlp->execute($pageid) or die $dlp->errstr;

    # add links from this page
    my $ilp = $db->prepare(q(insert into links values(?, ?)))
        or die $db->errstr;
    for my $link (@{$links}) {
        $ilp->execute($pageid, $link) or die $ilp->errstr;
    }
}

sub get_all_pages {
    my $pst = $db->prepare(q(select * from pages)) or die $db->errstr;
    my @pages;
    while (my $row = $pst->fetchrow_hashref) {
        push @pages, $row;
    }
    return @pages;
}

sub get_id {
    my ($title) = @_;
    if ($title =~ /^(\d+)$/) {
        return $title;
    }

    my $pst = $db->prepare(q(
        select pageid from pages
        where title = ?
        limit 1))
        or die $db->errstr;
    $pst->execute($title) or die $pst->errstr;
    my $row = $pst->fetchrow_hashref;
    return $row->{pageid};
}

sub get_title {
    my ($id) = @_;
    $id = get_id $id;
    my $pst = $db->prepare(q(
        select title from pages
        where pageid = ?
        limit 1))
        or die $db->errstr;
    $pst->execute($id) or die $pst->errstr;
    my $row = $pst->fetchrow_hashref;
    return $row->{title};
}

sub get_links {
    my ($title) = @_;
    my $id = get_id $title;
    my $pst = $db->prepare(q(
        select pages.*
        from links join pages
        on links.page = pages.pageid
        where target = ?
        order by pages.title))
        or die $db->errstr;
    $pst->execute($id) or die $pst->errstr;
    my @links;
    while (my $row = $pst->fetchrow_hashref) {
        push @links, $row;
    }
    return @links;
}

sub get_edits {
    my $pst = $db->prepare(q(
        select pages.pageid
             , pages.title
             , revisions.edited
             , revisions.editor
        from pages join revisions
        on pages.revision = revisions.revisionid
        order by revisions.edited desc
        limit 100))
        or die $db->errstr;
    $pst->execute() or die $pst->errstr;
    my @edits;
    while (my $row = $pst->fetchrow_hashref) {
        push @edits, $row;
    }
    return @edits;
}


### html output ###

sub show_page {
    my ($status, $title, $body) = @_;

    my $template = HTML::Template->new(filename => 'templates/main.html');
    $template->param(TITLE => $title);
    $template->param(BODY => $body);
    print $q->header("text/html; charset=utf-8", $status);
    print $template->output;
}

sub four_oh_four {
    my ($message) = @_;
    my $template = HTML::Template->new(filename => 'templates/404.html');
    $template->param(MESSAGE => $message);
    show_page "404 Not Found", "Not found", $template->output;
}


### markup rendering ###

sub handle_blocks {
    my ($lines) = @_;
    my @blocks = ();
    my @block = ();
    my $last = '';

    for (split /^/, $lines) {
        if (/^\s{4,}/) {
            # four or more spaces indicates rawtext
            if ($last ne 'code') {
                if (@block) { push @blocks, join('', @block); }
                @block = ();
                $last = 'code';
            }
            push @block, $_;
        } elsif (/^-{3,}$/) {
            # three or more dashes is a horizontal line
            if (@block) { push @blocks, join('', @block); }
            @block = ();
            $last = 'line';
            push @block, $_;
        } elsif (/^={2}/) {
            # two or more equals signs indicates a header
            if (@block) { push @blocks, join('', @block); }
            @block = ();
            $last = 'header';
            push @block, $_;
        } elsif (/^\*\s/) {
            # * is bullet list
            if ($last ne 'ul') {
                if (@block) { push @blocks, join('', @block); }
                @block = ();
                $last = 'ul';
            }
            push @block, $_;
        } elsif (/^#\s/) {
            # * is ordered list
            if ($last ne 'ol') {
                if (@block) { push @blocks, join('', @block); }
                @block = ();
                $last = 'ol';
            }
            push @block, $_;
        } elsif (/^$/) {
            # blank line separates paragraphs
            if (@block) { push @blocks, join('', @block); }
            @block = ();
            $last = '';
        } else {
            # lines are paragraphs
            if ($last ne 'p') {
                if (@block) { push @blocks, join('', @block); }
                @block = ();
                $last = 'p';
            }
            push @block, $_;
        }
    }

    if (@block) { push @blocks, join('', @block); }

    return @blocks;
}

sub render_inlines {
    my ($block) = @_;

    # avoid getting boned in exciting ways by HTML
    $block =~ s/&/&amp;/g;
    $block =~ s/</&lt;/g;
    $block =~ s/>/&gt;/g;

    # strong before em
    $block =~ s/\*\*(\w.*?\w|\w)\*\*/<strong>$1<\/strong>/gs;
    $block =~ s/\*(\w.*?\w|\w)\*/<em>$1<\/em>/gs;

    # nice quotes
    $block =~ s/(^|\s)"(\w.*?\w|\w)"(\s|$)/$1&ldquo;$2&rdquo;$3/gs;
    $block =~ s/(^|\s)'(\w.*?\w|\w)'(\w|$)/$1&lsquo;$2&rsquo;$3/gs;
    $block =~ s/'/&apos;/g;

    # links
    $block =~ s/\[\[(.+?)\|(.+?)\]\]/render_link($1, $2)/ge;
    $block =~ s/\[\[(.+?)\]\]/render_link($1)/ge;

    # images
    $block =~ s/\{\{(.+?)\|(.+?)\}\}/<img src="$1" title="$2" alt="$2" \/>/g;

    return $block;
}

sub render_link {
    my ($url, $text) = @_;

    # is it a numeric id? if so, convert to title
    if ($url =~ /^(\d+)$/) {
        if (my $title = get_title $1) {
            $text //= $title;
            return qq(<a href="$title.html" class="internal">$text</a>);
        } elsif (defined $text) {
            return qq(&#91;&#91;$url|$text&#93;&#93;);
        } else {
            return qq(&#91;&#91;$url&#93;&#93;);
        }
    } elsif ($url =~ TITLE_PATTERN) {
        $text //= $url;
        if (get_id $url) {
            return qq(<a href="$url.html" class="internal">$text</a>);
        } else {
            return qq(<a href="$url.html" class="internal broken">$text</a>);
        }
    } else {
        $text //= $url;
        return qq(<a href="$url" class="external">$text</a>);
    }
}

sub preprocess_entry {
    my ($content) = @_;

    # this should do two things: compile a list of links
    # this page makes to other pages, and rewrite links
    # appropriately.
    
    # fix newlines
    $content =~ s/\r\n|\r/\n/g;
    my @links;

    for (handle_blocks $content) {
        while (/\[\[(.+?)(\|.+?)?\]\]/g) {
            if (my $id = get_id $1) {
                push @links, $id;
            }
        }
    }

    @links = uniq(@links);
    return $content, \@links;
}

sub generate_partial {
    my ($header) = @_;
    $header =~ s/[\s]/_/g;
    $header =~ s/[^\w]//g;
    return $header;
}

sub render_entry {
    my ($content) = @_;
    my @output;
    my @sstack = (0);
    for (handle_blocks $content) {
        if (/^(={2,6})\s*(.*?)\s*(=*)\s*$/) {
            my $level = length $1;
            my $text = render_inlines $2;
            my $partial = generate_partial $2;
            while ($#sstack >= $level) {
                push @output, pop(@sstack);
            }
            push @output, qq(<section>);
            push @sstack, qq(</section>);
            push @output, qq(<h$level id="$partial">
                $text
                <a class="partial" href="#$partial">#</a>
            </h$level>);
        } elsif (/^\s{4,}/) {
            my $prefix = "<pre><code>";
            while (/^\s{4,}(.*)$/gm) {
                push @output, $prefix . $1;
                $prefix = '';
            }
            push @output, "</code></pre>";
        } elsif (/^-{3,}$/) {
            push @output, "<hr>";
        } elsif (/^\*\s/) {
            push @output, "<ul>";
            while (/^\*\s+(.*)$/gm) {
                push @output, "<li>" . render_inlines($1) . "</li>";
            }
            push @output, "</ul>";
        } elsif (/^#\s/) {
            push @output, "<ol>";
            while (/^#\s+(.*)$/gm) {
                push @output, "<li>" . render_inlines($1) . "</li>";
            }
            push @output, "</ol>";
        } elsif (/^bq(?:\(([\w\s]*)\))?\.\s+(.*)$/s) {
            push @output, qq(<blockquote class="$1">$2</blockquote>);
        } elsif (/^p(?:\(([\w\s]*)\))?\.\s+(.*)$/s) {
            push @output, qq(<p class="$1">$2</p>);
        } else {
            push @output, "<p>" . render_inlines($_) . "</p>";
        }
    }

    while ($#sstack > 1) {
        push @output, pop(@sstack);
    }

    return join "\n", @output;
}


### request handling ###

sub edit_entry {
    my ($slug) = @_;

    my $title = $slug;
    my $content = '';
    my $username = $q->cookie('username');
    my $base;
    my $id;
    my @errors;
    if (my $entry = get_entry $slug) {
        $id = $entry->{pageid};
        $title = $entry->{title};
        $content = $entry->{content};
        $base = $entry->{revision};
    }

    if ($q->request_method eq 'POST') {
        my $oldcontent = $content;
        my $oldtitle = $title;
        $base = $q->param('base');
        $username = $q->param('username');
        $content = $q->param('content');
        $title = $q->param('title');

        if ($title !~ TITLE_PATTERN) {
            # validate title format
            push @errors, { message => 
                "title must be made of letters and numbers and must begin " .
                "with a letter" };
        } elsif ($oldtitle ne $title and get_id($title)) {
            # validate duplicates
            push @errors, { message =>
                "a page with named '$title' already exists" };
        } elsif ($username !~ TITLE_PATTERN) {
            # validate username format
            push @errors, { message =>
                "a username must be made of one or more letters and numbers " .
                "and must begin with a letter" };
        } else {
            # validation passed, save and redirect
            my $fullname = $username . "@" . $q->remote_addr;
            my $cookie = CGI->cookie(
                -name => 'username',
                -value => $username);
            my ($pcontent, $links) = preprocess_entry($content);

            put_entry($id, $title, $fullname, $pcontent, $links, $base);

            my $template = HTML::Template->new(
                filename => 'templates/editok.html');
            $template->param(TITLE => $title);

            print $q->header("text/html; charset=utf-8", "200 OK"
                -cookie => $cookie);
            print $template->output;
            return;
        }
    }

    my $template = HTML::Template->new(
        filename => 'templates/edit.html',
        die_on_bad_params => 0);

    $template->param(ID => $id);
    $template->param(SLUG => $slug);
    $template->param(ERRORS => \@errors);
    $template->param(TITLE => $title);
    $template->param(BASE => $base);
    $template->param(USERNAME => $username);
    $template->param(IP => $q->remote_addr);
    $template->param(CONTENT => $content);
    show_page("200 OK", "Editing $slug", $template->output);
}

sub ref_list {
    my ($slug) = @_;

    if (my $title = get_title $slug) {
        my @links = get_links($slug);
        my $template = HTML::Template->new(
            filename => 'templates/links.html',
            die_on_bad_params => 0);
        $template->param(TITLE => $title);
        $template->param(LINKS => \@links);
        show_page("200 OK", "Links to $title", $template->output);
    } else {
        four_oh_four "No such entry '$slug'.";
    }
}

sub get_username {
    my ($editor) = @_;
    if ($editor =~ /^([^@]*)@([^@]*)$/) {
        return $1;
    }
    return $editor;
}

sub render_time {
    my ($timestamp) = @_;
    return time2str("%A the %o, %Om %Y, at %X %Z", $timestamp, TIMEZONE);
}

sub show_entry {
    my ($slug) = @_;

    if (my $page = get_entry $slug) {
        my $template = HTML::Template->new(filename => 'templates/entry.html');
        $template->param(TITLE => $page->{title});
        $template->param(CONTENT => render_entry($page->{content}));
        $template->param(USERNAME => get_username($page->{editor}));
        $template->param(EDITED => render_time($page->{edited}));
        show_page("200 OK", $page->{title}, $template->output);
    } else {
        print $q->redirect("$slug.edit");
    }
}

sub show_recent {
    my @edits = map { {
        TITLE => $_->{title},
        USERNAME => get_username($_->{editor}),
        EDITED => render_time($_->{edited}),
    } } get_edits;

    my $template = HTML::Template->new(
        filename => 'templates/recent.html',
        die_on_bad_params => 0);
    $template->param(EDITS => \@edits);
    show_page("200 OK", "Recently edited pages", $template->output);
}

sub dump_entry {
    my ($slug) = @_;

    if (my $page = get_entry $slug) {
        print $q->header("text/plain; charset=utf-8");
        print $page->{content};
    } else {
        four_oh_four
            "No such entry '$slug'. " .
            "<a href='$slug.edit'>Create it?</a>";
    }
}

$_ = (substr($q->path_info(), 1) or '1.html');
if (/^_([^\s.]*)$/) {
    if ($1 eq "recent") {
        show_recent;
    } else {
        four_oh_four "Unknown special page '$1'";
    }
} elsif (/^([^\s.]*)\.([^\s.]*)$/) {
    if ($2 eq "edit") {
        edit_entry $1;
    } elsif ($2 eq "links") {
        ref_list $1;
    } elsif ($2 eq "html") {
        show_entry $1;
    } elsif ($2 eq "txt") {
        dump_entry $1;
    } else {
        four_oh_four "Unknown mode '$2'";
    }
} elsif (TITLE_PATTERN) {
    print $q->redirect("$_.html");
} else {
    four_oh_four "Unknown page '$_'";
}

