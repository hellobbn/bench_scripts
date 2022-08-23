#!/bin/bash

# script run in 2020.4.19 12:29

numa0=0,1,2,3,4,5,6,7,8,9,10,11

for pattern in "randwrite"
do
    for size in "1k" "4k" "8k" "12k" "16k" "20k" "24k" "28k" "32k" "36k" "40k" "44k" "48k" "52k" "56k" "60k" "64k" "68k" "72k" "76k" "80k" "84k" "88k" "92k" "96k" "100k" "104k" "108k" "112k" "116k" "120k" "124k" "128k"
    do
        for engine in "sync"
        do
            for thread in "8"
            do
		# perl ./create_dm.pl
		# ./mount_nova.sh

                progress_bar=''
                for i in {0..100}
                do
                    printf "loading:[%-100s]%d%%\r" $progress_bar $i
                    sleep 0.05
                    progress_bar=#${progress_bar}
	       	done
                echo ""

                echo "benchmarking:" "$pattern"-"$size"-"$thread"-"$engine"
                fio --name=benchmark \
                    --rw=$pattern \
                    --numjobs=$thread \
                    --ioengine=$engine \
                    --bs=$size \
                    --runtime=10 \
                    --cpus_allowed=$numa0 \
                    --cpus_allowed_policy=split \
                    --time_based \
                    --direct=1 \
                    --group_reporting \
                    --directory=/mnt/nova \
                    --size=100M

                echo ""
                progress_bar=''
                for i in {0..100}
                do
                    printf "logging:[%-100s]%d%%\r" $progress_bar $i
                    sleep 0.05
                    progress_bar=#${progress_bar}
	       	done
                echo ""

                # umount /mnt/nova

                # progress_bar=''
                # for i in {0..100}
                # do
                #     printf "dumping:[%-100s]%d%%\r" $progress_bar $i
                #     sleep 0.05
                #     progress_bar=#${progress_bar}
	       	# done
                # echo ""

            done
        done
    done
done
