#!/usr/bin/env bash

set -eo pipefail

KERNEL_VER='5.10.158'

apt-get update
apt-get install debootstrap dosfstools parted -y

# Create a 16GB (14.9 GiB) disk image
dd if=/dev/zero of=synobian.img iflag=fullblock bs=1M count=15258 && sync

# Create a loopback device
loopdev=$(losetup --show -fP synobian.img)

# Create a GPT partition table
parted --script "$loopdev" mklabel gpt

# Create the first partition (256MB EFI partition)
parted --script "$loopdev" mkpart primary fat32 1MiB 513MiB
parted --script "$loopdev" set 1 esp on

# Create the second partition (rest of the disk)
parted --script "$loopdev" mkpart primary ext4 513MiB 100%

# Format the first partition as vfat
mkfs.vfat -F32 "${loopdev}p1"

# Format the second partition as ext4
mkfs.ext4 "${loopdev}p2"

# Create a temporary directory to mount the partitions
mkdir -p /mnt/synobian

# Mount the second partition (ext4) to /mnt/synobian
mount "${loopdev}p2" /mnt/synobian

# Create the EFI directory and mount the first partition (vfat)
mkdir -p /mnt/synobian/boot/efi
mount "${loopdev}p1" /mnt/synobian/boot/efi

debootstrap bookworm /mnt/synobian http://deb.debian.org/debian

# (Optional) Bind mount special filesystems needed for chroot
mount --bind /dev /mnt/synobian/dev
mount --bind /proc /mnt/synobian/proc
mount --bind /sys /mnt/synobian/sys

# Copy the custom kernel packages to the chroot environment
cp ./linux-headers-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /mnt/synobian/tmp/
cp ./linux-image-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /mnt/synobian/tmp/
cp ./linux-libc-dev_${KERNEL_VER}-1_amd64.deb /mnt/synobian/tmp/

# Enter the chroot environment
chroot /mnt/synobian /bin/bash << EOF
# Update the package list
apt-get update

# Install the custom kernel
dpkg -i /tmp/linux-headers-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /tmp/linux-image-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /tmp/linux-libc-dev_${KERNEL_VER}-1_amd64.deb

# Install GRUB2 and necessary packages
apt-get install -y grub-efi-amd64 shim-signed

# Install GRUB to the EFI partition
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck

# Generate the GRUB configuration file
update-grub

# Generate fstab
cat <<EOL > /etc/fstab
# /etc/fstab: static file system information.
#
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=\$(blkid -s UUID -o value /dev/loop0p2) / ext4 defaults 0 1
UUID=\$(blkid -s UUID -o value /dev/loop0p1) /boot/efi vfat defaults 0 1
EOL

# Clear cache
apt-get -y clean

# Exit chroot
exit
EOF

# Cleanup
rm /mnt/synobian/tmp/*.deb

# Unmount the special filesystems and partitions
umount /mnt/synobian/{boot/efi,dev,proc,sys}
umount /mnt/synobian

# Detach the loopback device
losetup -d "$loopdev"

# Remove the temporary directory
rmdir /mnt/synobian