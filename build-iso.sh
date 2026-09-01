#!/bin/bash
set -e

BUILD_DIR="$HOME/scara-iso-build"
ISO_NAME="$HOME/linuxscara.iso"
ROOTFS_DIR="$HOME/gnu-rootfs"
KERNEL_IMG="$HOME/linux-7.2/arch/x86/boot/bzImage"

echo "==> Mempersiapkan struktur ISO..."
mkdir -p "$BUILD_DIR"/live "$BUILD_DIR"/boot/grub ~/live-initramfs/{bin,dev,proc,sys,mnt,sysroot,tmp}

echo "==> Mengompresi RootFS menjadi SquashFS..."
sudo mksquashfs "$ROOTFS_DIR" "$BUILD_DIR"/live/filesystem.squashfs -comp zstd -b 1M -noappend

echo "==> Menyalin Kernel..."
cp "$KERNEL_IMG" "$BUILD_DIR"/boot/vmlinuz

echo "==> Menyiapkan Initrd Live..."
if [ ! -f ~/live-initramfs/bin/busybox ]; then
    curl -Lo ~/live-initramfs/bin/busybox https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
    chmod +x ~/live-initramfs/bin/busybox
    ~/live-initramfs/bin/busybox --install -s ~/live-initramfs/bin
fi

cat << 'INIT_EOF' > ~/live-initramfs/init
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /mnt/iso /mnt/squash

FOUND=""
for dev in /dev/sr* /dev/sd* /dev/vd*; do
    if [ -b "$dev" ]; then
        if mount -r "$dev" /mnt/iso 2>/dev/null; then
            if [ -f /mnt/iso/live/filesystem.squashfs ]; then
                echo "==> Booting Linux Scara Live Media dari $dev..."
                FOUND="$dev"
                break
            fi
            umount /mnt/iso 2>/dev/null
        fi
    fi
done

if [ -z "$FOUND" ]; then
    echo "ERROR: Media SquashFS tidak ditemukan!"
    exec sh
fi

mount -t squashfs /mnt/iso/live/filesystem.squashfs /mnt/squash
exec switch_root /mnt/squash /init
INIT_EOF

chmod +x ~/live-initramfs/init
(cd ~/live-initramfs && find . -print0 | cpio --null --create --format=newc | gzip -9 > "$BUILD_DIR"/boot/initrd.img)

echo "==> Menulis grub.cfg..."
cat << 'GRUB_EOF' > "$BUILD_DIR"/boot/grub/grub.cfg
set default=0
set timeout=5

menuentry "Linux Scara 7.2.0 Live (x86_64)" {
    linux /boot/vmlinuz boot=live quiet
    initrd /boot/initrd.img
}
GRUB_EOF

echo "==> Generating ISO..."
grub-mkrescue -o "$ISO_NAME" "$BUILD_DIR"
echo "==> BERHASIL! ISO tersimpan di: $ISO_NAME"
