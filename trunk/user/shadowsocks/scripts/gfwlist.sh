#!/bin/sh
# Compile:by-lanse	2019-11-04

route_vlan=`/sbin/ifconfig br0 |grep "inet addr"| cut -f 2 -d ":"|cut -f 1 -d " " `
Firewall_rules="/etc/storage/post_iptables_script.sh"

echo -e -n "\033[41;37m 开始构建翻墙平台......\033[0m\n"
sleep 3
if [ ! -d "/etc/storage/dnsmasq.d" ]; then
	mkdir -p -m 755 /etc/storage/dnsmasq.d
	echo -e "\e[1;36m 创建 dnsmasq 规则脚本文件夹 \e[0m\n"
	cp -f /etc/resolv.conf /etc/storage/dnsmasq.d/resolv_bak
fi

echo -e "\e[1;36m 创建 DNS 配置文件 \e[0m\n"
if [ ! -f "/etc/storage/dnsmasq.d/resolv.conf" ]; then
	cat > /etc/storage/dnsmasq.d/resolv.conf <<EOF
## DNS解析服务器设置
nameserver 127.0.0.1
## 根据网络环境选择DNS.最多6个地址按速排序
nameserver 114.114.115.110
nameserver 182.254.116.116
nameserver 223.5.5.5
nameserver 208.67.222.222
nameserver 8.8.4.4
nameserver 240c::6666
EOF
fi
chmod 644 /etc/storage/dnsmasq.d/resolv.conf && chmod 644 /etc/resolv.conf
cp -f /etc/storage/dnsmasq.d/resolv.conf /tmp/resolv.conf
sed -i "/#/d" /tmp/resolv.conf;mv -f /tmp/resolv.conf /etc/resolv.conf
echo -e "\e[1;36m 添加自定义 hosts 启动路径 \e[0m\n"
[ -f /tmp/tmp_dnsmasq ] && rm /tmp/tmp_dnsmasq
if [ -f "/etc/storage/dnsmasq/dnsmasq.conf" ]; then
	sed -i '/127.0.0.1/d; /min-cache/d; /conf-dir/d; /log/d' /etc/storage/dnsmasq/dnsmasq.conf
	echo -e "\033[41;37m 开始写入启动代码 \e[0m\n"
	echo "listen-address=${route_vlan},127.0.0.1
# 添加监听地址
# 开启日志选项
#log-queries
#log-facility=/tmp/ss-watchcat.log
# 异步log,缓解阻塞，提高性能。默认为5，最大为100
#log-async=50
# 缓存最长时间
min-cache-ttl=3600
# 指定服务器'域名''地址'文件夹
# conf-dir=/etc/storage/dnsmasq.d/conf
conf-dir=/etc/storage/gfwlist/
# conf-file=/etc/storage/dnsmasq.d/conf/hosts_fq.conf" >> /tmp/tmp_dnsmasq.conf
	cat /tmp/tmp_dnsmasq.conf | sed -E -e "/#/d" >> /etc/storage/dnsmasq/dnsmasq.conf;sleep 3
	rm /tmp/tmp_dnsmasq.conf
fi

if [ -f "/usr/bin/pdnsd" ]; then
	logger -t "SS" "正在启动pdnsd..."
	usr_dns="$1"
	usr_port="$2"

	tcp_dns_list="208.67.222.222, 208.67.220.220"
	[ -z "$usr_dns" ] && usr_dns="8.8.4.4"
	[ -z "$usr_port" ] && usr_port="53"
	if [ ! -d /etc/init.d/pdnsd ];then
		mkdir -p -m 755 /etc/init.d/pdnsd
		echo -ne "pd13\000\000\000\000" >/etc/init.d/pdnsd/pdnsd.cache
		chown -R nobody:nogroup /etc/init.d/pdnsd
	fi
	cat > /etc/init.d/pdnsd/pdnsd.conf <<EOF
global {
	perm_cache=1368;
	cache_dir="/etc/init.d/pdnsd";
	pid_file="/var/run/pdnsd.pid";
	run_as="nobody";
	server_port = 5335;
	server_ip = 127.0.0.1;
	status_ctl = on;
	query_method=tcp_only;
	min_ttl=1m;
	max_ttl=1w;
	timeout=5;
}
server {
	label= "ssr-usrdns";
	ip = $usr_dns;
	port = $usr_port;
	timeout=6;
	uptest=none;
	interval=10m;
	purge_cache=off;
}
server {
	label= "ssr-pdnsd";
	ip = $tcp_dns_list;
	port = 5353;
	timeout=6;
	uptest=none;
	interval=10m;
	purge_cache=off;
}

EOF
	chmod 644 /etc/init.d/pdnsd/pdnsd.conf
	/usr/bin/pdnsd -c /etc/init.d/pdnsd/pdnsd.conf -d
fi

grep "gfwlist" $Firewall_rules
if [ ! "$?" -eq "0" ]
then
	sed -i '/gfwlist/d' $Firewall_rules
	sed -i '$a ipset destroy gfwlist' $Firewall_rules
	sed -i '$a ipset create gfwlist hash:net' $Firewall_rules
	sed -i '$a ipset add gfwlist 8.8.4.4' $Firewall_rules
	sed -i '$a ipset add gfwlist 182.254.116.116' $Firewall_rules
	sed -i '$a ipset add gfwlist 91.108.8.0/22' $Firewall_rules
	sed -i '$a ipset add gfwlist 91.108.4.0/22' $Firewall_rules
	sed -i '$a ipset add gfwlist 91.108.56.0/22' $Firewall_rules
	sed -i '$a ipset add gfwlist 149.154.160.0/20' $Firewall_rules
	sed -i '$a iptables -t nat -I PREROUTING -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-port 1080' $Firewall_rules
	sed -i '$a iptables -t nat -I OUTPUT -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-port 1080' $Firewall_rules
fi

if [ -f "/etc/storage/post_iptables_script.sh" ]; then
	sed -i '/resolv.conf/d; /restart_dhcpd/d' /etc/storage/post_iptables_script.sh
	sed -i '$a cp -f /etc/storage/dnsmasq.d/resolv.conf /tmp/resolv.conf' /etc/storage/post_iptables_script.sh
	sed -i '$a sed -i "/#/d" /tmp/resolv.conf;mv -f /tmp/resolv.conf /etc/resolv.conf' /etc/storage/post_iptables_script.sh
	sed -i '$a restart_dhcpd' /etc/storage/post_iptables_script.sh
fi
