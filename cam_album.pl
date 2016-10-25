#!/usr/bin/perl -w
# webcam image album

use strict;
use warnings;
use LWP::UserAgent;
use MIME::Base64; # encode_base64()

my %cams = ( 'Cam1' => { URI => 'http://192.168.X.X/oneshotimage.jpg'
                       , DSC => 'Description Cam1'
                       , USR => 'XXXXX'
                       , PWD => 'XXXXX'
                       }
           , 'Cam2' => { URI => 'http://192.168.X.X/jpeg'
                       , DSC => 'Description Cam2'
                       , USR => 'XXXXX'
                       , PWD => 'XXXXX'
                       }
           );

my $ua = LWP::UserAgent->new( agent         => 'Mac Safari'
                            , show_progress => 0 # Adds fancy progressbars
                            , timeout       => 1
                            );

sub header() {
    $0 =~ s/.+\///g;
    print "Content-Type: text/html\n\n";
    print <<EOF;
<HTML>
    <HEAD>
        <META http-equiv="Content-Type" content="text/html; charset=utf-8">
        <TITLE>$0</TITLE>
        <META http-equiv="refresh" content=600>
        <STYLE TYPE="text/css">
            * {
                margin: 0;
                padding: 0;
            }
            body {
                padding: 30px;
                background: #FFF;
                text-align: center;
            }
            h1 {
                border-bottom: 1px dashed #CCC;
                color: #933;
                font: 24px Georgia, serif;
                text-align: center;
            }
            p {
                margin: 15px 0;
                text-align: center;
                font: 11px/1.5em "Lucida Grande", Arial, sans-serif;
            }
            #page-container {
                margin: 0 auto;
                width: 1002px;
                text-align: left;
            }
            .pg {
                width: 1002px;
                list-style: none none;
            }
            .pg li a {
                margin: 2px;
                border: 1px solid #CCC;
                padding: 4px;
                position: relative;
                float: left;
                display: block;
                width: 320px;
                height: 240px;
                background: #E6EAE9;
            }
            .pg li a img {
                position: absolute;
                width: 320px;
                height: 240px;
            }
            .pg li a:hover img {
                padding: 30px;
                width: 260px;
                height: 180px;
                z-index: 1;
            }
        </STYLE>
    </HEAD>
    <BODY>
        <DIV id="page-container">
            <H1>Cam "R" Us</H1>
            <P>Hover sobre la imagen para ver la descripción, click para abrir la GUI.</P>
            <UL class="pg">
EOF
}

sub tab() {
    my $times = shift || 1;
    return "    " x $times;
}

sub cam_image() {
    my $name    = shift;
    my $current = shift;
    my $page = &request($current->{URI}, $current->{USR}, $current->{PWD});
    if ($page =~ /^\d{3}\s/) {
        print &tab(4)."<LI><A>$current->{DSC}<BR><BR>$page</A></LI>\n";
    } else {
        my $link = $1 if $current->{URI} =~ /(http:\/\/[^\/]+)/;
        print &tab(4)."<LI><A href=\"$link\" target=\"_blank\"><img src=\"data:image/png;base64,$page\" alt=\"$current->{DSC}\" />$current->{DSC}</A></LI>\n";
    }
}

sub footer() {
    my $date = scalar localtime();
    my $runtime=(time - $^T);
    print <<EOF;
            </UL>
            <P>Generado el $date en $runtime segundos.</P>
        </DIV>
    </BODY>
</HTML>
EOF
    exit 0;
}

sub request($) {
    my $url  = shift || die "No url\n";
    my $user = shift;
    my $pass = shift;
    my $req  = HTTP::Request->new(GET => $url);
    $req->authorization_basic($user, $pass);
    my $resp = $ua->request($req);
    $resp->is_success ? return encode_base64($resp->content) : return $resp->status_line;
}

&header;
foreach my $cam (sort keys %cams) {
    &cam_image($cam, $cams{$cam});
}
&footer;
