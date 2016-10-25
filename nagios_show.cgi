#!/usr/bin/perl
# Query http a nagios a servicios con problemas.
# Se puede consultar un host concreto pasándolo como argumento.

use strict;
use warnings;
use LWP::UserAgent;
use HTML::Entities;     # decode_entities

my $nagios   = "127.0.0.1";
my $username = "user";
my $password = "pass";

my %colors = ( OK       => '#C2FFC3'
             , WARNING  => '#FEFFC1'
             , UNKNOWN  => '#FFE1C2'
             , CRITICAL => '#FFBBBB'
             );
my $colorkeys  = join("|", keys %colors);

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

print "Content-Type: text/html\n\n";
print <<EOF;
<HTML>
    <HEAD>
        <META http-equiv="Content-Type" content="text/html; charset=utf-8">
        <TITLE>$nagios</TITLE>
    </HEAD>
    <BODY>
EOF

my $response = &http("$nagios/cgi-bin/status.cgi?host=all&servicestatustypes=28");
my $page = decode_entities($response->decoded_content);
die "$page\n" if $page =~ /^\d{3}/;

$page =~ s/<td><\/td>/^/ig; # No me interesa tener celdas vacías...
$page =~ s/<[^>]+?>//g;     # para no cargármelas aquí.
$page =~ s/^\s*\n+//mg;     # Fuera whitelines.


print "\t<B>Re-scheduling the next services:</B>\n";
print "\t".'<TABLE style="text-align: center; border-style:solid; border-width:1px;" border="0" cellspacing="3"><TR bgcolor=#AAAAAA><TD>Host</TD><TD>Service</TD><TD>Status</TD><TD>Last Check</TD><TD>Duration</TD><TD>Attempt</TD><TD>Status Information</TD><TD>Code</TD></TR>'."\n";

my $host = undef;  # Para tener siempre el hostname en cada iteración.
while ($page =~ /([^\n]+)\n([^\n]+)\n((?:$colorkeys))\n([^\n]+)\n([^\n]+)\n(\d+\/\d+)\n([^\n]+)\n/gs) {
    my ($one, $two, $three, $four, $five, $six, $seven) = ($1, $2, $3, $4, $5, $6, $7);
    $seven =~ s/\s$//g;
    $host = $one unless $one eq '^';
    my $service = $two;
    $service =~ s/\s/+/g; # Fuera espacios
    my $response = &http( "$nagios/cgi-bin/cmd.cgi"
                        , 'POST'
                        , "cmd_typ=7&cmd_mod=2&host=${host}&service=${service}&start_time=31-12-1979+23%3A59%3A59&force_check=on&btnSubmit=Commit"
                        );
    print "\t\t<TR bgcolor=$colors{$three}><TD>$one</TD><TD>$two</TD><TD>$three</TD><TD>$four</TD><TD>$five</TD><TD>$six</TD><TD>$seven</TD><TD>".$response->status_line."</TD></TR>\n";
}

print <<EOF;
        </TABLE>
    </BODY>
</HTML>
EOF

exit 0;
