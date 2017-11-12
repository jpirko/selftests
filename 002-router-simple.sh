#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "SKIP: Need root privileges"
	exit 0
fi

if [ ! -f topo.sh ]; then
	echo "SKIP: Could not find topology file"
	exit 0
fi

source topo.sh
source lib.sh

num_netifs=4
topo_check $num_netifs
if [ $? -ne 0 ]; then
	echo "SKIP: Could not find all required interfaces"
	exit 0
fi

h1=${netifs[p1]}
rtr1=${netifs[p2]}
rtr2=${netifs[p3]}
h2=${netifs[p4]}

ipv4_fwd_path="net.ipv4.conf.all.forwarding"
ipv6_fwd_path="net.ipv6.conf.all.forwarding"

ret=0

h1_create()
{
	ip link add dev vrf-h1 type vrf table 10
	ip link set dev $h1 master vrf-h1
	ip link set dev vrf-h1 up
	ip link set dev $h1 up
	ip addr add 192.168.100.2/24 dev $h1
	ip addr add cafe::2/64 dev $h1
	ip route add table 10 192.168.101.0/24 nexthop via 192.168.100.1
	ip route add table 10 dead::/64 nexthop via cafe::1
}

h1_destroy()
{
	ip route del table 10 dead::/64
	ip route del table 10 192.168.101.0/24
	ip addr del cafe::2/64 dev $h1
	ip addr del 192.168.100.2/24 dev $h1
	ip link set dev $h1 down
	ip link del dev vrf-h1
}

h2_create()
{
	ip link add dev vrf-h2 type vrf table 20
	ip link set dev $h2 master vrf-h2
	ip link set dev vrf-h2 up
	ip link set dev $h2 up
	ip addr add 192.168.101.2/24 dev $h2
	ip addr add dead::2/64 dev $h2
	ip route add table 20 192.168.100.0/24 nexthop via 192.168.101.1
	ip route add table 20 cafe::/64 nexthop via dead::1
}

h2_destroy()
{
	ip route del table 20 cafe::/64
	ip route del table 20 192.168.100.0/24
	ip addr del dead::2/64 dev $h2
	ip addr del 192.168.101.2/24 dev $h2
	ip link set dev $h2 down
	ip link del dev vrf-h2
}

rtr_create()
{
	ipv4_fwd=$(sysctl -n $ipv4_fwd_path)
	ipv6_fwd=$(sysctl -n $ipv6_fwd_path)
	sysctl -q -w $ipv4_fwd_path=1
	sysctl -q -w $ipv6_fwd_path=1
	ip link set dev $rtr1 up
	ip link set dev $rtr2 up
	ip addr add 192.168.100.1/24 dev $rtr1
	ip addr add cafe::1/64 dev $rtr1
	ip addr add 192.168.101.1/24 dev $rtr2
	ip addr add dead::1/64 dev $rtr2
}

rtr_destroy()
{
	ip addr del dead::1/64 dev $rtr2
	ip addr del 192.168.101.1/24 dev $rtr2
	ip addr del cafe::1/64 dev $rtr1
	ip addr del 192.168.100.1/24 dev $rtr1
	ip link set dev $rtr2 down
	ip link set dev $rtr1 down
	sysctl -q -w $ipv6_fwd_path=$ipv6_fwd
	sysctl -q -w $ipv4_fwd_path=$ipv4_fwd
}

ping_test()
{
	ip vrf exec vrf-h1 ping 192.168.101.2 -c 10 -i 0.1 -w 2 &> /dev/null
	if [ $? -eq 0 ]; then
		echo "PASS: ping"
	else
		echo "FAIL: ping"
		ret=1
	fi
}

ping6_test()
{
	ip vrf exec vrf-h1 ping6 dead::2 -c 10 -i 0.1 -w 2 &> /dev/null
	if [ $? -eq 0 ]; then
		echo "PASS: ping6"
	else
		echo "FAIL: ping6"
		ret=1
	fi
}

setup_prepare()
{
	vrf_fib_rules_prepare 4
	vrf_fib_rules_prepare 6
	h1_create
	h2_create
	rtr_create
}

cleanup()
{
	rtr_destroy
	h2_destroy
	h1_destroy
	vrf_fib_rules_cleanup 6
	vrf_fib_rules_cleanup 4
}

trap cleanup EXIT

setup_prepare
setup_wait $num_netifs

ping_test
ping6_test

exit $ret
