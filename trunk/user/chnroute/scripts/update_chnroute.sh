#!/bin/sh

CHNROUTE_URL="$(nvram get ss_update_chnroute)"
tmp_chnroute="/tmp/chinadns_chnroute.txt"
set -e -o pipefail

[ -f $tmp_chnroute ] && rm -rf $tmp_chnroute && logger -st "chnroute" "Starting update..."

if [ "$1" != "force" ] && [ "$(nvram get ss_update_chnroute)" != "1" ]; then
	exit 0
else

	for URL in \
		"https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
	do
		wget -t 15 -T 50 -c --no-check-certificate -O- "${URL}" \
		| awk -F\| '/CN\|ipv4/ { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' >> $tmp_chnroute
	done
fi

if [ ! -d "/etc/storage/chinadns" ]; then
	mkdir -p /etc/storage/chinadns/
	mv -f $tmp_chnroute /etc/storage/chinadns/chnroute.txt
fi

logger -st "chnroute" "Update done"
restart_dhcpd
