#!/bin/bash
#
set -o nounset
set -e
ok() { echo -ne "\e[32m# $1\e[m\n"; }
nk() { echo -ne "\e[31m# $1\e[m\n"; exit 1; }

ok "$(basename $0) Monta livefs de archlinux en ram"
[ -e /cp2ram ] && nk "El Directorio /cp2ram ya existe."
[ $(whoami) != "root" ] && nk "Se requiere root."
ok "Verificando ram libre:"
FREE=$(free -m | sed -n 's/^-.* \([0-9]\+\)$/\1/p')
[ "600" -ge "$FREE" ] && nk "Se necesitan al menos 600 megas de ram." || ok "${FREE}MB libres."
ok "Esctibe OK para continuar..."
read -r choice
[ "$choice" = "OK" ] || nk "Saliendo"
ok "Creando directorio /cp2ram:"
mkdir /cp2ram
ok "Copiando contenido de /bootmnt a /cp2ram:"
cp -a /bootmnt/* /cp2ram/
sync
sleep 1
ok "desmontando /bootmt:"
umount /bootmnt
ok "Bindeando /cp2ram a /bootmnt:"
mount --bind /cp2ram /bootmnt  && {
    ok "Expulsando discos con label ARCH_*:"
    blkid | sed -n 's/^\(.\+\): LABEL="ARCH_[0-9]\+" TYPE="udf"/\1/p' | xargs -n1 eject
} || {
    nk "No se pudo hacer binding."
}
ok "Todo OK!"
