package V::Format::TimeAgo;

use 5.018;
use strict;
use warnings;
use diagnostics;
use lib '.';

use Exporter 'import';
our @EXPORT = qw(format_time_ago);
our @EXPORT_OK = qw(format_unit);

use constant PER_SECOND =>   1;
use constant PER_MINUTE =>  60 * PER_SECOND;
use constant PER_HOUR   =>  60 * PER_MINUTE;
use constant PER_DAY    =>  24 * PER_HOUR;
use constant PER_WEEK   =>   7 * PER_DAY;
use constant PER_MONTH  =>  30 * PER_DAY;
use constant PER_YEAR   => 365 * PER_DAY;

sub format_unit {
    my ($value, $singular, $plural) = @_;
    if ($value == 1) {
        return "$value $singular";
    } else {
        return "$value $plural";
    }
}

sub format_time_ago {
    my ($timestamp) = @_;
    my $interval = time - $timestamp;
    if ($interval < PER_MINUTE) {
        return format_unit(int $interval / PER_SECOND, "second", "seconds");
    } elsif ($interval < PER_HOUR) {
        return format_unit(int $interval / PER_MINUTE, "minute", "minutes");
    } elsif ($interval < PER_DAY) {
        return format_unit(int $interval / PER_HOUR, "hour", "hours");
    } elsif ($interval < PER_WEEK) {
        return format_unit(int $interval / PER_DAY, "day", "days");
    } elsif ($interval < PER_MONTH) {
        return format_unit(int $interval / PER_WEEK, "week", "weeks");
    } elsif ($interval < PER_YEAR) {
        return format_unit(int $interval / PER_MONTH, "month", "months");
    } else {
        return format_unit(int $interval / PER_YEAR, "year", "years");
    }
}

1;
