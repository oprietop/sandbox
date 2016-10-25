#!/usr/bin/perl

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request::Common;

my $ua = LWP::UserAgent->new;
$ua->cookie_jar(HTTP::Cookies->new());
my $response = $ua->request(POST 'http://localhost', [l => 'login', p => 'password']);
$response->content =~ /s=(\w+)/;
$response->is_success ? print "$1\n" : print $response->status_line
