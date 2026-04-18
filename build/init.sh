#!/bin/sh
exec >/dev/console 2>&1 </dev/console

echo "[webOS] /init stage 1: mounting pseudo filesystems"
/bin/busybox mount -t proc     proc     /proc
/bin/busybox mount -t sysfs    sysfs    /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null
/bin/busybox mount -t tmpfs    tmpfs    /tmp
/bin/busybox mount -t tmpfs    tmpfs    /run 2>/dev/null

/bin/busybox --install -s 2>/dev/null

mkdir -p /tmp/packages/bin
mkdir -p /tmp/packages/usr/bin
mkdir -p /tmp/packages/usr/lib

ln -sf /tmp/packages/bin /usr/local/bin 2>/dev/null || true
ln -sf /tmp/packages/usr/lib /usr/local/lib 2>/dev/null || true

echo "[webOS] /init stage 2: hostname + motd"
hostname webOS
[ -f /etc/motd ] && cat /etc/motd

echo ""
echo "Welcome to webOS!"
echo "Type '/bin/pkg help' for package management"
echo ""

exec env ENV=/etc/profile /sbin/init
