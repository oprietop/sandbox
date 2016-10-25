#!/usr/bin/perl
# Query http a nagios a servicios con problemas.
# Se puede consultar un host concreto pasándolo como argumento.

use strict;
use warnings;
use LWP::UserAgent;
use HTML::Entities;     # decode_entities
use Term::ANSIColor;
use Getopt::Long;
use Data::Dumper;

my $nagios   = "http://127.0.0.1/nagios";
my $username = "admin";
my $password = "password";

my %colors = ( OK       => 'green'
             , WARNING  => 'yellow'
             , UNKNOWN  => 'magenta' # ANSI hates orange.
             , CRITICAL => 'red'
             );
my $colorkeys  = join("|", keys %colors);

my $reschedule = 0;
my $debug      = 0;
GetOptions ( 'reschedule' => \$reschedule
           , 'debug'      => \$debug
           );

sub http($$$) {
    my $url     = shift || return 0;
    my $method  = shift || "GET";
    my $content = shift || 0;
    my $ua = LWP::UserAgent->new;
    $ua->agent('Mozilla/5.0');
    my $req = HTTP::Request->new($method => $url);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content($content) if $content;
    $req->authorization_basic($username, $password) if $password;
    my $res = $ua->request($req);
    $res->is_success ? return $res : return $res->status_line
}

sub swrite {
    my $format = shift;
    $^A = "";                  # El acumulador ha de estar vacío en cada iteración.
    formline($format,@_);      # http://perldoc.perl.org/functions/formline.html
    $^A =~ s/^[\s+\|]+\n+//mg; # Eliminamos líneas sin infomación.
    return $^A;
}

$ARGV[0] and $ARGV[0] =~ s/\W//g;                  # Sanitizamos 1er argumento si existe.
my $arg = $ARGV[0] || "all&servicestatustypes=28"; # No he mirado el resto de servicestatustypes.

my $response = &http("$nagios/cgi-bin/status.cgi?host=$arg");
print Dumper $response if $debug;
my $page = decode_entities($response->decoded_content);
die "$page\n" if $page =~ /^\d{3}/;

$page =~ s/<td><\/td>/^/ig; # No me interesa tener celdas vacías...
$page =~ s/<[^>]+?>//g;     # para no cargármelas aquí.
$page =~ s/^\s*\n+//mg;     # Fuera whitelines.

my $firstloop = 0; # Para mostrar el header una vez.
my $host = undef;  # Para tener siempre el hostname en cada iteración.
while ($page =~ /([^\n]+)\n([^\n]+)\n((?:$colorkeys))\n([^\n]+)\n([^\n]+)\n(\d+\/\d+)\n([^\n]+)\n/gs) {
    my ($one, $two, $three, $four, $five, $six, $seven) = ($1, $2, $3, $4, $5, $6, $7);
    if ($reschedule) {
        $host = $one unless $one eq '^';
        my $service = $two;
        $service =~ s/\s/+/g; # Fuera espacios
        my $response = &http( "$nagios/cgi-bin/cmd.cgi"
                            , 'POST'
                            , "cmd_typ=7&cmd_mod=2&host=${host}&service=${service}&start_time=31-12-1979+23%3A59%3A59&force_check=on&btnSubmit=Commit"
                            );
        print Dumper $response if $debug;
    }
    not $firstloop++ and print colored (<<'__EOF__', 'green');
Host              Service                  Since             Nº    Description
                |---------------------------------------------------------------------------------------|
__EOF__
    my $output = swrite(<<'__EOF__', $one, $two, $five, $six, $seven, $response->status_line);
^<<<<<<<<<<<<<< | ^<<<<<<<<<<<<<<<<<<<<< | ^>>>>>>>>>>>>>> | ^>> | ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< | ~~
                |---------------------------------------------------------------------------------------|
__EOF__
    print colored ($output, $colors{$3});
}
exit 0;
