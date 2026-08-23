#!/bin/sh

PATH=/bin
HOME=/root
export PATH HOME

failed=0

printf '==========================\n'
printf '       TEST_BEGIN\n'
printf '==========================\n'

for test_path in /tests/*; do
	[ -f "$test_path" ] || continue
	test_name=${test_path##*/}

	printf '\n\n=== TEST_RUN %s ===\n' "$test_name"
	busybox timeout -k 3 60 "$test_path"
	status=$?
	if [ "$status" -eq 0 ]; then
		printf '=== TEST_PASS %s ===\n' "$test_name"
	else
		printf '=== TEST_FAIL %s (exit status %s) ===\n' "$test_name" "$status"
		failed=$((failed + 1))
	fi
done

printf '==========================\n'
printf '  TEST_COMPLETE failed=%s\n' "$failed"
printf '==========================\n'
poweroff -f

while :; do
	sleep 1
done
