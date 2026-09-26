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
		"KALLSYMS_ALL"
		"DYNAMIC_DEBUG"
		"MEMTEST"
		"IRQ_TIME_ACCOUNTING"
		"SOFTLOCKUP_DETECTOR"
		"SOFTLOCKUP_DETECTOR_INTR_STORM"
		"HARDLOCKUP_DETECTOR"
		"ARM64_PSEUDO_NMI"
		"DETECT_HUNG_TASK"
		"DETECT_HUNG_TASK_BLOCKER"
		"WQ_WATCHDOG"
		"SCHEDSTATS"
		"PROVE_LOCKING"
		"PROVE_RCU"
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
