#!/usr/bin/perl -w
# Let's spam the ncdc chat with bad musical taste (plex version);

use strict;
use warnings;
use utf8;
use Encode;
use LWP::UserAgent;

my $host = 'plex_server';
my $user = 'user';
my $pass = 'pass';

my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , timeout       => 10
                            , show_progress => 0
                            , ssl_opts      => { verify_hostname => 0 }
                            );

$ua->default_header('X-Plex-Client-Identifier' => $0);
my $req = HTTP::Request->new(POST => 'https://my.plexapp.com/users/sign_in.xml');
$req->authorization_basic($user, $pass);
my $resp = $ua->request($req);
$resp->is_success or exit 1;
my $token = $1 if $resp->decoded_content =~ /<authentication-token>([^<]+)</;
exit 1 unless $token;
$req = HTTP::Request->new(GET => "http://$host:32400/status/sessions?X-Plex-Token=$token");
$resp = $ua->request($req);
my $content = encode('utf-8', $resp->decoded_content);

while ( $content =~ /<Track (.+?)>/g ) {
    my $track = $1;
    my %hash = ();
    $hash{$1} = $2 while $track =~ / ([^=]+)="([^"]+)"/g;
    if ( $hash{type} eq 'track' ) {
        my $line = sprintf( "/me listening to: '%.2d - %s' from the album '%s' <%.2d:%.2d/%.2d:%.2d(%d%%)>\n"
                          , $hash{index}
                          , $hash{title}
                          , $hash{parentTitle}
                          , ( $hash{viewOffset}/1000 )/60%60
                          , ( $hash{viewOffset}/1000 )%60
                          , ( $hash{duration}/1000 )/60%60
                          , ( $hash{duration}/1000 )%60
                          , ( $hash{viewOffset}*100 ) / $hash{duration}
                          );
        print STDERR $line;
        `tmux send-keys -t ncdc "\r${line}\n" 2>/dev/null`;
        last;
    }
}
