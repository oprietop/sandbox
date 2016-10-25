#!/bin/bash
# usage $0 <url1> <url2> ...
curl_vars=( url_effective http_code http_connect time_total time_namelookup time_connect time_appconnect time_pretransfer time_redirect time_starttransfer size_download size_upload size_header size_request speed_download speed_upload content_type )

for var in ${curl_vars[@]}; do
    cmd_vars="${cmd_vars}${var}: %{$var}\n"
done

while (($#)); do
    echo "# $1"
    curl -Lso /dev/null -H "Pragma: no-cache" -H "Cache-Control: no-cache" -w "$cmd_vars" "$1"
    shift
done
