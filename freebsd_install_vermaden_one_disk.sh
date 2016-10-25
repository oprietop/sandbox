#!/bin/sh -x
# http://forums.freebsd.org/showthread.php?t=31662

# Partitioning
#DISKS="ada0 ada1"
DISKS="ada0"
for I in ${DISKS}; do
NUMBER=$( echo ${I} | tr -c -d '0-9' )
    gpart destroy -F ${I}
    gpart create -s GPT ${I}
    gpart add -t freebsd-boot -l bootcode${NUMBER} -s 128k ${I}
    gpart add -t freebsd-zfs -l sys${NUMBER} ${I}
    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${I}
done

# ZFS
# zpool create -f -o cachefile=/tmp/zpool.cache sys mirror /dev/gpt/sys*
zpool create -f -o cachefile=/tmp/zpool.cache sys /dev/gpt/sys*
zpool set feature@lz4_compress=enabled sys
zfs set compression=lz4 sys
zfs set mountpoint=none sys
zfs set checksum=fletcher4 sys
zfs set atime=off sys
zfs create -V 1G sys/SWAP
zfs set org.freebsd:swap=on sys/SWAP
zfs set checksum=off sys/SWAP
zfs set copies=1 sys/SWAP
zfs create sys/ROOT
zfs create -o mountpoint=/mnt sys/ROOT/default
zpool set bootfs=sys/ROOT/default sys

# Install OS
cd /usr/freebsd-dist/
for I in base.txz kernel.txz; do
tar --unlink -xvpJf ${I} -C /mnt
done
cp /tmp/zpool.cache /mnt/boot/zfs/

# Prepare config files
cat << EOF >> /mnt/boot/loader.conf
loader_logo="beastie"
verbose_loading="YES"
autoboot_delay=1
comconsole_speed="115200"
console="vidconsole,comconsole"
boot_multicons="YES"
coretemp_load="YES"
ahci_load="YES"
aio_load="YES"
zfs_load="YES"
vfs.root.mountfrom="zfs:sys/ROOT/default"
EOF
cat << EOF >> /mnt/etc/rc.conf
hostname="freebs92"
ifconfig_em0="SYNCDHCP"
#ifconfig_em1="xn0 192.168.2.1 netmask 255.255.255.0"
zfs_enable="YES"
keymap="spanish.iso.acc"
tmpmfs="YES"
tmpsize="512m"
tmpmfs_flags="-m 0 -o async,noatime -S -p 1777"
syslogd_flags="-ss"
sshd_enable="YES"
inetd_enable="NO"
sendmail_enable="NO"
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"
named_enable="NO"
clear_tmp_enable="YES"
ntpd_enable="NO"
EOF
echo 'PermitRootLogin yes' >> /mnt/etc/ssh/sshd_config
echo 'PermitEmptyPasswords yes' >> /mnt/etc/ssh/sshd_config
echo 'security.bsd.see_other_uids=0' >> /mnt/etc/sysctl.conf
echo 'security.bsd.see_other_gids=0' >> /mnt/etc/sysctl.conf
:> /mnt/etc/fstab

# Clean and reboot
zfs umount -a
zfs set mountpoint=legacy sys/ROOT/default
#reboot

# Enable SSH on a FreeBSD LiveCD
# mkdir /tmp/etc
# mount_unionfs /tmp/etc /etc
# vi /etc/ssh/sshd_config # to permit root login
# passwd root
# service sshd onestart
