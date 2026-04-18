#!/bin/sh
exec >/dev/console 2>&1 </dev/console

/bin/busybox mount -t proc     proc     /proc
/bin/busybox mount -t sysfs    sysfs    /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null
/bin/busybox mount -t tmpfs    tmpfs    /tmp
/bin/busybox mount -t tmpfs    tmpfs    /run 2>/dev/null

/bin/busybox --install -s 2>/dev/null

mkdir -p /tmp/packages/bin /tmp/packages/usr/bin /tmp/packages/usr/lib \
         /tmp/packages/share /tmp/packages/db /tmp/packages/hook \
         /var/cache/pkg
: > /tmp/packages/db/installed.list

hostname webOS
[ -f /etc/motd ] && cat /etc/motd

echo ""
echo "  type  \033[38;5;120mfetch\033[0m     for system info"
echo "  type  \033[38;5;120mpkg help\033[0m  for package commands"
echo ""

exec env ENV=/etc/profile /sbin/init
