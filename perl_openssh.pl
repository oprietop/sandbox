#!/usr/bin/perl
use strict;
use Net::OpenSSH;
# $Net::OpenSSH::debug |= 16; # Debug

my $ssh = Net::OpenSSH->new('user:password@host');
my ($out, $err) = $ssh->capture2('uname -a');
# my @out = $ssh->capture('uname -a'); # Output as array
print "OUT:\n$out\n";
print "ERR:\n$err\n";
