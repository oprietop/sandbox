#!/usr/bin/perl

use Socket;   # inet_aton()
use SNMP::Info;
use Storable; # store, retrieve¶
use Time::HiRes qw( time );
use File::Spec;
use Cwd 'abs_path';

my %devices = ( 'ROUTER1' => { COMMUNITY => 'public'
                             , HOST      => 'router1.domain.es'
                                        }
              , 'SWITCH1' => { COMMUNITY => 'public2'
                             , HOST      => 'switch1.domain.es'
                             }
              );

my %result;
my $fullpath = abs_path($0);
my ($volume, $path, $file) = File::Spec->splitpath($fullpath);
my $starting_time = time();

sub tab() {
    my $times = shift || 1;
    return "    " x $times;
}
sub header() {
    print "Content-Type: text/html\n\n";
    print <<EOF;
<HTML>
    <HEAD>
        <META http-equiv="Content-Type" content="text/html; charset=utf-8">
        <TITLE>Marp Table</TITLE>
        <META HTTP-EQUIV="Cache-Control" content="no-cache">
        <META HTTP-EQUIV="Pragma" CONTENT="no-cache">
        <META HTTP-EQUIV="Refresh" CONTENT="300">
        <SCRIPT SRC="/sorttable.js"></SCRIPT>
        <STYLE TYPE="text/css">
            caption {
                padding: 0 0 5px 0;
                font: italic 11px "Trebuchet MS", Verdana, Arial, Helvetica, sans-serif;
                text-align: right;
            }
            table {
                width: 100%;
                border-collapse: collapse;
            }
            tr:nth-of-type(odd) { /* Zebra striping */
                background: #eee;
            }
            th {
                background: #333;
                color: white;
                font-weight: bold;
            }
            td, th {
                padding: 6px;
                border: 1px solid #ccc;
                text-align: left;
                font-size: small;
            }
            tr:hover {
                background: #333;
                color: #FFF;
            }
        </STYLE>
    </HEAD>
    <BODY>
EOF
}

sub footer() {
    print &tab."</BODY>\n</HTML>\n";
}

sub update() {
    # Read oui.txt locally and fill the vendors hash
    my %vendors = ();
    open(OUI, "<", "$path\/oui.txt") or die "Can't find oui.txt, get it from http://standards.ieee.org/develop/regauth/oui/oui.txt";
    while (my $line = <OUI>) {
        $vendors{lc("$1:$2:$3")} = $4 if $line =~ /(\w{2})-(\w{2})-(\w{2})\s+\(hex\)\s+(.+)$/;
    }

    # Traverse our devices hash and fill it with the L2 and L3 info
    foreach my $device (sort keys %devices) {
        my $info = new SNMP::Info ( BulkWalk    => 1
                                  , AutoSpecify => 1
                                  , Debug       => 0
                                  , DestHost    => $devices{$device}{HOST}
                                  , Community   => $devices{$device}{COMMUNITY} || 'public'
                                  , Version     => $devices{$device}{VERSION}   || 2
                                  );

        # Hashes for the stuff we need
        my $interfaces = $info->interfaces();
        my $fw_mac     = $info->fw_mac();
        my $fw_port    = $info->fw_port();
        my $bp_index   = $info->bp_index();
        my $at_paddr   = $info->at_paddr();

        # L2 mac -> port relation
        foreach my $fw_index (keys %$fw_mac){
            my $mac   = $fw_mac->{$fw_index};
            my $bp_id = $fw_port->{$fw_index};
            my $iid   = $bp_index->{$bp_id};
            my $port  = $interfaces->{$iid};
            $devices{$device}{L2}{$mac} = $port if $port !~ /lag/;
        }

        # L3 mac -> ip
        foreach my $ip_index (keys %$at_paddr){
            my $mac = $at_paddr->{$ip_index};
            if ($ip_index =~ /^\d+\.(.+)/) {
                $devices{$device}{L3}{$mac} = $1;
            }
        }

        # Traverse our devices hash and cross the L2 and L3 info to generate our output hash
        foreach my $device_l3 (sort keys %devices) {
            foreach my $host_mac (sort keys %{$devices{$device_l3}{L3}}) {
                foreach my $device_l2 (sort keys %devices) {
                    my $host_port = $devices{$device_l2}{L2}{$host_mac} || next;
                    $result{$host_mac} = { IP     => $devices{$device_l3}{L3}{$host_mac}
                                         , PORT   => $host_port
                                         , VENDOR => $vendors{substr($host_mac, 0, 8)} || "UNKNOWN (Virtual Machine?)"
                                         , L2     => $device_l2
                                         , L3     => $device_l3
                                         , DATE   => scalar localtime()
                                         }
                    }
            }
        } # foreach my $device_l3
    } # foreach my $device
} # sub update

sub table() {
    print &tab(2)."<TABLE class=\"sortable\">\n";
    print &tab(3)."<CAPTION>Generated on ".scalar localtime()." in ".sprintf("%.2f", (time() - $^T))." seconds. Click on a column title to apply sort.</CAPTION>\n";
    print &tab(3)."<TR><TH>Ip</TH><TH>Mac</TH><TH>Vendor</TH><TH>Switch</TH><TH>Port</TH><TH>Router</TH><TH>Last Seen</TH></TR>\n";
    foreach my $mac (sort keys %result) {
        print &tab(3)."<TR><TD>$result{$mac}{IP}</TD><TD>$mac</TD><TD>$result{$mac}{VENDOR}</TD><TD>$result{$mac}{L2}</TD><TD>$result{$mac}{PORT}</TD><TD>$result{$mac}{L3}</TD> <TD>$result{$mac}{DATE}</TD></TR>\n";
    }
    print &tab(2)."</TABLE>\n";
} # sub table

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
    &table;
    &footer;
}
