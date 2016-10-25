#/usr/bin/sh
# Network connect wrapper. It can fetch the binary+certificate and handle resolv.conf
# It needs 32bits compatibility. Arch: pacman -S lib32-glibc lib32-gcc-libs lib32-zlib

set -u # Exit if unbound variables
set -e # Exit is any exit status value >0

# Variables
HOST=
REALM=
USER=
PASS=

ok() { echo -ne "\e[32m# $1\e[m\n"; }
nk() { echo -ne "\e[31m# $1\e[m\n"; exit 1; }

# Housekeeping trap
trap cleanup EXIT
cleanup() {
    ok "Exiting..."
    ./ncsvc -K
    popd
    rm -rf $DIR
    chattr -i /etc/resolv.conf
    exit 0
}

# Check userland
BIN="openssl curl unzip sed ip chmod chattr"
ok "Looking for '$BIN':"
which $BIN || nk "Missing binaries!"

# Fill unbound variables
[ $HOST ] || { ok "Hostname: "; read -r HOST; }
[ $REALM ] || { ok "Realm: "; read -r REALM; }
[ $USER ] || { ok "User: "; read -r USER; }
[ $PASS ] || { ok "Pass: "; read -r -s PASS; }

ok "Sandboxing..."
pushd $(mktemp -d) && DIR=$(pwd)

ok "Getting the certificate from $HOST"
openssl s_client -connect $HOST:443 < /dev/null | openssl x509 -outform DER > cert.der

ok "Logging into '$REALM'."
URL="https://$HOST/dana-na/auth/url_default/login.cgi"
PAGE=$(curl -s -L -k $URL -d "tz_offset=60&username=$USER&password=$PASS&realm=$REALM&btnSubmit=Sign In" -c cookie.txt -b cookie.txt)

# Try to deal with parallel sessions
if echo "$PAGE" | grep -q "btnContinue" ; then
   BTNTEXT=$(echo "$PAGE" | sed -n 's/.*name="btnContinue" value="\([^"]\+\)".*/\1/p')
   echo "Warning, got '$BTNTEXT'. Reconnecting..."
   FORMDATASTR=$(echo "$PAGE" | sed -n 's/.*name="FormDataStr" value="\([^"]\+\)".*/\1/p')
   SIDS=($(echo "$PAGE" | sed -n 's/.*name="postfixSID" value="\([^"]\+\)".*/postfixSID=\1/p')) # Get only the first SID
   PAGE=$(curl -s -L -k $URL -d "$SIDS" --data-urlencode "btnContinue=$BTNTEXT" --data-urlencode "FormDataStr=$FORMDATASTR" -c cookie.txt -b cookie.txt)
fi
echo "$PAGE" | grep -q ">Please wait" && ok "Ok, we're inside!" || nk "Failed!"

ok "Fetching ncLinuxApp.jar"
curl -L -k "https://secure.uoc.edu/dana-cached/nc/ncLinuxApp.jar" -O -c cookie.txt -b cookie.txt
file -bs ncLinuxApp.jar
ok "Extracting the client."
unzip -o ncLinuxApp.jar ncsvc || nk "Could not extract contents..."
chmod +x ./ncsvc && ./ncsvc -v
ok "Launching ncsvc."
chattr -i /etc/resolv.conf # ncsvc won't work if resolv.conf is inmmutable at this point
./ncsvc -u $USER -p $PASS -h $HOST -r $REALM -f cert.der&

while true ; do sleep 20 ; clear
    chattr +i /etc/resolv.conf # Avoid the dhcp client messing with resolv.conf
    ok "resolv.conf" && cat /etc/resolv.conf
    ok "Interfaces" && ip -s a
    ok "Routes" && ip r
done
