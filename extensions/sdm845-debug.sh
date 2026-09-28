#!/usr/bin/env bash
# @description Opt-in SDM845 crash-capture kernel; keeps production modules and patches, adds costly diagnostics.

function post_family_config__sdm845_debug() {
	declare -g LINUXFAMILY="sdm845-debug"
	declare -g KERNELPATCHDIR="${KERNELPATCHDIR} archive/sdm845-6.18-debug"
	declare -g BOOTIMG_CMDLINE_EXTRA="${BOOTIMG_CMDLINE_EXTRA:+${BOOTIMG_CMDLINE_EXTRA} }crashkernel=512M irqchip.gicv3_pseudo_nmi=1"
}

function custom_kernel_config__sdm845_debug() {
	opts_n+=("KASAN")
	opts_y+=(
		"KEXEC_FILE"
		"CRASH_DUMP"
		"PROC_VMCORE"
		"PSTORE"
		"PSTORE_RAM"
		"PSTORE_CONSOLE"
		"PSTORE_PMSG"
		"PSTORE_FTRACE"
		"KALLSYMS_ALL"
		"DYNAMIC_DEBUG"
		"MEMTEST"
		"IRQ_TIME_ACCOUNTING"
		"SOFTLOCKUP_DETECTOR"
		"SOFTLOCKUP_DETECTOR_INTR_STORM"
		"HARDLOCKUP_DETECTOR"
		"WATCHDOG_SYSFS"
		"WATCHDOG_PRETIMEOUT_GOV"
		"WATCHDOG_PRETIMEOUT_GOV_PANIC"
		"WATCHDOG_PRETIMEOUT_DEFAULT_GOV_PANIC"
		"ARM64_PSEUDO_NMI"
		"DETECT_HUNG_TASK"
		"DETECT_HUNG_TASK_BLOCKER"
		"WQ_WATCHDOG"
		"SCHEDSTATS"
		"PROVE_LOCKING"
		"PROVE_RCU"
		"RCU_EQS_DEBUG"
		"DEBUG_IRQFLAGS"
		"DEBUG_ATOMIC_SLEEP"
		"DEBUG_PREEMPT"
		"DEBUG_LIST"
		"DEBUG_SG"
		"SCHED_STACK_END_CHECK"
		"FUNCTION_GRAPH_TRACER"
		"IRQSOFF_TRACER"
		"PREEMPT_TRACER"
		"SCHED_TRACER"
		"TRACER_SNAPSHOT"
		"RCU_TRACE"
	)
}

function post_customize_image__sdm845_debug_capture() {
	install -d -m 755 "${SDCARD}/etc/sysctl.d" "${SDCARD}/etc/systemd/system.conf.d" \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants"

	cat > "${SDCARD}/etc/sysctl.d/90-sdm845-debug-panic.conf" <<'EOF'
kernel.watchdog = 1
kernel.nmi_watchdog = 1
kernel.softlockup_panic = 1
kernel.hardlockup_panic = 1
kernel.hung_task_panic = 1
kernel.panic_on_rcu_stall = 1
kernel.panic_on_oops = 1
kernel.panic_on_warn = 0
kernel.panic = 1
EOF

	cat > "${SDCARD}/etc/systemd/system.conf.d/90-sdm845-debug-watchdog.conf" <<'EOF'
[Manager]
RuntimeWatchdogSec=30s
EOF

	cat > "${SDCARD}/etc/systemd/system/sdm845-debug-watchdog.service" <<'EOF'
[Unit]
Description=Configure SDM845 debug watchdog pretimeout
ConditionPathExists=/sys/class/watchdog/watchdog0/pretimeout

[Service]
Type=oneshot
ExecStart=/bin/sh -ec 'echo panic > /sys/class/watchdog/watchdog0/pretimeout_governor; echo 10 > /sys/class/watchdog/watchdog0/pretimeout'

[Install]
WantedBy=multi-user.target
EOF
	ln -s ../sdm845-debug-watchdog.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/sdm845-debug-watchdog.service"
}
