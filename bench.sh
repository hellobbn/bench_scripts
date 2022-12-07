#!/bin/bash

##
# General benchmark script
##

# Hide ^C
stty -echoctl

# Exit early when error
set -e

# print debug information print
set -x

# Export common benchmark variables
export MOUNT_DIR=/mnt/pmem
export PATH=/usr/local/bin:$PATH
export LOCAL_DIR
export date_suffix

LOCAL_DIR=$(pwd)
date_suffix=$(date --iso-8601=seconds)
export result_dir="result/result_${date_suffix}"

# Read from config
source common/setup

# Import util functions
source utils/fn_fs
source utils/fn_util
source utils/fn_zoned

function ask_for_deletion {
    echo "Bench got interrupted, dir: $result_dir"
    read -r -p " Do you want to delete this dir? [y/N]" response
    case "$response" in
        [yY][eE][sS]|[yY])
            rm -rf "$result_dir"
            echo "Deleted"
            ;;
        *)
            Exiting
            ;;
    esac
}
trap 'ask_for_deletion' SIGINT

function ask_for_tag {
	read -r -p "Do you want to enter a tag for this bench? [y/N]" response
	case "$response" in
        [yY][eE][sS]|[yY])
			read -r -p "Enter the tag: " tag
			;;
		*)
			echo
			;;
	esac

	echo "$tag" >> "${result_dir}"/bench_tag
}

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

for profile in $CONFIG_BENCH_PROFILE; do
	# Every profile has its own directory
	dir_name="${result_dir}/$profile"

	# shellcheck source=profile/main
	source profile/"$profile"

	init_profile "$setting_bench"

	for bench in $setting_bench; do
		# shellcheck source=bench/fio/fn_fio
		source "bench/${bench}/fn_${bench}"
		mkdir -p "$dir_name/$bench"
		if [[ -n $(echo "$bench" | grep raw || /bin/true) ]]; then
			zoned_cleanup
			bench_single_main "$dir_name/$bench/$bench-raw"
		else
			for bench_fs in $setting_fs; do

				if [[ "${bench_fs}" == "dm-zoned" ]]; then
					bench_zoned_fs=${setting_dmzoned_fs}
				else
					bench_zoned_fs=""
				fi

				for bench_zfs in $bench_zoned_fs; do

					export BENCH_DIR=${LOCAL_DIR}/${bench}

					zoned_format_"${bench_fs}"
					zoned_mount_"${bench_fs}"

					bench_single_main "$dir_name/$bench/$bench-${bench_fs}_${bench_zfs}"

					zoned_cleanup

				done # dm-zoned

			done # fs
		fi
	done # bench
done  # profile

rm result/latest || /bin/true
ln -s "$result_dir" "result/latest"
ask_for_tag
