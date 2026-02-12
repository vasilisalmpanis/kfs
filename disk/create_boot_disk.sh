#!/bin/sh
set -ex

DISK=${1:-kfs.img}
KERNEL=zig-out/bin/kfs.bin
EXT2=ext2.img
GRUB_CFG=iso/boot/grub/grub.cfg

DISK_SIZE_MB=80 # total disk size in MB (must be large enough to hold all partitions)
BOOT_SIZE_MB=8  # size of boot partition (must be large enough to hold kernel + GRUB files)
CORE_SIZE_MB=1  # size of core.img (BIOS Boot partition, must be at least 1MB for GRUB)

BS=512 # sector size in bytes

CORE_START=2048   # sector where core.img is written (BIOS Boot partition)
BOOT_START=$(( CORE_SIZE_MB * 1024 * 1024 / BS + CORE_START )) # sector where boot partition image is written
ROOT_START=$(( BOOT_SIZE_MB * 1024 * 1024 / BS + BOOT_START )) # sector where root partition image is written

# Detect grub tools
if command -v i686-elf-grub-mkimage >/dev/null 2>&1; then
    GRUB_MKIMAGE=i686-elf-grub-mkimage
    GRUB_PREFIX=$(brew --prefix i686-elf-grub)/lib/i686-elf/grub/i386-pc
else
    GRUB_MKIMAGE=grub-mkimage
    GRUB_PREFIX=/usr/lib/grub/i386-pc
fi

# Create empty disk
truncate -s $DISK_SIZE_MB"M" $DISK

# Create GPT: BIOS Boot (1MB) + boot + root (rest)
sgdisk -o $DISK
sgdisk -n 1:$CORE_START:$(( BOOT_START - 1 )) -t 1:ef02 -c 1:bios_boot $DISK
sgdisk -n 2:$BOOT_START:$(( ROOT_START - 1 )) -t 2:8300 -c 2:boot      $DISK
sgdisk -n 3:$ROOT_START:                      -t 3:8300 -c 3:root      $DISK

# Build /boot partition image
BOOT_DIR=$(mktemp -d)
mkdir -p        "$BOOT_DIR/boot/grub"
cp "$KERNEL"    "$BOOT_DIR/boot/kfs.bin"
cp "$GRUB_CFG"  "$BOOT_DIR/boot/grub/grub.cfg"

BOOT_IMG=$(mktemp)
mke2fs -L '' -N 0 -O ^64bit -d $BOOT_DIR -m 5 -r 1 -t ext2 $BOOT_IMG $BOOT_SIZE_MB"M"

# Write partition images at correct sector offsets
dd if=$BOOT_IMG of=$DISK bs=$BS seek=$BOOT_START conv=notrunc
dd if=$EXT2     of=$DISK bs=$BS seek=$ROOT_START conv=notrunc

# Build core.img with embedded prefix
$GRUB_MKIMAGE -O i386-pc -o core.img \
    -p '(hd0,gpt2)/boot/grub' \
    biosdisk part_gpt ext2 multiboot2 normal boot configfile

# Patch core.img's diskboot block list before writing to disk.
# diskboot.img (first 512 bytes of core.img) has a block list at offset 0x1F4
# that tells it which sectors to read for the rest of core.img.
# Format: start_sector(u64 LE) + num_sectors(u16 LE) + load_segment(u16 LE)
CORE_SIZE=$(stat -f%z core.img 2>/dev/null || stat -c%s core.img)
CORE_SECTORS=$(( (CORE_SIZE + 511) / BS ))
REMAINING=$(( CORE_SECTORS - 1 ))
REST_START=$(( CORE_START + 1 ))

python3 -c "
import struct
start = $REST_START
count = $REMAINING
segment = 0x0820  # GRUB_BOOT_MACHINE_KERNEL_SEG
entry = struct.pack('<QHH', start, count, segment)
with open('core.img', 'r+b') as f:
    f.seek(0x1F4)
    f.write(entry)
"

# Write core.img to BIOS Boot partition
dd if=core.img of=$DISK bs=$BS seek=$CORE_START conv=notrunc

# Write boot.img to MBR (first 440 bytes, preserving GPT partition table)
dd if="$GRUB_PREFIX/boot.img" of=$DISK bs=440 count=1 conv=notrunc

# Patch boot.img: write core.img's start sector at offset 0x5C (u64 LE)
python3 -c "
import struct
with open('$DISK', 'r+b') as f:
    f.seek(0x5C)
    f.write(struct.pack('<Q', $CORE_START))
"

# Cleanup
rm -rf $BOOT_DIR $BOOT_IMG core.img
