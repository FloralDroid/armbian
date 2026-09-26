#!/usr/bin/env bash
# @description Enables the common kernel capabilities required by Android containers on mobile devices.

# Keep this list hardware-agnostic. Board-specific drivers and policies belong
# in their board or family configuration.
function custom_kernel_config__kernel_common() {
	opts_y+=(
		"AUDIT"
		"CGROUPS"
		"MEMCG"
		"CGROUP_PIDS"
		"CGROUP_FREEZER"
		"CGROUP_BPF"
		"NAMESPACES"
		"UTS_NS"
		"IPC_NS"
		"USER_NS"
		"PID_NS"
		"NET_NS"
		"SECCOMP"
		"SECCOMP_FILTER"
		"ANDROID_BINDER_IPC"
		"ANDROID_BINDERFS"
		"SECURITY"
		"SECURITY_NETWORK"
		"SECURITY_SELINUX"
		"SECURITY_SELINUX_BOOTPARAM"
		"SECURITY_SELINUX_DEVELOP"
	)

	# BinderFS provides per-container Binder devices; retain the conventional
	# static devices for Android userspace that does not mount BinderFS itself.
	kernel_config_modifying_hashes+=(
		'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"'
		"kernel-common-lsm=append-selinux-v2"
	)

	[[ -f .config ]] || return 0

	run_host_command_logged ./scripts/config --set-str \
		ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder"

	# CONFIG_LSM is an ordered list and differs between kernel families. Keep
	# every existing entry and append SELinux only when it is not already listed.
	# With no explicit list, Kconfig selects its complete default after SELinux
	# is enabled; setting "selinux" alone here would discard those default LSMs.
	local lsm
	lsm="$(sed -n 's/^CONFIG_LSM="\(.*\)"$/\1/p' .config)"
	[[ -n "${lsm}" ]] || return 0
	case ",${lsm}," in
		*,selinux,*) ;;
		*)
			lsm="${lsm:+${lsm},}selinux"
			run_host_command_logged ./scripts/config --set-str LSM "${lsm}"
			;;
	esac
}
