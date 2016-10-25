#!/usr/bin/perl
# Assing hours on the current week

use strict;
use warnings;
use IO::Handle;
use LWP::UserAgent;
use URI::Escape;
use HTTP::Request::Common;

my $initials = '';       # name (3 letters)
my $pass     = '';       # password
my $defproj  = '';       # default project (EXXXXX)
my $deftask  = 'DEF';    # default description
my @holidays = qw(24/12/2013 25/12/2013 26/12/2013 31/12/2013); # holidays
my $holproj  = 'FESTIU'; # holidays project
my @vacation = qw(12/12/2010); # vacation days
my $vacproj  = 'VACANC'; # vacation project
my $sid      = (60 * 60 * 24); # (Seconds In Day) Secs * Mins * Hours

# Ask for user/pass/project if not previously filled
print "Initials (xxx): " and chomp($initials = <>) while $initials !~ /^[a-z]{3}$/;
$pass = uri_escape($pass);
print 'Password: ' and chomp($pass = <>) while not $pass;
print "Project (EXXXXX): " and chomp($defproj = <>) while $defproj !~ /^[Ee]\d{5}$/;

# Define and fill our needed variables
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
my $today = sprintf("%02d/%02d/%04d", $mday, $mon+1, $year+1900);
my $dow = qw(7 1 2 3 4 5 6)[$wday]; # (Day Of Week) $wday begins with sunday at 0
my $woy = int(($yday+1)/7)+1; # (Week Of Year)
print "Initials:'$initials' Project:'$defproj' WeekOfYear:'$woy' DayOfWeek:'$dow' Today:'$today'\n";

# Define and forge our POST arguments
my %args = ( INSERIR    => 'Y'
           , p_inicials => $initials
           , setmana    => $woy
           , ann        => $year+1900
           , num_files  => 7
           );

foreach my $day (1..5) {
    # Calculate the date for the current day of week
    my $res = time() + ((-$dow + $day) * $sid);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($res);
    my $date = sprintf("%02d/%02d/%04d", $mday, $mon+1, $year+1900);

    # Use the apropiated project
    my $proj = $defproj;
    $proj = $holproj if grep { /$date/ } @holidays;
    $proj = $vacproj if grep { /$date/ } @vacation;

    # Merge our post arguments hash with the data of the current day of week
    print "[$day] $date - $proj - $deftask\n";
    %args = (%args, "cmbDia_$day"             , $date
                  , "c_exe$day"               , $proj
                  , "c_hores_${day}_$day"     , '08:00'
                  , "c_horesFact_${day}_$day" , '08:00'
                  , "DescripcioTasca$day"     , $deftask
            );
}

# POST
my $ua = LWP::UserAgent->new( agent         => 'Windows IE 6' # ORLY
                            , show_progress => 1
                            , timeout       => 10
                            );
my $resp = $ua->request( POST "http://$initials:$pass\@www.xxxxxxx.net/intranet_cs/scripts/setmana2.asp"
                       , \%args
                       );
$resp->is_success ? exit 0 : print $resp->headers_as_string."\n";
