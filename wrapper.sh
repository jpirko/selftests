#!/bin/bash
# Execute a test with oops checking.

oops_state=/var/lib/abrt/abrt-dump-journal-oops.state
testname=$1

oops_get()
{
	if [ ! -f $oops_state ]; then
		echo ""
	else
		sha1sum $oops_state
	fi
}

oops1=$(oops_get)
./$testname
ret=$?
oops2=$(oops_get)

if [ "$oops1" == "" ]; then
	echo "SKIP: oops"
elif [ "$oops1" == "$oops2" ]; then
	echo "PASS: oops"
else
	echo "FAIL: oops"
	ret=1
fi

exit $ret
