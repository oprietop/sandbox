#!/usr/bin/perl -w
# http://search.cpan.org/src/HARDAKER/SNMP-5.0401/t/bulkwalk.t

use strict;
use SNMP;
use Data::Dumper;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

# ftp://ftp.enterasys.com/pub/snmp/mibs/cabletron/rbtws-ap-status-mib.txt
my %rbtwoids=(
    rbtwsApStatNumAps                       => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.1',       #Number of APs present and seen by AC (AP in ''ALIVE'' state)."
    rbtwsApStatApStatusBaseMac              => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.2',   #The Base MAC address of this AP."
    rbtwsApStatApStatusAttachType           => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.3',   #How this AP is attached to the AC (directly or via L2/L3 network)."
    rbtwsApStatApStatusPortOrDapNum         => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.4',   #The Port Number if this AP is directly attached, or the CLI-assigned DAP Number if attached via L2/L3 network. Obsoleted by rbtwsApStatApStatusApNum."
    rbtwsApStatApStatusApState              => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.5',   #The State of this AP."
    rbtwsApStatApStatusModel                => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.6',   #The Model name of this AP."
    rbtwsApStatApStatusFingerprint          => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.7',   #The RSA key fingerprint configured on this AP (binary value: it is the MD5 hash of the public key of the RSA key pair). For directly attached APs the fingerprint is a zero length string."
    rbtwsApStatApStatusApName               => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.8',   #The name of this AP, as assigned in AC's CLI; defaults to AP<Number> (examples: 'AP01', 'AP22', 'AP333', 'AP4444'); could have been changed from CLI to a meaningful name, for example the location of the AP (example: 'MeetingRoom73')."
    rbtwsApStatApStatusVlan                 => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.9',   #The name of the VLAN associated with this DAP. Only valid for network attached APs, otherwise zero length string."
    rbtwsApStatApStatusIpAddress            => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.10',  #The IP Address of this DAP. Only valid for network attached APs, otherwise 0.0.0.0."
    rbtwsApStatApStatusUptimeSecs           => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.11',  #Time in seconds since this AP's last boot."
    rbtwsApStatApStatusCpuInfo              => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.12',  #Information about this AP's CPU."
    rbtwsApStatApStatusManufacturerId       => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.13',  #Information about this AP's manufacturer."
    rbtwsApStatApStatusRamBytes             => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.14',  #The memory capacity of this AP (in bytes)."
    rbtwsApStatApStatusHardwareRev          => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.15',  #The hardware revision of this AP (e.g. 'A3')."
    rbtwsApStatApStatusClientSessions       => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.16',  #The number of client sessions on this AP."
    rbtwsApStatApStatusSoftwareVer          => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.17',  #The software version for this AP."
    rbtwsApStatApStatusBootVer              => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.18',  #The boot loader version for this AP."
    rbtwsApStatApStatusApNum                => '.1.3.6.1.4.1.52.4.15.1.4.5.1.1.2.1.19',  #The administratively assigned AP Number. Obsoletes rbtwsApStatApStatusPortOrDapNum."
);

sub SnmpSession() {
    my ($machine, $community) = @_;

    $machine   = 'localhost' unless $machine;
    $community = 'public' unless $community;

    my $session = new SNMP::Session(
        DestHost    => $machine,
        Community   => $community,
        Version     => 2,
        UseNumeric  => 1
    );
    return $session;
}

sub get() {
    my ($machine, $community, $oid) = @_;
    my $session = &SnmpSession($machine, $community);
    if ( $session->{ErrorNum} ) {
        print "Error ".$session->{ErrorNum}." \"".$session->{ErrorStr}."\n en ".$session->{ErrorInd}."\n";
        &end;
        exit 1;
    }
    return $session->get($oid);
}

sub convert_bytes ($$){
     my ($bytes, $dec) = @_;
     foreach my $posfix (qw(bytes Kb Mb Gb Tb Pb Eb Zb Yb)) {
             return sprintf("\%.${dec}f \%s", $bytes, $posfix) if $bytes < 1024;
             $bytes = $bytes / 1024;
     }
}

sub secs2proper($) {
    my $seconds = $_[0];
    return sprintf ("%.1d Days, %.2d:%.2d:%.2d", $seconds/86400, $seconds/3600%24, $seconds/60%60, $seconds%60) if $seconds or return 0;
}

sub dbg() {
   print "<pre>";
   print Dumper $_[0];
   print "</pre>";
}

sub td() {
    return "<TD>@_</TD>" if $_[0] or return "<TD bgcolor=#D1D175><I>Vacío</I></TD>";
}

sub header() {
print "Content-Type: text/html\n\n";
print <<EOF;
<HTML>
    <HEAD>
        <META http-equiv="Content-Type" content="text/html; charset=utf-8">
        <TITLE>OAL!</TITLE>
        <SCRIPT SRC="../sorttable.js"></SCRIPT>
    </HEAD>
<BODY>
EOF
}

sub footer() {
    print "</BODY></HTML>";
    exit 0;
}

sub highlander() {
    use Fcntl qw(LOCK_EX LOCK_NB);

    $0 =~ s/.*\///g;
    open HIGHLANDER, ">>/tmp/perl_$0_highlander" or die "Content-Type: text/html\n\nCannot open highlander: $!";

    my $count = 0;
    {
        flock HIGHLANDER, LOCK_EX | LOCK_NB and last;
        sleep 1;
        redo if ++$count < 10;
        ## No pudimos tener acceso exclusivo al fichero en 10 segundos..
        my $host = $ENV{REMOTE_HOST};
        $host = $ENV{REMOTE_ADDR} unless defined $host;
        warn "$0 @ ".(localtime).": highlander abort for $host after 10 seconds\n";
        print "Content-Type: text/html\n\nOuch!";
        exit 0;
    }
}

my @oids =( $rbtwoids{'rbtwsApStatApStatusApNum'},
            $rbtwoids{'rbtwsApStatApStatusApName'},
            $rbtwoids{'rbtwsApStatApStatusIpAddress'},
            $rbtwoids{'rbtwsApStatApStatusUptimeSecs'},
            $rbtwoids{'rbtwsApStatApStatusClientSessions'},
            $rbtwoids{'rbtwsApStatApStatusBaseMac'},
            $rbtwoids{'rbtwsApStatApStatusVlan'},
            $rbtwoids{'rbtwsApStatApStatusModel'},
            $rbtwoids{'rbtwsApStatApStatusCpuInfo'},
            $rbtwoids{'rbtwsApStatApStatusRamBytes'},
            $rbtwoids{'rbtwsApStatApStatusHardwareRev'},
            $rbtwoids{'rbtwsApStatApStatusSoftwareVer'}
);

my %ap = ();
my $table = '<TABLE class="sortable"; style="text-align: center; border-style:solid; border-width:1px;" border="0" cellspacing="3" SIZE=6>';

sub fillhash() {
    my $machine = "X.X.X.X";
    my $community = "public";
    my $session = &SnmpSession($machine, $community);
    my @VarBinds =();
    foreach (@oids) {
        push @VarBinds, new SNMP::Varbind([$_]);
    }
    my $VarList = new SNMP::VarList( @VarBinds );
    my $deep = &get($machine, $community, '.1.3.6.1.4.1.52.4.15.1.4.2.3.2.1.2.2');
    my @result = $session->bulkwalk( 0, $deep, $VarList );

    if ( $session->{ErrorNum} ) {
        print "Error ".$session->{ErrorNum}." \"".$session->{ErrorStr}."\" en ".$session->{ErrorInd};
        &end;
        exit 1;
    }

    for (0..$#{$result[0]}) {
        $ap{$result[0][$_][2]} = {
            ApNum          => $result[0][$_][2],
            ApName         => $result[1][$_][2],
            IpAddress      => $result[2][$_][2],
            UptimeSecs     => &secs2proper($result[3][$_][2]),
            ClientSessions => $result[4][$_][2],
            BaseMac        => sprintf("%02X:%02X:%02X:%02X:%02X:%02X", unpack("C6", $result[5][$_][2])),
            Vlan           => $result[6][$_][2],
            Model          => $result[7][$_][2],
            CpuInfo        => $result[8][$_][2],
            RamBytes       => &convert_bytes($result[9][$_][2], 0),
            HardwareRev    => $result[10][$_][2],
            SoftwareVer    => $result[11][$_][2]
        };
    }
}

sub aptable() {
    print "$table<TR bgcolor=#AAAAAA>".&td('ApNum').&td('ApName').&td('IpAddress').&td('UptimeSec').&td('ClientSessions').&td('BaseMac').&td('Vlan').&td('Model').&td('CpuInfo').&td('RamBytes').&td('HardwareRev').&td('SoftwareVer');
    foreach my $key (sort { $a <=> $b } keys %ap) {
        print "<TR bgcolor=#DDDDDD>\n";
        print "\t".&td($ap{$key}{'ApNum'}).&td($ap{$key}{'ApName'}).&td($ap{$key}{'IpAddress'}).&td($ap{$key}{'UptimeSecs'}).&td($ap{$key}{'ClientSessions'}).&td($ap{$key}{'BaseMac'}).&td($ap{$key}{'Vlan'}).&td($ap{$key}{'Model'}).&td($ap{$key}{'CpuInfo'}).&td($ap{$key}{'RamBytes'}).&td($ap{$key}{'HardwareRev'}).&td($ap{$key}{'SoftwareVer'});
        print "</TR>\n";
    }
        print "</TABLE>\n";
}

&highlander;
&header;
&fillhash;
print "<B>".scalar (keys %ap)." Ap's Online en Wireless-Switch.</B><BR/>\n";
&aptable;
&footer;
