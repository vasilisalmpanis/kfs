#!/bin/sh
set -ex

DISK=${1:-${DISK:-kfs.img}}
KERNEL=${KERNEL:-zig-out/bin/kfs.bin}
ROOT_IMG=${ROOT_IMG:-rootfs.img}
GRUB_CFG=${GRUB_CFG:-boot/grub/grub.cfg}
GRUB_THEME=${GRUB_THEME:-boot/grub/theme}

BOOT_TREE=$(dirname "$(dirname "$GRUB_CFG")")

KERNEL_SIZE_K=`du -s "$KERNEL" | awk '{print $1}'`
BOOT_DIR_SIZE_K=`du -s "$BOOT_TREE" | awk '{print $1}'`
ROOT_SIZE_K=`du -s "$ROOT_IMG" | awk '{print $1}'`
ROOT_SIZE_MB=$(( $ROOT_SIZE_K / 1024 ))

CORE_SIZE_MB=1
BOOT_SIZE_MB=$(( ($KERNEL_SIZE_K + $BOOT_DIR_SIZE_K) / 1024 + 2 ))
DISK_SIZE_MB=$(( $BOOT_SIZE_MB + $CORE_SIZE_MB + $ROOT_SIZE_MB + 16 ))

BS=512

CORE_START=2048
BOOT_START=$(( CORE_SIZE_MB * 1024 * 1024 / BS + CORE_START ))
ROOT_START=$(( BOOT_SIZE_MB * 1024 * 1024 / BS + BOOT_START ))

if command -v i686-elf-grub-mkimage >/dev/null 2>&1; then
    GRUB_MKIMAGE=i686-elf-grub-mkimage
    GRUB_PREFIX=$(brew --prefix i686-elf-grub)/lib/i686-elf/grub/i386-pc
elif command -v grub2-mkimage >/dev/null 2>&1; then
    GRUB_MKIMAGE=grub2-mkimage
    GRUB_PREFIX=/usr/lib/grub/i386-pc
else
    GRUB_MKIMAGE=grub-mkimage
    GRUB_PREFIX=/usr/lib/grub/i386-pc
fi

rm -f "$DISK"
truncate -s $DISK_SIZE_MB"M" "$DISK"
sgdisk -o "$DISK"
sgdisk -n 1:$CORE_START:$(( BOOT_START - 1 )) -t 1:ef02 -c 1:bios_boot "$DISK"
sgdisk -n 2:$BOOT_START:$(( ROOT_START - 1 )) -t 2:8300 -c 2:boot "$DISK"
sgdisk -n 3:$ROOT_START:                      -t 3:8300 -c 3:root "$DISK"

BOOT_TMP_DIR=$(mktemp -d)
mkdir -p                "$BOOT_TMP_DIR/grub"
cp "$KERNEL"            "$BOOT_TMP_DIR/kfs.bin"
cp "$GRUB_CFG"          "$BOOT_TMP_DIR/grub/grub.cfg"
cp -rf "$GRUB_THEME"    "$BOOT_TMP_DIR/grub/"

BOOT_IMG=$(mktemp)
mke2fs -L '' -N 0 -O ^64bit -d "$BOOT_TMP_DIR" -m 5 -r 1 -t ext2 "$BOOT_IMG" $BOOT_SIZE_MB"M"

dd if="$BOOT_IMG" of="$DISK" bs=$BS seek=$BOOT_START conv=notrunc
dd if="$ROOT_IMG" of="$DISK" bs=$BS seek=$ROOT_START conv=notrunc

$GRUB_MKIMAGE -O i386-pc -o core.img \
    -p '(hd0,gpt2)/grub' \
    biosdisk part_gpt ext2 multiboot2 normal boot configfile gfxterm gfxmenu font

CORE_SIZE=$(stat -f%z core.img 2>/dev/null || stat -c%s core.img)
CORE_SECTORS=$(( (CORE_SIZE + 511) / BS ))
REMAINING=$(( CORE_SECTORS - 1 ))
REST_START=$(( CORE_START + 1 ))

python3 -c "
import struct
start = $REST_START
count = $REMAINING
segment = 0x0820
entry = struct.pack('<QHH', start, count, segment)
with open('core.img', 'r+b') as f:
    f.seek(0x1F4)
    f.write(entry)
"

dd if=core.img                  of="$DISK" bs=$BS seek=$CORE_START conv=notrunc
dd if="$GRUB_PREFIX/boot.img"   of="$DISK" bs=440 count=1 conv=notrunc

python3 -c "
import struct
with open('$DISK', 'r+b') as f:
    f.seek(0x5C)
    f.write(struct.pack('<Q', $CORE_START))
"

rm -rf "$BOOT_TMP_DIR" "$BOOT_IMG" core.img
