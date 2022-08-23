#!/bin/bash

sudo modprobe nova_dm
sudo perl create_dm.pl /dev/pmem0 /dev/pmem1
sudo mount -t NOVA_DM -o init /dev/mapper/stripe_dev /mnt/nova
