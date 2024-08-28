#!/usr/bin/env bash

set -eo pipefail

# Build the Kernel
KERNEL_VER='5.10.158'
# Get latest version: curl -SsL https://cdn.kernel.org/pub/linux/kernel/v5.x/sha256sums.asc | grep linux-5.10 | awk '{print $2}' | grep -oP '\d+\.\d+\.\d+' | sort -V | tail -n 1
source ./build-5.10-kernel.sh $KERNEL_VER

apt-get update
apt-get install debootstrap dosfstools parted -y

# Create a 8GB (7.5 GiB) disk image
dd if=/dev/zero of=synobian.img iflag=fullblock bs=1M count=7629 && sync

# Create a loopback device
loopdev=$(losetup --show -fP synobian.img)

# Create a GPT partition table
parted --script "$loopdev" mklabel gpt

# Create the first partition (256MB EFI partition)
parted --script "$loopdev" mkpart primary fat32 1MiB 513MiB
parted --script "$loopdev" set 1 esp on

# Create the second partition (rest of the disk)
parted --script "$loopdev" mkpart primary ext2 513MiB 100%

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
mount --bind /sys/firmware/efi/efivars /mnt/synobian/sys/firmware/efi/efivars

# Copy the custom kernel packages to the chroot environment
cp ./linux-headers-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /mnt/synobian/tmp/
cp ./linux-image-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /mnt/synobian/tmp/
cp ./linux-libc-dev_${KERNEL_VER}-1_amd64.deb /mnt/synobian/tmp/

# Enter the chroot environment
chroot /mnt/synobian /bin/bash << EOF
# APT Update
apt-get update

# Setup Language
export LANGUAGE="en_US:en"
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen

apt-get install locales -y

# Install Dependencies
apt-get install grub-efi-amd64 shim-signed openssh-server sudo -y

# Install the custom kernel
dpkg -i /tmp/linux-headers-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /tmp/linux-image-${KERNEL_VER}_${KERNEL_VER}-1_amd64.deb /tmp/linux-libc-dev_${KERNEL_VER}-1_amd64.deb

# Generate fstab
cat <<EOL > /etc/fstab
# /etc/fstab: static file system information.
#
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=\$(blkid -s UUID -o value /dev/loop0p2) / ext4 defaults 0 1
UUID=\$(blkid -s UUID -o value /dev/loop0p1) /boot/efi vfat defaults 0 1
EOL

# Install GRUB to the EFI partition
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck

# Set Grub defaults
sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT='\''quiet console=ttyS2,115200n8 SataPortMap=22 sata_remap="0>2:1>3:2>0:3>1" syno_hdd_detect=18,179,176,175 syno_hdd_enable=21,20,19,9'\''' /etc/default/grub

# Generate the GRUB configuration file
update-grub

# Replace loop device path with UUID (only needed on image generation)
sed -i -e "s:root=/dev/loop0p2:root=UUID=\$(blkid -s UUID -o value /dev/loop0p2):g" /boot/grub/grub.cfg

# Setup SSH Server
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config

# Create synobian User
useradd --create-home --password synobian --uid 2000 --user-group --shell /bin/bash --comment "Initial Synobian User" synobian
echo "synobian ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/synobian

# Set Hostanme
hostname synobian
echo "synobian" > /etc/hostname
echo "127.0.1.1     synobian" >> /etc/hosts

# Deactivate root password
usermod -p ! root

# Clear cache
apt-get -y clean

# Cleanup history and exit chroot
cat /dev/null > ~/.bash_history && history -c && exit
EOF

# Compress Image
gzip synobian.img

# Cleanup
rm /mnt/synobian/tmp/*.deb

# Unmount the special filesystems and partitions
umount /mnt/synobian/{boot/efi,dev,proc,sys/firmware/efi/efivars,sys}
umount /mnt/synobian

# Detach the loopback device
losetup -d "$loopdev"

# Remove the temporary directory
rmdir /mnt/synobian

rm synobian.img
