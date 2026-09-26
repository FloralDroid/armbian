#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: stress-xiaomi-dipper-venus.sh [ROUNDS [LOG_DIR [VIDEO_DEVICE]]]

Run three concurrent 720p H.264 Venus encoders, paced near 30 fps, for 90
frames per round. ROUNDS defaults to 100. Logs default to a new directory
under /root; an explicit LOG_DIR must not already exist. VIDEO_DEVICE defaults
to /dev/video-enc12. Stop at the first failed round.
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
	usage
	exit 0
fi
if [[ $# -gt 3 || ! ${1:-100} =~ ^[1-9][0-9]*$ ]]; then
	usage >&2
	exit 2
fi

rounds=${1:-100}
device=${3:-/dev/video-enc12}
for command in v4l2-ctl timeout dmesg stdbuf sync; do
	command -v "$command" >/dev/null || {
		echo "Missing command: $command" >&2
		exit 1
	}
done
[[ -e $device ]] || {
	echo "Missing video device: $device" >&2
	exit 1
}
device_info=$(v4l2-ctl -d "$device" --info)
[[ $device_info == *"Driver name"* && $device_info == *"qcom-venus"* &&
	$device_info == *"video encoder"* ]] || {
	echo "Not a Qualcomm Venus encoder: $device" >&2
	exit 1
}

if [[ $# -ge 2 ]]; then
	log_dir=$2
	mkdir -- "$log_dir"
else
	log_dir=$(mktemp -d /root/venus-stress.XXXXXXXX)
fi
log_dir=$(realpath -e -- "$log_dir")
printf 'Logs: %s\n' "$log_dir"
printf 'Device: %s; rounds: %s; streams: 3; frames/stream: 90\n' \
	"$device" "$rounds" | tee -a "$log_dir/summary.log"

stdbuf -oL dmesg --follow-new > "$log_dir/kernel.log" 2>&1 &
kernel_pid=$!
cleanup() {
	kill "$kernel_pid" 2>/dev/null || true
	wait "$kernel_pid" 2>/dev/null || true
	sync -f "$log_dir/summary.log" "$log_dir/kernel.log" 2>/dev/null || sync
}
trap cleanup EXIT

for ((round = 1; round <= rounds; round++)); do
	printf 'Round %s/%s started %s\n' "$round" "$rounds" \
		"$(date --iso-8601=seconds)" | tee -a "$log_dir/summary.log"
	stream_pids=()
	for stream in 1 2 3; do
		(
			set +e
			timeout -k 5 20 v4l2-ctl -d "$device" \
				--set-fmt-video-out=width=1280,height=720,pixelformat=NV12 \
				--set-fmt-video=width=1280,height=720,pixelformat=H264 \
				--stream-mmap=4 --stream-out-mmap=4 --stream-count=90 \
				--stream-sleep count=1,sleep=33,mode=1 \
				--stream-to=/dev/null --verbose \
				> "$log_dir/round-${round}-stream-${stream}.log" 2>&1
			printf '%s\n' "$?" > "$log_dir/round-${round}-stream-${stream}.exit"
		) &
		stream_pids+=("$!")
	done
	for stream_pid in "${stream_pids[@]}"; do
		wait "$stream_pid"
	done

	failed=0
	for stream in 1 2 3; do
		prefix="$log_dir/round-${round}-stream-${stream}"
		status=$(< "$prefix.exit")
		frames=$(grep -Ec '^cap dqbuf:.*bytesused: [1-9][0-9]*' "$prefix.log" || true)
		eos=$(grep -Ec '^cap dqbuf:.*bytesused: 0.*\(last' "$prefix.log" || true)
		fps=$(grep -Eo '[0-9]+\.[0-9]+ fps' "$prefix.log" | tail -n 1 || true)
		printf '  stream %s: exit=%s frames=%s eos=%s speed=%s\n' \
			"$stream" "$status" "$frames" "$eos" "${fps:-unknown}" \
			| tee -a "$log_dir/summary.log"
		if [[ $status != 0 || $frames != 90 || $eos != 1 ]]; then
			failed=1
		fi
	done
	sync -f "$log_dir/summary.log" "$log_dir/kernel.log" 2>/dev/null || sync
	if ((failed)); then
		dmesg > "$log_dir/kernel-at-failure.log"
		sync -f "$log_dir/kernel-at-failure.log" 2>/dev/null || sync
		echo "FAILED: round $round; inspect $log_dir" | tee -a "$log_dir/summary.log"
		exit 1
	fi
done

echo "PASS: $rounds rounds; inspect $log_dir" | tee -a "$log_dir/summary.log"
