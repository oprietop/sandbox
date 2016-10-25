#!/usr/local/bin/bash

#AUTHD_ACCOUNT="test"
#AUTHD_PASSWORD="test"
#AUTHD_REMOTE_IP="127.0.0.1"
$AUTHD_ACCOUNT=${AUTHD_ACCOUNT//[^a-zA-Z0-9_]/}
$AUTHD_PASSWORD=${AUTHD_PASSWORD//[^a-zA-Z0-9_]/}
$AUTHD_REMOTE_IP=${AUTH_REMOTE_IP//[^a-zA-Z0-9_]/}


RES=$(sqlite3 ftpusers.db "SELECT Password,Uid,Gid,Dir,QuotaFiles,QuotaSize,ULBandwidth,DLBandwidth,ULRatio,DLRatio FROM users WHERE User = '"$AUTHD_ACCOUNT"' AND Status = '1' AND (Ipaddress = '*' OR Ipaddress LIKE '"$AUTHD_REMOTE_IP"')")
ARRAY=( ${RES//|/ } )
MD5PASS=$(echo -n "$AUTHD_PASSWORD" | md5)

#cat <<-EOF > /tmp/test
#'$AUTHD_ACCOUNT'
#'$AUTHD_PASSWORD'
#'$AUTHD_LOCAL_IP'
#'$AUTHD_LOCAL_PORT'
#'$AUTHD_REMOTE_IP'
#'$AUTHD_ENCRYPTED'
#'$RES'
#'$MD5PASS'
#EOF

if [ "${ARRAY[0]}" == "$MD5PASS" ]; then
    echo 'auth_ok:1'
    echo "uid:${ARRAY[1]}"
    echo "gid:${ARRAY[2]}"
    echo "dir:${ARRAY[3]}"
    [ ${ARRAY[4]} ] || echo "throttling_bandwidth_ul:${ARRAY[4]}"
    [ ${ARRAY[5]} ] || echo "throttling_bandwidth_dl:${ARRAY[5]}"
    [ ${ARRAY[6]} ] || echo "user_quota_size:${ARRAY[6]}"
    [ ${ARRAY[7]} ] || echo "user_quota_files:${ARRAY[7]}"
    [ ${ARRAY[8]} ] || echo "ratio_upload:${ARRAY[8]}"
    [ ${ARRAY[9]} ] || echo "ratio_download:${ARRAY[9]}"
    echo 'end'
    exit 0
fi
echo 'auth_ok:0'
echo 'end'

