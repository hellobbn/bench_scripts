#!/bin/bash

set -e

dmesg=$(sudo find . -type f -name 'dmesg-*' -printf "%T@ %p\n" | sort -k 1 -t ' ' | tail -1 | cut -d ' ' --fields=2)
cmd="less $dmesg"

echo '>>> Dmesg file: ' $dmesg
echo '>>> CMD: ' $cmd

sleep 2

$cmd

