#!/usr/bin/perl -w
# Export the configuration from a Junos Pulse Secure Access via http post
# Works on a SA-4000 7.1R4.1 (build 19525)

use strict;
use warnings;
use POSIX; # strftime
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1; # It doesn't seem to work everywhere.

my $host = $ARGV[0] || "localhost";
my $user = "admin";
my $pass = "pass";

my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , timeout       => 10
                            , show_progress => 1
                            , ssl_opts      => { verify_hostname => 0 }
                            , cookie_jar    => HTTP::Cookies->new( autosave => 1 )
                            , requests_redirectable => [ 'HEAD', 'GET', 'POST' ]
                            );

print GREEN BOLD "Logging in..." and print "\n";;
my $resp = $ua->request( POST "https://$host/dana-na/auth/url_admin/login.cgi"
                       , [ username  => $user
                         , password  => $pass
                         , realm     => 'Admin Users'
                         ]
                       );
$resp->is_success ? print $resp->status_line."\n" : print RED $resp->headers_as_string."\n";
$resp->is_success or exit 1;

if ( (my $formdatastr) = $resp->decoded_content =~ /name="FormDataStr" value="([^"]+)"/) {
    print GREEN BOLD "Account already logged, trying read-only access..." and print "\n";;
    print YELLOW "FormDataStr: $formdatastr" and print "\n";
    $resp = $ua->request( POST "https://$host/dana-na/auth/url_admin/login.cgi"
                        , [ FormDataStr => $formdatastr
                          , btnReadOnly => 'Continue the session with read-only access'
                          ]
                        );
    $resp->is_success ? print $resp->status_line."\n" : print RED $resp->headers_as_string."\n";
    $resp->is_success or exit 1;
}

print GREEN BOLD "Fetching the configuration..." and print "\n";;
$resp = $ua->request( POST "https://$host/dana-admin/download/system.cfg?url=/dana-admin/cached/config/export.cgi"
                    , [ op        => 'Export'
                      , type      => 'system'
                      , btnDnload => 'Save Config As...'
                      ]
                    );
$resp->is_success ? print $resp->status_line."\n" : print RED $resp->headers_as_string."\n";
$resp->is_success or exit 1;

print GREEN BOLD "Got it, ".length($resp->decoded_content)." bytes\n";
my $filename = "${host}-".strftime("%Y%m%d-%H%M%S", localtime).".cfg";
open(FH, ">", $filename) or die $!;
print FH $resp->decoded_content;
print BOLD "Written to: $filename\n";
close(FH);
