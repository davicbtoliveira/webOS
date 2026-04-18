#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run 2>/dev/null

hostname webOS
exec /sbin/init
