#!/bin/bash

set -e

crash_file=$(sudo find  /var/crash -type f -printf "%T@ %p\n" | sort -k 1 -t ' ' | tail -1 | cut -d ' ' --fields=2)
cmd="sudo crash ./linux-nova/vmlinux $crash_file"

echo '>>> Crash file: ' $crash_file
echo '>>> CMD: ' $cmd

sleep 2

$cmd

