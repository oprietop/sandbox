#!/usr/bin/perl
# Shows and updates a plone document to the current localtime.
# usage script.pl <url/s> -u

use strict;
use warnings;
use LWP::UserAgent;
use HTML::Entities; # decode_entities
use HTTP::Cookies;  # Cuquis
use Getopt::Long;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

die RED "No url/s.\n" unless @ARGV;

my $host = $ARGV[0];
$host =~ s/^http:\/\///ig;
$host =~ s/\/.*//g;
my $username   = "XXXXXX";
my $password   = "XXXXXX";
my $cookie_jar = HTTP::Cookies->new( autosave => 1 );
my $update     = 0;

GetOptions ('update|u' => \$update);

sub http($$$) {
    my $url     = shift || return 0;
    my $method  = shift || "GET";
    my $content = shift || 0;
    my $referer = shift || '127.0.0.1';
    my $ua = LWP::UserAgent->new;   # User Agent creation
    push @{ $ua->requests_redirectable }, 'POST' if $method =~ /post/i;
    $ua->agent('Mozilla/5.0');      # IMMAFAKE
    $ua->cookie_jar( $cookie_jar ); # We should have a jar somewhere
    my $req = HTTP::Request->new($method => $url); # Create a request
    $req->content_type('application/x-www-form-urlencoded');
    $req->referer($referer);
    $req->content($content) if $content;
    return $ua->request($req);   # Pass request to the User Agent and get a response back

}

sub date($) {
    my $resp = shift;
    if (ref($resp) eq "HTTP::Response" and $resp->is_success) {
        my $page = $resp->decoded_content;
        if ($page =~ /documentModified">.+?(\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}).+?class/s) {
            return $1;
        }
    }
    return 0;
}

print GREEN "Getting cookie from http://$host\n";
&http( "http://$host/login_form"
     , 'POST'
     , "form.submitted=1&__ac_name=$username&__ac_password=$password"
     );

unless ($cookie_jar->{'COOKIES'}->{"$host"}->{'/'}->{'__ac'}->[1]) {
    print BOLD RED "Got no cookie, check \$username and \$password.\n";
    exit 1;
}

foreach my $page (@ARGV) {
    print "$page";
    my $resp = &http("$page");
    my $doc_date = &date($resp);
    print BOLD RED " Error getting the original date." and next unless $doc_date;
    print YELLOW " $doc_date";
    if ($update) {
        &http("$page/content_status_modify", 'POST', 'workflow_action=reject');
        my $current_date = &date(&http("$page/content_status_modify", 'POST', 'workflow_action=publish_internally'));
        print RED " Error getting the new published date." and next unless $current_date;
        $doc_date ne $current_date ? print BOLD YELLOW " -> $current_date" : print BOLD RED " Error, date didn't change."
    }
    print "\n";
}
exit 0;
