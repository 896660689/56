#!/bin/sh

PIDFILE_SS_WATCHDOG="/var/run/ss-watchdog.pid"
echo "$$" > $PIDFILE_SS_WATCHDOG

LOGFILE="/tmp/ss-watchcat.log"

while true; do
sleep 120
loger(){
	LOGSIZE=$(wc -c < $LOGFILE)
	[ $LOGSIZE -ge 5000 ] && sed -i -e 1,10d $LOGFILE
	time=$(date "+%H:%M:%S")
	echo "$time ss-watchcat $1" >> $LOGFILE
}

restart_apps(){
	/usr/bin/shadowsocks.sh restart > /dev/null 2>&1 && loger "Problem decteted, restart shadowsocks."
}

wget -s -q -T 3 www.google.com.hk > /dev/null
if [ "$?" == "0" ]; then
	loger "Shadowsocks-服务正常,世界之窗已开启..."
	mtk_gpio -w 13 0
	mtk_gpio -w 14 1
	mtk_gpio -w 15 0
else
	wget -s -q -T 3 www.baidu.com > /dev/null
	if [ "$?" == "0" ]; then
		loger "互联网络正常-Shadowsocks-服务失败,正在重启..."
		mtk_gpio -w 13 1
		mtk_gpio -w 14 1
		mtk_gpio -w 15 1
		restart_apps
	else
		mtk_gpio -w 13 1
		mtk_gpio -w 14 0
		mtk_gpio -w 15 1
		[ "$?" = 1 ] && loger "互联网络未接通....."
	fi
fi
done
