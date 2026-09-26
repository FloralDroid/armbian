#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: inject-xiaomi-dipper-firmware.sh ROOTFS_IMG OUTPUT_IMG GPU_DIR VENUS_DIR

GPU_DIR must contain a630_zap.mdt and a630_zap.b00 (plus its other .bNN files).
VENUS_DIR must contain venus.mdt and venus.b00 (plus its other .bNN files).
The input image is unchanged; OUTPUT_IMG must not already exist.
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
	usage
	exit 0
fi
if [[ $# -ne 4 ]]; then
	usage >&2
	exit 2
fi

rootfs=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
gpu_dir=$(realpath -e -- "$3")
venus_dir=$(realpath -e -- "$4")

[[ -f $rootfs && $(blkid -p -s TYPE -o value "$rootfs") == ext4 ]] || {
	echo "Input must be an ext4 rootfs image: $rootfs" >&2
	exit 1
}
[[ -d $gpu_dir && -d $venus_dir ]] || {
	echo "GPU_DIR and VENUS_DIR must be directories" >&2
	exit 1
}
[[ $output != "$rootfs" && ! -e $output ]] || {
	echo "Output must be a new path different from the input: $output" >&2
	exit 1
}
[[ -d $(dirname "$output") ]] || {
	echo "Output directory does not exist: $(dirname "$output")" >&2
	exit 1
}

for required in "$gpu_dir/a630_zap.mdt" "$gpu_dir/a630_zap.b00" \
		"$venus_dir/venus.mdt" "$venus_dir/venus.b00"; do
	[[ -f $required && ! -L $required ]] || {
		echo "Missing regular firmware file: $required" >&2
		exit 1
	}
done

original_uuid=$(blkid -p -s UUID -o value "$rootfs")
work_image=$(mktemp -p "$(dirname "$output")" .dipper-firmware.XXXXXXXX.img)
mount_dir=$(mktemp -d -p "$(dirname "$output")" .dipper-firmware-mount.XXXXXXXX)
cleanup() {
	if mountpoint -q "$mount_dir"; then
		umount "$mount_dir" || {
			echo "Unmount failed; temporary image preserved at $work_image" >&2
			return
		}
	fi
	rmdir "$mount_dir"
	[[ ! -f $work_image ]] || rm -f -- "$work_image"
}
trap cleanup EXIT

cp --reflink=auto --sparse=always -- "$rootfs" "$work_image"
mount -o loop,rw "$work_image" "$mount_dir"
target="$mount_dir/lib/firmware/qcom/sdm845/dipper"
install -d -m 755 "$target"

shopt -s nullglob
gpu_files=("$gpu_dir"/a630_zap.mdt "$gpu_dir"/a630_zap.b[0-9][0-9])
venus_files=("$venus_dir"/venus.mdt "$venus_dir"/venus.b[0-9][0-9])
for source in "${gpu_files[@]}" "${venus_files[@]}"; do
	[[ -f $source && ! -L $source ]] || {
		echo "Invalid firmware file: $source" >&2
		exit 1
	}
	install -m 644 -- "$source" "$target/$(basename "$source")"
	cmp -s -- "$source" "$target/$(basename "$source")"
done

umount "$mount_dir"
e2fsck -fn "$work_image"
[[ $(blkid -p -s UUID -o value "$work_image") == "$original_uuid" ]] || {
	echo "Rootfs UUID changed during injection" >&2
	exit 1
}
mv -- "$work_image" "$output"
sha256sum "$output"
