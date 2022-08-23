#!/bin/bash

set -e
set -x

# == Functions ==
blk=""

# NUMA configuration
cpuinfo=$(lscpu)

# FIXME: We assume a 4-NUMA system, instead of getting data from lscpu
numa_num=4

# PMEM configuration saver
declare -A namespace_at_node=()
declare -A blkdev_at_node=()

# DO NOT MODIFY: The loop end
numa_end=$(($numa_num - 1))

declare -A numa_cpu=()
for i in $(seq 0 $numa_end); do
  numa_cpu[$i]=$(echo "$cpuinfo" | grep -i node$i | rev | cut -d ' ' -f 1 | rev)
done

pm_get_info() {
  for i in $(seq 0 $numa_end); do
    namespace_at_node[$i]=$(ndctl list --numa-node $i | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
    blkdev_at_node[$i]=$(ndctl list --numa-node $i | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  done
  if [[ ! -z "$DEBUG" ]]; then
    echo "============ DEBUG ============"
    for i in $(seq 0 $numa_end); do
      echo "namespace at node $i: " ${namespace_at_node[$i]} " --> " ${blkdev_at_node[$i]}
    done
    echo
  fi
}

pm_pattern_L_init() {
  # We assume the process is run on NUMA 0
  setup="L"
  pm_get_info
  blk="/dev/${blkdev_at_node[0]}"
  echo $blk
}

pm_pattern_L_exit() {
  # Dummy
  pm_get_info
  setup=""
}

pm_pattern_LL_init() {
  setup="LL"
  pm_get_info

  if [ $(echo "${namespace_at_node[0]}" | wc -l) -ne 1 ]; then
    pm_pattern_LL_exit
    pm_get_info
  fi

  sudo ndctl disable-namespace ${namespace_at_node[0]}
  sudo ndctl destroy-namespace ${namespace_at_node[0]}

  sudo ndctl create-namespace -m fsdax -s 300G
  sudo ndctl create-namespace -m fsdax -s 300G

  pm_get_info

  if [ $(echo "${blkdev_at_node[0]}" | wc -l) -ne 1 ]; then
    echo "We expected two blkdev in $setup setup, got " ${blkdev_at_node[0]}
    pm_pattern_${setup}_exit
    exit 1
  fi

  blk0=$(echo "${blkdev_at_node[0]}" | sed -n '1p')
  blk1=$(echo "${blkdev_at_node[0]}" | sed -n '2p')

  # Create a stripe device
  sudo ./create_dm.pl /dev/$blk0 /dev/$blk1
  blk="/dev/mapper/stripe_dev"
}

pm_pattern_LL_exit() {
  pm_get_info

  if test -L /dev/mapper/stripe_dev ; then
    sudo dmsetup remove /dev/mapper/stripe_dev
  fi

  for i in ${namespace_at_node[0]}; do
    sudo ndctl disable-namespace $i
    sudo ndctl destroy-namespace $i
  done

  sudo ndctl create-namespace
}

pm_pattern_LR_init() {
  namespace_at_node0=$(ndctl list --numa-node 0 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blkdev_at_node0=$(ndctl list --numa-node 0 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  namespace_at_node1=$(ndctl list --numa-node 1 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blkdev_at_node1=$(ndctl list --numa-node 1 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')

  blk0=$blkdev_at_node0
  blk1=$blkdev_at_node1

  sudo ./create_dm.pl /dev/$blk0 /dev/$blk1
  blk="/dev/mapper/stripe_dev"
}

pm_pattern_LR_exit() {
  sudo dmsetup remove /dev/mapper/stripe_dev
}

pm_pattern_RR_init() {
  namespace_at_node1=$(ndctl list --numa-node 1 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blkdev_at_node1=$(ndctl list --numa-node 1 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')

  if [ $(echo "$namespace_at_node0" | wc -l) -ne 1 ]; then
    pm_pattern_RR_exit
    namespace_at_node1=$(ndctl list --numa-node 1 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
    blkdev_at_node1=$(ndctl list --numa-node 1 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  fi

  sudo ndctl disable-namespace $namespace_at_node1
  sudo ndctl destroy-namespace $namespace_at_node1

  sudo ndctl create-namespace -m fsdax -s 201G
  sudo ndctl create-namespace -m fsdax -s 201G

  namespace_at_node1=$(ndctl list --numa-node 1 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blkdev_at_node1=$(ndctl list --numa-node 1 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')

  blk0=$(echo "$blkdev_at_node1" | sed -n '1p')
  blk1=$(echo "$blkdev_at_node1" | sed -n '2p')

  # Create a stripe device
  sudo ./create_dm.pl /dev/$blk0 /dev/$blk1
  blk="/dev/mapper/stripe_dev"
}

pm_pattern_RR_exit() {
  namespace_at_node1=$(ndctl list --numa-node 1 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blkdev_at_node1=$(ndctl list --numa-node 1 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')

  if test -L /dev/mapper/stripe_dev ; then
    sudo dmsetup remove /dev/mapper/stripe_dev
  fi

  for i in $namespace_at_node1; do
    sudo ndctl disable-namespace $i
    sudo ndctl destroy-namespace $i
  done

  sudo ndctl create-namespace
}

pm_pattern_R_init() {
  # We assume the process is run on NUMA 0
  namespace_at_node1=$(ndctl list --numa-node 1 | grep -i "\"dev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blkdev_at_node1=$(ndctl list --numa-node 1 | grep -i "\"blockdev\":" | rev | cut -d ':' -f 1 | rev | sed -r 's/[\",]//g')
  blk="/dev/${blkdev_at_node1}"
}

pm_pattern_R_exit() {
  echo
}

# == Main shell ==

pm_get_info
pm_pattern_LL_init
pm_pattern_LL_exit
exit 0

# Benchmark file system
setting_pm_pattern=("L" "LL" "LR" "RR" "R")
setting_fs=("ext4")
setting_pattern=("write")
setting_size=("4k" "2m" "4m")
setting_engine=("sync")
setting_thread=("1" "2" "4" "8" "16")


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
            if [[ $fs == "xfs" ]]; then
              mkfsflag="-f -m reflink=0"
            else
              mkfsflag="-F"
            fi
            echo $HeaderLine >> $TestFile
            echo "  ==> Setting: ${fs}_${stripe}_${pattern}_${size}_${engine}_${thread}" >> $TestFile

            pm_pattern_${stripe}_init

            # Test code here, the device is in $blk
            echo "Block is $blk"

            if [[ "$blk" == *"pmem"* ]] || [[ "$blk" == "/dev/mapper/stripe_dev" ]]; then
              echo "continue.."
            else
              echo "Safety err: $blk"
              pm_pattern_${stripe}_exit
              exit 1
            fi

            sudo mkfs.$fs $mkfsflag $blk
            sudo mount $mountflag -o dax $blk /mnt/pmem

            fio --name=benchmark \
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


