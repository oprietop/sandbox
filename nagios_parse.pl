#!/usr/bin/perl
# Prints service info from nagios hosts
# http://nagios.sourceforge.net/docs/3_0/configobject.html
# http://nagios.sourceforge.net/docs/3_0/objectinheritance.html

use strict;
use Data::Dumper;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1; # It doesn't seem to work everywhere.

my $cfg = "/opt/local/nagios/etc/nagios.cfg";
my %nagios_conf = ();
my %resources   = ();
my %objects     = ();

sub slurpfile {
    my $file = shift;
    local(*INPUT, $/);
    open (INPUT, '<', $file) or die "Error opening '$file': $!";
    my $slurp = <INPUT>;
    close(INPUT);
    return $slurp;
}

sub prt {
    my $tabs  = shift || 1;
    my $key   = shift || return;
    my $value = shift || return;
    print YELLOW "\t" x ($tabs).$key;
    print BLUE " => ";
    print "'$value'\n";
}

sub buildcmd {
    my ($cmd, $host) = @_;
    my @check_args = split (/!/, $cmd);
    $cmd = $objects{command}{$check_args[0]}{command_line};
    $cmd =~ s/(\$USER\d*\$)/$resources{$1}/g;
    $cmd =~ s/\$HOSTADDRESS\$/$objects{host}{$host}{address}/g;
    $cmd =~ s/\$ARG(\d)\$/$check_args[$1]/g;
    return $cmd;
}

# Build a hash with the nagios.cfg params.
my $slurp = &slurpfile($cfg);
$nagios_conf{$1} = $2 while $slurp =~ /^([^\n=#]+?)\s*=\s*([^\n]+)\s*$/gm;

# Get the location of our relevant files.
my $ocf = $nagios_conf{object_cache_file} || die "No 'object_cache_file' entry on nagios.cfg\n";
my $resfile = $nagios_conf{resource_file} || die "No 'resource_file' entry on nagios.cfg\n";

# Build a hash with the resurce.cfg params.
$slurp = &slurpfile($resfile);
$resources{$1} = $2 while $slurp =~ /^\s*?(\$USER\d*\$)\s*=\s*(.*)$/gm;

# Build a hash with the objects.cache elements.
$slurp = &slurpfile($ocf);
while ($slurp =~ /^define\s(\w+)\s{([^{]+)}/gm) {
    my ($type, $data) = ($1, $2);
    my %array = ();
    my ($oname, $hostname);
    while ($data =~ /^\s+(\S+)\s+(.+?)\s*$/gm) {
        my ($first, $second) = ($1, $2);
        $array{$first} = $second;
        $oname = $second if $first =~ /(${type}_(?:name|description))/;
        $hostname = $second if $first =~ /host_name/;
    }
    if ($hostname) {
        $type eq 'host' ? $objects{$type}{$oname} = \%array : $objects{$type}{$hostname}{$oname} = \%array;
    } else {
        $objects{$type}{$oname} = \%array;
    }
}

# Print the info we want for each argument/host that matches our args.
foreach my $arg (@ARGV) {
    foreach my $host (sort keys %{$objects{host}}) {
        if ($host =~ /$arg/i) {
            print BOLD RED "Host '$host' does not exist.\n" and next unless $objects{host}{$host};
            print BOLD GREEN "$host\n";
            my %result = %{$objects{host}{$host}};
            print BOLD CYAN "\thost\n";
            prt(2, 'address', $result{address});
            prt(2, 'alias', $result{alias});
            prt(2, 'check_command', $result{check_command});
            prt(2, $result{check_command}, $objects{command}{$result{check_command}}{command_line});
            prt(2, 'exec_command', buildcmd($result{check_command}, $host));
            prt(2, 'notes_url', $result{notes_url});
            print BOLD CYAN "\tservices\n";
        }
        my $count = 0;
        foreach my $service (sort keys %{$objects{service}{$host}}) {
            next unless $host =~ /$arg/i or $service =~ /$arg/i;
            print BOLD GREEN "$host\n" and print BOLD CYAN "\tservices\n" if (not $count++ and $host !~ /$arg/i); # Only the 1st time
            print GREEN "\t\t$service\n";
            prt(3, 'alias', $objects{service}{$host}{$service}{alias});
            prt(3, 'check_command', $objects{service}{$host}{$service}{check_command});
            my @check_args = split (/!/, $objects{service}{$host}{$service}{check_command});
            prt(3, $check_args[0], $objects{command}{$check_args[0]}{command_line});
            prt(3, 'exec_command', buildcmd($objects{service}{$host}{$service}{check_command}, $arg));
            prt(3, 'notes_url', $objects{service}{$host}{$service}{notes_url});
        }
    }
}

# Print all the objects if not argument was used.
print Dumper \%objects unless @ARGV;
