#!/usr/bin/perl
# Parsea recursivamente un directorio devolviendo la info de las mibs en formato filename -> OID -> NumOID -> Description

use strict;
use File::Find;
use SNMP;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

# Declaro un array de directorios con mibs asignando uno genérico.
my @mibdirs = qw(/usr/share/snmp/mibs);
my $dir = $ARGV[0] || $ENV{PWD};

print "$dir\n";

# Rellena mibdirs con directorios
sub busca_d {
    push(@mibdirs, $File::Find::name) if -d $_;
}

# Extrae info de un fichero
sub procesar_fichero {
    if ( -f $_) {
        my $fname = $_;
        my $file = $File::Find::name; # devuelve el fichero con ruta entera
        local(*INPUT, $/); # Para este INPUT hacemos un undef al carácter de salto de linea, por lo que leera todo el contenido de una vez.
        open (INPUT, $file) or die "No puedo abrir $file: $!";
        my $slurp=<INPUT>; # Metemos el fichero entero dentro de slurp.
        $slurp=~s/[\s\n]+/ /g; # Me cargo todos los retornor de carro y doble espacios
        while ($slurp=~/([-\w]+) OBJECT-TYPE SYNTAX.*?("[^\"]*")/sg) {
                my $oid = SNMP::translateObj("$1");
                if (!defined $oid) { $oid="Error resolviendo OID"; }
                print RED $fname;
                print GREEN BOLD " -> ";
                print WHITE $1;
                print GREEN BOLD " -> ";
                print YELLOW $oid;
                print GREEN BOLD " -> ";
                print BLUE "$2\n";
        }
    }
}

#Devuelve cada fichero dentro de $dir
find(\&busca_d, $dir);

#Preparamos el motor SNMP
$SNMP::debugging = 1;
foreach my $mibdir (@mibdirs) {
    SNMP::addMibDirs($mibdir);
}
SNMP::loadModules("ALL");
SNMP::initMib();

#Devuelve cada fichero dentro de $dir
find(\&procesar_fichero, $dir);
