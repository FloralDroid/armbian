#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z ${MI8_SSH_PASSWORD:-} ]]; then
	printf 'Usage: MI8_SSH_PASSWORD=... %s OUTPUT_DIR\n' "$0" >&2
	exit 2
fi

password=$MI8_SSH_PASSWORD
unset MI8_SSH_PASSWORD
output_dir=$1
umask 077
mkdir -p -- "$output_dir"
log_file="$output_dir/capture.log"

# Keep the records on the host: the phone's disk and USB link may stop together.
remote_command='
printf "== CAPTURE START ==\n"
cat /proc/sys/kernel/random/boot_id
dmesg -w &
kmsg_pid=$!
trap "kill $kmsg_pid 2>/dev/null" EXIT
while :; do
	date "+== SAMPLE %s.%N =="
	printf "== UPTIME AND LOAD ==\n"
	cat /proc/uptime /proc/loadavg
	printf "== INTERRUPTS ==\n"
	cat /proc/interrupts
	printf "== SOFTIRQS ==\n"
	cat /proc/softirqs
	printf "== CPU STAT ==\n"
	head -n 10 /proc/stat
	printf "== PRESSURE ==\n"
	cat /proc/pressure/cpu /proc/pressure/io /proc/pressure/memory
	sleep 1
done
'

while :; do
	printf '\n== HOST CONNECT %s ==\n' "$(date --iso-8601=seconds)" >> "$log_file"
	if MI8_CAPTURE_PASSWORD="$password" MI8_CAPTURE_COMMAND="$remote_command" \
		expect -c '
			set timeout 30
			set password $env(MI8_CAPTURE_PASSWORD)
			set command $env(MI8_CAPTURE_COMMAND)
			unset env(MI8_CAPTURE_PASSWORD)
			unset env(MI8_CAPTURE_COMMAND)
			spawn ssh -T -o BatchMode=no -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=accept-new root@172.16.42.1 $command
			expect {
				-re {(?i)password:} {
					send -- "$password\r"
					expect {
						-re {== CAPTURE START ==} {set timeout -1; expect eof}
						-re {(?i)password:} {exit 77}
						eof {}
						timeout {exit 124}
					}
				}
				-re {== CAPTURE START ==} {set timeout -1; expect eof}
				eof {}
				timeout {exit 124}
			}
			catch wait result
			exit [lindex $result 3]
		' >> "$log_file" 2>&1; then
		status=0
	else
		status=$?
	fi
	printf '== HOST DISCONNECT %s status=%s ==\n' "$(date --iso-8601=seconds)" "$status" >> "$log_file"
	sleep 2
done
