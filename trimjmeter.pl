#!/usr/bin/perl
# Trim a jmeter logfile keeping the last month entries.
# The first field must be the jmeter time (milliseconds since the epoch).
use strict;
use warnings;
use diagnostics;
use Scalar::Util qw(looks_like_number);

my $epoch = time();
local $^I = ''; # http://docstore.mik.ua/orelly/perl/cookbook/ch07_10.htm
while (<ARGV>) {
    my @fields = split(';', $_);
    print and next unless looks_like_number($fields[0]); # Keep the garbage.
    print if int($epoch-substr($fields[0], 0, 10)) lt 13140000;
}
