#!/usr/bin/perl
# Print short tiny url with a says-it.com xbox achievement

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
my ($upper, $lower);
print "Upper Text: " and chomp($upper = <>) while not $upper;
print 'Lower Text: ' and chomp($lower = <>) while not $lower;
my $ua = LWP::UserAgent->new;
my $url = "http://www.says-it.com/scripts/achievement-xbox.pl?text1=$upper&text2=$lower&emblem=";
my $resp = $ua->request( GET "http://tinyurl.com/api-create.php?url=$url");
$resp->is_success ? print $resp->content."\n" : print $resp->headers_as_string."\n";
