#!/bin/bash

set -e
# set -x

# Import trace related functions
source fn/fn_trace

# Import numa related functions
source fn/fn_numa

# Import benchmark related functions
source fn/fn_bench

# Import fs related functions
source fn/fn_fs

# Import other misc functions
source fn/fn_misc

# Main benchmark function
# We assume that everything is done before the benchmark begin
# Everything before the benchmark should be done before this function is called
#
# Related hooks
#  - setup_bench socket_num
#  - stop_bench socket_num
#
# Argument list:
#  - $1 for benchmark file name
#  - $2 for configuration: 0 for single socket, 1 for dual socket
function bench_main {
    setup_bench $2

    trace-query $1 &

    # pcm-memory 1 | tee  $1.pcm-log
    /home/chenlf/monitor_msr >$1.msr.log &

    $numactl_cmd /root/tpcc-mysql/tpcc_start -h 127.0.0.1 -P 3306 -d tpcc5000 -u root -p "" -w 5000 -c 14 -r 120 -l 600 -i 10 | tee $1

    # kill_if_exist pcm-memory
    killall monitor_msr

    stop-trace

    stop_bench $2
}

# Prepare a benchmark
# This function is called BEFORE every benchmark_main so as to prepare the benchmark
#  environment
# Argument list:
#  - $1 = 0 for single socket, 1 for striped target, the stripe is always /dev/pmem0 + /dev/pmem1
#  - $2 = 0 for CPU, 1 for DMA
#  - $3: Argument for mysql, innodb_page_cleaners
#  - $4: Filesystem to use
#  - $5: accel: local-write: Local write threshold
#  - $6: accel: local-read: Local read threshold
#  - $7: accel: chunks: Number of chunks to split (if is to split)
#  - $8: accel: watermark: Decide whether to split based on inflight and this
#  - $9: accel: main-switch: Routine to be used on master thread: 0 for DMA, 1 for CPU
#  - $10: accel: worker-switch: Routine to be used on worker thread, 0 for DMA, 1 for CPU
function prepare_benchmark {
    # Prepare a stripe target (or non-stripe target)
    echo "==> Check target"
    if [ $1 -eq 1 ]; then
        dev_target="/dev/mapper/stripe_dev"
        perl /home/chenlf/create_dm.pl /dev/pmem0 /dev/pmem1
    else
        dev_target="/dev/pmem0"
    fi
    echo "<== Target is $dev_target"

    # Prepare Hybrid Engine
    echo "==> Setting HE"
    sysctl accel.fastmove=0
    if [ $2 -eq 0 ]; then
        echo "<== Setting for CPU"
        sysctl accel.mode=0
        sysctl accel.watermark=0
        sysctl accel.ddio=1
        /root/tpcc-mysql/enable-ddio
    else
        echo "<== Setting for DMA"
        sysctl accel.mode=1
        sysctl accel.watermark=$8
        sysctl accel.ddio=0
        sysctl accel.sync-wait=1
        sysctl accel.local-read=$6
        sysctl accel.local-write=$5
        sysctl accel.remote-read=16384
        sysctl accel.remote-write=16384
        sysctl accel.main-switch=$9
        sysctl accel.worker-switch=${10}
        /root/tpcc-mysql/disable-ddio

        ## Customization section
        sysctl accel.chunks=$7
    fi
    if [ $1 -eq 0 ]; then
        echo "<== Setting for non-stripe target"
        sysctl accel.num-nodes=1
        disable_numa 1
    else
        echo "<== Setting for striped target"
        sysctl accel.num-nodes=2
    fi
    sysctl accel.fastmove=1

    # Mount Filesystem, umount before mount
    echo "==> Mount"
    mountret=$(mount | grep -i pmem | wc -l)
    if [ $mountret -ne 0 ]; then
        umount /mnt/pmem
    fi

    if [ $4 == "nova" ]; then
        format_nova $1 $dev_target "/mnt/pmem"
        mount_nova $1 $dev_target "/mnt/pmem"
    elif [ $4 == "ext4" ]; then
        format_ext4 $1 $dev_target "/mnt/pmem"
        mount_ext4 $1 $dev_target "/mnt/pmem"
    elif [ $4 == "xfs" ]; then
        format_xfs $1 $dev_target "/mnt/pmem"
        mount_xfs $1 $dev_target "/mnt/pmem"
    elif [ $4 == "odinfs" ]; then
        format_odinfs $1 $dev_target "/mnt/pmem"
        mount_odinfs $1 $dev_target "/mnt/pmem"
    else
        echo "ERROR: Not a valid filesystem $4"
        exit 1
    fi

    # Copy database
    echo "==> Copy MySQL Database"
    cp -rap /mnt/nvme/tpcc-p16-5000 /mnt/pmem/mysql
    sync
    chown -R mysql:mysql /mnt/pmem/mysql

    # Change MySQL Configuration
    echo "==> monitor-malloc-default-$3"
    printf "#\n# This group are read by MySQL server.\n# Use it for options that only the server (but not clients) should see\n#\n# For advice on how to change settings please see\n# http://dev.mysql.com/doc/refman/en/server-configuration-defaults.html\n#\n# Settings user and group are ignored when systemd is used.\n# If you need to run mysqld under a different user or group,\n# customize your systemd unit file for mysqld according to the\n# instructions in http://fedoraproject.org/wiki/Systemd\n" >/etc/my.cnf
    printf "[mysqld]\ndatadir=/mnt/pmem/mysql\nsocket=/mnt/pmem/mysql/mysql.sock\nlog-error=/var/log/mysql/mysqld.log\npid-file=/run/mysqld/mysqld.pid\n\ndefault_storage_engine=InnoDB\n" >>/etc/my.cnf
    printf "innodb_io_capacity=1000000\n" >>/etc/my.cnf
    printf "# innodb_page_cleaners=$3\n" >>/etc/my.cnf
    printf "innodb_buffer_pool_size=60G\n# innodb_page_size=65536\n# innodb_flush_method=O_DIRECT\n# innodb_flush_sync=1\n# innodb_adaptive_flushing=1\n# innodb_flush_neighbors=0\n# innodb_max_dirty_pages_pct=90\n# innodb_max_dirty_pages_pct_lwm=10\nlower_case_table_names=1\n# large_pages=ON\n\n# [mysqld_safe]\n# malloc-lib=/usr/lib64/libjemalloc.so\n" >>/etc/my.cnf
}

function end_benchmark {
    # Umount PMEM
    sleep 5
    umount /mnt/pmem

    # Destroy stripped target if exists
    if [ -e "/dev/mapper/stripe_dev" ]; then
        dmsetup remove /dev/mapper/stripe_dev
    fi

    if [ $1 == "odinfs" ]; then
        if [ $2 -eq 0 ]; then
            parradm delete /dev/pmem0
        else
            parradm delete /dev/pmem0 /dev/pmem1
        fi
    fi

    enable_numa 1
    # enable_numa 0
}

# Initialize the benchmark
# This function is called BEFORE the whole benchmark starts
function init_all {
    # Disable SMT
    echo "off" | sudo tee /sys/devices/system/cpu/smt/control

    # Enable only 2 NUMA nodes
    disable_numa 2
    disable_numa 3
    enable_numa 0
    enable_numa 1

    # Disable DDIO
    /root/tpcc-mysql/disable-ddio

    if [ -e "/dev/mapper/stripe_dev" ]; then
        dmsetup remove /dev/mapper/stripe_dev
    fi

    mkdir -p /run/mysqld
    chown -R mysql:mysql /run/mysqld
}

date_prefix=$(date --iso-8601=seconds)
dir_name="result_$date_prefix"
mkdir -p $dir_name

init_all

setting_fs="xfs ext4"
setting_skt_setup="SS"
setting_method_setup="CPU"
setting_write_thresh="16384"
setting_read_thresh="65536"
setting_watermark="128"
setting_chunk="1"
setting_main_wr="0"
setting_worker_wr="1"

for chunks in $setting_chunk; do
    for watermark in $setting_watermark; do
        for lwrite_thrsh in $setting_write_thresh; do
            for lread_thrsh in $setting_read_thresh; do
                for fs in $setting_fs; do
                    for ssetup in $setting_skt_setup; do
                        for msetup in $setting_method_setup; do
                            for main_wr in $setting_main_wr; do
                                for worker_wr in $setting_worker_wr; do
                                    for i in 16; do
                                        if [[ $ssetup == "DS" ]]; then
                                            s_cmd=1
                                        else
                                            s_cmd=0
                                        fi

                                        if [[ $msetup == "CPU" ]]; then
                                            m_cmd=0
                                        else
                                            m_cmd=1
                                        fi

                                        echo "==> Benchmark begin for $ssetup-$msetup-$i-$fs-$lwrite_thrsh-$lread_thrsh-$chunks-$watermark"
                                        prepare_benchmark $s_cmd $m_cmd $i $fs $lwrite_thrsh $lread_thrsh $chunks $watermark $main_wr $worker_wr
                                        bench_main "$dir_name/$ssetup-$msetup-$i-$fs-$lwrite_thrsh-$lread_thrsh-$chunks-$watermark-$main_wr-$worker_wr" $s_cmd
                                        end_benchmark $fs $s_cmd
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
    done
done

echo $date_prefix
