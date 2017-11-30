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

dc_test()
{
	dummy_create "dummy0"

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route get fibmatch 198.51.100.2 &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 &> /dev/null
	check_err $?

	ipns ip link set dev dummy0 down
	check_err $?

	ipns ip route get fibmatch 198.51.100.2 &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:1::2 &> /dev/null
	check_fail $?

	ipns ip link del dev dummy0

	if [ $ret -ne 0 ]; then
		echo "FAIL: directly connected route test"
		return 1
	fi
	echo "PASS: directly connected route test"
}

remote_test()
{
	dummy_create "dummy0"

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip route add 192.0.2.0/24 nexthop via 198.51.100.2 dev dummy0
	ipns ip -6 route add 2001:db8:2::/64 nexthop via 2001:db8:1::2 dev \
		dummy0

	ipns ip route get fibmatch 192.0.2.1 &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:2::1 &> /dev/null
	check_err $?

	ipns ip link set dev dummy0 down
	check_err $?

	ipns ip route get fibmatch 192.0.2.1 &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:2::1 &> /dev/null
	check_fail $?

	ipns ip link del dev dummy0

	if [ $ret -ne 0 ]; then
		echo "FAIL: remote route test"
		return 1
	fi
	echo "PASS: remote route test"
}

__multipath_test()
{
	local down_dev=$1
	local up_dev=$2

	ipns ip route get fibmatch 203.0.113.1 oif $down_dev &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:3::1 oif $down_dev &> /dev/null
	check_fail $?

	ipns ip route get fibmatch 203.0.113.1 oif $up_dev &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:3::1 oif $up_dev &> /dev/null
	check_err $?

	ipns ip route show 203.0.113.0/24 | grep $down_dev | \
		grep "dead linkdown" &> /dev/null
	check_err $?
	ipns ip -6 route show 2001:db8:3::/64 | grep $down_dev | \
		grep "dead linkdown" &> /dev/null
	check_err $?

	ipns ip route show 203.0.113.0/24 | grep $up_dev | \
		grep "dead linkdown" &> /dev/null
	check_fail $?
	ipns ip -6 route show 2001:db8:3::/64 | grep $up_dev | \
		grep "dead linkdown" &> /dev/null
	check_fail $?
}

multipath_test()
{
	dummy_create "dummy0"
	dummy_create "dummy1"

	ipns ip address add 198.51.100.1/24 dev dummy0
	ipns ip -6 address add 2001:db8:1::1/64 dev dummy0

	ipns ip address add 192.0.2.1/24 dev dummy1
	ipns ip -6 address add 2001:db8:2::1/64 dev dummy1

	ipns ip route add 203.0.113.0/24 \
		nexthop via 198.51.100.2 dev dummy0 \
		nexthop via 192.0.2.2 dev dummy1
	ipns ip -6 route add 2001:db8:3::/64 \
		nexthop via 2001:db8:1::2 dev dummy0 \
		nexthop via 2001:db8:2::2 dev dummy1

	ipns ip route get fibmatch 203.0.113.1 &> /dev/null
	check_err $?
	ipns ip -6 route get fibmatch 2001:db8:3::1 &> /dev/null
	check_err $?

	ipns ip link set dev dummy0 down
	check_err $?

	__multipath_test "dummy0" "dummy1"

	ipns ip link set dev dummy0 up
	check_err $?
	ipns ip link set dev dummy1 down
	check_err $?

	__multipath_test "dummy1" "dummy0"

	ipns ip link set dev dummy0 down
	check_err $?

	ipns ip route get fibmatch 203.0.113.1 &> /dev/null
	check_fail $?
	ipns ip -6 route get fibmatch 2001:db8:3::1 &> /dev/null
	check_fail $?

	ipns ip link del dev dummy1
	ipns ip link del dev dummy0

	if [ $ret -ne 0 ]; then
		echo "FAIL: multipath route test"
		return 1
	fi
	echo "PASS: multipath route test"
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

dc_test
remote_test
multipath_test

exit $ret
