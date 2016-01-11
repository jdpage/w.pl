#!/usr/bin/perl -T

use 5.018;
use strict;
use warnings;
use diagnostics;

use Test::More tests => 23;

use V::Format::TimeAgo qw(format_unit format_time_ago);


is(format_unit(0, "cat", "cats"), "0 cats");
is(format_unit(1, "cat", "cats"), "1 cat");
is(format_unit(7, "cat", "cats"), "7 cats");


is(format_time_ago(time), "0 seconds");
is(format_time_ago(time - 1), "1 second");
is(format_time_ago(time - 20), "20 seconds");

is(format_time_ago(time - 60), "1 minute");
is(format_time_ago(time - 61), "1 minute");
is(format_time_ago(time - 120), "2 minutes");

is(format_time_ago(time - 3600), "1 hour");
is(format_time_ago(time - 8000), "2 hours");

is(format_time_ago(time - 100000), "1 day");
is(format_time_ago(time - 200000), "2 days");
is(format_time_ago(time - 604799), "6 days");

is(format_time_ago(time - 604800), "1 week");
is(format_time_ago(time - 700000), "1 week");
is(format_time_ago(time - 1400000), "2 weeks");
is(format_time_ago(time - 2591999), "4 weeks");

is(format_time_ago(time - 2592000), "1 month");
is(format_time_ago(time - 3000000), "1 month");
is(format_time_ago(time - 6000000), "2 months");

is(format_time_ago(time - 32000000), "1 year");
is(format_time_ago(time - 64000000), "2 years");
