#!/usr/bin/env bash

set -eo pipefail

# This is based on the work of Debi-718:
# Sources: https://forum.doozan.com/read.php?2,123734,page=2

KERNEL_VER='5.10.158'

# Install Dependencies
sudo apt-get update
sudo apt-get install git curl wget rsync build-essential bc kmod cpio flex libncurses5-dev libelf-dev libssl-dev dwarves bison -y

# Get Kernel Sources
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$KERNEL_VER.tar.gz

# Check SHA256SUM
kernel_sha256sum=$(curl -SsL https://cdn.kernel.org/pub/linux/kernel/v5.x/sha256sums.asc | grep "linux-$KERNEL_VER.tar.gz" | awk '{print $1}' | xargs)
echo "$kernel_sha256sum linux-$KERNEL_VER.tar.gz" | sha256sum --check --status

# Untar
tar -xvf linux-$KERNEL_VER.tar.gz
cd linux-$KERNEL_VER

# Apply patches
for patch in ../patches/*.patch; do
    echo "Applying patch: $patch"
    git apply --whitespace=fix --directory=linux-$KERNEL_VER --verbose $patch
done

mkdir -p ../syno-linux-$KERNEL_VER-modules
mkdir -p ../syno-linux-$KERNEL_VER-kernel

# Build the Kernel
make olddefconfig
make -j$(nproc)
make -j$(nproc) modules
make -j$(nproc) INSTALL_MOD_PATH=../syno-linux-$KERNEL_VER-modules modules_install
make -j$(nproc) bzImage
make -j$(nproc) INSTALL_PATH=../syno-linux-$KERNEL_VER-kernel install
make -j$(nproc) bindeb-pkg

