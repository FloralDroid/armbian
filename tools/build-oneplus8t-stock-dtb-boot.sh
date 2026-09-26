#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_dir="${repo_root}/output/images"

stock_boot="${STOCK_BOOT:-${image_dir}/oneplus8t-firmware/extracted-602/boot.img}"
armbian_boot="${ARMBIAN_BOOT:-${image_dir}/Armbian-unofficial_26.11.0-trunk_Oneplus-kebab_trixie_current_6.18.52_minimal.boot_sm8250-oneplus-kebab.img}"
kernel_image="${KERNEL_IMAGE:-/tmp/kb-armbian/Image}"
ramdisk_image="${RAMDISK_IMAGE:-/tmp/kb-armbian/ramdisk}"
stock_dtb="${STOCK_DTB:-/tmp/kb-stock/dtb}"
output_image="${OUTPUT_IMAGE:-${image_dir}/Armbian-unofficial_26.11.0-trunk_Oneplus-kebab_trixie_current_6.18.52_minimal.boot_stock602-dtb.img}"
avbtool="${AVBTOOL:-/mnt/aosp-hdd/redroid/source/external/avb/avbtool.py}"
partition_size=100663296
expected_stock_boot_sha256="cb4e546fe00141cb315cdaf22980bcba6a96e82d6365350311697f9579816991"
expected_dtb_size=11028247

for tool in mkbootimg unpack_bootimg python3 sha256sum cmp od stat; do
	command -v "${tool}" >/dev/null || { echo "Missing tool: ${tool}" >&2; exit 1; }
done

for input in "${stock_boot}" "${armbian_boot}" "${kernel_image}" "${ramdisk_image}" "${stock_dtb}" "${avbtool}"; do
	[[ -f "${input}" ]] || { echo "Missing input: ${input}" >&2; exit 1; }
done

stock_sha256="$(sha256sum "${stock_boot}" | cut -d ' ' -f 1)"
[[ "${stock_sha256}" == "${expected_stock_boot_sha256}" ]] || {
	echo "Unexpected stock boot SHA256: ${stock_sha256}" >&2
	exit 1
}

[[ "$(stat -c %s "${stock_dtb}")" -eq "${expected_dtb_size}" ]] || {
	echo "Unexpected stock DTB size" >&2
	exit 1
}

# ARM64 Image magic (0x644d5241, little endian) is stored at offset 0x38.
kernel_magic="$(od -An -tx1 -j 56 -N 4 "${kernel_image}" | tr -d ' \n')"
[[ "${kernel_magic}" == "41524d64" ]] || {
	echo "Input kernel is not a raw ARM64 Image (magic: ${kernel_magic})" >&2
	exit 1
}

workdir="$(mktemp -d /tmp/oneplus8t-stock-dtb-boot.XXXXXX)"
trap 'rm -rf "${workdir}"' EXIT
mkdir -p "${workdir}/stock" "${workdir}/armbian" "${workdir}/verify"

declare -a stock_args=()
declare -a armbian_args=()
while IFS= read -r -d '' arg; do stock_args+=("${arg}"); done < <(
	unpack_bootimg --boot_img "${stock_boot}" --out "${workdir}/stock" --format=mkbootimg -0
)
while IFS= read -r -d '' arg; do armbian_args+=("${arg}"); done < <(
	unpack_bootimg --boot_img "${armbian_boot}" --out "${workdir}/armbian" --format=mkbootimg -0
)

arg_value() {
	local key="$1"
	local array_name="$2"
	local -n args_ref="${array_name}"
	local index

	for ((index = 0; index < ${#args_ref[@]}; index++)); do
		if [[ "${args_ref[index]}" == "${key}" ]]; then
			printf '%s' "${args_ref[index + 1]}"
			return 0
		fi
	done

	echo "Missing boot argument: ${key}" >&2
	return 1
}

header_version="$(arg_value --header_version stock_args)"
os_version="$(arg_value --os_version stock_args)"
os_patch_level="$(arg_value --os_patch_level stock_args)"
pagesize="$(arg_value --pagesize stock_args)"
base="$(arg_value --base stock_args)"
kernel_offset="$(arg_value --kernel_offset stock_args)"
ramdisk_offset="$(arg_value --ramdisk_offset stock_args)"
second_offset="$(arg_value --second_offset stock_args)"
tags_offset="$(arg_value --tags_offset stock_args)"
dtb_offset="$(arg_value --dtb_offset stock_args)"
board="$(arg_value --board stock_args)"
cmdline="$(arg_value --cmdline armbian_args)"

[[ "${header_version}" == "2" ]] || {
	echo "Stock boot header version is ${header_version}, expected 2" >&2
	exit 1
}

mkbootimg \
	--header_version "${header_version}" \
	--os_version "${os_version}" \
	--os_patch_level "${os_patch_level}" \
	--kernel "${kernel_image}" \
	--ramdisk "${ramdisk_image}" \
	--dtb "${stock_dtb}" \
	--pagesize "${pagesize}" \
	--base "${base}" \
	--kernel_offset "${kernel_offset}" \
	--ramdisk_offset "${ramdisk_offset}" \
	--second_offset "${second_offset}" \
	--tags_offset "${tags_offset}" \
	--dtb_offset "${dtb_offset}" \
	--board "${board}" \
	--cmdline "${cmdline}" \
	--output "${workdir}/boot.img"

python3 "${avbtool}" add_hash_footer \
	--image "${workdir}/boot.img" \
	--partition_name boot \
	--partition_size "${partition_size}" \
	--hash_algorithm sha256 \
	--algorithm NONE

[[ "$(stat -c %s "${workdir}/boot.img")" -eq "${partition_size}" ]] || {
	echo "Generated boot image is not exactly ${partition_size} bytes" >&2
	exit 1
}

declare -a verify_args=()
while IFS= read -r -d '' arg; do verify_args+=("${arg}"); done < <(
	unpack_bootimg --boot_img "${workdir}/boot.img" --out "${workdir}/verify" --format=mkbootimg -0
)
[[ "$(arg_value --header_version verify_args)" == "2" ]]
[[ "$(arg_value --cmdline verify_args)" == "${cmdline}" ]]
[[ "$(stat -c %s "${workdir}/verify/dtb")" -eq "${expected_dtb_size}" ]]
cmp --silent "${workdir}/verify/kernel" "${kernel_image}"
cmp --silent "${workdir}/verify/ramdisk" "${ramdisk_image}"
cmp --silent "${workdir}/verify/dtb" "${stock_dtb}"

install -m 0644 "${workdir}/boot.img" "${output_image}"

echo "Output: ${output_image}"
echo "Header version: ${header_version}"
echo "Command line: ${cmdline}"
echo "Kernel SHA256: $(sha256sum "${kernel_image}" | cut -d ' ' -f 1)"
echo "Ramdisk SHA256: $(sha256sum "${ramdisk_image}" | cut -d ' ' -f 1)"
echo "DTB size: $(stat -c %s "${stock_dtb}")"
echo "DTB SHA256: $(sha256sum "${stock_dtb}" | cut -d ' ' -f 1)"
echo "Boot size: $(stat -c %s "${output_image}")"
echo "Boot SHA256: $(sha256sum "${output_image}" | cut -d ' ' -f 1)"
