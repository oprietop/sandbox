#!/usr/bin/perl -w
use strict;
use SNMP;
use Getopt::Long;
use Net::Telnet;
use POSIX qw(strftime);
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

$0 =~ s/.*\///g;
my @cmds = ();
my $file = 0;

GetOptions ( 'command=s' => \@cmds
           , 'file'    => \$file
           );

unless (@ARGV) {
    print <<EOF;
Usage: $0 <host/s> --command <Command to send>
Args:
\t--command, -c\tOptional, can be repeated. Commands to send, use quotes for space-separated arguments.
\t\t\tIf no commands specified, it will use "show config".
\t--file\t\tOptional. Print the command output to a file.
Example: $0 management.fqdn.com -c "show version" -c "show interface status" -c "show interface trunk"
EOF
exit 1;
}

my %chuis =();
$chuis{'.1.3.6.1.4.1.2467.4.7'}        = {name => 'CSS11501',         user => '', pass => '', runcmd => 'terminal length 65535', defcmd => 'show running-config'};
$chuis{'.1.3.6.1.4.1.9.1.359'}         = {name => 'WS-C2950T-24',     user => '', pass => '', runcmd => 'terminal length 0', enable => ''};
$chuis{'.1.3.6.1.4.1.9.1.559'}         = {name => 'WS-C2950T-48-SI',  user => '', pass => '', runcmd => 'terminal length 0', enable => ''};
$chuis{'.1.3.6.1.4.1.9.1.716'}         = {name => 'WS-C2960-24TT-L',  user => '', pass => '', runcmd => 'terminal length 0', enable => ''};
$chuis{'.1.3.6.1.4.1.9.1.717'}         = {name => 'WS-C2960-48TT-L',  user => '', pass => '', runcmd => 'terminal length 0', enable => ''};
$chuis{'.1.3.6.1.4.1.9.1.696'}         = {name => 'WS-C2960G-24TC-L', user => '', pass => '', runcmd => 'terminal length 0', enable => ''};
$chuis{'.1.3.6.1.4.1.9.1.1000'}        = {name => 'WS-CBS3012-IBM-I', user => '', pass => '', runcmd => 'terminal length 0', enable => ''};
$chuis{'.1.3.6.1.4.1.5624.2.2.220'}    = {name => 'C2H124-48',        user => '', pass => ''};
$chuis{'.1.3.6.1.4.1.5624.2.2.286'}    = {name => 'C2H124-48P',       user => '', pass => ''};
$chuis{'.1.3.6.1.4.1.5624.2.1.100'}    = {name => 'B3G124-24',        user => '', pass => ''};
$chuis{'.1.3.6.1.4.1.5624.2.1.53'}     = {name => '7H4382-25',        user => '', pass => ''};
$chuis{'.1.3.6.1.4.1.5624.2.1.59'}     = {name => '1H582-25',         user => '', pass => '', runcmd => 'set terminal rows disable'};
$chuis{'.1.3.6.1.4.1.5624.2.1.34'}     = {name => '1H582-51',         user => '', pass => '', runcmd => 'set terminal rows disable'};
$chuis{'.1.3.6.1.4.1.3224.1.51'}       = {name => 'SSG-550M',         user => '', pass => '', runcmd => 'set cli screen-length 0', defcmd => 'get config'};
$chuis{'.1.3.6.1.4.1.2636.1.1.1.2.31'} = {name => 'ex4200-24p',       user => '', pass => '', runcmd => 'set cli screen-length 0'};
$chuis{'.1.3.6.1.4.1.2636.1.1.1.2.30'} = {name => 'ex3200-24p',       user => '', pass => '', runcmd => 'set cli screen-length 0'};
$chuis{'.1.3.6.1.4.1.52.4.15.1.3.1.2'} = {name => 'RBT-8200',         user => '', pass => '', runcmd => 'set length 0', enable => ''};

my @communities = qw/public admin@public/;

sub getSNMP() {
    my $machine   = shift || 'localhost';
    my $community = shift || 'public';
    my $oid       = shift || '.1.3.6.1.2.1.1.2.0';
    my $session   = new SNMP::Session( DestHost   => $machine
                                     , Community  => $community
                                     , Version    => 2
                                     , UseNumeric => 1
                                     );
    if ($session) {
        my $result = $session->get($oid);
        if ($result) {
            return $result;
        } else {
            print RED "#\tNo SNMP response from '$machine' using '$community'.\n";
            return 0;
        }
    } else {
        print RED "#\tNo SNMP session from '$machine'\n";
        return 0;
    }
}

foreach my $host (@ARGV) {
    my $sysObjectID = 0;
    print BOLD WHITE "#\n#\tTrying '$host'...\n#\n";
    foreach (@communities) {
        $sysObjectID = &getSNMP($host, $_, );
        last if $sysObjectID;
    }
    if ($sysObjectID) {
        if ($chuis{$sysObjectID}{name}) {
            print GREEN "#\tHardware: $chuis{$sysObjectID}{name} ($sysObjectID)\n";
        } else {
            print BOLD RED "#\t$sysObjectID no está en el hash:\n";
            foreach my $key (sort keys %chuis) {
                next unless $chuis{$key}{name};
                print GREEN "#\t$chuis{$key}{name}";
                print BOLD GREEN " $key\n";
            }
            next;
        }
    } else {
        print BOLD RED "#\tNo SNMP response from '$host'.\n";
        next;
    }

    my $telnet = new Net::Telnet ( Timeout => 10
                                 , Errmode => 'return'
                                 , Prompt  => '/(?m:.*[\w.-]+\s?(?:\(config[^\)]*\))?\s?[\+\$#>]\s?(?:\(enable\))?\s*$)/'
                                 );
    $telnet->open($host);
    $telnet->login($chuis{$sysObjectID}{user}, $chuis{$sysObjectID}{pass});
    my $prompt = $telnet->last_prompt;
    $prompt =~ tr/\015//d;

    if ($prompt) {
        print GREEN "#\tStrip Prompt -> '$prompt'\n";
    } else {
        print RED "#\tUnable to get prompt.\n";
        next;
    }

    if ($chuis{$sysObjectID}{enable}) {
        print GREEN "#\tSending enablepass...";
        $telnet->print('enable');
        $telnet->waitfor('/password/i');
        $telnet->cmd($chuis{$sysObjectID}{enable});
        if ($telnet->lastline =~ /denied/i) {
            print BOLD RED " NOK\n#\tSkipping Host '$host'\n";
            next;
        } else {
            print BOLD GREEN " OK\n";
        }
    }

    if ($chuis{$sysObjectID}{runcmd}) {
        print GREEN "#\tSending runcmd '$chuis{$sysObjectID}{runcmd}'\n";
        $telnet->cmd($chuis{$sysObjectID}{runcmd});
    }

    my $filename = "${host}-".strftime("%Y%m%d-%H%M%S", localtime).".txt";
    $filename =~ s/[^\.\w:-]/_/g;
    my $defcmd = $chuis{$sysObjectID}{defcmd} || "show config";
    @cmds = ("$defcmd") unless @cmds;
    open(LOG, ">> $filename") || print BOLD RED "#\tCan't open '$filename'" if $file;

    foreach (@cmds) {
        s/[\n\t\f]+/ /g;
        print CYAN "#\tExecuting '$_' on '$host'\n\n";
        my $output = join('', $telnet->cmd("$_"));
        print "${prompt}$_\n$output";
        print CYAN "#\tEOF '$_' on '$host'.\n";
        if ($file) {
            print GREEN "#\tWriting output on '$filename'.\n";
            $output =~ tr/\015//d;
            $output =~ s/\s+\n/\n/g;
            print LOG "${prompt}$_\n$output";
        }
    }
    close(LOG);
}
