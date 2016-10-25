#!/usr/bin/perl -w
use strict;
use Net::SSH2;

my $ssh2 = Net::SSH2->new();
$ssh2->debug(0);
$ssh2->connect('host') or die "Unable to connect host $@\n";
$ssh2->auth_password('user', 'password') or die "Unable to login $@\n";
my $chan2 = $ssh2->channel();
$chan2->shell();
print $chan2 "uname -a\n";
print "LINE : $_" while <$chan2>;
$chan2->close;
