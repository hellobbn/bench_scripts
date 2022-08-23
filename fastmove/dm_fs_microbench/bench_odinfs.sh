#!/bin/bash

set -e

# == Functions ==
blk=""

# NUMA configuration
cpuinfo=$(lscpu)

# FIXME: We assume a 4-NUMA system, instead of getting data from lscpu
numa_num=4

numa_end=$(($numa_num - 1))
declare -A numa_cpu=()
for i in $(seq 0 $numa_end); do
	  numa_cpu[$i]=$(echo "$cpuinfo" | grep -i node$i | rev | cut -d ' ' -f 1 | rev)
done

# PMEM configuration saver
declare -A namespace_at_node=()
declare -A blkdev_at_node=()

pm_pattern_L_init() {
  parradm create /dev/pmem0
}

pm_pattern_L_exit() {
  parradm delete /dev/pmem0
}

pm_pattern_LR_init() {
  parradm create /dev/pmem0 /dev/pmem1
}

pm_pattern_LR_exit() {
  parradm delete /dev/pmem0 /dev/pmem1
}

# Benchmark file system
setting_pm_pattern=("L" "LR")
setting_fs=("odinfs")
setting_pattern=("write" "read")
setting_size=("4k" "16k" "64k" "2m" "4m")
setting_engine=("sync")
setting_thread=("1" "2" "4" "8")

modprobe odinfs

TestFile=./test-out-$(date +"%Y-%m-%d-%H-%M-%S")
echo "Filename: $TestFile"

HeaderLine="========================================"
TailLine="========================================"

for fs in ${setting_fs[@]}; do
  echo "==> Testing $fs"

  for stripe in ${setting_pm_pattern[@]}; do
    for pattern in ${setting_pattern[@]}; do
      for size in ${setting_size[@]}; do
        for engine in ${setting_engine[@]}; do
          for thread in ${setting_thread[@]}; do
            echo $HeaderLine >> $TestFile
            echo "  ==> Setting: ${fs}_${stripe}_${pattern}_${size}_${engine}_${thread}" >> $TestFile

            pm_pattern_${stripe}_init

            sudo mount -t odinfs -o init,dele_thrds=12 /dev/pmem_ar0 /mnt/pmem

            numactl -m 0 -N 0 fio --name=benchmark \
                --rw=$pattern \
                --numjobs=$thread \
                --ioengine=$engine \
                --bs=$size \
                --runtime=10 \
                --cpus_allowed=${numa_cpu[0]} \
                --cpus_allowed_policy=split \
                --time_based \
                --direct=1 \
                --group_reporting \
                --directory=/mnt/pmem \
                --size=1G >> $TestFile

            sudo umount /mnt/pmem

            pm_pattern_${stripe}_exit
            echo $HeaderLine >> $TestFile
          done
        done
      done
    done
  done
done


