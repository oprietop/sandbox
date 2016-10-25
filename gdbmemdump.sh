#!/bin/bash
# dump all the memory contents of a process using the maps file and gdb
[ -r /proc/$1/maps ] || { echo "Can't find process."; exit 1;}
DIR="gdbmemdump_$1"
mkdir $DIR
cp /proc/$1/maps "$DIR/memory_maps"
sed -n "s@\([^-]\+\)-\([^ ]\+\).*@dump memory $DIR/\1-\2.dump 0x\1 0x\2@p" /proc/$1/maps > "$DIR/gdb_commands"
gdb -batch --pid $1 -n -x "$DIR/gdb_commands"
