#!/bin/bash

# ./mount_nova.sh

print_help() {
  echo Usage: $0 DD_DIR
}

if [ $# -ne 1 ]; then
  print_help
  exit 1
fi

while true; do
  sudo dd if=/dev/zero of=$1/test bs=1M count=600
  sudo bash -c 'echo ---------------------------- DD DONE --------------------------- >> /dev/kmsg'
  sync
done
