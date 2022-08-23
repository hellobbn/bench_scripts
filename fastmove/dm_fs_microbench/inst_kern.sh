#!/bin/bash

set -e

print_help() {
    echo "Usage: $0 LINUX_SRC"
}

if [ $# -ne 1 ]; then
    print_help
    exit 1
fi

if [ ! -d $1 ]; then
    echo "Directory does not exist!"
    print_help
    exit 1
fi

pushd $1

# Commit Temp message
# echo "==> Commit changed things"
# git add -u .
# git commit --amend --no-edit

echo "==> Compile kernel"
make -j12

sudo make modules_install
sudo cp -v arch/x86/boot/bzImage /boot/vmlinuz-linuxnova
sudo cp -v System.map /boot/System.map-linuxnova
sudo mkinitcpio -p linuxnova
sudo grub-mkconfig -o /boot/grub/grub.cfg

popd

