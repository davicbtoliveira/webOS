#!/bin/sh
exec >/dev/console 2>&1 </dev/console

echo "[webOS] /init stage 1: mounting pseudo filesystems"
/bin/busybox mount -t proc     proc     /proc
/bin/busybox mount -t sysfs    sysfs    /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null
/bin/busybox mount -t tmpfs    tmpfs    /tmp
/bin/busybox mount -t tmpfs    tmpfs    /run 2>/dev/null

/bin/busybox --install -s 2>/dev/null

echo "[webOS] /init stage 2: hostname + motd"
hostname webOS
[ -f /etc/motd ] && cat /etc/motd

echo "[webOS] /init stage 3: exec /sbin/init"
exec /sbin/init
