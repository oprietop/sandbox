#!/usr/bin/perl
# Let's spam the ncdc chat with bad musical taste.

use strict;
use warnings;
use utf8;
use Encode;
use LWP::UserAgent;
use HTTP::Request::Common;

my $host = "192.168.1.7:8180";
my $user = "user";
my $pass = "pass";

my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , timeout       => 10
                            , show_progress => 0
                            , ssl_opts      => { verify_hostname => 0 }
                            , requests_redirectable => [ 'HEAD', 'GET', 'POST' ]
                            );

my $resp = $ua->request( GET "http://$host/subsonic/rest/getNowPlaying.view?u=$user&p=$pass&v=1.12.0&c=perl" );
$resp->is_success or exit 1;
my $content = encode('utf-8', $resp->decoded_content);

while ( $content =~ /<entry (.+?)\/>/g ) {
    my $entry = $1;
    my %hash = ();
    $hash{$1} = $2 while $entry =~ / ([^=]+)="([^"]+)"/g;
    if ( $hash{username} eq $user ) {
        my $line = sprintf( "/me listening to: '%.2d - %s' from the album '%s'\n"
                          , $hash{track}
                          , $hash{title}
                          , $hash{album}
                          );
        print STDERR $line;
        `tmux send-keys -t ncdc "\r${line}\n" 2>/dev/null`;
        last;
    }
}

