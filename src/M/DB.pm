package M::DB;

use 5.018;
use strict;
use warnings;
use diagnostics;

use Scalar::Util 'blessed';
use DBI;

sub new {
    my ($class, $conn) = @_;
    my $db = DBI->connect("DBI:SQLite:dbname=$conn") or die $DBI::errstr;
    return bless({ db => $db }, $class);
}

sub get_entry {
    my ($self, $title, $on) = @_;

    my $stmt = q(
        select pages.pageid
             , pages.title
             , revisions.revisionid
             , revisions.edited
             , revisions.editor
             , revisions.content
        from revisions join pages
        on revisions.page = pages.pageid);

    if ($title =~ /^(\d+)$/) {
        $stmt .= q(
            where pages.pageid = ?);
    } else {
        $stmt .= q(
            where pages.title = ?);
    }
    if (defined $on) {
        $stmt .= q(
            and revisions.edited <= ?);
    }
    $stmt .= q(
        order by revisions.edited desc
        limit 1);
    my $pst = $self->{db}->prepare($stmt) or die $self->{db}->errstr;
    if (defined $on) {
        $pst->execute($title, $on) or die $pst->errstr;
    } else {
        $pst->execute($title) or die $pst->errstr;
    }
    return $pst->fetchrow_hashref;
}

sub put_entry {
    my ($self, $id, $title, $username, $content, $links, $base) = @_;

    # update page entry
    my $pagep = $self->{db}->prepare(
        q(insert or replace into pages values(?, ?)))
        or die $self->{db}->errstr;
    $pagep->execute($id, $title) or die $pagep->errstr;
    my $pageid = $self->{db}->sqlite_last_insert_rowid;

    # insert new revision
    my $revp = $self->{db}->prepare(
        q(insert into revisions values(NULL, ?, ?, ?, ?)))
        or die $self->{db}->errstr;
    $revp->execute(time, $username, $content, $pageid) or die $revp->errstr;
    my $revid = $self->{db}->sqlite_last_insert_rowid;

    # remove all links from this page
    my $dlp = $self->{db}->prepare(q(delete from links where page = ?))
        or die $self->{db}->errstr;
    $dlp->execute($pageid) or die $dlp->errstr;

    # add links from this page
    my $ilp = $self->{db}->prepare(q(insert into links values(?, ?)))
        or die $self->{db}->errstr;
    for my $link (@{$links}) {
        $ilp->execute($pageid, $link) or die $ilp->errstr;
    }
}

sub get_all_pages {
    my ($self) = @_;
    my $pst = $self->{db}->prepare(q(select * from pages order by pageid))
        or die $self->{db}->errstr;
    $pst->execute() or die $pst->errstr;
    my @pages;
    while (my $row = $pst->fetchrow_hashref) {
        push @pages, $row;
    }
    return @pages;
}

sub get_id {
    my ($self, $title) = @_;
    if ($title =~ /^(\d+)$/) {
        return $title;
    }

    my $pst = $self->{db}->prepare(q(
        select pageid from pages
        where title = ?
        limit 1))
        or die $self->{db}->errstr;
    $pst->execute($title) or die $pst->errstr;
    my $row = $pst->fetchrow_hashref;
    return $row->{pageid};
}

sub get_title {
    my ($self, $id) = @_;
    $id = $self->get_id($id);
    my $pst = $self->{db}->prepare(q(
        select title from pages
        where pageid = ?
        limit 1))
        or die $self->{db}->errstr;
    $pst->execute($id) or die $pst->errstr;
    my $row = $pst->fetchrow_hashref;
    return $row->{title};
}

sub get_links {
    my ($self, $title) = @_;
    my $id = $self->get_id($title);
    my $pst = $self->{db}->prepare(q(
        select pages.*
        from links join pages
        on links.page = pages.pageid
        where target = ?
        order by pages.title))
        or die $self->{db}->errstr;
    $pst->execute($id) or die $pst->errstr;
    my @links;
    while (my $row = $pst->fetchrow_hashref) {
        push @links, $row;
    }
    return @links;
}

sub get_all_edits {
    my ($self) = @_;
    my $pst = $self->{db}->prepare(q(
        select pages.pageid
             , pages.title
             , revisions.edited
             , revisions.editor
        from revisions join pages
        on revisions.page = pages.pageid
        order by revisions.edited desc
        limit 100))
        or die $self->{db}->errstr;
    $pst->execute() or die $pst->errstr;
    my @edits;
    while (my $row = $pst->fetchrow_hashref) {
        push @edits, $row;
    }
    return @edits;
}

sub get_edits {
    my ($self, $slug) = @_;
    my $id = $self->get_id($slug);
    my $pst = $self->{db}->prepare(q(
        select revisions.edited
             , revisions.editor
        from revisions join pages
        on revisions.page = pages.pageid
        where pages.pageid = ?
        order by revisions.edited desc
        limit 100))
        or die $self->{db}->errstr;
    $pst->execute($id) or die $pst->errstr;
    my @edits;
    while (my $row = $pst->fetchrow_hashref) {
        push @edits, $row;
    }
    return @edits;
}

1;
