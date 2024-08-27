#!/usr/bin/env bash

apt-get update
apt-get install -y debootstrap
debootstrap bookworm /debian-base http://deb.debian.org/debian
chroot /debian-base apt-get -q clean
