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

num_netifs=8
topo_check $num_netifs
if [ $? -ne 0 ]; then
	echo "SKIP: Could not find all required interfaces"
	exit 0
fi

h1=${netifs[p1]}
rtr11=${netifs[p2]}
rtr12=${netifs[p3]}
rtr13=${netifs[p5]}
rtr21=${netifs[p7]}
rtr22=${netifs[p4]}
rtr23=${netifs[p6]}
h2=${netifs[p8]}

ipv6_fwd_path="net.ipv6.conf.all.forwarding"

weight12=1
weight13=40

ret=0

h1_create()
{
	ip link add dev vrf-h1 type vrf table 10
	ip link set dev $h1 master vrf-h1
	ip link set dev vrf-h1 up
	ip link set dev $h1 up
	ip address add 2001:db8:1::1/64 dev $h1
	ip route add table 10 2001:db8:2::/64 nexthop via fe80::11 dev $h1
}

h1_destroy()
{
	ip route del table 10 2001:db8:2::/64
	ip address del 2001:db8:1::1/64 dev $h1
	ip link set dev $h1 down
	ip link del dev vrf-h1
}

h2_create()
{
	ip link add dev vrf-h2 type vrf table 20
	ip link set dev $h2 master vrf-h2
	ip link set dev vrf-h2 up
	ip link set dev $h2 up
	ip address add 2001:db8:2::1/64 dev $h2
	ip route add table 20 2001:db8:1::/64 nexthop via fe80::21 dev $h2
}

h2_destroy()
{
	ip route del table 20 2001:db8:1::/64
	ip address del 2001:db8:2::1/64 dev $h2
	ip link set dev $h2 down
	ip link del dev vrf-h2
}

rtr1_create()
{
	ip link add dev vrf-rtr1 type vrf table 30
	ip -6 route add vrf vrf-rtr1 unreachable default
	ip link set dev $rtr11 master vrf-rtr1
	ip link set dev $rtr12 master vrf-rtr1
	ip link set dev $rtr13 master vrf-rtr1
	ip link set dev vrf-rtr1 up
	ip link set dev $rtr11 up
	ip link set dev $rtr12 up
	ip link set dev $rtr13 up
	ip address add 2001:db8:1::2/64 dev $rtr11
	ip address add fe80::11/10 dev $rtr11
	ip address add fe80::12/10 dev $rtr12
	ip address add fe80::13/10 dev $rtr13
	ip route add table 30 2001:db8:2::/64 \
		nexthop via fe80::22 dev $rtr12 weight $weight12 \
		nexthop via fe80::23 dev $rtr13 weight $weight13
}

rtr1_destroy()
{
	ip route del table 30 2001:db8:2::/64
	ip address del fe80::13/10 dev $rtr13
	ip address del fe80::12/10 dev $rtr12
	ip address del fe80::11/10 dev $rtr11
	ip link set dev $rtr13 down
	ip link set dev $rtr12 down
	ip link set dev $rtr11 down
	ip link set dev vrf-rtr1 down
	ip -6 route del vrf vrf-rtr1 unreachable default
	ip link del dev vrf-rtr1
	sysctl -q -w $ipv6_fwd_path=$ipv6_fwd
}

rtr2_create()
{
	ip link add dev vrf-rtr2 type vrf table 40
	ip -6 route add vrf vrf-rtr2 unreachable default
	ip link set dev $rtr21 master vrf-rtr2
	ip link set dev $rtr22 master vrf-rtr2
	ip link set dev $rtr23 master vrf-rtr2
	ip link set dev vrf-rtr2 up
	ip link set dev $rtr21 up
	ip link set dev $rtr22 up
	ip link set dev $rtr23 up
	ip address add 2001:db8:2::2/64 dev $rtr21
	ip address add fe80::21/10 dev $rtr21
	ip address add fe80::22/10 dev $rtr22
	ip address add fe80::23/10 dev $rtr23
	ip route add table 40 2001:db8:1::/64 \
		nexthop via fe80::12 dev $rtr22 \
		nexthop via fe80::13 dev $rtr23
}

rtr2_destroy()
{
	ip route del table 40 2001:db8:1::/64
	ip address del fe80::23/10 dev $rtr23
	ip address del fe80::22/10 dev $rtr22
	ip address del fe80::21/10 dev $rtr21
	ip link set dev $rtr23 down
	ip link set dev $rtr22 down
	ip link set dev $rtr21 down
	ip link set dev vrf-rtr2 down
	ip -6 route del vrf vrf-rtr2 unreachable default
	ip link del dev vrf-rtr2
}

ping6_test()
{
	ip vrf exec vrf-h1 ping6 2001:db8:2::1 -c 10 -i 0.1 -w 2 &> /dev/null
	if [ $? -eq 0 ]; then
		echo "PASS: ping6"
	else
		echo "FAIL: ping6"
		ret=1
	fi
}

tx_pkts_get()
{
	echo $(ip -j -s link show dev $1 | \
	       jq '.[]["stats644"]["tx"]["packets"]')
}

multiple_flows_generate()
{
	ip vrf exec vrf-h1 mausezahn $h1 -q -6 -B 2001:db8:2::/112 -t ip \
		-p 64 -c 10
}

ratio_eval()
{
	local rtr13_pkts=$1
	local rtr12_pkts=$2
	local weight_ratio
	local pkts_ratio
	local diff
	local res

	pkts_ratio=$(echo $rtr13_pkts / $rtr12_pkts | bc -l)
	weight_ratio=$(echo $weight13 / $weight12 | bc -l)

	echo "Expected ratio: $weight_ratio, Measured ratio: $pkts_ratio"

	diff=$(echo $weight_ratio - $pkts_ratio | bc -l)
	diff=${diff#-}
	res=$(echo "$diff / $weight_ratio > 0.1" | bc -l)

	if [ $res -ne 0 ]; then
		echo "FAIL: Too large discrepancy (> 10%) in ratio"
		ret=1
	else
		echo "PASS: non-equal-cost multipath"
	fi
}

multipath_test()
{
	local rtr12_pkts_t0
	local rtr12_pkts_t1
	local rtr13_pkts_t0
	local rtr13_pkts_t1
	local rtr12_pkts
	local rtr13_pkts

	# Record number of sent packets on each one of rtr1's multipath
	# links.
	rtr12_pkts_t0=$(tx_pkts_get $rtr12)
	rtr13_pkts_t0=$(tx_pkts_get $rtr13)

	# Generate multiple flows from h1 to h2.
	multiple_flows_generate

	rtr12_pkts_t1=$(tx_pkts_get $rtr12)
	rtr13_pkts_t1=$(tx_pkts_get $rtr13)

	rtr13_pkts=$(($rtr13_pkts_t1 - $rtr13_pkts_t0))
	rtr12_pkts=$(($rtr12_pkts_t1 - $rtr12_pkts_t0))

	ratio_eval $rtr13_pkts $rtr12_pkts
}

setup_prepare()
{
	ipv6_fwd=$(sysctl -n $ipv6_fwd_path)

	sysctl -q -w $ipv6_fwd_path=1
	vrf_fib_rules_prepare 4
	vrf_fib_rules_prepare 6
	h1_create
	h2_create
	rtr1_create
	rtr2_create
}

cleanup()
{
	rtr2_destroy
	rtr1_destroy
	h2_destroy
	h1_destroy
	vrf_fib_rules_cleanup 6
	vrf_fib_rules_cleanup 4
	sysctl -q -w $ipv6_fwd_path=$ipv6_fwd
}

trap cleanup EXIT

setup_prepare
setup_wait $num_netifs

sleep 2
ping6_test
multipath_test

exit $ret
