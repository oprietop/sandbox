#!/usr/bin/perl -w
# Sanitize/Cleanup of delicious tags.
# http://delicious.com/developers

use strict;
use warnings;
use LWP::UserAgent;

my $user = "xxxxxx";
my $pass = "xxxxxx";
my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , show_progress => 1
                            , timeout       => 5
                            );

sub request ($$) {
    my $method = shift || 'get';
    my $args   = shift || '';;
    my $req = HTTP::Request->new(GET => "https://api.del.icio.us/v1/tags/$method?$args");
    $req->authorization_basic($user, $pass);
    my $resp = $ua->request($req);
    $resp->is_success ? return $resp->content : die $resp->status_line."\n";
}

print "Fetching taglist.\n";
my $taglist = &request();

print "Splitting spaced tags.\n";
while ($taglist =~ /<tag count="(\d+)" tag="([^"]+)"/sg) {
    my ($count, $tag) = ($1, $2);
    if ($tag =~ /\s/) {
        my $old = my $new = $tag;
        $old =~ s/\s+/\+/g;
        $new =~ s/\s+/,/g;
        print "($count) '$tag' -> '$new' ";
        my $response = &request('rename', "old=$old&new=$new");
        $response =~ /done/ ? print "OK!\n" : die "NOK! The response was '$response'\n";
        sleep(3); # Avoid hammering the site.
    }
}
