#!/bin/bash
# Creaites a 32 bit chroot on archlinux
set +o posix

[ $USER = "root" ] || { echo "requiere root"; exit 1; }
which mkarchroot linux32 mount umount || exit 1

CHROOT="/opt/arch32"
[ $1 ] && CHROOT=$1

exec 3<<__EOF__
[options]
HoldPkg      = pacman glibc
SyncFirst    = pacman
Architecture = i686

[core]
SigLevel = Never
Server   =  http://archlinux.polymorf.fr/core/os/i686
[extra]
SigLevel = Never
Server   =  http://archlinux.polymorf.fr/extra/os/i686
[community]
SigLevel = Never
Server   =  http://archlinux.polymorf.fr/community/os/i686
[archlinuxfr]
SigLevel = Optional TrustAll
Server   = http://repo.archlinux.fr/i686
__EOF__

exec 4<<__EOF__
DLAGENTS=('ftp::/usr/bin/wget -c --passive-ftp -t 3 --waitretry=3 -O %o %u'
          'http::/usr/bin/wget -c -t 3 --waitretry=3 -O %o %u'
          'https::/usr/bin/wget -c -t 3 --waitretry=3 --no-check-certificate -O %o %u'
          'rsync::/usr/bin/rsync -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
CARCH="i686"
CHOST="i686-unknown-linux-gnu"
CFLAGS="-march=i686 -mtune=generic -O2 -pipe"
CXXFLAGS="-march=i686 -mtune=generic -O2 -pipe"
LDFLAGS="-Wl,--hash-style=gnu -Wl,--as-needed"
BUILDENV=(fakeroot !distcc color !ccache)
OPTIONS=(strip docs libtool emptydirs zipman purge)
INTEGRITY_CHECK=(md5)
MAN_DIRS=({usr{,/local}{,/share},opt/*}/{man,info})
DOC_DIRS=(usr/{,local/}{,share/}{doc,gtk-doc} opt/*/{doc,gtk-doc})
STRIP_DIRS=(bin lib sbin usr/{bin,lib,sbin,local/{bin,lib,sbin}} opt/*/{bin,lib,sbin})
PURGE_TARGETS=(usr/{,share}/info/dir .packlist *.pod)
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'
__EOF__

# Create if doesn't exist or update the chroot
if [ ! -d ${CHROOT} ] ; then 
    echo -e "#\n#\tCreating chroot in ${CHROOT}\n#"
    linux32 mkarchroot -C /proc/$$/fd/3 -M /proc/$$/fd/4 ${CHROOT} base base-devel
else
    echo -e "#\n#\tUpgrading chroot in ${CHROOT}\n#"
    linux32 mkarchroot -u ${CHROOT} || exit 1
fi

echo -e "#\n#\tCreating bindings to the chroot\n#"
dirs=(/tmp /dev /dev/pts /home)
for dir in "${dirs[@]}"; do
    echo "binding $dir on ${CHROOT}$dir"
    mount -o bind $dir "${CHROOT}$dir"
done
echo "mounting /proc and /sys"
mount -t proc none "${CHROOT}/proc"
mount -t sysfs none "${CHROOT}/sys"

echo "# Copying some files"
cp -v /etc/resolv.conf "${CHROOT}/etc/resolv.conf"

echo -e "#\n#\tEntering the chroot\n#"
linux32 chroot ${CHROOT} /bin/bash

echo -e "#\n#\tUmounting bindings\n#"
umount "${CHROOT}/"{sys,proc}
dirs=(/home /dev/pts /tmp)
for dir in "${dirs[@]}"; do
    echo "umounting ${CHROOT}$dir"
    umount "${CHROOT}/$dir"
done
echo "Wating 5 seconds to umount /dev"
sleep 5s
echo "umounting ${CHROOT}/$dev"
umount "${CHROOT}/dev"	
echo -e "#\n#\tOk\n#"
