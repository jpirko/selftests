#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "SKIP: Need root privileges"
	exit 0
fi

source lib.sh

ret=0

shopt -s expand_aliases
alias ipns='ip netns exec test'

netns_create()
{
	ip netns add test
	ip netns exec test ip link set dev lo up
}

netns_destroy()
{
	ip netns del test
}

check_err()
{
	if [ $ret -eq 0 ]; then
		ret=$1
	fi
}

check_fail()
{
	if [ $1 -eq 0 ]; then
		ret=1
	fi
}

dummy_create()
{
	ipns ip link add name $1 type dummy
	ipns ip link set dev $1 up
}

creation_test()
{
	dummy_create "dummy0"

	ipns ip link set dev dummy0 carrier on

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route get fibmatch 198.51.100.2 | grep "linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 | \
		grep "linkdown" &> /dev/null
	check_fail $?

	ipns ip link del dev dummy0

	dummy_create "dummy0"

	ipns ip link set dev dummy0 carrier off

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route get fibmatch 198.51.100.2 | grep "linkdown" &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 | \
		grep "linkdown" &> /dev/null
	check_err $?

	ipns ip link del dev dummy0

	if [ $ret -ne 0 ]; then
		echo "FAIL: route creation carrier test"
		return 1
	fi
	echo "PASS: route creation carrier test"
}

local_test()
{
	dummy_create "dummy0"

	ipns ip link set dev dummy0 carrier on

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route get fibmatch 198.51.100.1 | grep "local" &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:1::1 | grep "local" &> /dev/null
	check_err $?

	ipns ip route get fibmatch 198.51.100.1 | grep "linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::1 | \
		grep "linkdown" &> /dev/null
	check_fail $?

	ipns ip link set dev dummy0 carrier off

	# Carrier change shouldn't affect local routes.
	ipns ip route get fibmatch 198.51.100.1 | grep "linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::1 | \
		grep "linkdown" &> /dev/null
	check_fail $?

	ipns ip link del dev dummy0

	dummy_create "dummy0"

	ipns ip link set dev dummy0 carrier off

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route get fibmatch 198.51.100.1 | grep "local" &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:1::1 | grep "local" &> /dev/null
	check_err $?

	ipns ip route get fibmatch 198.51.100.1 | grep "linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::1 | \
		grep "linkdown" &> /dev/null
	check_fail $?

	ipns ip link set dev dummy0 carrier on

	# Carrier change shouldn't affect local routes.
	ipns ip route get fibmatch 198.51.100.1 | grep "linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::1 | \
		grep "linkdown" &> /dev/null
	check_fail $?

	ipns ip link del dev dummy0

	if [ $ret -ne 0 ]; then
		echo "FAIL: local route carrier test"
		return 1
	fi
	echo "PASS: local route carrier test"
}

dc_test()
{
	dummy_create "dummy0"

	ipns ip link set dev dummy0 carrier on
	check_err $?

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route get fibmatch 198.51.100.2 &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 &> /dev/null
	check_err $?

	# NETDEV_CHANGE is sent from a workqueue. Sleep to make sure
	# event was already fired.
	ipns ip link set dev dummy0 carrier off
	check_err $?
	sleep 1

	ipns ip route get fibmatch 198.51.100.2 | grep "linkdown" &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 | \
		grep "linkdown" &> /dev/null
	check_err $?

	ipns ip link set dev dummy0 carrier on
	check_err $?
	sleep 1

	ipns ip route get fibmatch 198.51.100.2 | grep "linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 | \
		grep "linkdown" &> /dev/null
	check_fail $?

	ipns ip link del dev dummy0

	if [ $ret -ne 0 ]; then
		echo "FAIL: directly connected route carrier test"
		return 1
	fi
	echo "PASS: directly connected route carrier test"
}

setup_prepare()
{
	netns_create
}

cleanup()
{
	netns_destroy
}

trap cleanup EXIT

setup_prepare

creation_test
local_test
dc_test

exit $ret
