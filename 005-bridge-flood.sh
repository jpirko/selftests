#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "SKIP: Need root privileges"
	exit 0
fi

if [ ! -f topo.sh ]; then
	echo "SKIP: Could not find topology file"
	exit 0
fi

if [ ! -x "$(command -v mausezahn)" ]; then
	echo "SKIP: mausezahn not installed"
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
swp1=${netifs[p2]}
swp2=${netifs[p3]}
h2=${netifs[p4]}

ret=0

h1_create()
{
	ip link set dev $h1 up
}

h1_destroy()
{
	ip link set dev $h1 down
}

h2_create()
{
	# Packets are going to be flooded to this host. Make sure we're
	# able to receive them.
	tc qdisc add dev $h2 ingress
	tc filter add dev $h2 ingress protocol ip pref 1 flower \
		dst_mac de:ad:be:ef:13:37 action trap
	tc filter add dev $h2 ingress protocol ip pref 2 flower \
		dst_mac 01:00:5e:00:00:01 action trap
	ip link set dev $h2 up
}

h2_destroy()
{
	ip link set dev $h2 down
	tc filter del dev $h2 ingress protocol ip pref 2 flower \
		dst_mac 01:00:5e:00:00:01 action trap
	tc filter del dev $h2 ingress protocol ip pref 1 flower \
		dst_mac de:ad:be:ef:13:37 action trap
	tc qdisc del dev $h2 ingress
}

br_create()
{
	# 10 Seconds ageing time.
	ip link add dev br0 type bridge vlan_filtering 1 ageing_time 1000 \
		mcast_snooping 0
	ip link set dev $swp1 master br0
	ip link set dev $swp2 master br0
	ip link set dev br0 up
	ip link set dev $swp1 up
	ip link set dev $swp2 up
}

br_destroy()
{
	ip link set dev $swp2 down
	ip link set dev $swp1 down
	ip link del dev br0
}

__flood_test()
{
	local should_flood=$1
	local mac=$2
	local td_pid
	local ip=$3
	local err

	tcpdump -nn -e -i $h2 -Q in -c 1 ether dst $mac &> /dev/null &
	td_pid=$!
	sleep 5

	mausezahn $h1 -c 1 -p 64 -b $mac -B $ip -t ip -q
	sleep 5

	ps -p $td_pid &> /dev/null
	err=$?
	if [[ $err -eq 0 && $should_flood == "true" || \
	      $err -ne 0 && $should_flood == "false" ]]; then
		return 1
	fi

	kill -9 $td_pid &> /dev/null
	wait $td_pid &> /dev/null

	return 0
}

uc_test()
{
	local mac=de:ad:be:ef:13:37
	local ip=192.168.100.2

	bridge link set dev $swp2 flood off &> /dev/null

	__flood_test false $mac $ip
	if [ $? -ne 0 ]; then
		echo "FAIL: packet flooded when shouldn't"
		return 1
	fi

	bridge link set dev $swp2 flood on &> /dev/null

	__flood_test true $mac $ip
	if [ $? -ne 0 ]; then
		echo "FAIL: packet wasn't flooded when should"
		return 1
	fi

	echo "PASS: unknown unicast flood"
}

mc_test()
{
	local mac=01:00:5e:00:00:01
	local ip=239.0.0.1

	bridge link set dev $swp2 mcast_flood off &> /dev/null

	__flood_test false $mac $ip
	if [ $? -ne 0 ]; then
		echo "FAIL: packet flooded when shouldn't"
		return 1
	fi

	bridge link set dev $swp2 mcast_flood on &> /dev/null

	__flood_test true $mac $ip
	if [ $? -ne 0 ]; then
		echo "FAIL: packet wasn't flooded when should"
		return 1
	fi

	echo "PASS: multicast flood"
}

flood_test()
{
	uc_test
	if [ $? -ne 0 ]; then
		echo "FAIL: unknown unicast flood"
		ret=1
		return
	fi

	mc_test
	if [ $? -ne 0 ]; then
		echo "FAIL: multicast flood"
		ret=1
		return
	fi

	echo "PASS: flood"
}

setup_prepare()
{
	h1_create
	h2_create
	br_create
}

cleanup()
{
	br_destroy
	h2_destroy
	h1_destroy
}

trap cleanup EXIT

setup_prepare
setup_wait $num_netifs

flood_test

exit $ret
