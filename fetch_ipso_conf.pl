#!/usr/bin/perl -w
# Create and fetch a backup file from a Nokia Ipso device.

use strict;
use warnings;

use POSIX qw(strftime);
use Net::OpenSSH;
#$Net::OpenSSH::debug |= 16; # Debug

my $host = $ARGV[0] || 'host';
my $user = $ARGV[1] || 'user';
my $pass = $ARGV[2] || 'pass';
my $path = '/tmp';

print "Connecting to $host... ";
my $ssh = Net::OpenSSH->new( $host
                           , port                  => 22
                           , user                  => $user
                           , passwd                => $pass
                           , master_opts           => [-o => "StrictHostKeyChecking=no"]
                           , master_stderr_discard => 1
                           , timeout               => 120
                           );
$ssh->error ? die "Can't connect to '$ssh->{_host}'.\n" : print "OK\n";

sub ssh_cmd($$) {
    my $ssh = shift;
    my $cmd = shift;
    my ($stdout, $stderr) = $ssh->capture2($cmd);
    $ssh->error and die "Failed executing '$cmd' remotely: " . $ssh->error."\n";
    return $stdout;
}

my $file = "ipso-backup_".strftime("%Y%m%d", localtime).".tgz";
my $hostname = ssh_cmd($ssh, 'hostname');
$hostname =~ s/[^\w-]//g;
$path .= "/$hostname";
mkdir $path || die "Error creating $path locally...\n";
print "Creating backup file $file on $hostname...\n";
ssh_cmd($ssh, 'clish -c "set backup manual filename ipso-backup"');
ssh_cmd($ssh, 'clish -c "set backup manual on"');
print "Writing $file on '$path'... ";
$ssh->scp_get("/var/backup/$file", "$path");
$ssh->error ? die " ERROR'.\n": print "OK (".(-s "$path/$file")." bytes)\n";
