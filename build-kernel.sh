#!/usr/bin/env bash

# Sources: https://forum.doozan.com/read.php?2,123734,page=2

KERNEL_VER='5.10.158'
# Newest version
# KERNEL_VER='5.10.224'

# Install Dependencies
sudo apt-get install git curl wget build-essential bc kmod cpio flex libncurses5-dev libelf-dev libssl-dev dwarves bison

# Get Kernel Sources
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/$KERNEL_VER.tar.gz

# Check SHA256SUM
sha256sum = curl -SsL https://cdn.kernel.org/pub/linux/kernel/v5.x/sha256sums.asc | grep "$KERNEL_VER.tar.gz" | awk '{print $1}' | xargs
echo "$sha256sum $KERNEL_VER.tar.gz" | sha256sum --check --status

# Untar
tar -xvf $KERNEL_VER.tar.gz
cd linux-$KERNEL_VER

# Apply patches
for patch in ../patches/*.patch; do
    git apply --whitespace=fix $patch
done

mkdir ../syno-linux-$KERNEL_VER-modules
mkdir ../syno-linux-$KERNEL_VER-kernel

# Build the Kernel
# make menuconfig
make -j1
make -j1 modules
make -j1 INSTALL_MOD_PATH=../syno-linux-$KERNEL_VER-modules modules_install
make -j1 bzImage
make -j1 INSTALL_PATH=../syno-linux-$KERNEL_VER-kernel install
make -j1 bindeb-pkg