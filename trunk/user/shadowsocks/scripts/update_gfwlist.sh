#!/bin/sh

GFWLIST_URL="$(nvram get gfwlist_url)"
tmp_gfw="/tmp/dnsmasq_gfwlist_ipset.conf"
set -e -o pipefail

[ -f $tmp_gfw ] && rm -rf $tmp_gfw && logger -st "gfwlist" "Starting update..."

if [ "$1" != "force" ] && [ "$(nvram get ss_update_gfwlist)" != "1" ]; then
	exit 0
else

	for URL in \
		"https://cokebar.github.io/gfwlist2dnsmasq/dnsmasq_gfwlist_ipset.conf"
	do
		wget -t 15 -T 50 -c --no-check-certificate -O- "${URL}" \
		| sed -e "/github.com/d" -e '$a server=/transfer.sh/127.0.0.1#5353' -e '$a ipset=/transfer.sh/gfwlist' >> $tmp_gfw
	done
fi
#curl -k -s -o /tmp/dnsmasq_gfwlist_ipset.conf --connect-timeout 5 --retry 3 ${GFWLIST_URL:-"https://cokebar.github.io/gfwlist2dnsmasq/dnsmasq_gfwlist_ipset.conf"}


if [ ! -d "/etc/storage/gfwlist" ]; then
	mkdir -p /etc/storage/gfwlist/
	mv -f $tmp_gfw /etc/storage/gfwlist/dnsmasq_gfwlist_ipset.conf
fi

logger -st "gfwlist" "Update done"
restart_dhcpd
