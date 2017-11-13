#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "SKIP: Need root privileges"
	exit 0
fi

if [ ! -f topo.sh ]; then
	echo "SKIP: Could not find topology file"
	exit 0
fi

if [ ! -x "$(command -v jq)" ]; then
	echo "SKIP: jq not installed"
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
	ip link set dev $h2 up
}

h2_destroy()
{
	ip link set dev $h2 down
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

learning_test()
{
	bridge -j fdb show br br0 brport $swp1 vlan 1 |
		jq -e '.[] | select( .mac == "de:ad:be:ef:13:37" )' &> /dev/null
	if [ $? -eq 0 ]; then
		echo "FAIL: fdb exists when shouldn't"
		ret=1
		return
	fi

	mausezahn $h1 -c 1 -p 64 -a de:ad:be:ef:13:37 -t ip -q
	sleep 5

	bridge -j fdb show br br0 brport $swp1 vlan 1 |
		jq -e '.[] | select( .mac == "de:ad:be:ef:13:37" )' &> /dev/null
	if [ $? -ne 0 ]; then
		echo "FAIL: fdb doesn't exist when should"
		ret=1
		return
	fi

	sleep 20

	bridge -j fdb show br br0 brport $swp1 vlan 1 |
		jq -e '.[] | select( .mac == "de:ad:be:ef:13:37" )' &> /dev/null
	if [ $? -eq 0 ]; then
		echo "FAIL: fdb exists when shouldn't"
		ret=1
		return
	fi

	echo "PASS: learning"
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

learning_test

exit $ret
