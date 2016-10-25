#!/usr/bin/perl
# Shows or adds plone tags (removing the current ones if any)
# usage script.pl <document/s url/s> -t <Tagname>
# multiple -t flags can be used

use strict;
use warnings;
use LWP::UserAgent;
use HTML::Entities;  # decode_entities
use HTTP::Cookies;   # Cuquis
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Data::Dumper;
$Term::ANSIColor::AUTORESET = 1;

die RED "No url/s.\n" unless @ARGV;

my $host = $ARGV[0];
$host =~ s/^http:\/\///ig;
$host =~ s/\/.*//g;
my $username   = "XXXXXX";
my $password   = "XXXXXX";
my $cookie_jar = HTTP::Cookies->new( autosave => 1 );
my @tags       = ();
my $post       = "form.submitted=1";

GetOptions ('tags=s' => \@tags);

map { $post .= "&subject_existing_keywords:list=$_" } @tags;

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

print GREEN "Getting cookie from http://$host\n";
&http( "http://$host/login_form"
     , 'POST'
     , "form.submitted=1&__ac_name=$username&__ac_password=$password"
     );

unless ($cookie_jar->{'COOKIES'}->{"$host"}->{'/'}->{'__ac'}->[1]) {
    print RED "Got no cookie, check \$username and \$password.\n";
    exit 1;
}

foreach my $page (@ARGV) {
    unless (@tags) {
        print "$page\n";
        my $resp = &http("$page");
        if (ref($resp) eq "HTTP::Response" and $resp->is_success) {
            my $page = $resp->decoded_content;
            while ($page =~ /rel="tag">([^<]+)<\/a>/gs) {
                print YELLOW BOLD "\t$1\n";
            }
        } else {
            print RED BOLD $resp->status_line."\n";
        }
    } else {
        print "Tagging '";
        print BLUE "$page";
        print "' with ";
        print YELLOW BOLD join (', ', @tags);
        print " ... ";
        print RED "$post\n";
        my $resp = &http("$page/atct_edit", 'POST', $post);
        if (ref($resp) eq "HTTP::Response" and $resp->is_success) {
            print GREEN BOLD "OK\n";
            print Dumper $resp;
        } else {
            print RED BOLD $resp->status_line."\n";
        }
    }
}
exit 0;
