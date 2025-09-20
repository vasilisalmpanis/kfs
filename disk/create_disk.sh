#!/bin/sh
truncate -s 50M disk.img
mke2fs -L '' -N 0 -O ^64bit -d part1 -m 5 -r 1 -t ext2 -b 1024 part1.img 20M
mke2fs -L '' -N 0 -O ^64bit -d part2 -m 5 -r 1 -t ext2 -b 1024 part2.img 20M
sgdisk disk.img
sgdisk -p disk.img
sgdisk -n 1:2048:+20MB -t 1:8300 -c 1:partition1 disk.img
sgdisk -n 2:43008:+20MB -t 2:8300 -c 2:partition2 disk.img
sgdisk -p disk.img
dd if=part1.img of=disk.img bs=1 seek=1048576 conv=notrunc status=progress
dd if=part2.img of=disk.img bs=1 seek=22020096 conv=notrunc status=progress
