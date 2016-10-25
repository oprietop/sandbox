#!/bin/bash
# Wrapper sobre wvdial para módems 3G con Movistar (PIN Desactivado)
set +o posix # usaremos file descriptors
set -u       # exit si hay variables sin asignar

ok() { echo -ne "\e[32m#\n#\t$1\n#\e[m\n"; }
nk() { echo -ne "\e[31m#\n#\t$1\n#\e[m\n"; exit 1; }

ok "Verificando binarios:"
which wvdialconf wvdial pppd sed || nk "Faltan binarios!"

ok "Buscando módem con wvdial:"
USB=$(wvdialconf /$RANDOM/$RANDOM | sed -n 's/^Found .\+ modem on \(.\+\)\.$/\1/p')
[ $USB ] || nk "No se ha detectado el módem!"

ok "Conexión PPP en $USB"
exec 4<<__EOF__
[Dialer Defaults]
Modem       = $USB
Baud        = 460800
Init1       = ATZ
Init2       = ATQ0 V1 E1 S0=0 &C1 &D2 +FCLASS=0
Init3       = AT+CGDCONT=1,"IP","movistar.es"
Stupid Mode = 1
Phone       = *99***1#
Username    = MOVISTAR
Password    = MOVISTAR
__EOF__
wvdial -C /proc/$$/fd/4

ok "Out!"
