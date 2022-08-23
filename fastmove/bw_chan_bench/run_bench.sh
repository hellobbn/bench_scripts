#!/bin/bash
set -x
set -e

# CPU/PMEM either on socket 0 or 1, but always use dma device in socket 0
setting_cpu="0 1"
setting_pmem="0 1"
setting_chunk="1 2 4"
setting_thread=$(seq 1 8)
setting_blk="64k 256k"

# Set common parameters, never change
# Never split chunk, and set concurrency to 8, only use dma on socket 0
# sysctl accel.chunks=1
sysctl accel.concurrency=999999999999
sysctl accel.num-nodes=1

numa0_cpu="0,4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,64,68,72,76"
numa1_cpu="1,5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,69,73,77"

# Mount pmem
for cpu_socket in $setting_cpu; do
  for pmem_socket in $setting_pmem; do
    for thread in $setting_thread; do
      for blk_size in $setting_blk; do
        for ck_size in $setting_chunk; do
          sysctl accel.chunks=${ck_size}
          sysctl accel.fastmove=1
          mount -t NOVA -o init /dev/pmem${pmem_socket} /mnt/pmem

          if [[ ${cpu_socket} == "0" ]]; then
            numa_cpu=$numa0_cpu
          else
            numa_cpu=$numa1_cpu
          fi

          numactl -N ${cpu_socket} -m ${cpu_socket} fio \
              --name=benchmark \
              --rw=write \
              --numjobs=${thread} \
              --ioengine=sync \
              --bs=${blk_size} \
              --cpus_allowed=${numa_cpu} \
              --group_reporting \
              --runtime=10 \
              --cpus_allowed_policy=split \
              --time_based \
              --direct=1 \
              --directory=/mnt/pmem \
	      --size=10G | tee result_cpu${cpu_socket}_pmem${pmem_socket}_t${thread}_b${blk_size}_c${ck_size}

          sudo umount /mnt/pmem
          sysctl accel.fastmove=0
        done
      done
    done
  done
done

