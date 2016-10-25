#!/usr/bin/perl
# chuinfo.pl AKA test.pl+SNMP::Info AKA "Switch CPU Toaster".
# Sorttable from http://www.kryogenix.org/code/browser/sorttable/sorttable.js

use strict;
use warnings;
use SNMP::Info;

# Remove the path from the script name.
$0 =~ s/.*\///g;

# The SNMPv2 community we will use:
my $community = 'public';

#
# Functions.
#
# {{{ Execution Time
sub exec_time() {
    my $date = scalar localtime();
    my $runtime=(time - $^T);
    print "<P class=\"extime\">Generado el $date en $runtime segundos.</P>\n";
}
# }}}
# {{{ HTML Footer
sub footer() {
    print "</BODY></HTML>\n";
    exit 0;
}
# }}}
# {{{ TD Wrapper
sub td($$) {
    my $text = shift || "";
    my $args = shift || "";
    return "<TD $args>$text</TD>" if $text ne "" or return '<TD><div class="cross"></div></TD>';
}
# }}}
# {{{ TH Wrapper
sub th($$) {
    my $text = shift || "";
    my $args = shift || "";
    return "<TH $args>$text</TH>" if $text ne "" or return '<TH></TH>';
}
# }}}
# {{{ TDN Wrapper
sub tdn($$) {
    my $text = shift || "";
    my $args = shift || "";
    return "<TD $args>$text</TD>" if $text !~ /^\-/ or return '<TD>'.$text.'</TD>';
}
# }}}
# {{{ TDE Wrapper
sub tde($$) {
    my $text = shift || 0;
    my $args = shift || "";
    if (defined $text) {
        if ($text gt 0 or $text =~ /^-/) {
            return "<TD class=\"warning\"><I>$text</I></TD>";
        } else {
            return "<TD $args>$text</TD>";
        }
    } else {
        return '<TD><div class="cross"></div></TD>';
    }
}
# }}}
# {{{ non_empty(%) [Return 0 (false) if all the hash values are ""]
sub non_empty(%) {
    return grep { $_ ne "" } values %{$_[0]};
}
# }}}
# {{{ check_ip_host(@) [Check for a valid IP or Host]
sub check_ip_host(@) {
    my $validip = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\$";
    my $validhost = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])\$";
    @_ ? my @badhosts = grep { $_ !~ /(?:$validip|$validhost)/ } @_ : return "Empty array!\n";
    @badhosts ? return join(", ", @badhosts)." IP o Hostname inválido/s.\n" : return 0;
}
# }}}
# {{{ convert_bytes($$) [Bytes to 'Human Readable']

sub convert_bytes ($$){     my $bytes = shift || 0;
    my $dec   = shift || 2;
    foreach my $posfix (qw(bytes Kb Mb Gb Tb Pb Eb Zb Yb)) {
        return sprintf("\%.${dec}f \%s", $bytes, $posfix) if $bytes < 1024;
        $bytes /= 1024;
    }
}
# }}}
# {{{ timeticks2HR($) [Tents of second to "Human Readable"]

sub timeticks2HR($) {     my $seconds = ($_[0]/100);
    return sprintf ("%.1d Days, %.2d:%.2d:%.2d", $seconds/86400, $seconds/3600%24, $seconds/60%60, $seconds%60) if $seconds or return 0;
}
# }}}
# {{{ TrueSort(@) http://www.perlmonks.org/?node_id =483462

sub TrueSort(@) {
    my @list = @_;
    return @list[
        map { unpack "N", substr($_,-4) }
        sort
        map {
            my $key= $list[$_];
            $key =~ s[(\d+)][ pack "N", $1 ]ge;
            $key . pack "N", $_
        } 0..$#list
    ];
}
# }}}
# {{{  AgrArr(@) [Port list to range]
sub AgrArr(@) {
    my @out=();
    my $cache=undef;
    my @array=&TrueSort(@_);
    for my $i (0..$#array) {
        next if $array[$i+1] and $array[$i] eq $array[$i+1]; #Nos cargamos los duplicados
        my $next = $1.($2+1) if $array[$i] =~ /(.+?)(\d+)$/g or next;
        if ( not $array[$i+1] or $next ne $array[$i+1] ) {
            $cache ? push (@out, "$cache$array[$i]") : push (@out, $array[$i]);
            undef($cache);
        } elsif ( ! defined($cache) ) {
            $cache = "$array[$i]~";
        }
    }
    return @out;
}
# }}}
# {{{ arr_resta(@@) [returns @first - @second]
sub arr_resta {
    my $first  = shift;
    my $second = shift;
    my %hash;
    $hash{$_}=1 foreach @$second;
    return grep { not $hash{$_} } @$first;
}
# }}}
#
# Hammer a Device
#
# {{{ Highlander [Only allow one instance of the script running at once]
use Fcntl qw(LOCK_EX LOCK_NB);
open HIGHLANDER, ">>/tmp/perl_$0_highlander" or die "Content-Type: text/html\n\nCannot open highlander: $!";
{
    flock HIGHLANDER, LOCK_EX | LOCK_NB and last;
    print "Content-Type: text/html\n\n<P>Script en uso!</P>";
    exit 1;
}
# }}}
# {{{ Pick our host from the query string (GET) or command line.
my $host;
if ($ARGV[0]) {
    $host = $ARGV[0];
} elsif ($ENV{QUERY_STRING}) {
    $host = $1 if $ENV{QUERY_STRING} =~ /host=(.+)$/;
}
# }}}
# {{{ HTML Header and Guts
my $date = scalar localtime();
my $version = "v".int(rand(10))."\.".int(rand(1000))."b";
print "Content-Type: text/html\n\n";
print <<EOF;
<HTML>
    <HEAD>
        <META http-equiv="Content-Type" content="text/html; charset=utf-8">
        <TITLE>$host // $0 // $date</TITLE>
        <script type="text/javascript" src="../sorttable.js"></script>
        <style type="text/css">
            body {
                background: #B0B0B0;
                text-align: center;
            }
            p {
                font: x-large "helvetica neue", helvetica, arial, sans-serif;
                color: #222;
                text-shadow: 0px 2px 3px #666;
            }
            p.extime {
                font-size: small;
            }
            button {
                background-image: linear-gradient(#666 0%,#333 100%);
                border: 1px solid #172D6E;
                border-bottom: 1px solid #0E1D45;
                border-radius: 5px;
                box-shadow: inset 0 1px 0 0 #b1b9cb;
                color: #FFF;
                padding: 3px;
                font: normal "helvetica neue", helvetica, arial, sans-serif;
                font-weight: bold;
                text-shadow: 0 -1px 1px #111;
            }
            input {
                background: #FFF;
                border: 1px solid #DDD;
                border-radius: 5px;
                box-shadow: 0 0 5px #DDD inset;
                color: #666;
                float: left;
                padding: 3px;
                width: 165px;
            }
            table {
                border: 1px solid #111;
                background: #FAFAFA;
                border-radius: 5px;
                margin-left:auto;
                margin-right:auto;
            }
            table.fancy tr, table.fancy td, table.fancy th {
                font: small "helvetica neue", helvetica, arial, sans-serif;
                text-align: center;
                padding-right: 5px;
                padding-left: 5px;
                transition: all 0.3s;  /* Simple transition for hover effect */
            }
            table.fancy th {
                color: #FAFAFA;
                font-weight: bold;
                text-shadow: 0 -1px 1px #111;
                background: linear-gradient(#666 0%,#333 100%); /* Gradient Background */
            }
            table.fancy tr, table.fancy th:first-child { /* First-child header cell */
                border: 0 none;
                color: black;
                text-align: left;
                font-size: medium;
                text-shadow: none;
                background: #FAFAFA;
            }
            table.fancy tr:first-child, table.fancy th:last-child { border-radius: 0 5px 0 0; }
            table.fancy td:hover { /* Hover cell effect! */
                border-radius: 5px;
                background: #333;
                color: #FFF;
            }
            table.fancy .bold_right {
                font-style: italic;
                font-weight: bold;
                text-align: right;
            }
            table.fancy .dotted_cell {
                background: #FAFAFA;
                border: 1px dotted #666;
                font-style: italic;
                font-weight: bold;
                text-align: right;
                padding-right: 5px;
            }
            table.fancy .opadmup_gt_24h     { background: #E6E6E6; }
            table.fancy .opadmup_lt_24h     { background: #DBEDFF; }
            table.fancy .opadmup_lt_15m     { background: #8CB3D9; }
            table.fancy .opupadmdown        { background: #B38CD9; }
            table.fancy .opdownadmup_gt_24h { background: #F0E5CC; }
            table.fancy .opdownadmup_lt_24h { background: #CCF0D3; }
            table.fancy .opdownadmup_lt_15m { background: #8CD98C; }
            table.fancy .noneth             { background: #EAEAC8; }
            table.fancy .warning            {
                background: #FF7A7A;
                border-radius: 5px;
            }
            table.fancy .null {
                color: #DDD;
                text-shadow: 0px 1px 1px #CCC;
                background: #FAFAFA;
            }
            table.sortable th { color: #FAFAFA; } /* White font for the sorttable hlink */
            .cross{
                position: relative;
                margin-left: auto;
                margin-right: auto;
                width: 3px;
                height: 9px;
                transform: rotate(45deg);
                -webkit-transform: rotate(45deg);
                background: #DDD;
            }
            .cross:before{
                position: absolute;
                width: 9px;
                height: 3px;
                top: 3px;
                left: -3px;
                background: #DDD;
                content: "";
            }
        </style>
    </HEAD>
<BODY>
<P>ChuInfo $version</P>
<FORM action="$0" method="GET">
    <TABLE>
        <TR><TH>Host:</TH><TD><INPUT type="text" name="host" value=""/></TD><TD><BUTTON>Submit</BUTTON></TD></TR>
    </TABLE>
</FORM>
EOF
# }}}
# {{{ Print our chosen host
unless ($host) { # First time.
    &footer;
} elsif (not &check_ip_host($host)) {
    print "<H2>$host</H2>\n";
} else {
    print "<P>Invalid host entry.</P>\n";
    &footer;
}
# }}}
# {{{ Perform the SNMP Bulkwalk query
my $info = new SNMP::Info( AutoSpecify => 1
                         , Debug       => 0
                         , # The rest is passed to SNMP::Session
                         , DestHost    => $host # || '192.168.238.4', # 192.168.247.80
                         , Community   => $community
                         , Version     => 2
                         ) or print "<P>Can't connect to device.</P>\n" and &footer;

my $err = $info->error();
print "<H2>SNMP Community or Version probably wrong connecting to device. $err</H2>\n" and &footer if defined $err;
# }}}
# {{{ Fill our hashes
# Find out the Duplex status for the ports
my $interfaces     = $info->interfaces();
my $i_duplex       = $info->i_duplex();
my $i_duplex_admin = $info->i_duplex_admin();
# Iface Info
my $i_index       = $info->i_index();
my $i_description = $info->i_description();
my $i_type        = $info->i_type();
my $i_mtu         = $info->i_mtu();
my $i_speed       = $info->i_speed();
my $i_mac         = $info->i_mac();
my $i_up          = $info->i_up();
my $i_up_admin    = $info->i_up_admin();
my $i_lastchange  = $info->i_lastchange();
my $i_alias       = $info->i_alias();
# Iface Stats
my $i_octet_in64       = $info->i_octet_in64();
my $i_octet_out64      = $info->i_octet_out64();
my $i_errors_in        = $info->i_errors_in();
my $i_errors_out       = $info->i_errors_out();
my $i_pkts_bcast_in64  = $info->i_pkts_bcast_in64();
my $i_pkts_bcast_out64 = $info->i_pkts_bcast_out64();
my $i_discards_in      = $info->i_discards_in();
my $i_discards_out     = $info->i_discards_out();
my $i_bad_proto_in     = $info->i_bad_proto_in();
my $i_qlen_out         = $info->i_qlen_out();
# Get CDP Neighbor info
my $c_id       = $info->c_id();
my $c_if       = $info->c_if();
my $c_ip       = $info->c_ip();
my $c_port     = $info->c_port();
#Vlan
my $i_vlan            = $info->i_vlan();
my $i_vlan_membership = $info->i_vlan_membership();
my $qb_v_fbdn_egress  = $info->qb_v_fbdn_egress();
my $qb_v_untagged     = $info->qb_v_untagged();
my $v_name            = $info->v_name();
# Cisco sometimes returns keys like "1.100"
foreach (keys %$v_name) {
    next if /^\d+$/; # OK IF the vlan is all digits
    /\d+$/;
    $v_name->{$&} = $v_name->{$_};
    delete $v_name->{$_};
}
my $vtp_trunk_dyn = $info->vtp_trunk_dyn();
my $vtp_trunk_dyn_stat = $info->vtp_trunk_dyn_stat();
# }}}
#
# Show the stuff we got
#
# {{{ Print the INFO Table
print "<P>Info:</P>\n";
print "<TABLE class=\"fancy\"><TR><TH>OIDs</TH><TH>Name</TH></TR>\n";
print '<TR><TD class="dotted_cell">Name</TD>'.&td($info->name())."</TR>\n";
print '<TR><TD class="dotted_cell">Location</TD>'.&td($info->location())."</TR>\n";
print '<TR><TD class="dotted_cell">Contact</TD>'.&td($info->contact())."</TR>\n";
print '<TR><TD class="dotted_cell">Class</TD>'.&td($info->class())."</TR>\n";
print '<TR><TD class="dotted_cell">Model</TD>'.&td($info->model())."</TR>\n";
print '<TR><TD class="dotted_cell">OS Version</TD>'.&td($info->os_ver())."</TR>\n";
print '<TR><TD class="dotted_cell">Serial Number</TD>'.&td($info->serial())."</TR>\n";
print '<TR><TD class="dotted_cell">Base MAC</TD>'.&td($info->mac())."</TR>\n";
print '<TR><TD class="dotted_cell">Uptime</TD>'.&td(&timeticks2HR($info->uptime()))."</TR>\n";
print '<TR><TD class="dotted_cell">Booted on</TD>'.&td(scalar localtime(time - $info->uptime()/100))."</TR>\n";
print '<TR><TD class="dotted_cell">Layers</TD>'.&td($info->layers())."</TR>\n";
print '<TR><TD class="dotted_cell">Ports</TD>'.&td($info->ports())."</TR>\n";
print '<TR><TD class="dotted_cell">Ip Forwarding'.&td($info->ipforwarding())."</TR>\n";
print '<TR><TD class="dotted_cell">CDP'.&td($info->hasCDP())."</TR>\n";
print '<TR><TD class="dotted_cell">Bulkwalk</TD>'.&td($info->bulkwalk())."</TR>\n";
print "</TABLE>\n";
# }}}
# {{{ Print the IP Address Table
my $index = $info->ip_index();
my $tble = $info->ip_table();
my $netmask = $info->ip_netmask();
my $broadcast = $info->ip_broadcast();

print "<P>IP Adress Table:</P>\n";
print '<TABLE class="fancy"><TR>'
    .&th('Index')
    .&th('Port')
    .&th('Table')
    .&th('Netmask')
    .&th('Broadcast')
    ."</TR>\n";
foreach my $key (sort { $index->{$a} cmp $index->{$b} } keys %$index){
    print "\t<TR>"
        .&td($index->{$key}, 'class="dotted_cell"')
        .&td($interfaces->{$index->{$key}})
        .&td($tble->{$key})
        .&td($netmask->{$key})
        .&td($broadcast->{$key})
        ."</TR>\n";
}
print "</TABLE>\n";
# }}}
# {{{ Print the IP Routing Table
if ( &non_empty($info->ipr_if()) ) {
    my $ipr_route = $info->ipr_route();
    my $ipr_if = $info->ipr_if();
    my $ipr_1 = $info->ipr_1();
    my $ipr_2 = $info->ipr_2();
    my $ipr_3 = $info->ipr_3();
    my $ipr_4 = $info->ipr_4();
    my $ipr_5 = $info->ipr_5();
    my $ipr_dest = $info->ipr_dest();
    my $ipr_type = $info->ipr_type();
    my $ipr_proto = $info->ipr_proto();
    my $ipr_age = $info->ipr_age();
    my $ipr_mask = $info->ipr_mask();
    print "<P>Routing Table:</P>\n";
    print '<TABLE class="fancy"><TR>'
        .&th('Index')
        .&th('Route')
        .&th('Mask')
        .&th('Dest')
        .&th('1')
        .&th('2')
        .&th('3')
        .&th('4')
        .&th('5')
        .&th('Type')
        .&th('Proto');
    print &th('Age') if &non_empty($ipr_age);
    print "</TR>\n";
    foreach my $key (sort keys %$ipr_route){
        print "\t<TR>"
            .&td($ipr_if->{$key}, 'class="dotted_cell"')
            .&td($ipr_route->{$key})
            .&td($ipr_mask->{$key})
            .&td($ipr_dest->{$key})
            .&td($ipr_1->{$key})
            .&td($ipr_2->{$key})
            .&td($ipr_3->{$key})
            .&td($ipr_4->{$key})
            .&td($ipr_5->{$key})
            .&td($ipr_type->{$key})
            .&td($ipr_proto->{$key});
        print &td($ipr_age->{$key}) if &non_empty($ipr_age);
        print "</TR>\n";
    }
    print "</TABLE>\n";
}
# }}}
# {{{ hasmatch($$) Returns the ports asociated to a $hash key with a valued on $reg
sub hashmatch {
    my $hash = shift;
    my $reg = shift;
    my @tmplist = grep { $hash->{$_} =~ $reg and $i_type->{$_} eq "ethernetCsmacd" } keys %$hash;
    my @result = ();
    @result = map { $interfaces->{$_} } @tmplist or ();
    return @result;
}
# }}}
# {{{ Print The TOTALS table.
#Totals
my @ether      = &hashmatch($i_type,             ".*");
my @adminon    = &hashmatch($i_up_admin,         "up");
my @adminoff   = &arr_resta(\@ether,             \@adminon);
my @operon     = &hashmatch($i_up,               "up");
my @operoff    = &arr_resta(\@ether,             \@operon);
my @gbports    = &hashmatch($i_speed,            "1.0 G");
@gbports       = &arr_resta(\@gbports,           \@operoff);
my @fastports  = &hashmatch($i_speed,            "100 M");
@fastports     = &arr_resta(\@fastports,         \@operoff);
my @ethports   = &hashmatch($i_speed,            "10 M");
@ethports      = &arr_resta(\@ethports,          \@operoff);
my @halfdup    = &hashmatch($i_duplex,           "half");
@halfdup       = &arr_resta(\@halfdup,           \@operoff);
my @trunkports = &hashmatch($vtp_trunk_dyn_stat, '^trunking$' );
print '<P>Totals:</P>';
print '<TABLE class="fancy"><TR>'.&th('Range').&th('Ports').&th('Total')."</TR>";
print '<TR><TD class="dotted_cell">Admin On</TD>'    .&td(join (", ", &AgrArr(@adminon)))   .&td(($#adminon+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Admin Off</TD>'   .&td(join (", ", &AgrArr(@adminoff)))  .&td(($#adminoff+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Oper On</TD>'     .&td(join (", ", &AgrArr(@operon)))    .&td(($#operon+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Oper Off</TD>'    .&td(join (", ", &AgrArr(@operoff)))   .&td(($#operoff+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Gb Link</TD>'     .&td(join (", ", &AgrArr(@gbports)))   .&td(($#gbports+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Fast Link</TD>'   .&td(join (", ", &AgrArr(@fastports))) .&td(($#fastports+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Ether Link</TD>'  .&td(join (", ", &AgrArr(@ethports)))  .&tde(($#ethports+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Half Duplex</TD>' .&td(join (", ", &AgrArr(@halfdup)))   .&tde(($#halfdup+1))."</TR>\n";
print '<TR><TD class="dotted_cell">Trunking</TD>'    .&td(join (", ", &AgrArr(@trunkports))).&td(($#trunkports+1))."</TR>\n" if @trunkports;
print "</TABLE>\n";
# }}}
# {{{ Print the VLANs Table
print "<P>Vlans:</P>\n";
print "<TABLE class=\"fancy\"><TR><TH>Vlan Name</TH><TH>Pvid</TH><TH>Type</TH><TH>Ports</TH><TH>Total</TH></TR>\n";
foreach my $pvid ( sort {$a <=> $b} keys %$v_name) {
    my @pvid        = ();
    my @pegress     = ();
    my @pforbegress = ();
    my @puntagged   = ();
    foreach my $port (keys %$interfaces) {
        next unless $i_type->{$port} eq "ethernetCsmacd"; # We will onlu take "usable ports" into account
        push (@pvid,        $interfaces->{$port}) if $i_vlan->{$port} eq $pvid;
        push (@pegress,     $interfaces->{$port}) if grep { $_ eq $pvid } @{$i_vlan_membership->{$port}};
        push (@pforbegress, $interfaces->{$port}) if @{$qb_v_fbdn_egress->{$pvid}}[($port-1)];
        push (@puntagged,   $interfaces->{$port}) if @{$qb_v_untagged->{$pvid}}[($port-1)];
    }
    print "\t<TR><TD class=\"dotted_cell\" rowspan=\"4\">$v_name->{$pvid}</TD><TD rowspan=\"4\" >$pvid</TD><TD class=\"bold_right\">Pvid</TD>".&td(join (", ", &AgrArr(@pvid)))  .&td(($#pvid+1))."</TR>\n";
    print "\t<TR><TD class=\"dotted_cell\">Egress</TD>".&td(join (", ", &AgrArr(@pegress))).&td(($#pegress+1))."</TR>\n";
    print "\t<TR><TD class=\"bold_right\">Forbidden</TD>".&td(join (", ", &AgrArr(@pforbegress))).&tde(($#pforbegress+1))."</TR>\n";
    print "\t<TR><TD class=\"dotted_cell\">Untagged</TD>".&td(join (", ", &AgrArr(@puntagged))).&td(($#puntagged+1))."</TR>\n";
}
print "</TABLE>\n";
# }}}
# {{{ Print the PORTS Table:
print "<P>Ports:</P>\n";
#print '<TABLE class="fancy"><TR>'
print '<TABLE class="fancy sortable"><TR>'
    .&th('Index')
    .&th('Name');
print &th('Alias') if &non_empty($i_alias);
print &th('Oper')
    .&th('Admin')
    .&th('Duplex')
    .&th('Speed')
    .&th('PVID Name')
    .&th('PVID')
    .&th('Egress');
    if ($info->vtp_version()) {
        print &th('VTP Trunk State/Neg.');
    } else {
        print &th('Untagged');
    }
print &th('Last Change')
    .&th('Changed on')
    .&th('Octets In')
    .&th('Octets Out')
    .&th('Bcast In')
    .&th('Bcast Out')
    .&th('Errors In')
    .&th('Errors Out')
    .&th('Discards In')
    .&th('Discards Out')
    .&th('Bad Proto In');
print &th('Qlen_out') if &non_empty($i_qlen_out);
print &th('Mtu')
    .&th('Mac')
    .&th('Type')
    .&th('Description');
print &th('CDP') if &non_empty($c_ip);
print "</TR>";

foreach my $iid (sort { $a <=> $b } keys %$interfaces){
    my $itime = ($info->uptime() - $i_lastchange->{$iid});
    my $TRArgs;
    if ($itime > 0) {
        if ($i_up->{$iid} =~ /^(?:up|dormant)$/) {
            $TRArgs = 'class="opadmup_gt_24h"';
            $TRArgs = 'class="opadmup_lt_24h"' if $itime/100 < 86400;
            $TRArgs = 'class="opadmup_lt_15m"' if $itime/100 < 900;
            $TRArgs = 'class="opupadmdown"'    if $i_up_admin->{$iid} eq "down";
        } else {
            $TRArgs = 'class="opdownadmup_gt_24h"';
            $TRArgs = 'class="opdownadmup_lt_24h"' if $itime/100 < 86400;
            $TRArgs = 'class="opdownadmup_lt_15m"' if $itime/100 < 900;
            $TRArgs = 'class="null"' if $i_up_admin->{$iid} eq "down";
        }
    } else {
            $TRArgs = 'class="warning"'; # Negative time
    }
    $TRArgs = 'class="noneth"' if $i_type->{$iid} ne "ethernetCsmacd";

    my $egress = join('<BR>', &TrueSort(@{$i_vlan_membership->{$iid}})) if $i_vlan_membership->{$iid};

    my @untagged = ();
    foreach (keys %$v_name) {
        next unless $qb_v_untagged;
        next unless @{$qb_v_untagged->{$_}}[($iid-1)];
        push (@untagged, $_) if @{$qb_v_untagged->{$_}}[($iid-1)];
    }
    my $untag = join('<BR>', &TrueSort(@untagged));

    print "\t<TR $TRArgs>".&td($i_index->{$iid}, 'class="dotted_cell"')
        .&td($interfaces->{$iid});
    print &td($i_alias->{$iid}) if &non_empty($i_alias);
    print &td($i_up->{$iid})
        .&td($i_up_admin->{$iid});
    if ($i_duplex->{$iid} and $i_duplex_admin->{$iid}) {
        if ($i_duplex->{$iid} eq 'half' and $i_up->{$iid} eq 'up') {
            print &td("$i_duplex->{$iid}- / $i_duplex_admin->{$iid}", 'class="warning"');
        } else {
            print &td("$i_duplex->{$iid} / $i_duplex_admin->{$iid}");
        }
    } else {
        print &td;
    }
    print &td($i_speed->{$iid});
    if ($i_vlan->{$iid}) {
        print &td($v_name->{$i_vlan->{$iid}})
            .&td($i_vlan->{$iid});
    } else {
        print &td.&td;
    }
    print &td($egress);
    if ($info->vtp_version() and $vtp_trunk_dyn_stat->{$iid} and $vtp_trunk_dyn->{$iid}) {
        print &td("$vtp_trunk_dyn_stat->{$iid} / $vtp_trunk_dyn->{$iid}");
    } else {
        print &td($untag); }
    print &tdn(&timeticks2HR($itime))
        .&td(scalar localtime(time - $itime/100))
        .&td(&convert_bytes($i_octet_in64->{$iid}, 1))
        .&td(&convert_bytes($i_octet_out64->{$iid}, 1))
        .&td($i_pkts_bcast_in64->{$iid})
        .&td($i_pkts_bcast_out64->{$iid})
        .&tde($i_errors_in->{$iid})
        .&tde($i_errors_out->{$iid})
        .&tde($i_discards_in->{$iid})
        .&tde($i_discards_out->{$iid})
        .&tde($i_bad_proto_in->{$iid});
    print &tde($i_qlen_out->{$iid}) if &non_empty($i_qlen_out);
    print &td($i_mtu->{$iid})
        .&td($i_mac->{$iid})
        .&td($i_type->{$iid})
        .&td($i_description->{$iid}, 'nowrap=\"nowrap\"');
# The CDP Table has table entries different than the interface tables.
# So we use c_if to get the map from cdp table to interface table.
    print "</TR>\n" and next unless &non_empty($c_ip);
    my %c_map = reverse %$c_if;
    my $c_key = $c_map{$iid};
    my $portcdp = "<A HREF=\"$0?host=$c_ip->{$c_key}\" TARGET=\"_blank\">$c_id->{$c_key} ($c_port->{$c_key})</A>" if $c_key and defined $c_ip->{$c_key};
    print &td($portcdp);
    print "</TR>\n";
}
print "</TABLE>\n";
# }}}
# {{{ Print the LEGEND table:
print <<EOF;
<P>Legend:</P>
<TABLE class="fancy">
    <TR><TD class="opadmup_gt_24h">Op & Adm UP +24h</TD><TD class="opdownadmup_gt_24h">Op DOWN Adm UP +24h</TD></TR>
    <TR><TD class="opadmup_lt_24h">Op & Adm UP -24h</TD><TD class="opdownadmup_lt_24h">Op DOWN Adm UP -24h</TD></TR>
    <TR><TD class="opadmup_lt_15m">Op & Adm UP -15m</TD><TD class="opdownadmup_lt_15m">Op DOWN Adm UP -15m</TD></TR>
    <TR><TD class="opupadmdown">Op UP Adm DOWN</TD><TD class="null">Op & Adm DOWN</TD></TR>
    <TR><TD class="warning">Warning!</TD><TD class="noneth">Non Ethernet</TD></TR>
</TABLE>
EOF
# }}}

&exec_time if $host;
&footer;
