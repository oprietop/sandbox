#!/usr/bin/perl -w
use strict;
use Net::SSH::Perl;

my $ssh = Net::SSH::Perl->new( 'hostname'
                             , protocol => 2
                             , port     => 22
                             , debug    => 1
                             );
$ssh->login('user', 'password');
my($stdout, $stderr, $exit) = $ssh->cmd("uname -a");
print "$stdout\n";
