#!/bin/sh

username=`nvram get http_username`
ss_bin="ss-redir"
ss_json_file="/tmp/ss-redir.json"
ss_proc="/var/ss-redir"
Dnsmasq_dns="/etc/storage/dnsmasq/dnsmasq.conf"
Firewall_rules="/etc/storage/post_iptables_script.sh"

while [ -n "`pidof ss-watchcat.sh`" ] ; do
	kill -9 "`pidof ss-watchcat.sh`"
	sleep 1
done

#/usr/bin/ss-redir -> /var/ss-redir -> /usr/bin/ss-orig-redir or /usr/bin/ssr-redir

ss_type="$(nvram get ss_type)" #0=ss;1=ssr

if [ "${ss_type:-0}" = "0" ]; then
	ln -sf /usr/bin/ss-orig-redir $ss_proc
elif [ "${ss_type:-0}" = "1" ]; then
	ss_protocol=$(nvram get ss_protocol)
	ss_proto_param=$(nvram get ss_proto_param)
	ss_obfs=$(nvram get ss_obfs)
	ss_obfs_param=$(nvram get ss_obfs_param)
	ln -sf /usr/bin/ssr-redir $ss_proc
fi

ss_local_port=$(nvram get ss_local_port)
ss_udp=$(nvram get ss_udp)
ss_server=$(nvram get ss_server)

ss_server_port=$(nvram get ss_server_port)
ss_method=$(nvram get ss_method)
ss_password=$(nvram get ss_key)
ss_mtu=$(nvram get ss_mtu)
ss_timeout=$(nvram get ss_timeout)

ss_mode=$(nvram get ss_mode) #0:global;1:chnroute;2:gfwlist
ss_router_proxy=$(nvram get ss_router_proxy)
ss_lower_port_only=$(nvram get ss_lower_port_only)
ss_pdnsd=$(nvram get ss_pdnsd)
ss_tunnel_local_port=$(nvram get ss-tunnel_local_port)
ss_tunnel_remote=$(nvram get ss-tunnel_remote)

loger() {
	logger -st "$1" "$2"
}

get_arg_udp() {
	if [ "$ss_udp" = "1" ]; then
		echo "-u"
	fi
}

get_arg_out(){
	if [ "$ss_router_proxy" = "1" ]; then
		echo "-o"
	fi
}

get_wan_bp_list(){
	wanip="$(nvram get wan_ipaddr)"
	[ -n "$wanip" ] && [ "$wanip" != "0.0.0.0" ] && bp="-b $wanip" || bp=""
	if [ "$ss_mode" = "1" ]; then
		bp=${bp}" -B /etc/storage/chinadns/chnroute.txt"
		echo "$bp"
	fi
}

get_ipt_ext(){
	if [ "$ss_lower_port_only" = "1" ]; then
		echo '-e "--dport 22:1023"'
	elif [ "$ss_lower_port_only" = "2" ]; then
		echo '-e "-m multiport --dports 53,80,443"'
	fi
}

func_start_ss_redir(){
	sh -c "$ss_bin -c $ss_json_file $(get_arg_udp) & "
	return $?
}

func_start_ss_rules(){
	ss-rules -f
	sh -c "ss-rules -s $ss_server -l $ss_local_port $(get_wan_bp_list) -d SS_SPEC_WAN_AC $(get_ipt_ext) $(get_arg_out) $(get_arg_udp)"
	return $?
}

func_gen_ss_json(){
cat > "$ss_json_file" <<EOF
{
    "server": "$ss_server",
    "server_port": $ss_server_port,
    "password": "$ss_password",
    "method": "$ss_method",
    "timeout": $ss_timeout,
    "protocol": "$ss_protocol",
    "protocol_param": "$ss_proto_param",
    "obfs": "$ss_obfs",
    "obfs_param": "$ss_obfs_param",
    "local_address": "0.0.0.0",
    "local_port": $ss_local_port,
    "mtu": $ss_mtu
}

EOF
}

func_port_agent_mode(){
	if [ "$ss_pdnsd" = "1" ]; then
		start-stop-daemon -S -b -x /usr/bin/dns-forwarder -- -b 127.0.0.1 -p $ss_tunnel_local_port -s $ss_tunnel_remote 2>&1 &
	elif [ "$ss_pdnsd" = "2" ]; then
		/usr/bin/dnsproxy -T -p $ss_tunnel_local_port -R 8.8.4.4 2>&1 &
	else
		while [ -n "`pidof dns-forwarder`" ] ; do
			kill -9 "`pidof dns-forwarder`"
		done
		while [ -n "`pidof dnsproxy`" ] ; do
			kill -9 "`pidof dnsproxy`"
		done
	fi
}

func_start(){
	func_gen_ss_json && \
	[ ! -f "/tmp/ss-watchcat.log" ] && nohup /usr/bin/ss-watchcat.sh >> /tmp/ss-watchcat.log 2>&1 &
	grep "ss-watchcat.log" /etc/storage/cron/crontabs/$username
	if [ ! "$?" -eq "0" ]
	then
		sed -i '$a 30 6 * * * cat /dev/null > /tmp/ss-watchcat.log' /etc/storage/cron/crontabs/$username
	fi
	if [ "$ss_mode" = "2" ]; then
		func_port_agent_mode && \
		sh /usr/bin/gfwlist.sh
		$ss_bin -c $ss_json_file -b 0.0.0.0 -l $ss_local_port >/dev/null 2>&1 &
		echo "ss-redir started."
	else
		func_start_ss_redir && \
		func_start_ss_rules && \
		while [ -n "`pidof pdnsd`" ] ; do
			kill -9 "`pidof pdnsd`"
		done
		grep "gfwlist" $Firewall_rules
		if [ "$?" -eq "0" ]
		then
			sed -i '/gfwlist/d; /resolv.conf/d; /restart_dhcpd/d' $Firewall_rules
		fi
		grep "conf-dir" $Dnsmasq_dns
		if [ ! "$?" -eq "0" ]
		then
			sed -i '/127.0.0.1/d; /min-cache/d; /conf-dir/d; /log/d' $Dnsmasq_dns
		fi
	fi
	loger $ss_bin "start done" || { ss-rules -f && loger $ss_bin "start fail!";}
	restart_dhcpd && restart_firewall
}

func_stop(){
	nvram set ss-tunnel_enable=0
	sh /usr/bin/ss-tunnel.sh stop
	grep "conf-dir" $Dnsmasq_dns
	if [ "$?" -eq "0" ]
	then
		sed -i '/127.0.0.1/d; /min-cache/d; /conf-dir/d' $Dnsmasq_dns
	fi
	grep "gfwlist" $Firewall_rules
	if [ "$?" -eq "0" ]
	then
		sed -i '/gfwlist/d; /resolv.conf/d; /restart_dhcpd/d' $Firewall_rules
	fi
	grep "ss-watchcat.log" /etc/storage/cron/crontabs/$username
	if [ "$?" -eq "0" ]
	then
		sed -i '/ss-watchcat.log/d' /etc/storage/cron/crontabs/$username
	fi
	if [ -f "/etc/storage/dnsmasq.d/resolv_bak" ]; then
		cp -f /etc/storage/dnsmasq.d/resolv_bak /etc/resolv.conf
	else
		sed -i '/182.254/d; /208.67/d;  /240c/d; /8.8.4.4/d' /etc/resolv.conf
	fi
	[ -f /etc/storage/dnsmasq.d ] && rm -rf /etc/storage/dnsmasq.d
	if [ -n "`pidof ss-watchcat.sh`" ] ; then
		kill -9 "`pidof ss-watchcat.sh`"
	fi
	while [ -n "`pidof pdnsd`" ] ; do
		kill -9 "`pidof pdnsd`"
	done
	while [ -n "`pidof dnsproxy`" ] ; do
		kill -9 "`pidof dnsproxy`"
	done
	while [ -n "`pidof dns-forwarder`" ] ; do
		kill -9 "`pidof dns-forwarder`"
	done
	killall -q $ss_bin && restart_dhcpd && restart_firewall
	ss-rules -f && loger $ss_bin "stop"
	[ -f /tmp/ss-redir.json ] && rm -rf /tmp/ss-redir.json
	[ -f /tmp/ss-watchcat.log ] && rm -rf /tmp/ss-watchcat.log
	[ -f /etc/storage/gfwlist/custom_list.conf ] && rm -rf /etc/storage/gfwlist/custom_list.conf
	[ -f /var/run/ss-watchdog.pid ] && rm -rf /var/run/ss-watchdog.pid
	[ -f /var/run/pdnsd.pid ] && rm -rf /var/run/pdnsd.pid
	[ -d /etc/init.d/pdnsd ] && rm -rf /etc/init.d/pdnsd
	[ -f /tmp/shadowsocks_iptables.save ] && rm -rf /tmp/shadowsocks_iptables.save
}

case "$1" in
start)
	func_start
	;;
stop)
	func_stop
	;;
restart)
	func_stop
	func_start
	;;
*)
	echo "Usage: $0 { start | stop | restart }"
	exit 1
	;;
esac
