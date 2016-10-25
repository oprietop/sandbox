#!/bin/bash
# basic/crappy shnsplit frontend
set -u # Exit if unbound variables
set -e # Exit is any exit status value >0

ok() { echo -ne "\e[32m# $1\e[m\n"; }
nk() { echo -ne "\e[31m# $1\e[m\n"; exit 1; }

ok "Checking required binaries."
for i in sed readlink basename dirname shnsplit flac; do
    [ -f "$(which $i)" ] || { nk "Can't find '$i'.";}
done

ok "Getting the cuesheet dirname and filename w/o extension."
CUENAME=$(basename "$1" | sed -n 's/^\(.*\)\.cue$/\1/p')
DIRNAME=$(dirname "$(readlink -f "$1")")

ok "Getting the single audio filename and extension from the cuesheet."
eval $(sed -n 's/^FILE "\([^"]\+\)\.\([^\.]\+\)" WAVE.*/NAME="\1"; EXT="\2"/p' "$1")

ok "Checking if the previous audio file does exist."
if [ ! -f "${DIRNAME}/${NAME}.${EXT}" ]; then
    nk "Bad cuesheet, '${NAME}.${EXT}' does not exist."
fi

ok "Spliting/converting '${NAME}.${EXT}' on the fly into the '${CUENAME}' directory."
mkdir "$CUENAME"
shnsplit -D -o "flac flac -8 -s -o %f -" -d "$CUENAME" -t "%n - %t" -f "$1" "${DIRNAME}/${NAME}.${EXT}"

ok "OK"
