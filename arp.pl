#!/usr/bin/perl
# Keep and show an arp table from several routers.
# CSS Table from http://www.duoh.com/csstutorials/csstables/
# sorttable.js from www.kryogenix.org/code/browser/sorttable/

use strict;
use warnings;
use SNMP;
use Socket;   # inet_aton()
use Storable; # store, retrieve¶
use Time::HiRes qw( time );
use File::Spec;
use Cwd 'abs_path';
use Data::Dumper;

my $fullpath = abs_path($0);
my ($volume, $path, $file) = File::Spec->splitpath($fullpath);
my $starting_time = time();
my %result  = (); # Main Hash
my %routers = ( 'router1 (datos)' => { COMMUNITY => 'datos@public'
                                     , HOST      => '127.0.0.1'
                                     }
              , 'router2'         => { COMMUNITY => 'public' }
              );

sub header() {
    print "Content-Type: text/html\n\n";
    print <<EOF;
<HTML>
    <HEAD>
        <META http-equiv="Content-Type" content="text/html; charset=utf-8">
        <TITLE>Arp Table</TITLE>
        <SCRIPT SRC="/sorttable.js"></SCRIPT>
        <STYLE TYPE="text/css">
            body {
                font: normal 11px auto "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
                color: #4f6b72;
                background: #E6EAE9;
            }
            a {
                font: italic 11px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
            }
            caption {
                padding: 0 0 5px 0;
                font: italic 11px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
                text-align: right;
            }
            td {
                border-right: 1px solid #C1DAD7;
                border-bottom: 1px solid #C1DAD7;
                background: #fff;
                padding: 6px 6px 6px 12px;
                color: #4f6b72;
            }
            td.noip {
                background: #F5FAFA;
                color: #797268;
            }
            th {
                font: bold 11px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
                color: #4f6b72;
                border-right: 1px solid #C1DAD7;
                border-bottom: 1px solid #C1DAD7;
                border-top: 1px solid #C1DAD7;
                letter-spacing: 2px;
                text-transform: uppercase;
                text-align: left;
                padding: 6px 6px 6px 12px;
                background: #C1DAD7
            }
            th.nobg {
                border-top: 0;
                border-left: 0;
                border-right: 1px solid #C1DAD7;
                background: none;
            }
            th.ip {
                border-left: 1px solid #C1DAD7;
                border-top: 0;
                background: #fff url(data:image/gif;base64,R0lGODlhCQAKAIAAAOrNqf///yH5BAAAAAAALAAAAAAJAAoAAAIOjI+ZwH3NEFyRqgCu3gUAOw==) no-repeat;
                font: bold 10px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
            }
            th.noip {
                border-left: 1px solid #C1DAD7;
                border-top: 0;
                background: #f5fafa url(data:image/gif;base64,R0lGODlhKwEoAJEAAKnT6v////X6+gAAACH5BAAAAAAALAAAAAArASgAAALXjI+py+0Po5y02ouz3lz4D4biSJbmiabqyrbuC8fyLAcCgOf0zvf+DwwKhyJbDkdMKpfMpnNo1D2n1Kr1GowCsNyu99uNgsfksnlnPKvX7LbA5o7L51Q4/Y7P8+z6vv9fwgc4SJgnWIiYuHao2OgY9hgpecU4aXkJVIm5yQmj2QkaavIpWmpKapraiaraasnqGusIK1tbSGub64er23vH6xvsBixcfEZsnAyGrNyMxewcPQUtXb1EbZ0thK3d3cPtHV4jTl5Xft4Ejr4eyO6e9R7/LU8/UwAAOw==) no-repeat;
                font: bold 10px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
                color: #797268;
            }
        </STYLE>
    </HEAD>
    <BODY>
EOF
}

sub tab() {
    my $times = shift || 1;
    return "    " x $times;
}

sub th() {
    my $text  = shift || "No text";
    my $scope = shift || '';
    my $class = shift || '';
    return "<TH scope=\"$scope\" class=\"$class\">$text</TH>\n";
}

sub td() {
    my $text  = shift || "No text";
    my $class = shift || '';
    return "<TD class=\"$class\">$text</TD>\n";
}

sub stats_table() {
    return 0;
}

sub arp_table() {
    print &tab."<TABLE id=\"arp_table\" class=\"sortable\" cellspacing=\"0\">\n";
    print &tab(2)."<CAPTION>Generated on ".scalar localtime()." in ".sprintf("%.2f", (time() - $^T))." seconds. Click on a column title to apply sort. Hover over a router name to get the last seen date..</CAPTION>\n";
    print &tab(2)."<TR>\n".&tab(3).&th('Host', 'col', 'nobg').&tab(3).&th('MAC', 'col').&tab(3).&th('Vendor', 'col').&tab(3).&th('Router(s)', 'col').&tab(2)."</TR>\n";
    foreach my $ip (sort keys %result) {
        my ($host, $trclass, $tdclass)  = ($ip, 'noip', 'noip');
        if ($result{$ip}{HOST}) {
            $host .= " ($result{$ip}{HOST})";
            $trclass = "ip";
            $tdclass = "ip";
        }
        print &tab(2)."<TR>\n";
        my @seen_routers = map { "<a title=\"Last seeen on $result{$ip}{ROUTERS}{$_}\">$_</a>"} keys %{$result{$ip}{ROUTERS}};
        print &tab(3).&th($host, 'row', $trclass).&tab(3).&td($result{$ip}{MAC}, $tdclass).&tab(3).&td($result{$ip}{VENDOR}, $tdclass).&tab(3).&td(join('</BR>', @seen_routers), $tdclass);
        print &tab(2)."</TR>\n";
    }
    print &tab."</TABLE>\n";
}

sub footer() {
    print &tab."</BODY>\n</HTML>\n";
}

sub update() {
    my %vendors = (); # Will containt the parsed oid.txt
    open(OUI, "<", "$path\/oui.txt") or die "Can't find oui.txt, get it from http://standards.ieee.org/develop/regauth/oui/oui.txt";
    while (my $line = <OUI>) {
        $vendors{$1} = $2 if $line =~ /(\S+)\s+\(hex\)\s+(.+)$/;
    }
    foreach my $router (sort keys %routers) {
        my $start_timer = time();
        my %oids = ( '1.3.6.1.2.1.4.22.1.2' => { 'DESC' => 'ipNetToMediaPhysAddress'
                                               , 'OID'  => 'ipNetToMediaPhysAddress'
                                               , 'RES'  => []
                                               }
                   , '1.3.6.1.2.1.4.22.1.3' => { 'DESC' => 'ipNetToMediaNetAddress'
                                               , 'OID'  => 'ipNetToMediaNetAddress'
                                               , 'RES'  => []
                                               }
                   );

        my $session = new SNMP::Session( DestHost   => $routers{$router}{HOST} || $router
                                       , Community  => $routers{$router}{COMMUNITY}
                                       , Version    => $routers{$router}{VERSION} || 2
                                       , UseNumeric => 1
                                       );

        if ($session->{ErrorNum}) {
            print "Error ".$session->{ErrorNum}." \"".$session->{ErrorStr}."\n en ".$session->{ErrorInd}."\n";
        }
        my @VarBinds =();
        foreach (keys %oids) {
            push @VarBinds, new SNMP::Varbind([$_]);
        }
        my $VarList = new SNMP::VarList(@VarBinds);
        my @result = $session->bulkwalk(0, 100, $VarList);
        my $i=0;
        for my $vbarr (@result) {
            my $oid = $$VarList[$i++]->tag();
            foreach my $v (@$vbarr) {
                push(@{$oids{$oid}{RES}}, $v->val);
            }
        }
        my $total = scalar @{$oids{'1.3.6.1.2.1.4.22.1.2'}{RES}};
        for $i (0..($total-1)) {
            my $ip = $oids{'1.3.6.1.2.1.4.22.1.3'}{RES}[$i];
            my $host = gethostbyaddr(inet_aton($ip), AF_INET) || 0;
            my $mac = sprintf("%02X:%02X:%02X:%02X:%02X:%02X", unpack("C6", $oids{'1.3.6.1.2.1.4.22.1.2'}{RES}[$i]));
            my $vendor = $vendors{sprintf("%02X-%02X-%02X", unpack("C3", $oids{'1.3.6.1.2.1.4.22.1.2'}{RES}[$i]))} || "UNKNOWN (Virtual Machine?)";
            my %rhash = ();
            %rhash = %{$result{$ip}{ROUTERS}} if ref($result{$ip}{ROUTERS}) eq "HASH";
            $rhash{$router} = scalar localtime();
            $result{$ip} = { HOST    => $host
                           , MAC     => $mac
                           , VENDOR  => $vendor
                           , ROUTERS => \%rhash
                           };
        }
        $routers{$router}{ENTRIES} = $total;
        $routers{$router}{ELAPSED} = sprintf("%.2f", (time() - $start_timer));
    }
} #update

my $href;
if (-f "$fullpath.hash") {
   $href = retrieve("$fullpath.hash");
   %result = %{$href};
} else {
   $ARGV[0] = "update";
}

if($ARGV[0]) {
    &update;
    store(\%result, "$fullpath.hash") or die "Can't store hash!\n";
} else {
    &header;
    &stats_table;
    &arp_table;
    &footer;
}

#exit 0;
print Dumper %result;
print Dumper %routers;
