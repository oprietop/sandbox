#!/usr/bin/perl
use Net::IMAP::Simple;

$server = new Net::IMAP::Simple('hostname');
$server->login('username', 'password');
my @mailboxes = $server->mailboxes;
print "Got ".($#mailboxes+1)." mailboxes.\n";
@mailboxes or exit 2;
