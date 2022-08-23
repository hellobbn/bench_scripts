#!/bin/bash

# First argument should be the microbench directory
# Second argument should be the configuration:
#   mt dma thp fm etc...
function print_help {
    echo $0 "microbench_dir configuration"
}

function debug_print {
    if [[ ! -z $DEBUG ]]; then
        echo "$@"
    fi
}

function get_and_generate_data {
    if [[ ! -f $1 ]]; then
        echo "WARN: file $1 does not exist!"
        return
    fi

    cycle_desc=""
    cycle_line=""
    bd_desc=""
    bd_line=""
    curr_line=0
    epoch=0

    rand_filename=$(echo $RANDOM | md5sum | head -c 5; echo;)
    tmp_file_name="$rand_filename.tmp"
    if [[ $config == "fm" ]]; then
        echo "$config$suffix-$mt-$ck-$cc-$pl" >> $tmp_file_name
    else
        echo "$config$suffix-$mt-$pl" >> $tmp_file_name
    fi

    while read line; do
        debug_print "==> $line"

        if [[ $line == *"Total_cycles"* ]]; then
            cycle_desc=$line
            curr_line=0


        elif [[ $curr_line -eq 0 ]]; then
            cycle_line=$line
            curr_line=-1


        elif [[ $line == *"syscall_timestamp"* ]]; then
            bd_desc=$line
            curr_line=1


        elif [[ $curr_line -eq 1 ]]; then
            bd_line=$line
            curr_line=-1

            debug_print "EPOCH: $epoch"
            debug_print "cycle_desc: $cycle_desc"
            debug_print "cycle_line: $cycle_line"
            debug_print "bd_desc: $bd_desc"
            debug_print "bd_line: $bd_line"
            epoch=$(($epoch+1))

            
            echo $epoch >> $tmp_file_name
            echo $cycle_desc >> $tmp_file_name
            echo $cycle_line >> $tmp_file_name
            echo $bd_desc >> $tmp_file_name
            echo $bd_line >> $tmp_file_name
        fi
    done < $1

    python3 microbench_process.py $tmp_file_name "${config}${suffix}"_cycle.$(date -d "today" +"%Y%m%d%H%M").dat "${config}${suffix}"_bd.$(date -d "today" +"%Y%m%d%H%M").dat
    rm $tmp_file_name
}

if [ $# -lt 2 ]; then
    print_help
    exit 1
fi

if [[ ! -d $1 ]]; then
    echo "$1 is not a directory!"
    print_help
    exit 1
fi

if [[ ! -d $1/stats_$2 ]]; then
    echo "Cannot find the stats for configuration $2"
    print_help
    exit 1
fi

# This file should define 2 things:
#  - PAGE_LIST
#  - MULTI (is not used for dma/fastmove), however, analyse anyway

# The filename will be: $2_${MT}_2mb_page_order_${N}
# FIXME: In non-2mb pages
if [[ ! -z $3 ]]; then
	echo "==> Non THP impl"
	suffix="_nonthp"
fi
source $1/test_param$suffix

dirname="$1/stats_$2${suffix}"
echo "==> Processing $dirname"

if [[ $2 == "thp" ]]; then
    config="mt"
elif [[ $2 == "fm" ]]; then
    config="fm"
    for pl in $PAGE_LIST; do
        for ck in $chunk_split; do
            for cc in $concurrency; do
                filename="$dirname/${config}_${mt}_${ck}_${cc}_2mb_page_order_${pl}"
                echo "==> Processing $filename"
                get_and_generate_data $filename
            done
        done
    done

    exit 0
elif [[ $2 == "dma" ]]; then
    config="dma"
    for pl in $PAGE_LIST; do
        filename="$dirname/${config}_${mt}_2mb_page_order_${pl}"
	get_and_generate_data $filename
    done

    exit 0
else
	config=$2
fi



for mt in $MULTI; do
    for pl in $PAGE_LIST; do
        filename="$dirname/${config}_${mt}_2mb_page_order_${pl}"
        debug_print "==> Processing $filename"

        get_and_generate_data $filename
    done
done
