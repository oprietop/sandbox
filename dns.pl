#!/usr/bin/perl -w

use strict;
use warnings;
use Socket;

my $iaddr = inet_aton("127.1");
my $result = gethostbyaddr($iaddr, AF_INET);
print "$result\n";
print inet_ntoa($iaddr);
