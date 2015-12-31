package M::Render;

use 5.018;
use strict;
use warnings;
use diagnostics;
use lib '.';

use M::Const;

use CGI;
use Date::Format;
use Digest::MD5 qw(md5_hex);
use HTML::Template;
use List::MoreUtils qw(uniq);
use Scalar::Util 'blessed';

use constant PER_SECOND => 1;
use constant PER_MINUTE => 60 * PER_SECOND;
use constant PER_HOUR => 60 * PER_MINUTE;
use constant PER_DAY => 24 * PER_HOUR;
use constant PER_WEEK => 7 * PER_DAY;
use constant PER_MONTH => 30 * PER_DAY;
use constant PER_YEAR => 365 * PER_DAY;

sub new {
    my ($class, %args) = @_;
    my $q = CGI->new;
    return bless({
        q => $q,
        db => $args{database},
        site_root => $args{site_root},
        timezone => $args{timezone},
    }, $class);
}

sub q {
    my ($self) = @_;
    return $self->{q};
}

### html templating ###

sub show_page {
    my ($self, $status, $title, $body) = @_;

    my $template = HTML::Template->new(
        filename => 'templates/main.html',
        die_on_bad_params => 0);
    $template->param(TITLE => $title);
    $template->param(SITE_ROOT => $self->{site_root});
    $template->param(BODY => $body);
    print $self->q->header("text/html; charset=utf-8", $status);
    print $template->output;
}

sub four_oh_four {
    my ($self, $message) = @_;
    my $template = HTML::Template->new(
        filename => 'templates/404.html',
        die_on_bad_params => 0);
    $template->param(SITE_ROOT => $self->{site_root});
    $template->param(MESSAGE => $message);
    $self->show_page("404 Not Found", "Not found", $template->output);
}


### markup rendering ###

sub handle_blocks {
    my ($self, $lines) = @_;
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
        } elsif (/^#{2}/) {
            # two or more hash signs indicates a header
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

sub escape_html {
    my ($self, $block) = @_;

    # avoid getting boned in exciting ways by HTML
    $block =~ s/&/&amp;/g;
    $block =~ s/</&lt;/g;
    $block =~ s/>/&gt;/g;

    return $block;
}

sub hash_inline {
    my ($self, $inlines, $text) = @_;
    my $hash = md5_hex($text);
    $inlines->{$hash} = $text;
    return qq([[inline:$hash]]);
}

sub render_inlines {
    my ($self, $block) = @_;

    $block = $self->escape_html($block);

    # some things need to be taken out entirely before rendering is done.
    my %inlines;

    # save off the <code> stuff so it doesn't get mangled
    $block =~ s/`([^\s](?:.*?[^\s])?)`/
        $self->hash_inline(\%inlines, "<code>$1<\/code>")
    /gse;

    # save off MathJAX stuff too
    $block =~ s/\$\$(.*?)\$\$/$self->hash_inline(\%inlines, "\$\$$1\$\$")/gse;
    $block =~ s/\\\[(.*?)\\\]/$self->hash_inline(\%inlines, "\\[$1\\]")/gse;
    $block =~ s/\\\((.*?)\\\)/$self->hash_inline(\%inlines, "\\($1\\)")/gse;

    # nice dashes
    $block =~ s/--/&mdash;/g;
    $block =~ s/(^|\s)-(\s|$)/$1&ndash;$2/g;

    # strong before em
    $block =~ s/\*\*([^\s](?:.*?[^\s])?)\*\*/<strong>$1<\/strong>/gs;
    $block =~ s/\*([^\s](?:.*?[^\s])?)\*/<em>$1<\/em>/gs;

    # nice quotes
    $block =~ s/(^|\s)"([^\s](?:.*?[^\s])?)"(\s|$)/$1&ldquo;$2&rdquo;$3/gs;
    $block =~ s/(^|\s)'([^\s](?:.*?[^\s])?)'(\s|$)/$1&lsquo;$2&rsquo;$3/gs;
    $block =~ s/'/&apos;/g;

    # times symbol
    $block =~ s/(\d\s*)[xX](\s*\d)/$1&times;$2/gs;

    # ellipses
    $block =~ s/\.{3}/&#8230;/g;

    # TM, C, R
    $block =~ s/(^|\s)\(TM\)(\s|$)/$1&#8482;$2/gi;
    $block =~ s/(^|\s)\(C\)(\s|$)/$1&#169;$2/gi;
    $block =~ s/(^|\s)\(R\)(\s|$)/$1&#174;$2/gi;

    # images
    $block =~ s/\{\{(.+?)\|(.+?)\}\}/<img src="$1" title="$2" alt="$2" \/>/g;

    # links
    $block =~ s/\[\[(.+?)(?:\|(.+?))?\]\]/$self->render_link($1, $2)/ge;

    # re-insert inlines
    $block =~ s/\[\[inline:(.*?)\]\]/$inlines{$1}/ge;

    return $block;
}

sub render_link {
    my ($self, $url, $text) = @_;

    if ($url =~ /^(\d+)$/) {
        # is it a numeric id? if so, convert to title
        if (my $title = $self->{db}->get_title($1)) {
            $text //= $title;
            return qq(<a href=") . $self->{site_root} .
                qq(/w/$title.html" class="internal">$text</a>);
        } elsif (defined $text) {
            return qq(&#91;&#91;$url|$text&#93;&#93;);
        } else {
            return qq(&#91;&#91;$url&#93;&#93;);
        }
    } elsif ($url =~ TITLE_PATTERN) {
        # if it's a textual title, determine if it's broken or not
        $text //= $url;
        if ($self->{db}->get_id($url)) {
            return qq(<a href=") . $self->{site_root} .
                qq(/w/$url.html" class="internal">$text</a>);
        } else {
            return qq(<a href=") . $self->{site_root} .
                qq(/w/$url.html" class="internal broken">$text</a>);
        }
    } elsif ($url =~ /^inline:(.*)$/) {
        # a hashed inline; just pass it through
        return qq([[$url]]);
    } elsif ($url =~ /^user:(.*?)(?:!(.*))?$/) {
        if (defined $2) {
            return $self->render_link("User/$1", qq($1<img src="http://gravatar.com/avatar/$2?s=16&d=retro&f=y" alt="$1" class="tripicon" />));
        } else {
            return $self->render_link("User/$1", $1);
        }
    } elsif ($url =~ /^date:(\d+)$/) {
        # auto-render a date
        return $self->render_time($1);
    } elsif ($url =~ /^doi:(.*)$/) {
        # auto-render a DOI
        $text //= $url;
        return qq(<a href="http://doi.org/$1" rel="nofollow" 
                     class="external doi">$text</a>);
    } elsif ($url =~ /^mailto:(.*)$/) {
        # email address
        return qq(<a href="$url">$1</a>);
    } else {
        # just output it
        $text //= $url;
        return qq(<a rel="nofollow" href="$url" class="external">$text</a>);
    }
}

sub preprocess_link {
    my ($self, $url, $text) = @_;

    # is it a named title?
    if ($url =~ TITLE_PATTERN and my $id = $self->{db}->get_id($url)) {
        # rewrite that
        $text //= $url;
        return qq([[$id|$text]]);
    } elsif ($url =~ /^date::now$/) {
        return '[[date:' . time . ']]';
    } else {
        # pass through
        if (defined $text) {
            return qq([[$url|$text]]);
        } else {
            return qq([[$url]]);
        }
    }
}

sub generate_signature {
    my ($self, $username) = @_;
    my $time = time;

    return qq(--[[user:$username]], [[date:$time]]);
}

sub preprocess_entry {
    my ($self, $content, $username) = @_;

    # this should do two things: compile a list of links
    # this page makes to other pages, and rewrite links
    # appropriately.
    
    # fix newlines
    $content =~ s/\r\n|\r/\n/g;
    my @links;
    my @blocks;

    for ($self->handle_blocks($content)) {
        while (/\[\[(.+?)(\|.+?)?\]\]/g) {
            if (my $id = $self->{db}->get_id($1)) {
                push @links, $id;
            }
        }
        if (!/^\s{4,}/) {
            s/\[\[(.+?)(?:\|(.+?))?\]\]/$self->preprocess_link($1, $2)/ge;
            s/~~~~/$self->generate_signature($username)/ge;
        }
        push @blocks, $_;
    }

    @links = uniq(@links);
    return join("\n", @blocks), \@links;
}

sub generate_partial {
    my ($self, $header) = @_;
    $header =~ s/[\s]/_/g;
    $header =~ s/[^\w]//g;
    return $header;
}

sub render_username {
    my ($self, $editor) = @_;
    if ($editor =~ /^([^@]*)@([^@]*)$/) {
        return $self->render_link("user:$1");
    }
    return $self->render_link($editor);
}

sub pick {
    my ($self, $value, $singular, $plural) = @_;
    if ($value == 1) {
        return $singular;
    } else {
        return $plural;
    }
}

sub render_fuzzy_time {
    my ($self, $timestamp) = @_;
    my $interval = time - $timestamp;
    if ($interval < PER_MINUTE) {
        my $seconds = $interval / PER_SECOND;
        return $seconds . " " . $self->pick($seconds, "second", "seconds");
    } elsif ($interval < PER_HOUR) {
        my $minutes = int $interval / PER_MINUTE;
        return $minutes . " " . $self->pick($minutes, "minute", "minutes");
    } elsif ($interval < PER_DAY) {
        my $hours = int $interval / PER_HOUR;
        return $hours . " " . $self->pick($hours, "hour", "hours");
    } elsif ($interval < PER_WEEK) {
        my $days = int $interval / PER_DAY;
        return $days . " " . $self->pick($days, "day", "days");
    } elsif ($interval < PER_MONTH) {
        my $weeks = int $interval / PER_WEEK;
        return $weeks . " " . $self->pick($weeks, "week", "weeks");
    } elsif ($interval < PER_YEAR) {
        my $months = int $interval / PER_MONTH;
        return $months . " " . $self->pick($months, "month", "months");
    } else {
        my $years = int $interval / PER_YEAR;
        return $years . " " . $self->pick($years, "year", "years");
    }
}

sub render_time {
    my ($self, $timestamp) = @_;
    my $long = time2str("on %A the %o, %Om %Y, at %X %Z",
        $timestamp, $self->{timezone});
    my $short = $self->render_fuzzy_time($timestamp);
    return qq(<span title="$long">$short ago</span>);
}


sub render_entry {
    my ($self, $content) = @_;
    my @output;
    my @sstack; while ($#sstack < 1) { push @sstack, 0; }

    for ($self->handle_blocks($content)) {
        if (/^(#{2,6})\s*(.*)$/) {
            my $level = length $1;
            my $text = $self->render_inlines($2);
            my $partial = $self->generate_partial($2);
            while ($#sstack >= $level) {
                push @output, pop(@sstack);
            }
            while ($#sstack < $level) {
                push @sstack, qq(</section>);
                push @output, qq(<section>);
            }
            push @output, qq(<h$level id="$partial">
                $text
                <a class="partial" href="#$partial">#</a>
            </h$level>);
        } elsif (/^\s{4,}/) {
            my $prefix = "<pre><code>";
            while (/^\s{4,}(.*)$/gm) {
                push @output, $prefix . $self->escape_html($1);
                $prefix = '';
            }
            push @output, "</code></pre>";
        } elsif (/^-{3,}$/) {
            push @output, "<hr>";
        } elsif (/^\*\s/) {
            push @output, "<ul>";
            while (/^\*\s+(.*)$/gm) {
                push @output, "<li>" . $self->render_inlines($1) . "</li>";
            }
            push @output, "</ul>";
        } elsif (/^#\s/) {
            push @output, "<ol>";
            while (/^#\s+(.*)$/gm) {
                push @output, "<li>" . $self->render_inlines($1) . "</li>";
            }
            push @output, "</ol>";
        } elsif (/^bq(?:\(([\w\s]*)\))?\.\s+(.*)$/s) {
            push @output, qq(<blockquote class=") . $self->escape_html($1) .
                qq(">) . $self->render_inlines($2) . qq(</blockquote>);
        } elsif (/^p(?:\(([\w\s]*)\))?\.\s+(.*)$/s) {
            push @output, qq(<p class=") . $self->escape_html($1) . qq(">) .
                $self->render_inlines($2) . qq(</p>);
        } else {
            push @output, "<p>" . $self->render_inlines($_) . "</p>";
        }
    }

    while ($#sstack > 1) {
        push @output, pop(@sstack);
    }

    return join "\n", @output;
}


1;
