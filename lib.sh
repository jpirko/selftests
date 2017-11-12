#!/bin/bash

topo_check()
{
	for i in $(eval echo {1..$1})
	do
		ip link show dev ${netifs[p$i]} &> /dev/null
		if [ $? -ne 0 ]; then
			return 1
		fi
	done

	return 0
}

setup_wait()
{
	for i in $(eval echo {1..$1})
	do
		while true; do
			ip link show dev ${netifs[p$i]} up | grep 'state UP' \
				&> /dev/null
			if [ $? -ne 0 ]; then
				sleep 1
			else
				break
			fi
		done
	done

	# Make sure links are ready.
	sleep 1
}

vrf_fib_rules_prepare()
{
	ip -${1} rule add pref 32765 table local
	ip -${1} rule del pref 0
}

vrf_fib_rules_cleanup()
{
	ip -${1} rule add pref 0 table local
	ip -${1} rule del pref 32765
}
