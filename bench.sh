#!/bin/bash

##
# General benchmark script
##

# Hide ^C
stty -echoctl

# Exit early when error
set -e

# print debug information print
if [[ ${DEBUG} -eq 1 ]]; then
	set -x
fi

# Export common benchmark variables
export PATH=/usr/local/bin:$PATH
export LOCAL_DIR
export date_suffix
export BPFTRACE_DIR

LOCAL_DIR=$(pwd)
date_suffix=$(date +%Y%m%d_%H%M%S)
BPFTRACE_DIR="${LOCAL_DIR}/utils/bpftrace"
export result_dir="result/result_${date_suffix}"

# Read from config
spec_config=setup_$(hostname)
if [[ -f "config/${spec_config}" ]]; then
	# shellcheck source=common/setup_bbnpm
	source "config/${spec_config}"
else
	# shellcheck source=common/setup
	source "config/setup"
fi

# The arguments are the profile to run
if [[ $# -gt 0 ]]; then
	CONFIG_BENCH_PROFILE="$*"
fi

# Import util functions
source utils/fn_fs
source utils/fn_util
source utils/fn_zoned
source utils/fn_tags

function on_sigint {
	# Ask if we want to delete this directory
	ask_for_deletion

	# Cleanup if needed
	sudo service mysql stop

	exit 0
}
trap 'on_sigint' SIGINT

##
# Initialize before all benchmarks begin
#
# Arguments:
#  - $1: Benchmark list
##
function init_profile {
	echo "off" | sudo tee /sys/devices/system/cpu/smt/control || /bin/true

	# TODO
}

function run_prepare {
	zoned_format_"$1"
	zoned_mount_"$1"
}

setup_loop

for profile in $CONFIG_BENCH_PROFILE; do
	# Every profile has its own directory
	dir_name="${result_dir}/$profile"
	mkdir -p "${dir_name}"

	# shellcheck source=profile/main
	source profile/"$profile"
	inline_func profile/"$profile" >"$dir_name/profile"

	init_profile "$setting_bench"

	for bench in $setting_bench; do
		# shellcheck source=bench/fio/fn_fio
		source "bench/${bench}/fn_${bench}"
		mkdir -p "$dir_name/$bench"
		if [[ -n $(echo "$bench" | grep raw || /bin/true) ]]; then
			zoned_cleanup
			bench_single_main_${bench} "$dir_name/$bench/$bench-raw"
		else
			for bench_fs in $setting_fs; do
				if [[ ${bench_fs} == "dm-zoned" ]]; then
					bench_zoned_fs=${setting_dmzoned_fs}
				else
					bench_zoned_fs="${bench_fs}"
				fi

				for bench_zfs in $bench_zoned_fs; do
					export BENCH_DIR=${LOCAL_DIR}/bench/${bench}

					zoned_format_"${bench_fs}" $bench_zfs
					zoned_mount_"${bench_fs}" $bench_zfs

					bench_single_main_${bench} "$dir_name/$bench/$bench-${bench_fs}_${bench_zfs}"

					zoned_cleanup
				done # for bench_zfs in $bench_zoned_fs
			done  # fs
		fi     # if raw

		# this bench is over, see if we want to process
		# Test whether or not the file fn_${bench}_process exists
		if [[ -f "bench/${bench}/fn_${bench}_process" ]]; then
			# shellcheck source=bench/fio/fn_fio_process
			source "bench/${bench}/fn_${bench}_process"
			post_process "$dir_name/$bench"
			unset post_process
		fi
	done # bench
done  # profile

rm result/latest || /bin/true
if [[ -n $CONFIG_USER ]]; then
	chown -R $CONFIG_USER:$CONFIG_USER "$LOCAL_DIR"/result
fi
ln -s $LOCAL_DIR/"$result_dir" $LOCAL_DIR/"result/latest"
ask_for_tag
