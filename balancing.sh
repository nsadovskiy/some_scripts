#!/bin/sh

IF_LOCAL=eth0
IP_LOCAL=10.10.3.1
NET_LOCAL=10.10.3.0/24

IF_GOODLINE=eth1
IP_GOODLINE=95.181.37.90
NET_GOODLINE=95.181.37.252/30
NET_GOODLINE_LOCAL=10.0.0.0/8
GW_GOODLINE=95.181.37.89
MARK_GOODLINE=1

IF_MEDVED=eth2
IP_MEDVED=93.190.105.202
NET_MEDVED=93.190.105.224/27
GW_MEDVED=93.190.105.193
MARK_MEDVED=2

IF_KRU=kru
IP_KRU_TUNNEL=94.137.254.129
IP_KRU=10.6.9.2
NET_TALDA=10.16.11.0/24
NET_KBROD=10.21.11.0/24

start() {

    ###########################################################
    #    Подгрузка нужных модулей ядра                        #
    ###########################################################
    modprobe ip_nat_ftp
    modprobe nf_conntrack_ftp

    ###########################################################
    #    Настройка основных маршрутов                         #
    ###########################################################
    ip route add default via $GW_GOODLINE dev $IF_GOODLINE table goodline       # Шлюз по-умолчанию в таблице goodline
    ip route add default via $GW_MEDVED dev $IF_MEDVED table medved             # Шлюз по-умолчанию в таблице medved
    ip route add $NET_LOCAL via $IP_LOCAL dev $IF_LOCAL table static            # Наша локалка
    ip route add $NET_GOODLINE via $GW_GOODLINE dev $IF_GOODLINE table static   # Подсеть Goodline
    ip route add $NET_MEDVED via $GW_MEDVED dev $IF_MEDVED table static         # Подсеть Русского Медведа
    ip route add $IP_KRU_TUNNEL via $GW_MEDVED dev $IF_MEDVED table static      # Хост для GRE-туннеля в КузбассРазрезУголь
    ip route add 195.93.228.0/24 via $GW_MEDVED dev $IF_MEDVED table static     # СДС
    ip route add 78.107.194.226 via $GW_MEDVED dev $IF_MEDVED table static      # Московский 1С
    ip route add 80.82.168.241  via $GW_MEDVED dev $IF_MEDVED table static      # ЛуТЭК
    ip route add 217.14.50.160  via $GW_GOODLINE dev $IF_GOODLINE table static  # TeleBank VTB24
    ip route add 193.16.208.72 via $GW_MEDVED dev $IF_MEDVED table static       # Магнитка cisco vpn
    ip route add 80.93.53.97 via $GW_GOODLINE dev $IF_GOODLINE table static
    ip route add 89.108.105.10 via $GW_GOODLINE dev $IF_GOODLINE table static
    ip route add 212.220.165.68 via $GW_MEDVED dev $IF_MEDVED table static
    ip route add 212.220.165.70 via $GW_MEDVED dev $IF_MEDVED table static
    ip route add 212.75.210.66 via $GW_GOODLINE dev $IF_GOODLINE table static

    ###########################################################
    #    Настройка основных правил маршрутизации              #
    ###########################################################
    ip rule add table static prio 1
    ip rule add fwmark $MARK_GOODLINE table goodline prio 2
    ip rule add fwmark $MARK_MEDVED table medved prio 3

    ###########################################################
    #    Туннель в КузбассРазрезУголь                         #
    ###########################################################
    ip tunnel add $IF_KRU mode gre local $IP_MEDVED remote $IP_KRU_TUNNEL ttl 255
    ip link set $IF_KRU up
    ip addr add $IP_KRU dev $IF_KRU

    ip route add $NET_TALDA dev $IF_KRU table static
    ip route add $NET_KBROD dev $IF_KRU table static

    ip route flush cache

    ###########################################################
    #    Складываем всех наших провайдеров в аккуратную кучку #
    ###########################################################
    ipset -N GOODVED iphash
    ipset -A GOODVED $IP_GOODLINE
    ipset -A GOODVED $IP_MEDVED

    #iptables -t mangle -A FORWARD -p icmp -s 10.10.3.8 -j LOG --log-level INFO --log-prefix "FORWARD: "

    #iptables -t mangle -A PREROUTING -p icmp -s 10.10.3.8 -j LOG --log-level INFO --log-prefix "PREROUTING: "
    #iptables -t mangle -A FORWARD -p icmp -s 10.10.3.8 -j LOG --log-level INFO --log-prefix "FORWARD: "
    #iptables -t mangle -A INPUT -p icmp -s 10.10.3.8 -j LOG --log-level INFO --log-prefix "INPUT: "
    #iptables -t mangle -A OUTPUT -p icmp -s 10.10.3.8 -j LOG --log-level INFO --log-prefix "OUTPUT: "
    #iptables -t mangle -A POSTROUTING -s 10.10.3.8 -p icmp -j LOG --log-level INFO --log-prefix "POSTROUTING: "

    #iptables -t mangle -A PREROUTING -p tcp --dport 22 -j LOG --log-level INFO --log-prefix "PREROUTING: "
    #iptables -t mangle -A FORWARD -p tcp --dport 22 -j LOG --log-level INFO --log-prefix "FORWARD: "
    #iptables -t mangle -A INPUT -p tcp --dport 22 -j LOG --log-level INFO --log-prefix "INPUT: "
    #iptables -t mangle -A OUTPUT -p tcp --dport 22 -j LOG --log-level INFO --log-prefix "OUTPUT: "
    #iptables -t mangle -A POSTROUTING -p tcp --dport 22 -j LOG --log-level INFO --log-prefix "POSTROUTING: "

    ###########################################################
    #    Привязываем входящие соединения к их интерфейсам     #
    ###########################################################
    iptables -t mangle -A INPUT -i $IF_GOODLINE -m conntrack --ctstate NEW -j CONNMARK --set-mark $MARK_GOODLINE
    iptables -t mangle -A INPUT -i $IF_MEDVED -m conntrack --ctstate NEW -j CONNMARK --set-mark $MARK_MEDVED

    ###########################################################
    #    Ставим NAT на интерфейсы                             #
    ###########################################################
    iptables -t nat -A POSTROUTING -o $IF_GOODLINE -j SNAT --to-source $IP_GOODLINE
    iptables -t nat -A POSTROUTING -o $IF_MEDVED -j SNAT --to-source $IP_MEDVED
    iptables -t nat -A POSTROUTING -s $NET_LOCAL -d $NET_LOCAL -j SNAT --to-source $IP_LOCAL

    ###########################################################
    #    Редирект портов (NAT снаружи)                        #
    ###########################################################

    # Хозяйство. Сельское. Oracle.
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 10521 -j DNAT --to-destination 10.10.3.6:1521

    # Хозяйство. Сельское. RDP.
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 3389 -j DNAT --to-destination 10.10.3.6

    # Хозяйство. Сельское. V3. RDP.
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 13389 -j DNAT --to-destination 10.10.3.18:3389

    # Хозяйство. Сельское. V3. Oracle.
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 11521 -j DNAT --to-destination 10.10.3.18:1521

    # Хозяйство. Сельское. V3. Apex.
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 80 -j DNAT --to-destination 10.10.3.18:7000

    # Хозяйство. Сельское. Входящие данные от техники.
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 6666,7777,8888,9999,4444,55555 -j DNAT --to-destination 10.10.3.6

    # Ftp
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 20,21 -j DNAT --to-destination 10.10.3.3

    # Mapserver
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 8080 -j DNAT --to-destination 10.10.3.7:80

    # Dokuwiki
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 8081 -j DNAT --to-destination 10.10.3.71:80

    # Oracle v3_test
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 41521 -j DNAT --to-destination 10.10.3.15:1521

    # PostgreSQL
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 5432 -j DNAT --to-destination 10.10.3.14

    # Subversion
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 3690 -j DNAT --to-destination 10.10.3.4
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p udp --dport 3690 -j DNAT --to-destination 10.10.3.4

    # Мой ноут
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 10000:10010 -j DNAT --to-destination 10.10.3.8
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p udp -m multiport --dports 10000:10010 -j DNAT --to-destination 10.10.3.8

    # Voodo
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 10011:10020 -j DNAT --to-destination 10.10.3.3
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p udp -m multiport --dports 10011:10020 -j DNAT --to-destination 10.10.3.3

    # petrovdp
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 10021:10030 -j DNAT --to-destination 10.10.3.16
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p udp -m multiport --dports 10021:10030 -j DNAT --to-destination 10.10.3.16

    # fedorov
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 10031 -j DNAT --to-destination 10.10.3.191:3389
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 10032:10040 -j DNAT --to-destination 10.10.3.191
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p udp -m multiport --dports 10032:10040 -j DNAT --to-destination 10.10.3.191

    # dreamer
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 10050 -j DNAT --to-destination 10.10.3.3
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp -m multiport --dports 10041:10049 -j DNAT --to-destination 10.10.3.192
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p udp -m multiport --dports 10041:10049 -j DNAT --to-destination 10.10.3.192

    # Ssh на devel для Git
    iptables -t nat -A PREROUTING -m set --match-set GOODVED dst -p tcp --dport 1022 -j DNAT --to-destination 10.10.3.4:22

    ###########################################################
    #    Магия тут. Раскидываем пакеты по каналам.            #
    ###########################################################

    # Маркируем пакеты по соединениям
    iptables -t mangle -N SELECT_CONN
    iptables -t mangle -A SELECT_CONN -j CONNMARK --set-mark $MARK_GOODLINE
    iptables -t mangle -A SELECT_CONN -m statistic --mode random --probability 0.75 -j RETURN
    iptables -t mangle -A SELECT_CONN -j CONNMARK --set-mark $MARK_MEDVED

    # Выбираем соединения, который нуждаются в маркировке
    iptables -t mangle -N SORT_CONN
    iptables -t mangle -A SORT_CONN -o $IF_LOCAL -j RETURN
    iptables -t mangle -A SORT_CONN -o lo -j RETURN
    iptables -t mangle -A SORT_CONN -m conntrack --ctstate NEW,RELATED -j SELECT_CONN
    iptables -t mangle -A SORT_CONN -j CONNMARK --restore-mark

    # Отправляем на балансировку все входящие и проходящие пакеты
    iptables -t mangle -I OUTPUT -j SORT_CONN
    iptables -t mangle -I PREROUTING -j SORT_CONN
}

stop() {

    ip route flush table goodline
    ip rule del table goodline > /dev/null 2>&1
    ip route flush table medved
    ip rule del table medved > /dev/null 2>&1
    ip route flush table static
    ip rule del table static > /dev/null 2>&1
    ip route flush cache

    ip link set kru down > /dev/null 2>&1
    ip tunnel del kru > /dev/null 2>&1

    iptables -t nat -F
    iptables -t filter -F
    iptables -t mangle -F
    #iptables -t raw -F
    iptables -t mangle -F SORT_CONN > /dev/null 2>&1
    iptables -t mangle -X SORT_CONN > /dev/null 2>&1
    iptables -t mangle -F SELECT_CONN > /dev/null 2>&1
    iptables -t mangle -X SELECT_CONN > /dev/null 2>&1
    iptables -t mangle -F BIND_CONN > /dev/null 2>&1
    iptables -t mangle -X BIND_CONN > /dev/null 2>&1

    ipset -F GOODVED > /dev/null 2>&1
    ipset -X GOODVED > /dev/null 2>&1
}

case $1 in
    start)
	start
	;;

    stop)
	stop
	;;

    restart)
	stop
	start
	;;
    *)
	echo "Usage: start|stop|restart"
	;;
esac
