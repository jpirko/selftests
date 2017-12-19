#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "SKIP: Need root privileges"
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

source lib.sh

declare -A options
declare -A netifs
count=0

# Try to load netdev names from command like

while [[ $# -gt 0 ]]
do
	echo $1 | grep "=" &> /dev/null
	if [ $? -eq 0 ]; then
		splitarr=(${1//=/ })
		options[${splitarr[0]}]=${splitarr[1]}
	else
		count=$(($count + 1))
		netifs[p$count]="$1"
	fi
	shift
done

# Fallback to topo.sh in case the netdev names are not loaded

if [ ${#netifs[@]} -eq 0 ]; then
	if [ ! -f topo.sh ]; then
		echo "SKIP: Could not find topology file"
		exit 0
	fi
	source topo.sh
fi

[ "${options[debug]}" == "yes" ] && set -x

num_netifs=2
topo_check $num_netifs

h1=${netifs[p1]}
h2=${netifs[p2]}
h1mac=$(mac_get $h1)
h2mac=$(mac_get $h2)

tcflags="skip_hw"

ret=0
retmsg=""

check_err()
{
	if [ $ret -eq 0 ]; then
		ret=$1
		retmsg=$2
	fi
}

check_fail()
{
	if [ $1 -eq 0 ]; then
		ret=1
		retmsg=$2
	fi
}

print_result()
{
	if [ $ret -ne 0 ]; then
		echo "FAIL: $1 ($tcflags) - $retmsg"
		return 1
	fi
	echo "PASS: $1 ($tcflags)"
	return 0
}

h1_create()
{
	ip link add dev vrf-h1 type vrf table 10
	ip link set dev $h1 master vrf-h1
	ip link set dev vrf-h1 up
	ip link set dev $h1 up
	ip addr add 192.168.100.1/24 dev $h1
	ip addr add 192.168.101.1/24 dev $h1
	ip addr add cafe::1/64 dev $h1
	tc qdisc add dev $h1 clsact
}

h1_destroy()
{
	tc qdisc del dev $h1 clsact
	ip addr del cafe::1/64 dev $h1
	ip addr del 192.168.101.1/24 dev $h1
	ip addr del 192.168.100.1/24 dev $h1
	ip link set dev $h1 down
	ip link del dev vrf-h1
}

h2_create()
{
	ip link add dev vrf-h2 type vrf table 20
	ip link set dev $h2 master vrf-h2
	ip link set dev vrf-h2 up
	ip link set dev $h2 up
	ip addr add 192.168.100.2/24 dev $h2
	ip addr add 192.168.101.2/24 dev $h2
	ip addr add cafe::2/64 dev $h2
	tc qdisc add dev $h2 clsact
}

h2_destroy()
{
	tc qdisc del dev $h2 clsact
	ip addr del cafe::2/64 dev $h2
	ip addr del 192.168.101.2/24 dev $h2
	ip addr del 192.168.100.2/24 dev $h2
	ip link set dev $h2 down
	ip link del dev vrf-h2
}

match_dst_mac_test()
{
	ret=0

	tc filter add dev $h2 ingress protocol ip pref 1 handle 101 flower $tcflags dst_mac de:ad:be:ef:aa:aa action drop
	tc filter add dev $h2 ingress protocol ip pref 2 handle 102 flower $tcflags dst_mac $h2mac action drop

	mausezahn $h1 -c 1 -p 64 -a $h1mac -b $h2mac -A 192.168.100.1 -B 192.168.100.2 -t ip -q

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.dst_mac == "de:ad:be:ef:aa:aa") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_fail $? "matched on a wrong filter"

	tc -j -s filter show dev $h2 ingress |
		jq -e ".[] | select(.options.keys.dst_mac == \"$h2mac\") |
		       select(.options.actions[0].stats.packets == 1)" &> /dev/null
	check_err $? "did not match on correct filter"

	tc filter del dev $h2 ingress protocol ip pref 1 handle 101 flower
	tc filter del dev $h2 ingress protocol ip pref 2 handle 102 flower

	print_result "dst_mac match"
	return $?
}

match_src_mac_test()
{
	ret=0

	tc filter add dev $h2 ingress protocol ip pref 1 handle 101 flower $tcflags src_mac de:ad:be:ef:aa:aa action drop
	tc filter add dev $h2 ingress protocol ip pref 2 handle 102 flower $tcflags src_mac $h1mac action drop

	mausezahn $h1 -c 1 -p 64 -a $h1mac -b $h2mac -A 192.168.100.1 -B 192.168.100.2 -t ip -q

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.src_mac == "de:ad:be:ef:aa:aa") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_fail $? "matched on a wrong filter"

	tc -j -s filter show dev $h2 ingress |
		jq -e ".[] | select(.options.keys.src_mac == \"$h1mac\") |
		       select(.options.actions[0].stats.packets == 1)" &> /dev/null
	check_err $? "did not match on correct filter"

	tc filter del dev $h2 ingress protocol ip pref 1 handle 101 flower
	tc filter del dev $h2 ingress protocol ip pref 2 handle 102 flower

	print_result "src_mac match"
	return $?
}

match_dst_ip_test()
{
	ret=0

	tc filter add dev $h2 ingress protocol ip pref 1 handle 101 flower $tcflags dst_ip 192.168.101.2 action drop
	tc filter add dev $h2 ingress protocol ip pref 2 handle 102 flower $tcflags dst_ip 192.168.100.2 action drop
	tc filter add dev $h2 ingress protocol ip pref 3 handle 103 flower $tcflags dst_ip 192.168.100.0/24 action drop

	mausezahn $h1 -c 1 -p 64 -a $h1mac -b $h2mac -A 192.168.100.1 -B 192.168.100.2 -t ip -q

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.dst_ip == "192.168.101.2") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_fail $? "matched on a wrong filter"

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.dst_ip == "192.168.100.2") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_err $? "did not match on correct filter"

	tc filter del dev $h2 ingress protocol ip pref 2 handle 102 flower

	mausezahn $h1 -c 1 -p 64 -a $h1mac -b $h2mac -A 192.168.100.1 -B 192.168.100.2 -t ip -q

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.dst_ip == "192.168.100.0/24") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_err $? "did not match on correct filter with mask"

	tc filter del dev $h2 ingress protocol ip pref 1 handle 101 flower
	tc filter del dev $h2 ingress protocol ip pref 3 handle 103 flower

	print_result "dst_ip match"
	return $?
}

match_src_ip_test()
{
	ret=0

	tc filter add dev $h2 ingress protocol ip pref 1 handle 101 flower $tcflags src_ip 192.168.101.1 action drop
	tc filter add dev $h2 ingress protocol ip pref 2 handle 102 flower $tcflags src_ip 192.168.100.1 action drop
	tc filter add dev $h2 ingress protocol ip pref 3 handle 103 flower $tcflags src_ip 192.168.100.0/24 action drop

	mausezahn $h1 -c 1 -p 64 -a $h1mac -b $h2mac -A 192.168.100.1 -B 192.168.100.2 -t ip -q

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.src_ip == "192.168.101.1") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_fail $? "matched on a wrong filter"

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.src_ip == "192.168.100.1") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_err $? "did not match on correct filter"

	tc filter del dev $h2 ingress protocol ip pref 2 handle 102 flower

	mausezahn $h1 -c 1 -p 64 -a $h1mac -b $h2mac -A 192.168.100.1 -B 192.168.100.2 -t ip -q

	tc -j -s filter show dev $h2 ingress |
		jq -e '.[] | select(.options.keys.src_ip == "192.168.100.0/24") |
		       select(.options.actions[0].stats.packets == 1)' &> /dev/null
	check_err $? "did not match on correct filter with mask"

	tc filter del dev $h2 ingress protocol ip pref 1 handle 101 flower
	tc filter del dev $h2 ingress protocol ip pref 3 handle 103 flower

	print_result "src_ip match"
	return $?
}

setup_init()
{
	if [ "${options[noinit]}" == "yes" ]; then
		echo "INFO: Not doing setup init"
		return 0
	fi
	vrf_fib_rules_prepare 4
	vrf_fib_rules_prepare 6
	h1_create
	h2_create
}

setup_fini()
{
	if [ "${options[nofini]}" == "yes" ]; then
		echo "INFO: Not doing setup fini"
		return 0
	fi
	h2_destroy
	h1_destroy
	vrf_fib_rules_cleanup 6
	vrf_fib_rules_cleanup 4
}

trap setup_fini EXIT

setup_init
setup_wait $num_netifs

match_dst_mac_test
match_src_mac_test
match_dst_ip_test
match_src_ip_test

tc_offload_check $num_netifs
if [ $? -ne 0 ]; then
	echo "WARN: Could not test offloaded functionality"
else
	tcflags="skip_sw"
	match_dst_mac_test
	match_src_mac_test
	match_dst_ip_test
	match_src_ip_test
fi

exit $ret
